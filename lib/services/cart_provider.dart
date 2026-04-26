import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import 'telegram_service.dart';
import 'menu_data_service.dart';

class CartProvider with ChangeNotifier {
  final String tableId;
  String? _deviceId;

  List<CartItem> _items = [];
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _userName;

  // Список ID, удалённых локально — фильтруем их из КАЖДОГО обновления стрима
  final Set<String> _deletedIds = {};
  bool _isReadyLocally = false;

  StreamSubscription? _cartSub;
  StreamSubscription? _participantSub;

  CartProvider({required this.tableId}) {
    _init();
  }

  List<CartItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get deviceId => _deviceId ?? '';
  String? get userName => _userName;
  bool get isReadyLocally => _isReadyLocally;
  List<Map<String, dynamic>> get participants => _participants;
  int get totalItems => _items.length;
  bool get isReady {
    if (_deviceId == null) return false;
    final me = _participants.firstWhere(
      (p) => p['device_id'] == _deviceId,
      orElse: () => {},
    );
    return me['is_ready'] == true || _isReadyLocally;
  }

  int? get myGuestNumber {
    if (_deviceId == null) return null;
    final me = _participants.firstWhere(
      (p) => p['device_id'] == _deviceId,
      orElse: () => {},
    );
    return me['guest_number'];
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name');
    _deviceId = prefs.getString('device_id');
    
    if (_deviceId == null) {
      _deviceId = 'u_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
    }

    // Синхронизируем имя с базой сразу при входе, если оно уже есть
    if (_userName != null && _userName!.isNotEmpty) {
      _syncName(_userName!);
    }

    // Очистка старых участников (более 4 часов назад) чтобы не копились призраки
    try {
      final fourHoursAgo = DateTime.now().subtract(const Duration(hours: 4)).toIso8601String();
      await Supabase.instance.client
          .from('table_participants')
          .delete()
          .eq('table_id', tableId)
          .lt('last_active', fourHoursAgo);

      // Удаляем "двойников" с таким же именем (если имя уже задано)
      if (_userName != null && _userName!.isNotEmpty) {
        await Supabase.instance.client
            .from('table_participants')
            .delete()
            .eq('table_id', tableId)
            .eq('user_name', _userName!)
            .neq('device_id', _deviceId!);
      }
    } catch (_) {}

    try {
      await Supabase.instance.client.rpc('get_guest_number', params: {
        'p_table_id': tableId,
        'p_device_id': _deviceId,
      });
      
      // Повторно пушим имя после RPC (на случай если RPC создал новый рекорд с null именем)
      if (_userName != null && _userName!.isNotEmpty) {
        _syncName(_userName!);
      }
    } catch (_) {}

    _startStreams();
  }

  Future<void> _syncName(String name) async {
    try {
      await Supabase.instance.client
          .from('table_participants')
          .update({'user_name': name})
          .eq('table_id', tableId)
          .eq('device_id', _deviceId!);
    } catch (e) {
      debugPrint('Sync name error: $e');
    }
  }

  void _startStreams() {
    _cartSub?.cancel();
    _cartSub = Supabase.instance.client
        .from('orders_new')
        .stream(primaryKey: ['id'])
        .eq('table_id', tableId)
        .listen((data) {
          // ВСЕГДА фильтруем удалённые ID, независимо от причины обновления стрима
          _items = data
              .map((json) => CartItem.fromJson(json))
              .where((item) => !_deletedIds.contains(item.id))
              .toList();
          _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _isLoading = false;
          notifyListeners();
        });

    _participantSub?.cancel();
    _participantSub = Supabase.instance.client
        .from('table_participants')
        .stream(primaryKey: ['id'])
        .eq('table_id', tableId)
        .listen((data) {
          _participants = data;
          
          // Проверка: если есть участники и ВСЕ готовы, подтверждаем заказ
          if (_participants.isNotEmpty && 
              _participants.every((p) => p['is_ready'] == true) &&
              _items.any((it) => it.status == 'ordering')) {
            confirmOrder();
          }
          
          notifyListeners();
        });
  }

  Future<void> addToCart(String menuItemId, int quantity) async {
    try {
      final existingIndex = _items.indexWhere(
        (it) => it.menuItemId == menuItemId && it.status == 'ordering',
      );

      if (existingIndex != -1) {
        await Supabase.instance.client
            .from('orders_new')
            .update({'quantity': _items[existingIndex].quantity + quantity})
            .eq('id', _items[existingIndex].id);
      } else {
        await Supabase.instance.client.from('orders_new').insert({
          'table_id': tableId,
          'menu_item_id': menuItemId,
          'quantity': quantity,
          'added_by': _deviceId,
          'user_name': _userName,
          'status': 'ordering',
        });
      }
    } catch (e) {
      _showError("Ошибка добавления");
    }
  }

  Future<void> removeFromCart(String id) async {
    // 1. Добавляем в список удалённых — стрим больше никогда не покажет этот ID
    _deletedIds.add(id);

    // 2. Убираем из текущего списка
    _items.removeWhere((it) => it.id == id);
    notifyListeners();

    // 3. Пытаемся удалить из базы (если база отказывает — фильтр всё равно скрывает)
    try {
      await Supabase.instance.client
          .from('orders_new')
          .delete()
          .eq('id', id);
      debugPrint('DB delete sent for $id');
    } catch (e) {
      debugPrint('DB delete error for $id: $e');
      // Не возвращаем — ID остаётся в _deletedIds и не будет показан
    }
  }

  Future<void> confirmOrder() async {
    try {
      // Собираем данные для уведомления ПЕРЕД обновлением статуса
      final pendingItems = _items.where((it) => it.status == 'ordering').toList();
      double total = 0;
      List<Map<String, dynamic>> itemsForTelegram = [];
      
      for (var it in pendingItems) {
        final menuDish = MenuDataService.items.firstWhere((m) => m.id == it.menuItemId, 
            orElse: () => MenuItem(id: '', title: 'Блюдо', price: 0, categoryId: '', description: '', images: []));
        total += it.quantity * menuDish.price;
        itemsForTelegram.add({
          'title': menuDish.title,
          'qty': it.quantity,
          'price': menuDish.price,
        });
      }

      // 1. Все товары в 'confirmed'
      await Supabase.instance.client
          .from('orders_new')
          .update({'status': 'confirmed'})
          .eq('table_id', tableId)
          .eq('status', 'ordering');

      // 2. Уведомляем официанта (или общий чат)
      if (itemsForTelegram.isNotEmpty) {
        final waiterChatId = await TelegramService.getWaiterChatId(tableId);
        await TelegramService.notifyNewOrder(
          tableId: tableId, 
          items: itemsForTelegram, 
          total: total,
          customChatId: waiterChatId,
        );
      }

      // 2. Сессия стола в 'confirmed' (для звука в админке)
      try {
        await Supabase.instance.client.from('table_sessions').upsert({
          'table_id': tableId,
          'status': 'confirmed',
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Skip table_sessions update: $e');
      }

      // 3. Сбрасываем готовность всех участников для следующего круга
      await Supabase.instance.client
          .from('table_participants')
          .update({'is_ready': false})
          .eq('table_id', tableId);
          
    } catch (e) {
      _showError("Ошибка подтверждения");
    }
  }

  Future<void> toggleReady() async {
    if (_deviceId == null) return;
    final currentStatus = isReady;
    try {
      await Supabase.instance.client
          .from('table_participants')
          .update({'is_ready': !currentStatus})
          .eq('table_id', tableId)
          .eq('device_id', _deviceId!);
    } catch (e) {
      _showError("Ошибка статуса");
    }
  }

  Future<void> clearTable() async {
    _deletedIds.clear();
    _items.clear();
    notifyListeners();
    try {
      await Supabase.instance.client
          .from('orders_new')
          .delete()
          .eq('table_id', tableId);
    } catch (e) {
      _showError("Ошибка очистки");
    }
  }

  Future<void> updateQuantity(String id, int newQuantity) async {
    try {
      await Supabase.instance.client
          .from('orders_new')
          .update({'quantity': newQuantity})
          .eq('id', id);
    } catch (e) {
      _showError("Ошибка обновления");
    }
  }

  Future<void> removeItem(String id) => removeFromCart(id);

  void clearCartLocally() {
    _items.clear();
    _deletedIds.clear();
    notifyListeners();
  }

  void _showError(String msg) {
    _errorMessage = msg;
    notifyListeners();
    Future.delayed(const Duration(seconds: 3), () {
      _errorMessage = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _cartSub?.cancel();
    _participantSub?.cancel();
    super.dispose();
  }

  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    _userName = name;
    
    // Также обновляем имя в списке участников стола в базе
    try {
      await Supabase.instance.client
          .from('table_participants')
          .update({'user_name': name})
          .eq('table_id', tableId)
          .eq('device_id', deviceId);
    } catch (_) {}
    
    notifyListeners();
  }
}

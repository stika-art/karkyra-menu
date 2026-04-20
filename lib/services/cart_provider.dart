import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';

class CartProvider with ChangeNotifier {
  final String tableId;
  String? _deviceId;

  List<CartItem> _items = [];
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Список ID, удалённых локально — фильтруем их из КАЖДОГО обновления стрима
  final Set<String> _deletedIds = {};

  StreamSubscription? _cartSub;
  StreamSubscription? _participantSub;

  CartProvider({required this.tableId}) {
    _init();
  }

  List<CartItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get deviceId => _deviceId ?? '';
  List<Map<String, dynamic>> get participants => _participants;
  int get totalItems => _items.length;

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
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      _deviceId = 'u_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
    }

    try {
      await Supabase.instance.client.rpc('get_guest_number', params: {
        'p_table_id': tableId,
        'p_device_id': _deviceId,
      });
    } catch (_) {}

    _startStreams();
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
      await Supabase.instance.client
          .from('orders_new')
          .update({'status': 'confirmed'})
          .eq('table_id', tableId)
          .eq('status', 'ordering');

      await Supabase.instance.client.from('table_sessions').upsert({
        'table_id': tableId,
        'status': 'confirmed',
      });
    } catch (e) {
      _showError("Ошибка подтверждения");
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
}

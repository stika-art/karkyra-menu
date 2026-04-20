import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';

class CartProvider with ChangeNotifier {
  final String tableId;
  String? _deviceId;
  int? _myGuestNumber;
  List<Map<String, dynamic>> _participants = [];
  List<CartItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  // Session properties
  String _sessionStatus = 'ordering'; // 'ordering', 'confirmed', 'locked'
  DateTime? _confirmedAt;

  CartProvider({required this.tableId}) {
    _initProvider();
  }

  String get deviceId => _deviceId ?? '';
  String get sessionStatus => _sessionStatus;
  DateTime? get confirmedAt => _confirmedAt;

  bool get isLocked => false; // Блокировка отключена пользователем

  Future<void> _initProvider() async {
    await _initDeviceId();
    await _initGuestRegistration();
    _initRealtimeSubscription();
    _initSessionSubscription();
  }

  // Загружаем ID из памяти или создаем новый
  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      _deviceId = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('device_id', _deviceId!);
    }
  }

  // Геттеры для UI
  List<CartItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get myGuestNumber => _myGuestNumber;
  List<Map<String, dynamic>> get participants => _participants;
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  // Регистрация гостя через RPC функцию
  Future<void> _initGuestRegistration() async {
    try {
      final number = await Supabase.instance.client
          .rpc('get_guest_number', params: {
            'p_table_id': tableId,
            'p_device_id': deviceId,
          });
      _myGuestNumber = number;
      _initParticipantsSubscription();
    } catch (e) {
      debugPrint('Error registering guest: $e');
    }
  }

  void _initParticipantsSubscription() {
    Supabase.instance.client
        .from('table_participants')
        .stream(primaryKey: ['id'])
        .eq('table_id', tableId)
        .handleError((error) {
          debugPrint('Participants stream error: $error');
          // Попытка переподключения при ошибке
          Future.delayed(const Duration(seconds: 5), () {
            _initParticipantsSubscription();
          });
        })
        .listen((data) {
          _participants = data;
          notifyListeners();
        });
  }

  void _initSessionSubscription() {
    Supabase.instance.client
        .from('table_sessions')
        .stream(primaryKey: ['table_id'])
        .eq('table_id', tableId)
        .handleError((error) {
          debugPrint('Session stream error: $error');
          // Попытка переподключения при ошибке
          Future.delayed(const Duration(seconds: 5), () {
            _initSessionSubscription();
          });
        })
        .listen((data) {
          if (data.isNotEmpty) {
            _sessionStatus = data.first['status'];
            final confirmedStr = data.first['confirmed_at'];
            if (confirmedStr != null) {
              _confirmedAt = DateTime.parse(confirmedStr);
            }
          } else {
            _sessionStatus = 'ordering';
            _confirmedAt = null;
          }
          notifyListeners();
        });
  }

  // Основная подписка на корзину (единственный источник данных)
  void _initRealtimeSubscription() {
    Supabase.instance.client
        .from('cart_items')
        .stream(primaryKey: ['id'])
        .eq('table_id', tableId)
        .handleError((error) {
          _errorMessage = "Проблема с подключением к серверу. Попытка восстановиться...";
          notifyListeners();
          // Пытаемся переподключиться через 3 секунды при ошибке
          Future.delayed(const Duration(seconds: 3), () {
            _initRealtimeSubscription();
          });
        })
        .listen((List<Map<String, dynamic>> data) {
          _items = data.map((json) => CartItem.fromJson(json)).toList();
          _isLoading = false;
          _errorMessage = null;
          notifyListeners();
        });
  }

  Future<void> confirmOrder() async {
    try {
      await Supabase.instance.client.rpc('confirm_table_order', params: {
        'p_table_id': tableId,
      });
    } catch (e) {
      debugPrint('Error confirming order: $e');
    }
  }

  // Метод для административного сброса стола (для тестов)
  Future<void> clearTable() async {
    try {
      _isLoading = true;
      notifyListeners();

      // 1. Очищаем корзину
      await Supabase.instance.client
          .from('cart_items')
          .delete()
          .eq('table_id', tableId);

      // 2. Сбрасываем сессию
      await Supabase.instance.client
          .from('table_sessions')
          .update({
            'status': 'ordering',
            'confirmed_at': null,
          })
          .eq('table_id', tableId);

      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing table: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  // Добавление в корзину
  Future<void> addToCart(String menuItemId, int quantity) async {
    try {
      final existingIndex = _items.indexWhere(
        (item) => item.menuItemId == menuItemId && item.addedBy == deviceId
      );
      
      if (existingIndex != -1) {
        final newQuantity = _items[existingIndex].quantity + quantity;
        await Supabase.instance.client
            .from('cart_items')
            .update({'quantity': newQuantity})
            .eq('id', _items[existingIndex].id);
      } else {
        await Supabase.instance.client
            .from('cart_items')
            .insert({
              'menu_item_id': menuItemId,
              'quantity': quantity,
              'table_id': tableId,
              'added_by': deviceId,
            });
      }
    } catch (e) {
      debugPrint('Error adding to cart: $e');
    }
  }

  // Удаление
  Future<void> removeFromCart(String cartItemId) async {
    final index = _items.indexWhere((item) => item.id == cartItemId);
    if (index != -1) {
      final removedItem = _items.removeAt(index);
      notifyListeners();

      try {
        await Supabase.instance.client
            .from('cart_items')
            .delete()
            .eq('id', cartItemId);
      } catch (e) {
        _items.insert(index, removedItem);
        notifyListeners();
      }
    }
  }
}

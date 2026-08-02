import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для работы официанта с Supabase и локальной сессией
class WaiterService {
  static const String _waiterIdKey = 'current_waiter_id';
  static const String _waiterNameKey = 'current_waiter_name';
  static const String _waiterPhoneKey = 'current_waiter_phone';

  static final SupabaseClient _client = Supabase.instance.client;

  // ==========================================
  // Сессия официанта (SharedPreferences)
  // ==========================================

  static Future<void> saveCurrentWaiter(Map<String, dynamic> waiter) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_waiterIdKey, waiter['id'].toString());
    await prefs.setString(_waiterNameKey, (waiter['name'] ?? '').toString());
    await prefs.setString(_waiterPhoneKey, (waiter['phone'] ?? '').toString());
  }

  static Future<Map<String, String>?> getCurrentWaiter() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_waiterIdKey);
    if (id == null || id.isEmpty) return null;
    return {
      'id': id,
      'name': prefs.getString(_waiterNameKey) ?? 'Официант',
      'phone': prefs.getString(_waiterPhoneKey) ?? '',
    };
  }

  static Future<void> clearCurrentWaiter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_waiterIdKey);
    await prefs.remove(_waiterNameKey);
    await prefs.remove(_waiterPhoneKey);
  }

  /// Попытка входа под профилем официанта с проверкой активной сессии
  static Future<Map<String, dynamic>> loginWaiter(Map<String, dynamic> waiter) async {
    final waiterId = waiter['id'].toString();
    try {
      // Проверяем текущее состояние официанта в БД
      final res = await _client
          .from('waiters')
          .select('is_online')
          .eq('id', waiterId)
          .maybeSingle();

      if (res != null && res['is_online'] == true) {
        final currentLocal = await getCurrentWaiter();
        if (currentLocal == null || currentLocal['id'] != waiterId) {
          // Другое устройство уже зашло под этим официантом
          return {
            'success': false,
            'message': 'Этот официант уже авторизован на другом устройстве!',
          };
        }
      }

      // Отмечаем профиль как занятый (is_online = true)
      try {
        await _client
            .from('waiters')
            .update({'is_online': true})
            .eq('id', waiterId);
      } catch (_) {
        // Если в БД пока нет колонки is_online, пропускаем ошибку обновления
      }

      await saveCurrentWaiter(waiter);
      return {'success': true};
    } catch (e) {
      await saveCurrentWaiter(waiter);
      return {'success': true};
    }
  }

  static Future<void> logoutCurrentWaiter() async {
    final current = await getCurrentWaiter();
    if (current != null && current['id'] != null) {
      try {
        await _client
            .from('waiters')
            .update({'is_online': false})
            .eq('id', current['id']!);
      } catch (_) {}
    }
    await clearCurrentWaiter();
  }

  // ==========================================
  // Официанты
  // ==========================================

  static Future<List<Map<String, dynamic>>> fetchWaiters() async {
    try {
      final res = await _client.from('waiters').select().order('name');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [];
    }
  }

  // ==========================================
  // Залы и Столы
  // ==========================================

  static Future<List<Map<String, dynamic>>> fetchFloors() async {
    try {
      final res = await _client.from('floors').select().order('sort_order');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchTables() async {
    try {
      final res = await _client.from('restaurant_tables').select().order('label');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [];
    }
  }

  /// Закрепление свободного стола за официантом
  static Future<bool> claimTable({
    required String tableId,
    required String waiterId,
  }) async {
    try {
      // Проверяем, свободен ли стол сейчас
      final current = await _client
          .from('restaurant_tables')
          .select('waiter_id')
          .eq('id', tableId)
          .single();

      final currentWaiterId = current['waiter_id'];
      if (currentWaiterId != null && currentWaiterId != waiterId) {
        // Стол уже занят другим официантом
        return false;
      }

      await _client
          .from('restaurant_tables')
          .update({'waiter_id': waiterId})
          .eq('id', tableId);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Отвязка стола от официанта (сделать стол свободным)
  static Future<bool> releaseTable({
    required String tableId,
    required String waiterId,
  }) async {
    try {
      await _client
          .from('restaurant_tables')
          .update({'waiter_id': null})
          .eq('id', tableId)
          .eq('waiter_id', waiterId); // безопасность: отвязывать только свои столы

      return true;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // Заказы (orders_new & table_sessions)
  // ==========================================

  static Future<List<Map<String, dynamic>>> fetchOrders() async {
    try {
      final res = await _client
          .from('orders_new')
          .select('*, restaurant_tables(label, waiter_id)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      // Резервный запрос, если нет связи
      try {
        final res = await _client.from('orders_new').select().order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        return [];
      }
    }
  }

  static Future<bool> updateOrderStatus(String orderId, String status) async {
    try {
      await _client.from('orders_new').update({'status': status}).eq('id', orderId);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // Вызовы официанта (waiter_calls)
  // ==========================================

  static Future<List<Map<String, dynamic>>> fetchWaiterCalls() async {
    try {
      final res = await _client
          .from('waiter_calls')
          .select('*, restaurant_tables(label, waiter_id)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      try {
        final res = await _client.from('waiter_calls').select().order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        return [];
      }
    }
  }

  static Future<bool> updateCallStatus(String callId, String status) async {
    try {
      await _client.from('waiter_calls').update({'status': status}).eq('id', callId);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // Бронирования (table_reservations)
  // ==========================================

  static Future<List<Map<String, dynamic>>> fetchReservations() async {
    try {
      final res = await _client
          .from('table_reservations')
          .select('*, restaurant_tables(label, waiter_id)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      try {
        final res = await _client.from('table_reservations').select().order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      } catch (_) {
        return [];
      }
    }
  }

  static Future<bool> updateReservationStatus(String reservationId, String status) async {
    try {
      await _client
          .from('table_reservations')
          .update({'status': status})
          .eq('id', reservationId);
      return true;
    } catch (e) {
      return false;
    }
  }
}

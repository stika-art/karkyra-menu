import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:js' as js;
import 'package:flutter/services.dart';
import 'dart:async';
import '../../services/menu_data_service.dart';

// orders_screen.dart — заглушка для Telegram (добавьте токен позже)
// import '../../services/telegram_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _tableOrders = [];
  List<Map<String, dynamic>> _deliveryOrders = [];
  List<Map<String, dynamic>> _waiterCalls = [];
  List<Map<String, dynamic>> _bookings = [];
  Map<String, String> _tablesMap = {}; // ID -> Label
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;
  Timer? _notifyTimer;
  final Map<String, bool> _pendingTableNotifications = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadOrders();
    _initRealtime();
    _requestNotificationPermission();
    // Загружаем меню чтобы видеть названия блюд в заказах
    if (MenuDataService.items.isEmpty) {
      MenuDataService.load();
    }
  }

  void _requestNotificationPermission() {
    if (kIsWeb) {
      js.context.callMethod('eval', [
        "if (Notification.permission !== 'granted') { Notification.requestPermission(); }"
      ]);
    }
  }

  void _initRealtime() {
    _realtimeChannel = Supabase.instance.client
        .channel('admin_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders_new',
          callback: (payload) {
            Future.delayed(const Duration(milliseconds: 300), () => _loadOrders(silent: true));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_sessions',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.update || payload.eventType == PostgresChangeEvent.insert) {
              final newStatus = payload.newRecord['status'];
              if (newStatus == 'confirmed') {
                final tableId = payload.newRecord['table_id'];
                _playSound();
                _showSystemNotification('Новый заказ!', 'Стол №$tableId подтвердил заказ');
                _loadOrders(silent: true);
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'delivery_orders',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              _playSound();
              _showSystemNotification('Новая доставка!', 'Клиент ${payload.newRecord['customer_name']} оформил доставку');
            }
            _loadOrders(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'waiter_calls',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              final tableId = payload.newRecord['table_id'];
              _playSound();
              _showSystemNotification('Вызов официанта!', 'Вас ждут за столом №$tableId');
              _loadOrders(silent: true);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              _playSound();
              _showSystemNotification('Новая бронь!', 'Гость ${payload.newRecord['customer_name']} забронировал стол');
            }
            _loadOrders(silent: true);
          },
        )
        .subscribe((status, error) {
          debugPrint('REALTIME STATUS: $status');
          if (error != null) {
            debugPrint('REALTIME ERROR: $error');
          }
          if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('Check if Realtime is enabled in Supabase Dashboard (Database -> Replication)');
          }
        });
  }

  void _playSound() {
    SystemSound.play(SystemSoundType.click);
    if (kIsWeb) {
      try {
        js.context.callMethod('eval', [
          "new Audio('https://assets.mixkit.io/active_storage/sfx/2568/2568-preview.mp3').play()"
        ]);
      } catch (e) {
        debugPrint('Sound error: $e');
      }
    }
  }

  void _showSystemNotification(String title, String body) {
    if (kIsWeb) {
      try {
        js.context.callMethod('eval', [
          "new Notification('$title', { body: '$body', icon: 'https://cdn-icons-png.flaticon.com/512/3135/3135715.png' })"
        ]);
      } catch (e) {
        debugPrint('Notification error: $e');
      }
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  String _getMenuItemTitle(String? menuItemId) {
    if (menuItemId == null) return 'Блюдо';
    try {
      final item = MenuDataService.items.firstWhere((m) => m.id == menuItemId);
      return item.title;
    } catch (_) {
      return 'Блюдо #${menuItemId.length > 8 ? menuItemId.substring(0, 8) : menuItemId}';
    }
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final tableRes = await Supabase.instance.client
          .from('orders_new')
          .select()
          .neq('status', 'ordering')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      final deliveryRes = await Supabase.instance.client
          .from('delivery_orders')
          .select<List<Map<String, dynamic>>>()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      final callsRes = await Supabase.instance.client
          .from('waiter_calls')
          .select<List<Map<String, dynamic>>>()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      final bookingsRes = await Supabase.instance.client
          .from('bookings')
          .select<List<Map<String, dynamic>>>()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      final tablesRes = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id, label');

      setState(() {
        _tableOrders = List<Map<String, dynamic>>.from(tableRes);
        _deliveryOrders = List<Map<String, dynamic>>.from(deliveryRes);
        _waiterCalls = List<Map<String, dynamic>>.from(callsRes);
        _bookings = List<Map<String, dynamic>>.from(bookingsRes);
        
        _tablesMap = {
          for (var t in (tablesRes as List)) 
            t['id'].toString(): t['label'].toString()
        };

        _loading = false;
      });
      debugPrint('ADMIN: Loaded ${_tableOrders.length} table orders, ${_deliveryOrders.length} delivery, ${_waiterCalls.length} calls, ${_bookings.length} bookings');
    } catch (e) {
      debugPrint('ADMIN LOAD ERROR: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelBooking(String id) async {
    await Supabase.instance.client
        .from('bookings')
        .delete()
        .eq('id', id);
    _loadOrders(silent: true);
  }

  Future<void> _acceptBooking(String id) async {
    await Supabase.instance.client
        .from('bookings')
        .update({'status': 'accepted'})
        .eq('id', id);
    _loadOrders(silent: true);
  }

  Future<void> _freeTable(String? tableId, String bookingId) async {
    if (tableId != null) {
      await Supabase.instance.client
          .from('restaurant_tables')
          .update({'is_booked': false})
          .eq('id', tableId);
    }
    await Supabase.instance.client
        .from('bookings')
        .delete()
        .eq('id', bookingId);
    _loadOrders(silent: true);
  }

  Future<void> _resolveCall(String id) async {
    await Supabase.instance.client
        .from('waiter_calls')
        .update({'status': 'accepted'})
        .eq('id', id);
    _loadOrders();
  }

  Future<void> _acceptTableOrder(String tableId) async {
    debugPrint('ACCEPT ORDER: tableId=$tableId');
    try {
      final res = await Supabase.instance.client
          .from('orders_new')
          .update({'status': 'processing'})
          .eq('table_id', tableId)
          .inFilter('status', ['confirmed', 'ordering'])
          .select();
      debugPrint('ACCEPT ORDER RESULT: $res');
      _loadOrders(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заказ принят! Готовим ✅'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('ACCEPT ORDER ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _updateDeliveryStatus(String id, String status) async {
    await Supabase.instance.client
        .from('delivery_orders')
        .update({'status': status})
        .eq('id', id);
    _loadOrders();
  }

  Future<void> _clearAllDeliveryOrders() async {
    try {
      await Supabase.instance.client
          .from('delivery_orders')
          .delete()
          .not('id', 'is', null); // Самый надежный способ удалить всё
      _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('История доставки очищена'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Clear error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка очистки: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _clearTableOrders(String tableId) async {
    try {
      // Удаляем заказы стола
      await Supabase.instance.client
          .from('orders_new')
          .delete()
          .eq('table_id', tableId);
      
      // Удаляем участников (призраков) стола
      await Supabase.instance.client
          .from('table_participants')
          .delete()
          .eq('table_id', tableId);
      
      // Сбрасываем сессию
      await Supabase.instance.client
          .from('table_sessions')
          .delete()
          .eq('table_id', tableId);

      _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Стол №$tableId полностью очищен ✅'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Clear table error: $e');
    }
  }

  Future<void> _clearAllTableOrders() async {
    try {
      await Supabase.instance.client.from('orders_new').delete().not('id', 'is', null);
      await Supabase.instance.client.from('table_participants').delete().not('table_id', 'is', null);
      await Supabase.instance.client.from('table_sessions').delete().not('table_id', 'is', null);
      
      _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Все столы и участники очищены'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Clear all error: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD4A043),
          labelColor: const Color(0xFFD4A043),
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Столы (${_tableOrders.length})'),
            Tab(text: 'Доставка (${_deliveryOrders.length})'),
            Tab(text: 'Вызовы (${_waiterCalls.length})'),
            Tab(text: 'Брони (${_bookings.length})'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTableOrders(),
                    _buildDeliveryOrders(),
                    _buildWaiterCalls(),
                    _buildBookings(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
      color: const Color(0xFF1A1A1A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Заказы', style: GoogleFonts.outfit(
            color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold,
          )),
          IconButton(
            onPressed: _loadOrders,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFD4A043)),
          ),
        ],
      ),
    );
  }
  Widget _buildTableOrders() {
    if (_tableOrders.isEmpty) {
      return _buildEmpty('Заказов со столов нет');
    }

    // Группируем по столу
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final order in _tableOrders) {
      final tableId = order['table_id']?.toString() ?? 'unknown';
      grouped.putIfAbsent(tableId, () => []).add(order);
    }

    return Column(
      children: [
        if (_tableOrders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _clearAllTableOrders,
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('ОЧИСТИТЬ ВСЕ ЗАКАЗЫ СО СТОЛОВ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.2),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: grouped.entries.map((entry) {
              final tableId = entry.key;
              final items = entry.value;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: items.any((it) => it['status'] == 'ordering' || it['status'] == 'confirmed')
                      ? Border.all(color: const Color(0xFFD4A043).withOpacity(0.4))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: items.any((it) => it['status'] == 'ordering' || it['status'] == 'confirmed')
                                  ? const Color(0xFFD4A043)
                                  : Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Стол №$tableId',
                              style: GoogleFonts.outfit(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Spacer(),
                          IconButton(
                            onPressed: () => _clearTableOrders(tableId),
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            tooltip: 'Очистить стол',
                          ),
                          if (items.any((it) => it['status'] == 'ordering' || it['status'] == 'confirmed'))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Ожидает подтверждения',
                                style: GoogleFonts.outfit(color: Colors.orange, fontSize: 12),
                              ),
                            )
                          else if (items.any((it) => it['status'] == 'processing'))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Принято, готовим',
                                style: GoogleFonts.outfit(color: Colors.blue, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...() {
                      // Группируем блюда: блюдо + статус + имя гостя = одна строка
                      final Map<String, Map<String, dynamic>> grouped = {};
                      for (var it in items) {
                        final key = "${it['menu_item_id']}_${it['status']}_${it['user_name']}";
                        if (grouped.containsKey(key)) {
                          grouped[key]!['quantity'] = (grouped[key]!['quantity'] as int) + (it['quantity'] as int);
                        } else {
                          grouped[key] = Map<String, dynamic>.from(it);
                        }
                      }
                      return grouped.values.map((it) => _buildTableOrderItem(it));
                    }(),
                    const SizedBox(height: 12),
                    if (items.any((it) => it['status'] == 'ordering' || it['status'] == 'confirmed'))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: ElevatedButton(
                          onPressed: () => _acceptTableOrder(tableId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.withOpacity(0.2),
                            foregroundColor: Colors.blue,
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Принять заказ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTableOrderItem(Map<String, dynamic> item) {
    final status = item['status'];
    final isNew = status == 'confirmed';
    final isOrdering = status == 'ordering';
    final isProcessing = status == 'processing';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Индикатор статуса
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isNew ? Colors.orange : (isProcessing ? Colors.blue : Colors.grey),
              shape: BoxShape.circle,
              boxShadow: isNew ? [
                BoxShadow(color: Colors.orange.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)
              ] : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getMenuItemTitle(item['menu_item_id']?.toString()),
                  style: GoogleFonts.outfit(
                    color: isNew ? Colors.white : Colors.white70, 
                    fontSize: 15, 
                    fontWeight: isNew ? FontWeight.bold : FontWeight.w500
                  ),
                ),
                if (item['user_name'] != null)
                  Text(
                    'Заказал(а): ${item['user_name']}',
                    style: GoogleFonts.outfit(color: const Color(0xFFD4A043).withOpacity(0.8), fontSize: 11),
                  ),
                if (isNew)
                  Text(
                    'НОВЫЙ ЗАКАЗ',
                    style: GoogleFonts.outfit(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isNew ? Colors.orange.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'x${item['quantity']}',
              style: GoogleFonts.outfit(
                color: isNew ? Colors.orange : const Color(0xFFD4A043), 
                fontWeight: FontWeight.bold,
                fontSize: 16
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryOrders() {
    return Column(
      children: [
        if (_deliveryOrders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _clearAllDeliveryOrders,
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('ОЧИСТИТЬ ВСЕ ЗАКАЗЫ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.2),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _deliveryOrders.length,
            itemBuilder: (context, i) {
        try {
          final order = _deliveryOrders[i];
          final String status = order['status']?.toString() ?? 'new';
          final dynamic rawItems = order['items'];
          final List items = (rawItems is List) ? rawItems : [];
          final double total = double.tryParse(order['total']?.toString() ?? '0') ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: status == 'new'
                  ? Border.all(color: Colors.orange.withOpacity(0.4))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order['customer_name']?.toString() ?? 'Без имени',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(order['customer_phone']?.toString() ?? '',
                          style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 14)),
                      ],
                    ),
                    _statusChip(status),
                  ],
                ),
                const SizedBox(height: 12),
                ...items.map((it) {
                  if (it is! Map) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${it['title'] ?? 'Блюдо'} x${it['qty'] ?? 1}',
                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Итого: ${total.toStringAsFixed(0)} сом',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        if (status == 'new')
                          _actionButton('Принять', Colors.blue, () => _updateDeliveryStatus(order['id'].toString(), 'processing')),
                        if (status == 'processing')
                          _actionButton('Готово', Colors.green, () => _updateDeliveryStatus(order['id'].toString(), 'done')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        } catch (e) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            color: Colors.red.withOpacity(0.1),
            child: Text('Ошибка данных заказа: $e', style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
          );
        }
      },
    ),
  ),
],
);
}

  Widget _statusChip(String status) {
    String label = 'Неизвестно';
    Color color = Colors.grey;
    
    if (status == 'new') {
      label = 'Новый';
      color = Colors.orange;
    } else if (status == 'processing') {
      label = 'Принято, готовим';
      color = Colors.blue;
    } else if (status == 'done') {
      label = 'Завершено';
      color = Colors.green;
    } else if (status == 'cancelled') {
      label = 'Отменён';
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: GoogleFonts.outfit(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildWaiterCalls() {
    if (_waiterCalls.isEmpty) {
      return _buildEmpty('Активных вызовов нет');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _waiterCalls.length,
      itemBuilder: (context, i) {
        final call = _waiterCalls[i];
        final time = DateTime.tryParse(call['created_at'] ?? '')?.toLocal();
        final timeStr = time != null ? '${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '--:--';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A043).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFD4A043)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('СТОЛ №${call['table_id']}',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('Вызов в $timeStr',
                      style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _resolveCall(call['id'].toString()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withOpacity(0.2),
                  foregroundColor: Colors.green,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('ОК', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_rounded, color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          Text(text, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildBookings() {
    if (_bookings.isEmpty) {
      return _buildEmpty('Активных броней нет');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final b = _bookings[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A043).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_seat_rounded, color: Color(0xFFD4A043)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Гость: ${b['customer_name']}', 
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Тел: ${b['customer_phone']}', 
                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: 14, color: const Color(0xFFD4A043).withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text('${b['booking_time']}', 
                              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline, size: 14, color: const Color(0xFFD4A043).withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text('${b['guests_count']} чел', 
                              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A043).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _tablesMap[b['table_id'].toString()] ?? 'Стол: ${b['table_id']}', 
                            style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (b['status'] == 'confirmed')
                          _actionBtn('Принять', Colors.green, () => _acceptBooking(b['id'].toString())),
                        const SizedBox(width: 8),
                        _actionBtn('Освободить', Colors.redAccent, () => _freeTable(b['table_id']?.toString(), b['id'].toString())),
                        if (b['status'] == 'accepted')
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                Text('Принято', style: GoogleFonts.outfit(color: Colors.green, fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final tableRes = await Supabase.instance.client
          .from('orders_new')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      final deliveryRes = await Supabase.instance.client
          .from('delivery_orders')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      final callsRes = await Supabase.instance.client
          .from('waiter_calls')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 7));

      setState(() {
        _tableOrders = List<Map<String, dynamic>>.from(tableRes);
        _deliveryOrders = List<Map<String, dynamic>>.from(deliveryRes);
        _waiterCalls = List<Map<String, dynamic>>.from(callsRes);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _resolveCall(String id) async {
    await Supabase.instance.client
        .from('waiter_calls')
        .update({'status': 'resolved'})
        .eq('id', id);
    _loadOrders();
  }

  Future<void> _updateDeliveryStatus(String id, String status) async {
    await Supabase.instance.client
        .from('delivery_orders')
        .update({'status': status})
        .eq('id', id);
    _loadOrders();
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
      final tableId = order['table_id'] ?? 'unknown';
      grouped.putIfAbsent(tableId, () => []).add(order);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.map((entry) {
        final tableId = entry.key;
        final items = entry.value;
        final hasUnconfirmed = items.any((it) => it['status'] == 'ordering');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: hasUnconfirmed
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
                        color: hasUnconfirmed
                            ? const Color(0xFFD4A043)
                            : Colors.green,
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
                    if (hasUnconfirmed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Ожидает',
                          style: GoogleFonts.outfit(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              ...items.map((it) => _buildTableOrderItem(it)),
              const SizedBox(height: 8),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTableOrderItem(Map<String, dynamic> item) {
    final isOrdering = item['status'] == 'ordering';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: isOrdering ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              'Блюдо ID: ${(item['menu_item_id']?.toString().length ?? 0) > 8 ? item['menu_item_id'].toString().substring(0, 8) + '...' : item['menu_item_id'].toString()}',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
            ),
          ),
          Text(
            'x${item['quantity']}',
            style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryOrders() {
    if (_deliveryOrders.isEmpty) {
      return _buildEmpty('Заказов на доставку нет');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
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
                      'Итого: ${total.toStringAsFixed(0)} ₽',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        if (status == 'new')
                          _actionButton('В работу', Colors.blue, () => _updateDeliveryStatus(order['id'].toString(), 'processing')),
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
    );
  }

  Widget _statusChip(String status) {
    final map = {
      'new': ('Новый', Colors.orange),
      'processing': ('В работе', Colors.blue),
      'done': ('Готово', Colors.green),
      'cancelled': ('Отменён', Colors.red),
    };
    final (label, color) = map[status] ?? ('Неизвестно', Colors.grey);
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
                child: Text('ПОДОШЁЛ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/waiter_service.dart';

class WaiterOrdersScreen extends StatefulWidget {
  final Map<String, String> currentWaiter;

  const WaiterOrdersScreen({super.key, required this.currentWaiter});

  @override
  State<WaiterOrdersScreen> createState() => _WaiterOrdersScreenState();
}

class _WaiterOrdersScreenState extends State<WaiterOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  List<Map<String, dynamic>> _tables = [];
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOrders();
    _initRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  void _initRealtime() {
    _realtimeChannel = Supabase.instance.client
        .channel('waiter_orders_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders_new',
          callback: (payload) {
            _loadOrders(silent: true);
          },
        )
        .subscribe();
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final orders = await WaiterService.fetchOrders();
    final tables = await WaiterService.fetchTables();
    if (mounted) {
      setState(() {
        _orders = orders;
        _tables = tables;
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    final success = await WaiterService.updateOrderStatus(orderId, newStatus);
    if (mounted && success) {
      final statusLabel = newStatus == 'served'
          ? 'Подан'
          : newStatus == 'closed'
              ? 'Закрыт'
              : 'Обновлен';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заказ отмечен: $statusLabel ✅', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFD4A043),
        ),
      );
      _loadOrders(silent: true);
    }
  }

  Future<void> _confirmClearClosedOrders() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Очистить прошлые заказы?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Удалить все закрытые заказы прошлых смен, чтобы они не мешали сегодня?',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Очистить', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await WaiterService.clearClosedOrders();
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('История закрытых заказов очищена 🧹', style: GoogleFonts.outfit()),
              backgroundColor: const Color(0xFFD4A043),
            ),
          );
          _loadOrders();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiterId = widget.currentWaiter['id'];

    final myAssignedTables = _tables.where((t) => t['waiter_id']?.toString() == waiterId?.toString()).toList();
    final myTableIds = myAssignedTables.map((t) => t['id']?.toString()).toSet();
    final myTableLabels = myAssignedTables.map((t) => t['label']?.toString()).toSet();

    // Фильтрация: заказы ТОЛЬКО своих столов
    final myOrders = _orders.where((o) {
      final tid = (o['table_id'] ?? '').toString();
      final table = o['restaurant_tables'];
      if (table != null && table is Map && table['waiter_id']?.toString() == waiterId) {
        return true;
      }
      return myTableIds.contains(tid) || myTableLabels.contains(tid);
    }).toList();

    final tablesStr = myAssignedTables.map((t) => t['label'] ?? 'Стол').join(', ');

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            // Информационный баннер закрепленных столов
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: myAssignedTables.isNotEmpty
                      ? const Color(0xFFD4A043).withOpacity(0.4)
                      : Colors.redAccent.withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    myAssignedTables.isNotEmpty ? Icons.table_restaurant_rounded : Icons.warning_amber_rounded,
                    color: myAssignedTables.isNotEmpty ? const Color(0xFFD4A043) : Colors.redAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          myAssignedTables.isNotEmpty ? 'Ваши столы ($tablesStr)' : 'Нет закрепленных столов',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          myAssignedTables.isNotEmpty
                              ? 'Отображаются заказы только ваших столов'
                              : 'Закрепите столы во вкладке «Столы» для приема заказов',
                          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (myOrders.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A043),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${myOrders.length}',
                        style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                  : _buildOrdersList(
                      myOrders,
                      emptyMessage: myAssignedTables.isEmpty
                          ? 'Закрепите столы во вкладке «Столы», чтобы видеть их заказы'
                          : 'На ваших столах пока нет активных заказов',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllOrdersTab(List<Map<String, dynamic>> orders) {
    final closedCount = orders.where((o) => o['status'] == 'closed' || o['status'] == 'completed').length;

    return Column(
      children: [
        if (closedCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: const Color(0xFFD4A043).withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _confirmClearClosedOrders,
                icon: const Icon(Icons.cleaning_services_rounded, size: 18, color: Color(0xFFD4A043)),
                label: Text(
                  'Очистить прошлые заказы ($closedCount)',
                  style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        Expanded(
          child: _buildOrdersList(orders, emptyMessage: 'Заказы в ресторане отсутствуют'),
        ),
      ],
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> list, {required String emptyMessage}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(emptyMessage, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = list[index];
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as String;
    final status = (order['status'] ?? 'pending').toString();
    final items = order['items'] as List<dynamic>? ?? [];
    final totalAmount = order['total_amount'] ?? 0;
    final table = order['restaurant_tables'];
    String tableLabel = 'Стол №${order['table_id'] ?? '?'}';
    if (table != null && table is Map && table['label'] != null) {
      tableLabel = table['label'];
    }

    Color statusBg = Colors.orange.withOpacity(0.2);
    Color statusColor = Colors.orange;
    String statusTitle = 'В обработке';

    if (status == 'confirmed' || status == 'cooking') {
      statusBg = Colors.blue.withOpacity(0.2);
      statusColor = Colors.lightBlueAccent;
      statusTitle = 'Готовится';
    } else if (status == 'ready' || status == 'served') {
      statusBg = Colors.green.withOpacity(0.2);
      statusColor = Colors.greenAccent;
      statusTitle = 'Подан';
    } else if (status == 'closed' || status == 'completed') {
      statusBg = Colors.white.withOpacity(0.1);
      statusColor = Colors.white54;
      statusTitle = 'Закрыт';
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A043).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.restaurant_rounded, color: Color(0xFFD4A043), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    tableLabel,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusTitle,
                  style: GoogleFonts.outfit(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),

          // Список блюд
          Column(
            children: items.map((it) {
              final title = it['title'] ?? it['name'] ?? 'Блюдо';
              final qty = it['quantity'] ?? it['qty'] ?? 1;
              final price = it['price'] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$qty x $title',
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${price * qty} сом',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Итого:', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
              Text(
                '$totalAmount сом',
                style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Кнопка управления статусом
          Row(
            children: [
              if (status != 'ready' && status != 'served' && status != 'closed')
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _updateStatus(orderId, 'served'),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Подано', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
              if (status != 'ready' && status != 'served' && status != 'closed')
                const SizedBox(width: 8),
              if (status != 'closed')
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _updateStatus(orderId, 'closed'),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text('Закрыть заказ', style: GoogleFonts.outfit()),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

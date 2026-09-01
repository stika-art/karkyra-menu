import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/menu_data_service.dart';
import '../services/waiter_service.dart';

class WaiterOrdersScreen extends StatefulWidget {
  final Map<String, String> currentWaiter;

  const WaiterOrdersScreen({super.key, required this.currentWaiter});

  @override
  State<WaiterOrdersScreen> createState() => _WaiterOrdersScreenState();
}

class _WaiterOrdersScreenState extends State<WaiterOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  List<Map<String, dynamic>> _tables = [];
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    if (MenuDataService.items.isEmpty) {
      MenuDataService.load();
    }
    _loadOrders();
    _initRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
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

  String _getMenuItemTitle(String? menuItemId) {
    if (menuItemId == null) return 'Блюдо';
    try {
      final item = MenuDataService.items.firstWhere((m) => m.id == menuItemId);
      return item.title;
    } catch (_) {
      return 'Блюдо #${menuItemId.length > 8 ? menuItemId.substring(0, 8) : menuItemId}';
    }
  }

  Future<void> _updateTableStatus(String tableId, String newStatus) async {
    final success = await WaiterService.updateTableOrdersStatus(tableId, newStatus);
    if (mounted && success) {
      final statusLabel = newStatus == 'processing'
          ? 'Принят в готовку'
          : newStatus == 'served'
              ? 'Подан'
              : 'Закрыт';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Стол №$tableId: $statusLabel ✅', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFD4A043),
        ),
      );
      _loadOrders(silent: true);
    }
  }

  Future<void> _confirmClearTableOrders(String tableId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Очистить стол №$tableId?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Удалить все позиции заказов для стола №$tableId и освободить стол?',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Очистить стол', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await WaiterService.clearTableOrders(tableId);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Стол №$tableId очищен и готов к приему новых гостей 🧹', style: GoogleFonts.outfit()),
              backgroundColor: const Color(0xFFD4A043),
            ),
          );
          _loadOrders();
        }
      }
    }
  }

  Future<void> _confirmClearAllMyTablesOrders(List<String> tableIds) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Очистить ВСЕ ваши столы?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Удалить все текущие и старые заказы со всех закрепленных за вами столов?',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Очистить всё', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await WaiterService.clearAllMyTablesOrders(tableIds);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Все ваши столы успешно очищены 🧹', style: GoogleFonts.outfit()),
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

    // Фильтрация: заказы ТОЛЬКО своих столов
    final myOrders = _orders.where((o) {
      return WaiterService.isTableAssignedToWaiter(
        itemTableId: o['table_id'],
        waiterId: waiterId,
        allTables: _tables,
      );
    }).toList();

    // Группировка заказов по table_id
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var o in myOrders) {
      final tid = (o['table_id'] ?? '').toString();
      if (!grouped.containsKey(tid)) grouped[tid] = [];
      grouped[tid]!.add(o);
    }

    final tablesStr = myAssignedTables.map((t) => t['label'] ?? 'Стол').join(', ');
    final allMyTableIds = myAssignedTables.map((t) => t['id'].toString()).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            // Информационный баннер закрепленных столов с кнопкой очистки
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
                              ? 'Активных столов с заказами: ${grouped.length}'
                              : 'Закрепите столы во вкладке «Столы» для приема заказов',
                          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (grouped.isNotEmpty)
                    IconButton(
                      onPressed: () => _confirmClearAllMyTablesOrders(grouped.keys.toList()),
                      icon: const Icon(Icons.cleaning_services_rounded, color: Colors.redAccent, size: 22),
                      tooltip: 'Очистить все столы',
                    ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                  : grouped.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(
                                myAssignedTables.isEmpty
                                    ? 'Закрепите столы во вкладке «Столы», чтобы видеть их заказы'
                                    : 'На ваших столах нет активных заказов',
                                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: grouped.entries.map((entry) {
                            final tableId = entry.key;
                            final items = entry.value;
                            return _buildTableOrdersCard(tableId, items);
                          }).toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableOrdersCard(String tableId, List<Map<String, dynamic>> items) {
    final double totalAmount = items.fold(0.0, (sum, it) {
      final double price = (it['price'] ?? 0).toDouble();
      final int qty = (it['quantity'] ?? 1);
      return sum + (price * qty);
    });

    final bool isAnyCooking = items.any((it) => it['status'] == 'processing');
    final bool isAnyServed = items.any((it) => it['status'] == 'served');
    final bool isAllClosed = items.every((it) => it['status'] == 'closed');

    Color statusBg = Colors.orange.withOpacity(0.2);
    Color statusColor = Colors.orange;
    String statusTitle = 'Ожидает принятия';

    if (isAllClosed) {
      statusBg = Colors.white.withOpacity(0.1);
      statusColor = Colors.white54;
      statusTitle = 'Закрыт';
    } else if (isAnyServed) {
      statusBg = Colors.green.withOpacity(0.2);
      statusColor = Colors.greenAccent;
      statusTitle = 'Подан';
    } else if (isAnyCooking) {
      statusBg = Colors.blue.withOpacity(0.2);
      statusColor = Colors.lightBlueAccent;
      statusTitle = 'Готовится';
    }

    // Ищем читабельное название стола
    final tMatch = _tables.firstWhere(
      (t) => t['id']?.toString() == tableId || t['label']?.toString() == tableId,
      orElse: () => {},
    );
    final tableLabel = tMatch['label'] ?? 'Стол №$tableId';

    // Группируем блюда стола
    final Map<String, Map<String, dynamic>> groupedItems = {};
    for (var it in items) {
      final key = "${it['menu_item_id']}_${it['user_name'] ?? ''}";
      if (groupedItems.containsKey(key)) {
        groupedItems[key]!['quantity'] = (groupedItems[key]!['quantity'] as int) + (it['quantity'] as int);
      } else {
        groupedItems[key] = Map<String, dynamic>.from(it);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              Row(
                children: [
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
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _confirmClearTableOrders(tableId),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Очистить стол',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),

          // Список блюд
          Column(
            children: groupedItems.values.map((it) {
              final title = _getMenuItemTitle(it['menu_item_id']?.toString());
              final qty = it['quantity'] ?? 1;
              final price = (it['price'] ?? 0).toDouble();
              final userName = it['user_name']?.toString() ?? '';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$qty x $title',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          if (userName.isNotEmpty)
                            Text(
                              'Гость: $userName',
                              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${(price * qty).toStringAsFixed(0)} сом',
                      style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold),
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
              Text('Итого к оплате:', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
              Text(
                '${totalAmount.toStringAsFixed(0)} сом',
                style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Кнопки управления заказом стола
          Row(
            children: [
              if (!isAnyCooking && !isAnyServed && !isAllClosed)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _updateTableStatus(tableId, 'processing'),
                    icon: const Icon(Icons.soup_kitchen_rounded, size: 18),
                    label: Text('Принять заказ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
              if (isAnyCooking && !isAnyServed && !isAllClosed)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _updateTableStatus(tableId, 'served'),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Заказ подан', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.2),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _confirmClearTableOrders(tableId),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: Text('Очистить стол', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

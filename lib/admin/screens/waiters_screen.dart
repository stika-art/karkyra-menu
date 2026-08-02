import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WaitersScreen extends StatefulWidget {
  const WaitersScreen({super.key});

  @override
  State<WaitersScreen> createState() => _WaitersScreenState();
}

class _WaitersScreenState extends State<WaitersScreen> {
  List<Map<String, dynamic>> _waiters = [];
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('waiters')
          .select()
          .order('name');
      final tRes = await Supabase.instance.client.from('restaurant_tables').select().order('label');
      
      List<Map<String, dynamic>> oRes = [];
      try {
        final rawO = await Supabase.instance.client.from('orders_new').select();
        oRes = List<Map<String, dynamic>>.from(rawO);
      } catch (_) {}

      setState(() {
        _waiters = List<Map<String, dynamic>>.from(res);
        _tables = List<Map<String, dynamic>>.from(tRes);
        _orders = oRes;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _showAddWaiter([Map<String, dynamic>? existing]) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final telegramCtrl = TextEditingController(text: existing?['telegram_chat_id'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(existing == null ? 'Новый официант' : 'Редактировать',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(nameCtrl, 'Имя официанта'),
            const SizedBox(height: 12),
            _field(phoneCtrl, 'Номер телефона', keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _field(telegramCtrl, 'Telegram Chat ID (для уведомлений)', keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            Text('Узнать ID можно в боте @userinfobot', 
              style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            onPressed: () async {
              final data = {
                'name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'telegram_chat_id': telegramCtrl.text.trim(),
              };
              if (existing == null) {
                await Supabase.instance.client.from('waiters').insert(data);
              } else {
                await Supabase.instance.client.from('waiters').update(data).eq('id', existing['id']);
              }
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: GoogleFonts.outfit(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white24),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  void _showAssignTables(Map<String, dynamic> waiter) {
    final wId = waiter['id'];
    List<String> selectedTableIds = _tables
        .where((t) => t['waiter_id'] == wId)
        .map((t) => t['id'] as String)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text('Столы официанта: ${waiter['name']}', style: GoogleFonts.outfit(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tables.length,
                itemBuilder: (context, index) {
                  final t = _tables[index];
                  final tId = t['id'];
                  final isSelected = selectedTableIds.contains(tId);
                  final otherWaiter = t['waiter_id'] != null && t['waiter_id'] != wId;
                  
                  String label = t['label'] ?? 'Стол';
                  if (otherWaiter) {
                    final otherName = _waiters.firstWhere((w) => w['id'] == t['waiter_id'], orElse: () => {'name': 'другой'})['name'];
                    label += ' (закреплен: $otherName)';
                  }

                  return CheckboxListTile(
                    title: Text(label, style: const TextStyle(color: Colors.white)),
                    value: isSelected,
                    activeColor: const Color(0xFFD4A043),
                    checkColor: Colors.black,
                    onChanged: (val) {
                      setD(() {
                        if (val == true) {
                          selectedTableIds.add(tId);
                        } else {
                          selectedTableIds.remove(tId);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white38))),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() => _loading = true);
                  await Supabase.instance.client
                      .from('restaurant_tables')
                      .update({'waiter_id': null})
                      .eq('waiter_id', wId);
                  for (final tid in selectedTableIds) {
                    await Supabase.instance.client
                        .from('restaurant_tables')
                        .update({'waiter_id': wId})
                        .eq('id', tid);
                  }
                  _load();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
                child: const Text('Сохранить', style: TextStyle(color: Colors.black)),
              ),
            ],
          );
        }
      ),
    );
  }

  // Расчет аналитики по конкретному официанту
  Map<String, dynamic> _getWaiterStats(String waiterId) {
    final waiterTableIds = _tables
        .where((t) => t['waiter_id'] == waiterId)
        .map((t) => t['id'].toString())
        .toSet();

    int closedOrdersCount = 0;
    num totalRevenue = 0;

    for (final order in _orders) {
      final orderTableId = (order['table_id'] ?? '').toString();
      final status = (order['status'] ?? '').toString();

      // Учитываем заказы на столах официанта
      if (waiterTableIds.contains(orderTableId)) {
        if (status == 'closed' || status == 'completed' || status == 'served' || status == 'confirmed') {
          closedOrdersCount++;
          totalRevenue += (order['total_amount'] ?? 0);
        }
      }
    }

    return {
      'closedOrdersCount': closedOrdersCount,
      'totalRevenue': totalRevenue,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Подсчет общей аналитики по ресторану
    int totalClosedOrders = 0;
    num totalRestaurantRevenue = 0;
    for (final w in _waiters) {
      final st = _getWaiterStats(w['id']);
      totalClosedOrders += (st['closedOrdersCount'] as int);
      totalRestaurantRevenue += (st['totalRevenue'] as num);
    }
    final totalTips = (totalRestaurantRevenue * 0.10).toInt();

    return Column(
      children: [
        // Заголовок и Кнопка Добавить
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Официанты и Аналитика',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddWaiter(),
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Добавить официанта'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A043),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

        // Дашборд общей статистики
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryCard(
                title: 'Закрытых чеков',
                value: '$totalClosedOrders',
                icon: Icons.receipt_long_rounded,
                color: Colors.lightBlueAccent,
              ),
              Container(height: 40, width: 1, color: Colors.white12),
              _buildSummaryCard(
                title: 'Общая выручка',
                value: '$totalRestaurantRevenue сом',
                icon: Icons.monetization_on_rounded,
                color: const Color(0xFFD4A043),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Список официантов с индивидуальной статистикой
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _waiters.length,
                  itemBuilder: (_, i) {
                    final w = _waiters[i];
                    final wId = w['id'] as String;
                    final assignedTables = _tables.where((t) => t['waiter_id'] == wId).toList();
                    final tableLabels = assignedTables.map((t) => (t['label'] ?? 'Стол').toString()).join(', ');
                    final stats = _getWaiterStats(wId);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(0xFFD4A043).withOpacity(0.15),
                                child: Text(
                                  (w['name'] ?? 'W')[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFFD4A043),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      w['name'] ?? 'Официант',
                                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Тел: ${w['phone'] ?? 'Не указан'}',
                                      style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.table_restaurant_rounded, size: 14, color: Color(0xFFD4A043)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            assignedTables.isEmpty ? 'Нет закрепленных столов' : 'Столы: $tableLabels',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: assignedTables.isEmpty ? Colors.white38 : const Color(0xFFD4A043),
                                              fontSize: 13,
                                              fontWeight: assignedTables.isEmpty ? FontWeight.normal : FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Блок индивидуальной аналитики и чаевых
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatMetric(
                                  label: 'Закрытых чеков',
                                  value: '${stats['closedOrdersCount']}',
                                  color: Colors.white70,
                                ),
                                _buildStatMetric(
                                  label: 'Выручка',
                                  value: '${stats['totalRevenue']} сом',
                                  color: const Color(0xFFD4A043),
                                ),
                              ],
                            ),
                          ),

                          const Divider(color: Colors.white12, height: 24),
                          
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showAssignTables(w), 
                                  icon: const Icon(Icons.table_restaurant_rounded, size: 18, color: Color(0xFFD4A043)),
                                  label: Text('Закрепить столы', style: GoogleFonts.outfit(color: const Color(0xFFD4A043))),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFD4A043)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                                child: IconButton(onPressed: () => _showAddWaiter(w), icon: const Icon(Icons.edit_rounded, color: Colors.white70)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: IconButton(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: const Color(0xFF1E1E1E),
                                        title: Text('Удалить официанта?', style: GoogleFonts.outfit(color: Colors.white)),
                                        content: Text('Вы уверены, что хотите удалить ${w['name']}?', style: GoogleFonts.outfit(color: Colors.white70)),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена', style: TextStyle(color: Colors.white38))),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.redAccent))),
                                        ],
                                      )
                                    );
                                    if (confirm == true) {
                                      await Supabase.instance.client.from('waiters').delete().eq('id', w['id']);
                                      _load();
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.outfit(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(title, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildStatMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(color: color, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

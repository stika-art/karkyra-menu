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
    final pinCtrl = TextEditingController(text: existing?['pin']?.toString() ?? '1234');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(existing == null ? 'Новый официант' : 'Редактировать официанта',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(nameCtrl, 'Имя официанта'),
            const SizedBox(height: 12),
            _field(phoneCtrl, 'Номер телефона', keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _field(pinCtrl, 'ПИН-код для входа (например: 1234)', keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final pin = pinCtrl.text.trim().isEmpty ? '1234' : pinCtrl.text.trim();
              final data = {
                'name': name,
                'phone': phoneCtrl.text.trim(),
                'pin': pin,
              };
              if (existing == null) {
                await Supabase.instance.client.from('waiters').insert(data);
              } else {
                await Supabase.instance.client.from('waiters').update(data).eq('id', existing['id']);
              }
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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

  // Расчет аналитики по конкретному официанту
  Map<String, dynamic> _getWaiterStats(String waiterId) {
    final waiterTableIds = _tables
        .where((t) => t['waiter_id']?.toString() == waiterId.toString())
        .map((t) => t['id'].toString())
        .toSet();

    int closedOrdersCount = 0;
    num totalRevenue = 0;

    for (final order in _orders) {
      final orderTableId = (order['table_id'] ?? '').toString();
      final status = (order['status'] ?? '').toString();

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
    int totalClosedOrders = 0;
    num totalRestaurantRevenue = 0;
    for (final w in _waiters) {
      final st = _getWaiterStats(w['id'].toString());
      totalClosedOrders += (st['closedOrdersCount'] as int);
      totalRestaurantRevenue += (st['totalRevenue'] as num);
    }

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
                    final wId = w['id'].toString();
                    final assignedTables = _tables.where((t) => t['waiter_id']?.toString() == wId).toList();
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
                                    Row(
                                      children: [
                                        Text(
                                          'Тел: ${w['phone'] ?? 'Не указан'}',
                                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD4A043).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.4)),
                                          ),
                                          child: Text(
                                            'PIN: ${w['pin'] ?? '1234'}',
                                            style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
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

                              // Кнопки действия (Редактировать, Удалить)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                                    child: IconButton(
                                      onPressed: () => _showAddWaiter(w),
                                      icon: const Icon(Icons.edit_rounded, color: Colors.white70),
                                      tooltip: 'Редактировать',
                                    ),
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
                                      tooltip: 'Удалить',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Блок индивидуальной аналитики (Чеки и Выручка)
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

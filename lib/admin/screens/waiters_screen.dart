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
      setState(() {
        _waiters = List<Map<String, dynamic>>.from(res);
        _tables = List<Map<String, dynamic>>.from(tRes);
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
            child: const Text('Сохранить'),
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
                  // First, unassign all tables currently assigned to this waiter
                  await Supabase.instance.client
                      .from('restaurant_tables')
                      .update({'waiter_id': null})
                      .eq('waiter_id', wId);
                  // Then, assign selected ones
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Официанты',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => _showAddWaiter(),
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Добавить'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _waiters.length,
                  itemBuilder: (_, i) {
                    final w = _waiters[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(0xFFD4A043).withOpacity(0.1),
                                child: const Icon(Icons.person, color: Color(0xFFD4A043)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(w['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text('ID: ${w['telegram_chat_id'] ?? 'Не указан'}', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('Столов: ${_tables.where((t) => t['waiter_id'] == w['id']).length}', style: const TextStyle(color: Color(0xFFD4A043), fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showAssignTables(w), 
                                  icon: const Icon(Icons.table_restaurant_rounded, size: 18, color: Color(0xFFD4A043)),
                                  label: const Text('Столы', style: TextStyle(color: Color(0xFFD4A043))),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFD4A043)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                                child: IconButton(onPressed: () => _showAddWaiter(w), icon: const Icon(Icons.edit_rounded, color: Colors.white70)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: IconButton(
                                  onPressed: () async {
                                    // Show confirmation before deleting
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: const Color(0xFF1E1E1E),
                                        title: const Text('Удалить официанта?', style: TextStyle(color: Colors.white)),
                                        content: Text('Вы уверены, что хотите удалить ${w['name']}? Это действие нельзя отменить.', style: const TextStyle(color: Colors.white70)),
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
}

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
      setState(() {
        _waiters = List<Map<String, dynamic>>.from(res);
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
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFD4A043).withOpacity(0.1),
                          child: const Icon(Icons.person, color: Color(0xFFD4A043)),
                        ),
                        title: Text(w['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('ID: ${w['telegram_chat_id'] ?? 'Не указан'}', style: const TextStyle(color: Colors.white38)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(onPressed: () => _showAddWaiter(w), icon: const Icon(Icons.edit_rounded, color: Colors.white38)),
                            IconButton(
                              onPressed: () async {
                                await Supabase.instance.client.from('waiters').delete().eq('id', w['id']);
                                _load();
                              },
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

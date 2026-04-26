import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BanquetScreen extends StatefulWidget {
  const BanquetScreen({super.key});

  @override
  State<BanquetScreen> createState() => _BanquetScreenState();
}

class _BanquetScreenState extends State<BanquetScreen> {
  List<Map<String, dynamic>> _sets = [];
  List<Map<String, dynamic>> _allDishes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // 1. Загружаем сеты
      final setsRes = await Supabase.instance.client
          .from('banquet_menu')
          .select()
          .order('created_at', ascending: false);
      
      // 2. Загружаем все блюда для выборщика
      final allDishesRes = await Supabase.instance.client
          .from('menu_items_db')
          .select()
          .eq('is_available', true);

      setState(() {
        _sets = List<Map<String, dynamic>>.from(setsRes);
        _allDishes = List<Map<String, dynamic>>.from(allDishesRes);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load banquet error: $e');
      setState(() => _loading = false);
    }
  }

  void _editSet([Map<String, dynamic>? set]) {
    final isNew = set == null;
    final titleCtrl = TextEditingController(text: set?['title'] ?? '');
    final priceCtrl = TextEditingController(text: set?['price']?.toString() ?? '');
    final descCtrl = TextEditingController(text: set?['description'] ?? '');
    final photoCtrl = TextEditingController(text: set?['image_url'] ?? '');
    List<String> selectedDishIds = List<String>.from(set?['dish_ids'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(isNew ? 'Новый банкетный сет' : 'Редактировать сет',
              style: GoogleFonts.outfit(color: Colors.white)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(titleCtrl, 'Название (напр. Сет №1)'),
                  const SizedBox(height: 12),
                  _field(priceCtrl, 'Цена за персону', keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _field(descCtrl, 'Краткое описание', maxLines: 2),
                  const SizedBox(height: 12),
                  _field(photoCtrl, 'Ссылка на фотографию сета'),
                  const SizedBox(height: 20),
                  Text('Состав сета (блюда из меню):', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      ...selectedDishIds.map((id) {
                        final dish = _allDishes.firstWhere((d) => d['id'] == id, orElse: () => {'title': 'Удалено'});
                        return Chip(
                          label: Text(dish['title'], style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setD(() => selectedDishIds.remove(id)),
                          backgroundColor: const Color(0xFFD4A043).withOpacity(0.1),
                          labelStyle: const TextStyle(color: Color(0xFFD4A043)),
                        );
                      }),
                      ActionChip(
                        label: const Text('+ Добавить блюдо'),
                        onPressed: () async {
                          final picked = await _pickDish();
                          if (picked != null) {
                            setD(() => selectedDishIds.add(picked['id']));
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'title': titleCtrl.text.trim(),
                  'price': int.tryParse(priceCtrl.text.trim()) ?? 0,
                  'description': descCtrl.text.trim(),
                  'dish_ids': selectedDishIds,
                  'image_url': photoCtrl.text.trim(),
                };
                if (isNew) {
                  await Supabase.instance.client.from('banquet_menu').insert(data);
                } else {
                  await Supabase.instance.client.from('banquet_menu').update(data).eq('id', set['id']);
                }
                Navigator.pop(ctx);
                _loadAll();
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _pickDish() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Выберите блюдо из меню', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _allDishes.length,
            itemBuilder: (_, i) {
              final d = _allDishes[i];
              return ListTile(
                title: Text(d['title'], style: const TextStyle(color: Colors.white)),
                subtitle: Text('${d['price']} сом', style: const TextStyle(color: Colors.white38)),
                onTap: () => Navigator.pop(ctx, d),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
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
        Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          color: const Color(0xFF1A1A1A),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Банкетные сеты', style: GoogleFonts.outfit(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => _editSet(),
                icon: const Icon(Icons.add),
                label: const Text('Создать сет'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _sets.isEmpty
                  ? const Center(child: Text('Сеты пока не созданы', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sets.length,
                      itemBuilder: (_, i) {
                        final s = _sets[i];
                        final dishCount = (s['dish_ids'] as List?)?.length ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                child: s['image_url'] != null && s['image_url'].toString().isNotEmpty
                                    ? Image.network(s['image_url'], width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (_,__,___) => _photoPh())
                                    : _photoPh(),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                    Text('$dishCount блюд в составе', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                                    Text('${s['price']} сом / чел', style: const TextStyle(color: Color(0xFFD4A043), fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              IconButton(onPressed: () => _editSet(s), icon: const Icon(Icons.edit_rounded, color: Colors.white38)),
                              IconButton(
                                onPressed: () async {
                                  await Supabase.instance.client.from('banquet_menu').delete().eq('id', s['id']);
                                  _loadAll();
                                },
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
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

  Widget _photoPh() => Container(width: 100, height: 100, color: Colors.white10, child: const Icon(Icons.celebration_rounded, color: Colors.white24));
}

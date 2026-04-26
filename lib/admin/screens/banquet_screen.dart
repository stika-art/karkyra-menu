import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

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
      final setsRes = await Supabase.instance.client
          .from('banquet_menu')
          .select()
          .order('created_at', ascending: false);
      
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
    String? currentPhotoUrl = set?['image_url'];
    List<String> selectedDishIds = List<String>.from(set?['dish_ids'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          bool isUploading = false;

          Future<void> pickImage() async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              withData: true,
            );
            if (result == null || result.files.isEmpty) return;
            
            setD(() => isUploading = true);
            try {
              final file = result.files.first;
              final ext = file.name.split('.').last;
              final path = 'banquets/${DateTime.now().millisecondsSinceEpoch}.${ext}';
              
              await Supabase.instance.client.storage.from('media').uploadBinary(
                path,
                file.bytes!,
                fileOptions: FileOptions(contentType: 'image/$ext'),
              );
              
              final url = Supabase.instance.client.storage.from('media').getPublicUrl(path);
              setD(() {
                currentPhotoUrl = url;
                isUploading = false;
              });
            } catch (e) {
              setD(() => isUploading = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(isNew ? 'Новый банкетный сет' : 'Редактировать сет',
                style: GoogleFonts.outfit(color: Colors.white)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Секция фото
                    Center(
                      child: GestureDetector(
                        onTap: isUploading ? null : pickImage,
                        child: Container(
                          width: 200,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                            image: currentPhotoUrl != null
                                ? DecorationImage(image: NetworkImage(currentPhotoUrl!), fit: BoxFit.cover)
                                : null,
                          ),
                          child: isUploading
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                              : currentPhotoUrl == null
                                  ? const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_a_photo_rounded, color: Colors.white38, size: 32),
                                        SizedBox(height: 8),
                                        Text('Загрузить фото', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                      ],
                                    )
                                  : Container(
                                      alignment: Alignment.bottomRight,
                                      padding: const EdgeInsets.all(8),
                                      child: const CircleAvatar(
                                        backgroundColor: Colors.black54,
                                        radius: 14,
                                        child: Icon(Icons.edit, size: 14, color: Colors.white),
                                      ),
                                    ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _field(titleCtrl, 'Название (напр. Сет №1)'),
                    const SizedBox(height: 12),
                    _field(priceCtrl, 'Цена за персону', keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    _field(descCtrl, 'Краткое описание', maxLines: 2),
                    const SizedBox(height: 24),
                    Text('Состав сета (блюда из меню):', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
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
                            deleteIconColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16, color: Colors.black),
                          label: const Text('Добавить блюдо', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          backgroundColor: const Color(0xFFD4A043),
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white38))),
              ElevatedButton(
                onPressed: () async {
                  final data = {
                    'title': titleCtrl.text.trim(),
                    'price': int.tryParse(priceCtrl.text.trim()) ?? 0,
                    'description': descCtrl.text.trim(),
                    'dish_ids': selectedDishIds,
                    'image_url': currentPhotoUrl,
                  };
                  if (isNew) {
                    await Supabase.instance.client.from('banquet_menu').insert(data);
                  } else {
                    await Supabase.instance.client.from('banquet_menu').update(data).eq('id', set['id']);
                  }
                  Navigator.pop(ctx);
                  _loadAll();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black),
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
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
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _allDishes.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
            itemBuilder: (_, i) {
              final d = _allDishes[i];
              return ListTile(
                title: Text(d['title'], style: const TextStyle(color: Colors.white)),
                trailing: Text('${d['price']} сом', style: const TextStyle(color: Color(0xFFD4A043))),
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
        hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A043), 
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
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
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E), 
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
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
                                    const SizedBox(height: 4),
                                    Text('$dishCount блюд в составе', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                                    Text('${s['price']} сом / чел', style: const TextStyle(color: Color(0xFFD4A043), fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                              ),
                              IconButton(onPressed: () => _editSet(s), icon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 20)),
                              IconButton(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E1E),
                                      title: const Text('Удалить сет?', style: TextStyle(color: Colors.white)),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
                                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да', style: TextStyle(color: Colors.redAccent))),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await Supabase.instance.client.from('banquet_menu').delete().eq('id', s['id']);
                                    _loadAll();
                                  }
                                },
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _photoPh() => Container(width: 100, height: 100, color: Colors.white.withOpacity(0.05), child: const Icon(Icons.celebration_rounded, color: Colors.white12, size: 32));
}

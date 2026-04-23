import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  List<Map<String, dynamic>> _ingredients = [];
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
          .from('ingredients')
          .select()
          .eq('is_active', true)
          .order('name');
      setState(() {
        _ingredients = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _snack('Ошибка загрузки: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showForm([Map<String, dynamic>? existing]) {
    final isNew = existing == null;
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final photoCtrl = TextEditingController(text: existing?['photo_url'] ?? '');
    bool uploading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isNew ? 'Новый ингредиент' : 'Редактировать',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Название
              Text('Название', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: _inputDecor('Например: Говядина'),
              ),
              const SizedBox(height: 16),

              // Фото
              Text('Фото ингредиента', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Превью фото
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: photoCtrl.text.isNotEmpty
                        ? Image.network(photoCtrl.text, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_rounded,
                              color: Colors.white24, size: 24))
                        : const Icon(Icons.add_photo_alternate_rounded,
                            color: Colors.white24, size: 24),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        // Загрузить с устройства
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: uploading ? null : () async {
                              final result = await FilePicker.platform.pickFiles(
                                type: FileType.image,
                                withData: true,
                              );
                              if (result == null || result.files.first.bytes == null) return;
                              final file = result.files.first;
                              setD(() => uploading = true);
                              try {
                                final path = 'ingredients/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                                await Supabase.instance.client.storage.from('media').uploadBinary(
                                  path, file.bytes!,
                                  fileOptions: FileOptions(contentType: 'image/${file.extension}', upsert: true),
                                );
                                final url = Supabase.instance.client.storage.from('media').getPublicUrl(path);
                                setD(() { photoCtrl.text = url; uploading = false; });
                              } catch (e) {
                                setD(() => uploading = false);
                              }
                            },
                            icon: uploading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.upload_rounded, size: 16),
                            label: Text(uploading ? 'Загрузка...' : 'Загрузить',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4A043),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  if (isNew) {
                    await Supabase.instance.client.from('ingredients').insert({
                      'name': name,
                      'photo_url': photoCtrl.text.trim().isEmpty ? null : photoCtrl.text.trim(),
                    });
                  } else {
                    await Supabase.instance.client.from('ingredients').update({
                      'name': name,
                      'photo_url': photoCtrl.text.trim().isEmpty ? null : photoCtrl.text.trim(),
                    }).eq('id', existing!['id']);
                  }
                  _load();
                  _snack(isNew ? 'Ингредиент добавлен' : 'Сохранено', Colors.green);
                } catch (e) {
                  _snack('Ошибка: $e', Colors.red);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A043),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(isNew ? 'Создать' : 'Сохранить',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Удалить ингредиент?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Удалить', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Supabase.instance.client.from('ingredients').update({'is_active': false}).eq('id', id);
      _load();
    }
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.outfit(color: Colors.white38),
    filled: true,
    fillColor: const Color(0xFF2A2A2A),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ингредиенты', style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                Text('${_ingredients.length} позиций в базе',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13)),
              ]),
              ElevatedButton.icon(
                onPressed: () => _showForm(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Добавить', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A043),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
              : _ingredients.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🥕', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('Ингредиентов нет',
                        style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Добавьте первый ингредиент',
                        style: GoogleFonts.outfit(color: Colors.white24, fontSize: 13)),
                    ]))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _ingredients.length,
                      itemBuilder: (_, i) {
                        final ing = _ingredients[i];
                        return GestureDetector(
                          onTap: () => _showForm(ing),
                          onLongPress: () => _delete(ing['id']),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Фото
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: ing['photo_url'] != null
                                      ? Image.network(
                                          ing['photo_url'],
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _photoPlaceholder(),
                                        )
                                      : _photoPlaceholder(),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    ing['name'] ?? '',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Удерж. для удаления',
                                  style: GoogleFonts.outfit(color: Colors.white24, fontSize: 9)),
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

  Widget _photoPlaceholder() => Container(
    width: 72, height: 72,
    decoration: BoxDecoration(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.eco_rounded, color: Colors.white24, size: 28),
  );
}

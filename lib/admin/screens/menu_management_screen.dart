import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

// ============================================================
// Экран списка категорий
// ============================================================
class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  List<Map<String, dynamic>> _categories = [];
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
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('sort_order');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _snack('Ошибка загрузки категорий. Выполните SQL в Supabase!', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showAddCategory([Map<String, dynamic>? existing]) {
    final isNew = existing == null;
    final titleCtrl = TextEditingController(text: existing?['title'] ?? '');
    String icon = existing?['icon'] ?? '🍽';
    final icons = ['🍽','🥩','🍲','🥗','🍜','🍣','🍕','🧆','🥤','🍰','🫕','🥘','🍱','🌮','🥙','🍔','🍟'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isNew ? 'Новая категория' : 'Редактировать категорию',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Название категории *',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Text('Иконка', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: icons.map((ic) => GestureDetector(
                  onTap: () => setD(() => icon = ic),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: icon == ic ? const Color(0xFFD4A043).withOpacity(0.15) : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(10),
                      border: icon == ic ? Border.all(color: const Color(0xFFD4A043)) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(ic, style: const TextStyle(fontSize: 22)),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white38))),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  if (isNew) {
                    await Supabase.instance.client.from('categories').insert({
                      'title': title,
                      'icon': icon,
                      'sort_order': _categories.length,
                      'is_active': true,
                    });
                    _snack('Категория "$title" создана ✅', Colors.green);
                  } else {
                    await Supabase.instance.client.from('categories').update({
                      'title': title,
                      'icon': icon,
                    }).eq('id', existing!['id']);
                    _snack('Сохранено', Colors.green);
                  }
                  _load();
                } catch (e) {
                  _snack('Ошибка: ${e.toString()}', Colors.red);
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

  Future<void> _deleteCategory(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Удалить "$title"?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Все блюда в этой категории тоже удалятся.',
          style: GoogleFonts.outfit(color: Colors.white54)),
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
      await Supabase.instance.client.from('categories').update({'is_active': false}).eq('id', id);
      _load();
    }
  }

  Future<int> _getDishCount(String categoryId) async {
    try {
      final res = await Supabase.instance.client
          .from('menu_items_db').select('id').eq('category_id', categoryId).eq('is_available', true);
      return (res as List).length;
    } catch (_) { return 0; }
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
              Text('Меню', style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => _showAddCategory(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Категория', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
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
              : _categories.isEmpty
                  ? _buildEmpty()
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _categories.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) newIndex--;
                        setState(() {
                          final item = _categories.removeAt(oldIndex);
                          _categories.insert(newIndex, item);
                        });
                        for (int i = 0; i < _categories.length; i++) {
                          await Supabase.instance.client.from('categories')
                              .update({'sort_order': i}).eq('id', _categories[i]['id']);
                        }
                      },
                      itemBuilder: (context, i) {
                        final cat = _categories[i];
                        return Container(
                          key: ValueKey(cat['id']),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 52, height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4A043).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(cat['icon'] ?? '🍽', style: const TextStyle(fontSize: 26)),
                            ),
                            title: Text(cat['title'] ?? '',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: FutureBuilder<int>(
                              future: _getDishCount(cat['id']),
                              builder: (_, snap) => Text('${snap.data ?? 0} блюд',
                                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13)),
                            ),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, color: Color(0xFFD4A043), size: 20),
                                onPressed: () => _showAddCategory(cat),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                onPressed: () => _deleteCategory(cat['id'], cat['title'] ?? ''),
                              ),
                              const Icon(Icons.drag_handle_rounded, color: Colors.white24),
                            ]),
                            onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => DishesListScreen(category: cat))
                            ).then((_) => _load()),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍽', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('Создайте первую категорию',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 17)),
          const SizedBox(height: 4),
          Text('Например: Горячие блюда, Напитки',
            style: GoogleFonts.outfit(color: Colors.white24, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddCategory(),
            icon: const Icon(Icons.add_rounded),
            label: Text('Добавить категорию', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A043),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Экран блюд категории
// ============================================================
class DishesListScreen extends StatefulWidget {
  final Map<String, dynamic> category;
  const DishesListScreen({super.key, required this.category});

  @override
  State<DishesListScreen> createState() => _DishesListScreenState();
}

class _DishesListScreenState extends State<DishesListScreen> {
  List<Map<String, dynamic>> _dishes = [];
  List<Map<String, dynamic>> _allIngredients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dishRes = await Supabase.instance.client
          .from('menu_items_db').select().eq('category_id', widget.category['id'])
          .eq('is_available', true).order('sort_order');
      final ingRes = await Supabase.instance.client
          .from('ingredients').select().eq('is_active', true).order('name');
      setState(() {
        _dishes = List<Map<String, dynamic>>.from(dishRes);
        _allIngredients = List<Map<String, dynamic>>.from(ingRes);
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
      SnackBar(content: Text(msg, style: GoogleFonts.outfit()),
        backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<List<String>> _getDishIngredients(String dishId) async {
    try {
      final res = await Supabase.instance.client
          .from('dish_ingredients').select('ingredient_id').eq('dish_id', dishId);
      return (res as List).map((r) => r['ingredient_id'] as String).toList();
    } catch (_) { return []; }
  }

  Future<void> _saveDishIngredients(String dishId, List<String> ingredientIds) async {
    try {
      await Supabase.instance.client.from('dish_ingredients').delete().eq('dish_id', dishId);
      if (ingredientIds.isNotEmpty) {
        await Supabase.instance.client.from('dish_ingredients').insert(
          ingredientIds.map((id) => {'dish_id': dishId, 'ingredient_id': id}).toList(),
        );
      }
    } catch (_) {}
  }

  void _showEditDish([Map<String, dynamic>? dish]) async {
    final isNew = dish == null;
    final titleCtrl = TextEditingController(text: dish?['title'] ?? '');
    final priceCtrl = TextEditingController(text: dish?['price']?.toString() ?? '');
    final descCtrl = TextEditingController(text: dish?['description'] ?? '');
    final weightCtrl = TextEditingController(text: dish?['weight'] ?? '');
    final photoCtrl1 = TextEditingController(text: dish?['photo_url'] ?? '');
    final photoCtrl2 = TextEditingController(text: dish?['photo_url2'] ?? '');
    final photoCtrl3 = TextEditingController(text: dish?['photo_url3'] ?? '');
    final calCtrl = TextEditingController(text: dish?['calories']?.toString() ?? '');
    final protCtrl = TextEditingController(text: dish?['proteins']?.toString() ?? '');
    final fatCtrl = TextEditingController(text: dish?['fats']?.toString() ?? '');
    final carbCtrl = TextEditingController(text: dish?['carbs']?.toString() ?? '');

    int spice = dish?['spice_level'] ?? 0;
    bool isHit = dish?['is_hit'] ?? false;
    bool isNewTag = dish?['is_new'] ?? false;
    bool isChef = dish?['is_chef_choice'] ?? false;
    bool isTop = dish?['is_top'] ?? false;
    bool isPromo = dish?['is_promo'] ?? false;
    List<bool> photoUploading = [false, false, false];

    // Загружаем ингредиенты блюда
    List<String> selectedIngredients = isNew ? [] : await _getDishIngredients(dish!['id']);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
            child: Column(
              children: [
                // Заголовок
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isNew ? 'Новое блюдо' : 'Редактировать блюдо',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white38)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // === ФОТО ===
                        _sectionLabel('Фотографии блюда (до 3-х)'),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 100,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _photoSlot(1, photoCtrl1, photoUploading[0], (v) => setD(() => photoUploading[0] = v), setD),
                              _photoSlot(2, photoCtrl2, photoUploading[1], (v) => setD(() => photoUploading[1] = v), setD),
                              _photoSlot(3, photoCtrl3, photoUploading[2], (v) => setD(() => photoUploading[2] = v), setD),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // === ОСНОВНОЕ ===
                        _sectionLabel('Основная информация'),
                        const SizedBox(height: 8),
                        _field(titleCtrl, 'Название блюда *'),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _field(priceCtrl, 'Цена *', type: TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _field(weightCtrl, 'Выход (г/мл)')),
                        ]),
                        const SizedBox(height: 10),
                        _field(descCtrl, 'Описание', maxLines: 2),
                        const SizedBox(height: 16),

                        // === КБЖУ ===
                        _sectionLabel('КБЖУ (на 100г)'),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _field(calCtrl, 'Ккал', type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: _field(protCtrl, 'Белки', type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: _field(fatCtrl, 'Жиры', type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: _field(carbCtrl, 'Углев.', type: TextInputType.number)),
                        ]),
                        const SizedBox(height: 16),

                        // === ОСТРОТА ===
                        _sectionLabel('Острота блюда'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ...List.generate(5, (i) => GestureDetector(
                              onTap: () => setD(() => spice = spice == i + 1 ? 0 : i + 1),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('🌶', style: TextStyle(
                                  fontSize: 28,
                                  color: i < spice ? Colors.red : Colors.white24,
                                )),
                              ),
                            )),
                            const SizedBox(width: 8),
                            Text(
                              spice == 0 ? 'Не острое' : ['Слегка', 'Средне', 'Остро', 'Очень остро', 'Экстремально'][spice - 1],
                              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // === МЕТКИ ===
                        _sectionLabel('Метки и фильтры'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            _filterChip('🔥 Топ', isTop, const Color(0xFFFF8C00), (v) => setD(() => isTop = v)),
                            _filterChip('✨ Новинки', isNewTag, const Color(0xFFFFD700), (v) => setD(() => isNewTag = v)),
                            _filterChip('👨‍🍳 От шефа', isChef, const Color(0xFFD4AF37), (v) => setD(() => isChef = v)),
                            _filterChip('🏷 Акции', isPromo, const Color(0xFF00C9FF), (v) => setD(() => isPromo = v)),
                            _filterChip('⭐ Хиты', isHit, const Color(0xFFEE9CA7), (v) => setD(() => isHit = v)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // === ИНГРЕДИЕНТЫ ===
                        _sectionLabel('Состав (ингредиенты)'),
                        const SizedBox(height: 8),
                        if (_allIngredients.isEmpty)
                          Text(
                            'Ингредиенты не найдены. Добавьте их в разделе "Ингредиенты".',
                            style: GoogleFonts.outfit(color: Colors.white24, fontSize: 13),
                          )
                        else ...[
                          // Отображаем выбранные ингредиенты
                          if (selectedIngredients.isNotEmpty)
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: selectedIngredients.map((id) {
                                final ing = _allIngredients.firstWhere(
                                  (it) => it['id'] == id,
                                  orElse: () => {'name': '?', 'photo_url': null},
                                );
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4A043).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.4)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (ing['photo_url'] != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(ing['photo_url'], width: 20, height: 20, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const SizedBox()),
                                      ),
                                    if (ing['photo_url'] != null) const SizedBox(width: 6),
                                    Text(ing['name'], style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 12)),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => setD(() => selectedIngredients.remove(id)),
                                      child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFD4A043)),
                                    ),
                                  ]),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 8),
                          // Кнопка выбора ингредиентов
                          GestureDetector(
                            onTap: () async {
                              final result = await showDialog<List<String>>(
                                context: ctx,
                                builder: (_) => _IngredientPickerDialog(
                                  allIngredients: _allIngredients,
                                  selectedIds: List.from(selectedIngredients),
                                ),
                              );
                              if (result != null) {
                                setD(() => selectedIngredients = result);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.checklist_rounded, color: Colors.white38, size: 18),
                                const SizedBox(width: 8),
                                Text('Выбрать ингредиенты (${_allIngredients.length} доступно)',
                                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13)),
                              ]),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                // Кнопка сохранения
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        final price = double.tryParse(priceCtrl.text.trim());
                        if (title.isEmpty || price == null) {
                          _snack('Заполните название и цену', Colors.orange);
                          return;
                        }
                        final data = {
                          'category_id': widget.category['id'],
                          'title': title,
                          'price': price,
                          'description': descCtrl.text.trim(),
                          'weight': weightCtrl.text.trim().isEmpty ? null : weightCtrl.text.trim(),
                          'photo_url': photoCtrl1.text.trim().isEmpty ? null : photoCtrl1.text.trim(),
                          'photo_url2': photoCtrl2.text.trim().isEmpty ? null : photoCtrl2.text.trim(),
                          'photo_url3': photoCtrl3.text.trim().isEmpty ? null : photoCtrl3.text.trim(),
                          'calories': double.tryParse(calCtrl.text),
                          'proteins': double.tryParse(protCtrl.text),
                          'fats': double.tryParse(fatCtrl.text),
                          'carbs': double.tryParse(carbCtrl.text),
                          'spice_level': spice,
                          'is_hit': isHit,
                          'is_new': isNewTag,
                          'is_chef_choice': isChef,
                          'is_top': isTop,
                          'is_promo': isPromo,
                          'sort_order': _dishes.length,
                          'is_available': true,
                        };
                        Navigator.pop(ctx);
                        try {
                          if (isNew) {
                            final res = await Supabase.instance.client
                                .from('menu_items_db').insert(data).select();
                            final newId = (res as List).first['id'];
                            await _saveDishIngredients(newId, selectedIngredients);
                          } else {
                            await Supabase.instance.client
                                .from('menu_items_db').update(data).eq('id', dish!['id']);
                            await _saveDishIngredients(dish['id'], selectedIngredients);
                          }
                          _snack(isNew ? 'Блюдо добавлено ✅' : 'Сохранено ✅', Colors.green);
                          _load();
                        } catch (e) {
                          _snack('Ошибка: ${e.toString()}', Colors.red);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A043),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(isNew ? 'Добавить блюдо' : 'Сохранить',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDish(String id) async {
    await Supabase.instance.client.from('menu_items_db').update({'is_available': false}).eq('id', id);
    _load();
  }

  Widget _sectionLabel(String text) => Text(text,
    style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600));

  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl, maxLines: maxLines, keyboardType: type,
      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
        filled: true, fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, Color color, ValueChanged<bool> onChange) {
    return FilterChip(
      label: Text(label, style: GoogleFonts.outfit(fontSize: 13)),
      selected: selected,
      onSelected: onChange,
      selectedColor: color.withOpacity(0.2),
      backgroundColor: const Color(0xFF2A2A2A),
      labelStyle: TextStyle(color: selected ? color : Colors.white54),
      checkmarkColor: color,
      side: BorderSide(color: selected ? color.withOpacity(0.5) : Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _photoPh() => Container(
    width: 80, height: 80,
    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12)),
    child: const Icon(Icons.fastfood_rounded, color: Colors.white24, size: 30),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 48, 16, 16),
            color: const Color(0xFF1A1A1A),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(child: Text(
                '${widget.category['icon']} ${widget.category['title']}',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              )),
              ElevatedButton.icon(
                onPressed: () => _showEditDish(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Блюдо', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                : _dishes.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🍽', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text('Нет блюд в категории',
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _dishes.length,
                        itemBuilder: (_, i) {
                          final d = _dishes[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: d['photo_url'] != null
                                    ? Image.network(d['photo_url'], width: 70, height: 70, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _photoPh370())
                                    : _photoPh370(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(d['title'] ?? '',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                if (d['weight'] != null)
                                  Text(d['weight'], style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
                                Text('${(d['price'] ?? 0).toStringAsFixed(0)} ₽',
                                  style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold)),
                                Wrap(spacing: 4, children: [
                                  if (d['is_top'] == true) _tag('Топ', const Color(0xFFFF8C00)),
                                  if (d['is_new'] == true) _tag('Новинка', const Color(0xFFFFD700)),
                                  if (d['is_chef_choice'] == true) _tag('От шефа', const Color(0xFFD4AF37)),
                                  if (d['is_promo'] == true) _tag('Акция', const Color(0xFF00C9FF)),
                                  if (d['is_hit'] == true) _tag('Хит', const Color(0xFFEE9CA7)),
                                  if ((d['spice_level'] ?? 0) > 0)
                                    Text('🌶' * (d['spice_level'] as int), style: const TextStyle(fontSize: 11)),
                                ]),
                                if (d['calories'] != null)
                                  Text(
                                    'К:${(d['calories'] as num).toInt()} Б:${(d['proteins'] ?? 0).toInt()} Ж:${(d['fats'] ?? 0).toInt()} У:${(d['carbs'] ?? 0).toInt()}',
                                    style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11),
                                  ),
                              ])),
                              Column(children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: Color(0xFFD4A043), size: 20),
                                  onPressed: () => _showEditDish(d),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                  onPressed: () => _deleteDish(d['id']),
                                ),
                              ]),
                            ]),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _photoPh370() => Container(
    width: 70, height: 70,
    color: const Color(0xFF2A2A2A),
    child: const Icon(Icons.fastfood_rounded, color: Colors.white24, size: 28),
  );

  Widget _photoSlot(int num, TextEditingController ctrl, bool uploading, ValueSetter<bool> setUploading, StateSetter setD) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: uploading ? null : () async {
                final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                if (result == null || result.files.first.bytes == null) return;
                final file = result.files.first;
                setUploading(true);
                try {
                  final path = 'dishes/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                  await Supabase.instance.client.storage.from('media').uploadBinary(
                    path, file.bytes!,
                    fileOptions: FileOptions(contentType: 'image/${file.extension}', upsert: true),
                  );
                  final url = Supabase.instance.client.storage.from('media').getPublicUrl(path);
                  setD(() { ctrl.text = url; });
                  setUploading(false);
                } catch (_) { setUploading(false); }
              },
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ctrl.text.isNotEmpty
                        ? Image.network(ctrl.text, width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _photoPh())
                        : _photoPh(),
                  ),
                  if (uploading)
                    Container(
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4A043))),
                    ),
                  if (ctrl.text.isNotEmpty && !uploading)
                    Positioned(
                      top: 4, right: 4,
                      child: GestureDetector(
                        onTap: () => setD(() => ctrl.clear()),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Фото $num', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: GoogleFonts.outfit(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

// ============================================================
// Диалог выбора ингредиентов (мультивыбор с поиском)
// ============================================================
class _IngredientPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allIngredients;
  final List<String> selectedIds;
  const _IngredientPickerDialog({required this.allIngredients, required this.selectedIds});

  @override
  State<_IngredientPickerDialog> createState() => _IngredientPickerDialogState();
}

class _IngredientPickerDialogState extends State<_IngredientPickerDialog> {
  late List<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allIngredients.where((ing) =>
      (ing['name'] as String).toLowerCase().contains(_search.toLowerCase())).toList();

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Выбор ингредиентов',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white38)),
                ],
              ),
            ),
            // Поиск
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Поиск ингредиента...',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                  filled: true, fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // Счётчик
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('Выбрано: ${_selected.length}',
                    style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: Text('Очистить', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
                    ),
                ],
              ),
            ),
            // Список
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final ing = filtered[i];
                  final isSelected = _selected.contains(ing['id']);
                  return ListTile(
                    onTap: () => setState(() {
                      if (isSelected) _selected.remove(ing['id']);
                      else _selected.add(ing['id']);
                    }),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ing['photo_url'] != null
                          ? Image.network(ing['photo_url'], width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _igPh())
                          : _igPh(),
                    ),
                    title: Text(ing['name'] ?? '',
                      style: GoogleFonts.outfit(
                        color: isSelected ? const Color(0xFFD4A043) : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      )),
                    trailing: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFD4A043) : Colors.transparent,
                        border: Border.all(color: isSelected ? const Color(0xFFD4A043) : Colors.white24, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.black, size: 16)
                          : null,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Применить (${_selected.length})',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _igPh() => Container(width: 40, height: 40,
    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
    child: const Icon(Icons.eco_rounded, color: Colors.white24, size: 20));
}

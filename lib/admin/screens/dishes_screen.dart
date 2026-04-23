import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/mock_data.dart';
import '../../models/menu_item.dart';

class DishesScreen extends StatefulWidget {
  const DishesScreen({super.key});

  @override
  State<DishesScreen> createState() => _DishesScreenState();
}

class _DishesScreenState extends State<DishesScreen> {
  // Используем mock данные для отображения (в продакшене — из Supabase)
  final List<MenuItem> _items = menuItems;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            itemBuilder: (context, i) => _buildDishCard(_items[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
      color: const Color(0xFF1A1A1A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Меню', style: GoogleFonts.outfit(
            color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold,
          )),
          ElevatedButton.icon(
            onPressed: () => _showEditDialog(null),
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
    );
  }

  Widget _buildDishCard(MenuItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              item.images[0],
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 70,
                height: 70,
                color: const Color(0xFF2A2A2A),
                child: const Icon(Icons.image_not_supported_rounded, color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text('${item.price.toInt()} ₽',
                  style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item.isHit) _chip('Хит', Colors.orange),
                    if (item.isNew) _chip('Новинка', Colors.blue),
                    if (item.isChefChoice) _chip('От шефа', Colors.purple),
                    // Острота
                    if (item.spiciness > 0)
                      Row(children: List.generate(
                        item.spiciness,
                        (_) => const Text('🌶', style: TextStyle(fontSize: 10)),
                      )),
                  ],
                ),
                // КБЖУ
                if (item.calories != null)
                  Text(
                    'К: ${item.calories?.toInt()} | Б: ${item.proteins?.toInt()} | Ж: ${item.fats?.toInt()} | У: ${item.carbs?.toInt()}',
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Color(0xFFD4A043), size: 20),
                onPressed: () => _showEditDialog(item),
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                onPressed: () => _confirmDelete(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: GoogleFonts.outfit(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  void _confirmDelete(MenuItem item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Удалить?', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text('Удалить "${item.title}"?', style: GoogleFonts.outfit(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white38))),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Удалить', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(MenuItem? item) {
    final isNew = item == null;
    final titleCtrl = TextEditingController(text: item?.title ?? '');
    final priceCtrl = TextEditingController(text: item?.price.toString() ?? '');
    final descCtrl = TextEditingController(text: item?.description ?? '');
    final weightCtrl = TextEditingController(text: item?.weight ?? '');
    final calCtrl = TextEditingController(text: item?.calories?.toString() ?? '');
    final protCtrl = TextEditingController(text: item?.proteins?.toString() ?? '');
    final fatCtrl = TextEditingController(text: item?.fats?.toString() ?? '');
    final carbCtrl = TextEditingController(text: item?.carbs?.toString() ?? '');
    int spiceLevel = item?.spiciness ?? 0;
    bool isHit = item?.isHit ?? false;
    bool isNew2 = item?.isNew ?? false;
    bool isChef = item?.isChefChoice ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isNew ? 'Новое блюдо' : 'Редактировать',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white38)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dialogField(titleCtrl, 'Название блюда *'),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _dialogField(priceCtrl, 'Цена ₽ *', type: TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _dialogField(weightCtrl, 'Выход (г)')),
                        ]),
                        const SizedBox(height: 10),
                        _dialogField(descCtrl, 'Описание', maxLines: 3),
                        const SizedBox(height: 16),
                        // КБЖУ
                        Text('КБЖУ', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _dialogField(calCtrl, 'Ккал', type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: _dialogField(protCtrl, 'Белки', type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: _dialogField(fatCtrl, 'Жиры', type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: _dialogField(carbCtrl, 'Углев.', type: TextInputType.number)),
                        ]),
                        const SizedBox(height: 16),
                        // Острота
                        Text('Острота', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(5, (i) => GestureDetector(
                            onTap: () => setDialogState(() => spiceLevel = i + 1),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text('🌶', style: TextStyle(
                                fontSize: 28,
                                color: i < spiceLevel ? Colors.red : Colors.white24,
                              )),
                            ),
                          )),
                        ),
                        const SizedBox(height: 16),
                        // Выбор изображения
                        Text('Изображение', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(type: FileType.image);
                            if (result != null) {
                              setDialogState(() {
                                // В вебе мы получаем bytes или path (blob url)
                                // Для простоты пока представим, что мы сохраняем выбранный файл
                              });
                            }
                          },
                          child: Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: item?.images.isNotEmpty == true
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(item!.images[0], fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.add_a_photo_rounded, color: Colors.white24, size: 32)),
                                )
                              : const Icon(Icons.add_a_photo_rounded, color: Colors.white24, size: 32),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Метки
                        Text('Метки', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilterChip(
                              label: Text('Хит', style: GoogleFonts.outfit()),
                              selected: isHit,
                              onSelected: (v) => setDialogState(() => isHit = v),
                              selectedColor: Colors.orange.withOpacity(0.3),
                              backgroundColor: const Color(0xFF2A2A2A),
                              labelStyle: TextStyle(color: isHit ? Colors.orange : Colors.white54),
                              checkmarkColor: Colors.orange,
                            ),
                            FilterChip(
                              label: Text('Новинка', style: GoogleFonts.outfit()),
                              selected: isNew2,
                              onSelected: (v) => setDialogState(() => isNew2 = v),
                              selectedColor: Colors.blue.withOpacity(0.3),
                              backgroundColor: const Color(0xFF2A2A2A),
                              labelStyle: TextStyle(color: isNew2 ? Colors.blue : Colors.white54),
                              checkmarkColor: Colors.blue,
                            ),
                            FilterChip(
                              label: Text('От шефа', style: GoogleFonts.outfit()),
                              selected: isChef,
                              onSelected: (v) => setDialogState(() => isChef = v),
                              selectedColor: Colors.purple.withOpacity(0.3),
                              backgroundColor: const Color(0xFF2A2A2A),
                              labelStyle: TextStyle(color: isChef ? Colors.purple : Colors.white54),
                              checkmarkColor: Colors.purple,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(ctx); },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A043),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isNew ? 'Создать блюдо' : 'Сохранить',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
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

  Widget _dialogField(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: type,
      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

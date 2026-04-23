import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _tables = [];
  String? _selectedFloorId;
  bool _loading = true;

  // Режимы взаимодействия
  String _mode = 'view'; // view | add | move
  String? _draggingId;
  bool _uploadingPlan = false;

  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fRes = await Supabase.instance.client.from('floors').select().order('sort_order');
      final tRes = await Supabase.instance.client.from('restaurant_tables').select();
      
      setState(() {
        _floors = List<Map<String, dynamic>>.from(fRes);
        _tables = List<Map<String, dynamic>>.from(tRes);
        if (_floors.isNotEmpty && _selectedFloorId == null) {
          _selectedFloorId = _floors.first['id'];
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e', style: GoogleFonts.outfit())),
        );
      }
      setState(() => _loading = false);
    }
  }

  // === ЭТАЖИ ===
  Future<void> _addFloor() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Новый зал / этаж', style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Название', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            child: const Text('Создать', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await Supabase.instance.client.from('floors').insert({
        'name': name,
        'sort_order': _floors.length,
      });
      _load();
    }
  }

  Future<void> _uploadFloorPlan() async {
    if (_selectedFloorId == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.first.bytes == null) return;

    setState(() => _uploadingPlan = true);
    try {
      final file = result.files.first;
      // Санитизация пути: используем только метку времени и расширение, 
      // чтобы избежать ошибок с кириллицей или пробелами в Supabase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = file.extension ?? 'png';
      final path = 'floor_plans/${timestamp}.$ext';
      
      await Supabase.instance.client.storage.from('media').uploadBinary(
        path, file.bytes!,
        fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
      );
      final url = Supabase.instance.client.storage.from('media').getPublicUrl(path);

      await Supabase.instance.client
          .from('floors')
          .update({'plan_url': url})
          .eq('id', _selectedFloorId!);
      
      _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Схема успешно загружена! ✅')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _uploadingPlan = false);
    }
  }

  Future<void> _deleteFloor() async {
    if (_selectedFloorId == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text('Удалить зал?', style: GoogleFonts.outfit(color: Colors.white)),
      content: const Text('Все столы и их брони в этом зале будут удалены. Это действие необратимо.', style: TextStyle(color: Colors.white54)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Удалить'),
        ),
      ],
    ));

    if (ok == true) {
      try {
        final floorId = _selectedFloorId!;
        
        // Удаляем только зал. Если вы выполнили SQL с ON DELETE CASCADE, 
        // столы и брони удалятся автоматически на стороне сервера.
        await Supabase.instance.client
            .from('floors')
            .delete()
            .eq('id', floorId);

        setState(() {
          _selectedFloorId = null;
        });
        await _load(); // Перезагружаем список
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Зал успешно удален ✅')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  // === СТОЛЫ ===
  Future<void> _editTable(Map<String, dynamic> table) async {
    final labelCtrl = TextEditingController(text: table['label'] ?? '');
    final seatsCtrl = TextEditingController(text: (table['seats'] ?? 4).toString());
    final widthCtrl = TextEditingController(text: (table['width'] ?? 80).toString());
    final heightCtrl = TextEditingController(text: (table['height'] ?? 80).toString());
    final rotationCtrl = TextEditingController(text: (table['rotation'] ?? 0).toString());

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Параметры стола', style: GoogleFonts.outfit(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(labelCtrl, 'Номер / Название'),
              const SizedBox(height: 12),
              _dialogField(seatsCtrl, 'Кол-во мест', type: TextInputType.number),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dialogField(widthCtrl, 'Ширина', type: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _dialogField(heightCtrl, 'Высота', type: TextInputType.number)),
              ]),
              const SizedBox(height: 12),
              _dialogField(rotationCtrl, 'Поворот (градусы)', type: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, {
                'label': labelCtrl.text.trim(),
                'seats': int.tryParse(seatsCtrl.text) ?? 4,
                'width': double.tryParse(widthCtrl.text) ?? 80.0,
                'height': double.tryParse(heightCtrl.text) ?? 80.0,
                'rotation': double.tryParse(rotationCtrl.text) ?? 0.0,
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            child: const Text('Сохранить', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (result != null) {
      await Supabase.instance.client.from('restaurant_tables').update(result).eq('id', table['id']);
      _load();
    }
  }

  Widget _dialogField(TextEditingController ctrl, String label, {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true, fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
      style: const TextStyle(color: Colors.white, fontSize: 14),
    );
  }

  Future<void> _addTable(double x, double y) async {
    if (_selectedFloorId == null) return;
    
    int tableNum = _tables.length + 1;
    await Supabase.instance.client.from('restaurant_tables').insert({
      'floor_id': _selectedFloorId,
      'label': 'Стол $tableNum',
      'seats': 4,
      'pos_x': x,
      'pos_y': y,
      'width': 80,
      'height': 80,
      'rotation': 0,
      'is_active': true,
    });
    _load();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Стол добавлен. Настройте его параметры кликом.')));
  }

  Future<void> _deleteTable(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text('Удалить стол?', style: GoogleFonts.outfit(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Удалить'),
        ),
      ],
    ));
    if (ok == true) {
      try {
        // 1. Сначала удаляем все брони для этого стола (чтобы не было ошибки Foreign Key)
        await Supabase.instance.client
            .from('bookings')
            .delete()
            .eq('table_id', id);

        // 2. Затем удаляем сам стол
        await Supabase.instance.client
            .from('restaurant_tables')
            .delete()
            .eq('id', id);
            
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Стол успешно удален ✅')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _updateAllTablesSize(double newSize) async {
    if (_selectedFloorId == null) return;
    try {
      await Supabase.instance.client
          .from('restaurant_tables')
          .update({'width': newSize, 'height': newSize})
          .eq('floor_id', _selectedFloorId!);
      
      setState(() {
        for (var t in _tables) {
          if (t['floor_id'] == _selectedFloorId) {
            t['width'] = newSize;
            t['height'] = newSize;
          }
        }
      });
    } catch (e) {
      debugPrint('Bulk size update error: $e');
    }
  }

  // === UI БИЛДЕРЫ ===

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)));

    final currFloor = _selectedFloorId != null 
        ? _floors.firstWhere((f) => f['id'] == _selectedFloorId, orElse: () => {}) 
        : null;
    final currTables = _selectedFloorId != null 
        ? _tables.where((t) => t['floor_id'] == _selectedFloorId).toList()
        : <Map<String, dynamic>>[];

    return SingleChildScrollView(
      child: Column(
        children: [
        // Шапка и Вкладки
        Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          color: const Color(0xFF1A1A1A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Схема столов', style: GoogleFonts.outfit(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._floors.map((floor) {
                      final isSel = floor['id'] == _selectedFloorId;
                      return GestureDetector(
                        onTap: () => setState(() { _selectedFloorId = floor['id']; _mode = 'view'; }),
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFFD4A043) : const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            floor['name'] ?? '',
                            style: GoogleFonts.outfit(
                              color: isSel ? Colors.black : Colors.white70,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: _addFloor,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add_rounded, color: Colors.white54, size: 18),
                            SizedBox(width: 4),
                            Text('Новый зал', style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Панель инструментов для текущего этажа
        if (currFloor != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                _toolBtn(
                  icon: Icons.touch_app_rounded,
                  label: 'Добавить стол',
                  isActive: _mode == 'add',
                  color: const Color(0xFFD4A043),
                  onTap: () => setState(() => _mode = _mode == 'add' ? 'view' : 'add'),
                ),
                const SizedBox(width: 12),
                _toolBtn(
                  icon: Icons.open_with_rounded,
                  label: 'Двигать столы',
                  isActive: _mode == 'move',
                  color: Colors.blue,
                  onTap: () => setState(() => _mode = _mode == 'move' ? 'view' : 'move'),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  color: const Color(0xFF2A2A2A),
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                  onSelected: (val) {
                    if (val == 'photo') _uploadFloorPlan();
                    if (val == 'delete') _deleteFloor();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'photo', child: Text('📸 Загрузить схему (фон)', style: GoogleFonts.outfit(color: Colors.white))),
                    PopupMenuItem(value: 'delete', child: Text('🗑 Удалить зал', style: GoogleFonts.outfit(color: Colors.red))),
                  ],
                ),
              ],
            ),
          ),

        // Инструкция режима
        if (_mode == 'add')
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: const Color(0xFFD4A043).withOpacity(0.2),
            child: Text('👆 Кликните на схему, чтобы поставить стол', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: const Color(0xFFD4A043))),
          )
        else if (_mode == 'move')
          Container(
            width: double.infinity, 
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24), 
            color: Colors.blue.withOpacity(0.1),
            child: Column(
              children: [
                Text('✋ Перетаскивайте столы или измените размер всех сразу:', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: Colors.blue, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.photo_size_select_small_rounded, color: Colors.blue, size: 20),
                    Expanded(
                      child: Slider(
                        value: (currTables.isNotEmpty ? (currTables.first['width'] ?? 80).toDouble() : 80).clamp(20, 200).toDouble(),
                        min: 20,
                        max: 200,
                        activeColor: const Color(0xFFD4A043),
                        inactiveColor: Colors.white10,
                        onChanged: (val) => _updateAllTablesSize(val),
                      ),
                    ),
                    Text('${(currTables.isNotEmpty ? (currTables.first['width'] ?? 80) : 80).toInt()} px', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),

        // Канвас (схема)
        Center(
          child: Container(
            width: 360,
            height: 600,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: currFloor == null 
                  ? Center(child: Text('Создайте или выберите зал', style: GoogleFonts.outfit(color: Colors.white38)))
                  : _uploadingPlan
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                      : GestureDetector(
                          onTapUp: _mode == 'add' ? (details) => _handleAddTap(details) : null,
                          child: _buildHallSchemeUI(currFloor, currTables),
            ),
          ),
        ),
      ),
      const SizedBox(height: 100),
    ],
  ),
);
}

  Widget _buildHallSchemeUI(Map<String, dynamic> currFloor, List<Map<String, dynamic>> currTables) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. ФОН
        if (currFloor['plan_url'] != null && currFloor['plan_url'].toString().isNotEmpty)
          Image.network(
            currFloor['plan_url'],
            fit: BoxFit.fill,
            alignment: Alignment.center,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)));
            },
            errorBuilder: (_, __, ___) => _buildFallbackGrid(),
          )
        else
          _buildFallbackGrid(),

        // 2. СТОЛЫ
        ...currTables.map((mapTable) => _buildTableNode(mapTable)),
      ],
    );
  }

  // === ОБРАБОТЧИКИ КАНВАСА ===

  void _handleAddTap(TapUpDetails details) {
    // details.localPosition даёт координаты ВНУТРИ Stack (ровно относительно картинки/сетки)
    _addTable(details.localPosition.dx, details.localPosition.dy);
    setState(() => _mode = 'view'); // Автоматически выходим после добавления
  }

  Widget _buildTableNode(Map<String, dynamic> table) {
    final tId = table['id'] as String;
    final double w = (table['width'] ?? 80).toDouble();
    final double h = (table['height'] ?? 80).toDouble();
    final double rotation = (table['rotation'] ?? 0).toDouble();
    
    double x = (table['pos_x'] as num).toDouble();
    double y = (table['pos_y'] as num).toDouble();
    if (x < 2.0 && y < 2.0) {
      x = x * 2000;
      y = y * 2000;
    }

    final isDragging = _draggingId == tId;

    return Positioned(
      left: x - (w / 2),
      top: y - (h / 2),
      child: Transform.rotate(
        angle: rotation * (3.1415926535 / 180),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _mode == 'move'
                ? GestureDetector(
                    onPanStart: (_) => setState(() => _draggingId = tId),
                    onPanUpdate: (details) {
                      final scale = _transformCtrl.value.getMaxScaleOnAxis();
                      final dx = details.delta.dx / scale;
                      final dy = details.delta.dy / scale;
                      setState(() {
                        final idx = _tables.indexWhere((t) => t['id'] == tId);
                        if (idx != -1) {
                          _tables[idx] = {..._tables[idx], 'pos_x': x + dx, 'pos_y': y + dy};
                        }
                      });
                    },
                    onPanEnd: (_) async {
                      setState(() => _draggingId = null);
                      final updated = _tables.firstWhere((t) => t['id'] == tId);
                      await Supabase.instance.client
                          .from('restaurant_tables')
                          .update({'pos_x': updated['pos_x'], 'pos_y': updated['pos_y']})
                          .eq('id', tId);
                    },
                    child: _TableShape(table: table, width: w, height: h, isMoving: true, isDragging: isDragging),
                  )
                : GestureDetector(
                    onTap: () => _editTable(table),
                    onLongPress: () => _deleteTable(tId),
                    child: _TableShape(table: table, width: w, height: h, isMoving: false, isDragging: false),
                  ),
            // Кнопка удаления (крестик) — теперь внутри границ для хит-теста
            Positioned(
              right: 2,
              top: 2,
              child: GestureDetector(
                onTap: () {
                  debugPrint('DELETE CLICKED for $tId');
                  _deleteTable(tId);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9), 
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackGrid() {
    return Container(
      width: 3000, height: 3000, // Громадный пустой холст по умолчанию
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
      ),
      child: Stack(
        children: [
          CustomPaint(
            painter: _GridPainter(),
            size: const Size(3000, 3000),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_photo_alternate_rounded, size: 64, color: Colors.white12),
                const SizedBox(height: 16),
                Text('Схема не загружена', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Рекомендуемый размер: 360 x 600 px', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 14)),
                const SizedBox(height: 16),
                Text('Загрузите фото через меню ⋮', style: GoogleFonts.outfit(color: const Color(0xFFD4A043).withOpacity(0.5), fontSize: 13)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // === ВИДЖЕТЫ-ПОМОЩНИКИ ===

  Widget _toolBtn({required IconData icon, required String label, required bool isActive, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? color : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.black : color),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.outfit(
              color: isActive ? Colors.black : color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }
}

class _TableShape extends StatelessWidget {
  final Map<String, dynamic> table;
  final double width;
  final double height;
  final bool isMoving;
  final bool isDragging;

  const _TableShape({required this.table, required this.width, required this.height, required this.isMoving, required this.isDragging});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: isMoving ? Colors.blue.withOpacity(0.2) : const Color(0xFFD4A043).withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMoving ? Colors.blue : const Color(0xFFD4A043),
          width: isDragging ? 3 : 1.5,
        ),
        boxShadow: isDragging ? [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)] : null,
      ),
      child: Center(
        child: SingleChildScrollView( // Защита от переполнения
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isMoving ? Icons.open_with_rounded : Icons.table_restaurant_rounded, 
                color: isMoving ? Colors.blue : const Color(0xFFD4A043), 
                size: (width * 0.4).clamp(12, 24)),
              if (width >= 60 && height >= 60) ...[
                const SizedBox(height: 2),
                Text(table['label'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                Text('${table['seats'] ?? 4} 👤', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03) // Очень слабая сетка
      ..strokeWidth = 1;
    
    // Шаг сетки 40px
    for (double i = 0; i <= size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i <= size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

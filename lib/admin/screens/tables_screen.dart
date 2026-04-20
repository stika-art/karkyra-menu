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
      final path = 'floor_plans/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await Supabase.instance.client.storage.from('media').uploadBinary(
        path, file.bytes!,
        fileOptions: FileOptions(contentType: 'image/${file.extension}', upsert: true),
      );
      final url = Supabase.instance.client.storage.from('media').getPublicUrl(path);

      await Supabase.instance.client
          .from('floors')
          .update({'plan_url': url})
          .eq('id', _selectedFloorId!);
      
      _load();
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
      content: const Text('Все столы в этом зале также будут удалены.', style: TextStyle(color: Colors.white54)),
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
      await Supabase.instance.client.from('floors').delete().eq('id', _selectedFloorId!);
      _selectedFloorId = null;
      _load();
    }
  }

  // === СТОЛЫ ===
  Future<void> _addTable(double x, double y) async {
    if (_selectedFloorId == null) return;
    
    int tableNum = _tables.length + 1;
    final labelCtrl = TextEditingController(text: 'Стол $tableNum');
    final seatsCtrl = TextEditingController(text: '4');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Новый стол', style: GoogleFonts.outfit(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Номер / Название', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seatsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Кол-во мест', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, {
                'label': labelCtrl.text.trim(),
                'seats': int.tryParse(seatsCtrl.text) ?? 4,
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            child: const Text('Добавить', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (result != null) {
      await Supabase.instance.client.from('restaurant_tables').insert({
        'floor_id': _selectedFloorId,
        'label': result['label'],
        'seats': result['seats'],
        'pos_x': x,
        'pos_y': y,
        'is_active': true,
      });
      _load();
    }
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
      await Supabase.instance.client.from('restaurant_tables').delete().eq('id', id);
      _load();
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
        : [];

    return Column(
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
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: Colors.blue.withOpacity(0.2),
            child: Text('✋ Перетаскивайте столы на новые места', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: Colors.blue)),
          ),

        // Канвас (схема)
        Expanded(
          child: currFloor == null 
              ? Center(child: Text('Создайте или выберите зал', style: GoogleFonts.outfit(color: Colors.white38)))
              : _uploadingPlan
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                  : Stack(
                      children: [
                        // Схема с возможностью бесконечного панорамирования без ограничений размера
                        InteractiveViewer(
                          transformationController: _transformCtrl,
                          boundaryMargin: const EdgeInsets.all(5000), // Позволяет уходить далеко за пределы
                          constrained: false, // ВАЖНО: Разрешает детям быть своего родного размера
                          minScale: 0.1,
                          maxScale: 3.0,
                          panEnabled: _mode == 'view', // Скроллинг только в режиме просмотра
                          scaleEnabled: true,
                          child: GestureDetector(
                            onTapUp: _mode == 'add' ? (details) => _handleAddTap(details) : null,
                            child: Stack(
                              clipBehavior: Clip.none, // Разрешаем столам выходить за границы (если вдруг)
                              children: [
                                // 1. ФОН: Либо загруженная картинка, либо дефолтная сетка
                                if (currFloor['plan_url'] != null && currFloor['plan_url'].toString().isNotEmpty)
                                  Image.network(
                                    currFloor['plan_url'],
                                    loadingBuilder: (ctx, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        width: 1500, height: 1000, color: const Color(0xFF1E1E1E),
                                        child: const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043))),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => _buildFallbackGrid(),
                                  )
                                else
                                  _buildFallbackGrid(),

                                // 2. СТОЛЫ
                                ...currTables.map((mapTable) => _buildTableNode(mapTable)),
                              ],
                            ),
                          ),
                        ),
                        // Кнопка масштаба по умолчанию
                        Positioned(
                          right: 16, bottom: 16,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.fit_screen_rounded, color: Colors.white54),
                            onPressed: () {
                              _transformCtrl.value = Matrix4.identity();
                            },
                          ),
                        ),
                      ],
                    ),
        ),
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
    // Столы отцентрированы по своим координатам
    final double size = 80.0; 
    
    // Поддержка старых относительных координат
    double x = (table['pos_x'] as num).toDouble();
    double y = (table['pos_y'] as num).toDouble();
    if (x < 2.0 && y < 2.0) {
      x = x * 2000;
      y = y * 2000;
    }

    final isDragging = _draggingId == tId;

    return Positioned(
      left: x - (size / 2),
      top: y - (size / 2),
      child: _mode == 'move'
          ? GestureDetector(
              onPanStart: (_) => setState(() => _draggingId = tId),
              onPanUpdate: (details) {
                // Перемещаем с учётом масштаба зума
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
              child: _TableShape(table: table, size: size, isMoving: true, isDragging: isDragging),
            )
          : GestureDetector(
              onLongPress: _mode == 'view' ? () => _deleteTable(tId) : null,
              child: _TableShape(table: table, size: size, isMoving: false, isDragging: false),
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
                const Icon(Icons.map_rounded, size: 64, color: Colors.white12),
                const SizedBox(height: 16),
                Text('Базовая сетка (3000x3000)', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 24)),
                const SizedBox(height: 8),
                Text('Загрузите фото схемы Вашего ресторана в меню ⋮', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 16)),
              ],
            ),
          )
        ],
      )
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
  final double size;
  final bool isMoving;
  final bool isDragging;

  const _TableShape({required this.table, required this.size, required this.isMoving, required this.isDragging});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: isMoving ? Colors.blue.withOpacity(0.2) : const Color(0xFFD4A043).withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMoving ? Colors.blue : const Color(0xFFD4A043),
          width: isDragging ? 3 : 1.5,
        ),
        boxShadow: isDragging ? [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)] : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isMoving ? Icons.open_with_rounded : Icons.table_restaurant_rounded, 
            color: isMoving ? Colors.blue : const Color(0xFFD4A043), size: 24),
          const SizedBox(height: 2),
          Text(table['label'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          Text('${table['seats'] ?? 4} 👤', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10)),
        ],
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
    
    // Шаг сетки 100px
    for (double i = 0; i <= size.width; i += 100) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i <= size.height; i += 100) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

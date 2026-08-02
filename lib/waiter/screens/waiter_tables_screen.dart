import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/waiter_service.dart';

class WaiterTablesScreen extends StatefulWidget {
  final Map<String, String> currentWaiter;

  const WaiterTablesScreen({super.key, required this.currentWaiter});

  @override
  State<WaiterTablesScreen> createState() => _WaiterTablesScreenState();
}

class _WaiterTablesScreenState extends State<WaiterTablesScreen> {
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _allWaiters = [];
  String? _selectedFloorId;
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _initRealtime() {
    _realtimeChannel = Supabase.instance.client
        .channel('waiter_tables_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_tables',
          callback: (payload) {
            _loadTablesOnly();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final floors = await WaiterService.fetchFloors();
    final tables = await WaiterService.fetchTables();
    final waiters = await WaiterService.fetchWaiters();

    setState(() {
      _floors = floors;
      _tables = tables;
      _allWaiters = waiters;
      if (_floors.isNotEmpty && _selectedFloorId == null) {
        _selectedFloorId = _floors.first['id'];
      }
      _loading = false;
    });
  }

  Future<void> _loadTablesOnly() async {
    final tables = await WaiterService.fetchTables();
    if (mounted) {
      setState(() {
        _tables = tables;
      });
    }
  }

  Future<void> _claimTable(Map<String, dynamic> table) async {
    final tableId = table['id'] as String;
    final label = table['label'] ?? 'Стол';
    final success = await WaiterService.claimTable(
      tableId: tableId,
      waiterId: widget.currentWaiter['id']!,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Стол "$label" закреплен за вами! ✅', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
        _loadTablesOnly();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Этот стол уже занят другим официантом!', style: GoogleFonts.outfit()),
            backgroundColor: Colors.redAccent,
          ),
        );
        _loadTablesOnly();
      }
    }
  }

  Future<void> _releaseTable(Map<String, dynamic> table) async {
    final tableId = table['id'] as String;
    final label = table['label'] ?? 'Стол';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Отвязать стол?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Вы уверены, что хотите освободить стол "$label"?', style: GoogleFonts.outfit(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Да, освободить', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await WaiterService.releaseTable(
        tableId: tableId,
        waiterId: widget.currentWaiter['id']!,
      );

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Стол "$label" снова свободен', style: GoogleFonts.outfit())),
        );
        _loadTablesOnly();
      }
    }
  }

  String _getWaiterName(String? waiterId) {
    if (waiterId == null) return '';
    if (waiterId == widget.currentWaiter['id']) return 'Вы';
    final found = _allWaiters.firstWhere((w) => w['id'] == waiterId, orElse: () => {'name': 'Другой официант'});
    return found['name'] ?? 'Другой официант';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)));
    }

    final filteredTables = _selectedFloorId == null
        ? _tables
        : _tables.where((t) => t['floor_id'] == _selectedFloorId).toList();

    final myTablesCount = _tables.where((t) => t['waiter_id'] == widget.currentWaiter['id']).length;
    final freeTablesCount = _tables.where((t) => t['waiter_id'] == null).length;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            // Верхняя плашка со статистикой
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Мои столы', '$myTablesCount', const Color(0xFFD4A043), Icons.table_restaurant_rounded),
                  Container(height: 30, width: 1, color: Colors.white.withOpacity(0.1)),
                  _buildStatItem('Свободные', '$freeTablesCount', Colors.greenAccent, Icons.event_available_rounded),
                  Container(height: 30, width: 1, color: Colors.white.withOpacity(0.1)),
                  _buildStatItem('Всего', '${_tables.length}', Colors.white70, Icons.grid_view_rounded),
                ],
              ),
            ),

            // Фильтр залов (Floors)
            if (_floors.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: _floors.map((floor) {
                    final isSelected = floor['id'] == _selectedFloorId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          floor['name'] ?? 'Зал',
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFFD4A043),
                        backgroundColor: const Color(0xFF1C1C1E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (_) {
                          setState(() {
                            _selectedFloorId = floor['id'];
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Сетка столов
            Expanded(
              child: filteredTables.isEmpty
                  ? Center(
                      child: Text(
                        'В этом зале пока нет столов',
                        style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: filteredTables.length,
                      itemBuilder: (context, index) {
                        final table = filteredTables[index];
                        final waiterId = table['waiter_id'];
                        final isMine = waiterId == widget.currentWaiter['id'];
                        final isFree = waiterId == null;
                        final label = table['label'] ?? 'Стол №${index + 1}';
                        final waiterName = _getWaiterName(waiterId);

                        return _buildTableCard(
                          table: table,
                          label: label,
                          isMine: isMine,
                          isFree: isFree,
                          waiterName: waiterName,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.outfit(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildTableCard({
    required Map<String, dynamic> table,
    required String label,
    required bool isMine,
    required bool isFree,
    required String waiterName,
  }) {
    Color cardColor = const Color(0xFF1C1C1E);
    Color borderColor = Colors.white.withOpacity(0.08);
    Color statusColor = Colors.white38;
    String statusText = 'Занят: $waiterName';
    IconData statusIcon = Icons.lock_outline_rounded;

    if (isMine) {
      cardColor = const Color(0xFFD4A043).withOpacity(0.12);
      borderColor = const Color(0xFFD4A043);
      statusColor = const Color(0xFFD4A043);
      statusText = 'Ваш стол';
      statusIcon = Icons.check_circle_rounded;
    } else if (isFree) {
      borderColor = Colors.greenAccent.withOpacity(0.3);
      statusColor = Colors.greenAccent;
      statusText = 'Свободен';
      statusIcon = Icons.add_circle_outline_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isMine ? 2 : 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(statusIcon, color: statusColor, size: 20),
            ],
          ),
          
          Text(
            statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: statusColor,
              fontSize: 13,
              fontWeight: isMine ? FontWeight.bold : FontWeight.normal,
            ),
          ),

          SizedBox(
            width: double.infinity,
            height: 36,
            child: isMine
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _releaseTable(table),
                    child: Text('Освободить', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                : isFree
                    ? ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4A043),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => _claimTable(table),
                        child: Text('Взять стол', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    : Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Занят коллегой',
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

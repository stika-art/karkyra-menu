import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/waiter_service.dart';

class WaiterCallsScreen extends StatefulWidget {
  final Map<String, String> currentWaiter;

  const WaiterCallsScreen({super.key, required this.currentWaiter});

  @override
  State<WaiterCallsScreen> createState() => _WaiterCallsScreenState();
}

class _WaiterCallsScreenState extends State<WaiterCallsScreen> {
  List<Map<String, dynamic>> _calls = [];
  List<Map<String, dynamic>> _tables = [];
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadCalls();
    _initRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _initRealtime() {
    _realtimeChannel = Supabase.instance.client
        .channel('waiter_calls_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'waiter_calls',
          callback: (payload) {
            _loadCalls(silent: true);
          },
        )
        .subscribe();
  }

  Future<void> _loadCalls({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final calls = await WaiterService.fetchWaiterCalls();
    final tables = await WaiterService.fetchTables();
    if (mounted) {
      setState(() {
        _calls = calls;
        _tables = tables;
        _loading = false;
      });
    }
  }

  Future<void> _resolveCall(String callId, String status) async {
    final success = await WaiterService.updateCallStatus(callId, status);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'completed' ? 'Вызов завершен ✅' : 'Вызов принят 👍', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFD4A043),
        ),
      );
      _loadCalls(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiterId = widget.currentWaiter['id'];

    final myAssignedTables = _tables.where((t) => t['waiter_id']?.toString() == waiterId?.toString()).toList();

    // Фильтрация: вызовы ТОЛЬКО своих столов
    final activeCalls = _calls.where((c) {
      if (c['status'] == 'completed' || c['status'] == 'done') return false;
      return WaiterService.isTableAssignedToWaiter(
        itemTableId: c['table_id'],
        waiterId: waiterId,
        allTables: _tables,
      );
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: Colors.redAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Вызовы официанта',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (activeCalls.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${activeCalls.length}',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                  : activeCalls.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_none_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text('Новых вызовов нет', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: activeCalls.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final call = activeCalls[index];
                            final callId = call['id'] as String;
                            final table = call['restaurant_tables'];
                            String tableLabel = 'Стол №${call['table_id'] ?? '?'}';
                            if (table != null && table is Map && table['label'] != null) {
                              tableLabel = table['label'];
                            }
                            final callType = call['call_type'] ?? 'Вызов официанта';

                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.redAccent.withOpacity(0.2),
                                    child: const Icon(Icons.notifications_active, color: Colors.redAccent),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tableLabel,
                                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          callType,
                                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD4A043),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => _resolveCall(callId, 'completed'),
                                    child: Text('Обслужен', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/waiter_service.dart';

class WaiterReservationsScreen extends StatefulWidget {
  final Map<String, String> currentWaiter;

  const WaiterReservationsScreen({super.key, required this.currentWaiter});

  @override
  State<WaiterReservationsScreen> createState() => _WaiterReservationsScreenState();
}

class _WaiterReservationsScreenState extends State<WaiterReservationsScreen> {
  List<Map<String, dynamic>> _reservations = [];
  List<Map<String, dynamic>> _tables = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReservations();
  }

  Future<void> _loadReservations() async {
    setState(() => _loading = true);
    final res = await WaiterService.fetchReservations();
    final tables = await WaiterService.fetchTables();
    if (mounted) {
      setState(() {
        _reservations = res;
        _tables = tables;
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    final success = await WaiterService.updateReservationStatus(id, status);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Статус бронирования обновлен ✅', style: GoogleFonts.outfit())),
      );
      _loadReservations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiterId = widget.currentWaiter['id'];

    // Фильтрация броней только для столов текущего официанта
    final myReservations = _reservations.where((res) {
      return WaiterService.isTableAssignedToWaiter(
        itemTableId: res['table_id'],
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
                      color: const Color(0xFFD4A043).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.event_seat_rounded, color: Color(0xFFD4A043), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Бронирования столов',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                  : myReservations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text('Нет активных броней на ваших столах', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: myReservations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final res = myReservations[index];
                            final id = res['id'].toString();
                            final guestName = res['customer_name'] ?? 'Гость';
                            final guestPhone = res['customer_phone'] ?? '';
                            final guestCount = res['guests_count'] ?? 1;
                            final time = res['booking_time'] ?? '';
                            final endTime = res['end_time'] ?? '';
                            final status = res['status'] ?? 'confirmed';
                            final preorder = res['preorder_details']?.toString() ?? '';

                            final table = _tables.firstWhere(
                              (t) => t['id']?.toString() == res['table_id']?.toString() || 
                                     t['label']?.toString() == res['table_id']?.toString(),
                              orElse: () => {},
                            );
                            final tableLabel = table['label'] ?? 'Стол №${res['table_id']}';

                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        tableLabel,
                                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: status == 'accepted' || status == 'arrived'
                                              ? Colors.green.withOpacity(0.2)
                                              : const Color(0xFFD4A043).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          status == 'arrived' ? 'Гости пришли' : (status == 'accepted' ? 'Принято официантом' : 'Ожидает принятия'),
                                          style: GoogleFonts.outfit(
                                            color: status == 'arrived' || status == 'accepted' ? Colors.greenAccent : const Color(0xFFD4A043),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Гость: $guestName', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                  if (guestPhone.isNotEmpty)
                                    Text('Тел: $guestPhone', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.people_outline, color: Color(0xFFD4A043), size: 16),
                                      const SizedBox(width: 4),
                                      Text('$guestCount чел.', style: GoogleFonts.outfit(color: Colors.white70)),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.access_time, color: Color(0xFFD4A043), size: 16),
                                      const SizedBox(width: 4),
                                      Text('$time ${endTime.isNotEmpty ? "— $endTime" : ""}', style: GoogleFonts.outfit(color: Colors.white70)),
                                    ],
                                  ),
                                  if (preorder.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Предзаказ: $preorder', style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 12)),
                                  ],
                                  const SizedBox(height: 12),
                                  if (status == 'confirmed')
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => _updateStatus(id, 'accepted'),
                                        child: Text('Принять бронь', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                                      ),
                                    )
                                  else if (status == 'accepted')
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFD4A043),
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => _updateStatus(id, 'arrived'),
                                        child: Text('Отметить приход гостей', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                                      ),
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

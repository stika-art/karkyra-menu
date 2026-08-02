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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReservations();
  }

  Future<void> _loadReservations() async {
    setState(() => _loading = true);
    final res = await WaiterService.fetchReservations();
    if (mounted) {
      setState(() {
        _reservations = res;
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
                  : _reservations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text('Нет активных бронирований', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _reservations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final res = _reservations[index];
                            final id = res['id'] as String;
                            final guestName = res['guest_name'] ?? 'Гость';
                            final guestPhone = res['guest_phone'] ?? '';
                            final guestCount = res['guest_count'] ?? 1;
                            final date = res['date'] ?? '';
                            final time = res['time'] ?? '';
                            final status = res['status'] ?? 'pending';

                            final table = res['restaurant_tables'];
                            String tableLabel = 'Стол №${res['table_id'] ?? '?'}';
                            if (table != null && table is Map && table['label'] != null) {
                              tableLabel = table['label'];
                            }

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
                                          color: status == 'arrived'
                                              ? Colors.green.withOpacity(0.2)
                                              : const Color(0xFFD4A043).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          status == 'arrived' ? 'Гости пришли' : 'Ожидаются',
                                          style: GoogleFonts.outfit(
                                            color: status == 'arrived' ? Colors.greenAccent : const Color(0xFFD4A043),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Имя: $guestName', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14)),
                                  if (guestPhone.isNotEmpty)
                                    Text('Тел: $guestPhone', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.people_outline, color: Colors.white38, size: 16),
                                      const SizedBox(width: 4),
                                      Text('$guestCount чел.', style: GoogleFonts.outfit(color: Colors.white70)),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.access_time, color: Colors.white38, size: 16),
                                      const SizedBox(width: 4),
                                      Text('$date $time', style: GoogleFonts.outfit(color: Colors.white70)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (status != 'arrived')
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

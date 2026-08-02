import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/waiter_service.dart';

class WaiterLoginScreen extends StatefulWidget {
  final Function(Map<String, String>) onLoginSuccess;

  const WaiterLoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends State<WaiterLoginScreen> {
  List<Map<String, dynamic>> _waiters = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWaiters();
  }

  Future<void> _loadWaiters() async {
    setState(() => _loading = true);
    final waiters = await WaiterService.fetchWaiters();
    setState(() {
      _waiters = waiters;
      _loading = false;
    });
  }

  Future<void> _selectWaiter(Map<String, dynamic> waiter) async {
    final res = await WaiterService.loginWaiter(waiter);
    if (!mounted) return;

    if (res['success'] == true) {
      final saved = {
        'id': waiter['id'].toString(),
        'name': (waiter['name'] ?? 'Официант').toString(),
        'phone': (waiter['phone'] ?? '').toString(),
      };
      widget.onLoginSuccess(saved);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Этот официант уже в сети на другом устройстве!', style: GoogleFonts.outfit()),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A043).withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.person_pin_rounded, color: Color(0xFFD4A043), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Каркыра Waiter',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Выберите ваш профиль для работы',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                    : _waiters.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: _waiters.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final waiter = _waiters[index];
                              final name = waiter['name'] ?? 'Официант';
                              final phone = waiter['phone'] ?? 'Нет телефона';

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _selectWaiter(waiter),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1C1C1E),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: const Color(0xFFD4A043).withOpacity(0.2),
                                          child: Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : 'W',
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFFD4A043),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                phone,
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white38,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),

              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Регистрация новых официантов выполняется через панель администратора',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Список официантов пуст',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Обратитесь к администратору для создания вашего аккаунта',
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

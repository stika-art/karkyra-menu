import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    await WaiterService.saveCurrentWaiter(waiter);
    final saved = {
      'id': waiter['id'] as String,
      'name': (waiter['name'] ?? 'Официант') as String,
      'phone': (waiter['phone'] ?? '') as String,
    };
    widget.onLoginSuccess(saved);
  }

  void _showAddWaiterDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Регистрация официанта', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Имя и фамилия',
                hintStyle: GoogleFonts.outfit(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Номер телефона',
                hintStyle: GoogleFonts.outfit(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A043),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final phone = phoneCtrl.text.trim();
              try {
                final res = await Supabase.instance.client
                    .from('waiters')
                    .insert({'name': name, 'phone': phone})
                    .select()
                    .single();
                Navigator.pop(ctx);
                _selectWaiter(res);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка сохранения: $e', style: GoogleFonts.outfit())),
                );
              }
            },
            child: Text('Войти', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext me) {
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
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C1C1E),
                    foregroundColor: const Color(0xFFD4A043),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: const Color(0xFFD4A043).withOpacity(0.4)),
                    ),
                  ),
                  onPressed: _showAddWaiterDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    'Новый официант',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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
            'Нажмите кнопку ниже, чтобы зарегистрироваться',
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

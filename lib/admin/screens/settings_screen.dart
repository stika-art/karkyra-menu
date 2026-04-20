import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _passwordCtrl;
  late TextEditingController _tokenCtrl;
  late TextEditingController _chatIdCtrl;
  bool _saving = false;
  bool _showPassword = false;
  bool _showToken = false;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _passwordCtrl = TextEditingController(text: SettingsService.adminPassword);
    _tokenCtrl = TextEditingController(text: SettingsService.telegramToken);
    _chatIdCtrl = TextEditingController(text: SettingsService.telegramChatId);
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _tokenCtrl.dispose();
    _chatIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    if (_passwordCtrl.text.trim().isEmpty) {
      _showError('Пароль не может быть пустым');
      return;
    }
    setState(() => _saving = true);
    try {
      await SettingsService.update('admin_password', _passwordCtrl.text.trim());
      await SettingsService.update('telegram_token', _tokenCtrl.text.trim());
      await SettingsService.update('telegram_chat_id', _chatIdCtrl.text.trim());
      setState(() {
        _saving = false;
        _successMessage = 'Настройки сохранены!';
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _successMessage = null);
      });
    } catch (e) {
      setState(() => _saving = false);
      _showError('Ошибка сохранения: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit()),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _testTelegram() async {
    final token = _tokenCtrl.text.trim();
    final chatId = _chatIdCtrl.text.trim();
    if (token.isEmpty || chatId.isEmpty) {
      _showError('Введите Token и Chat ID');
      return;
    }
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {
          'chat_id': chatId,
          'text': '✅ Тестовое сообщение от Каркыра Админ-панели. Всё работает!',
          'parse_mode': 'HTML',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сообщение отправлено! Проверьте Telegram', style: GoogleFonts.outfit()),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError('Ошибка отправки: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Успешное сохранение
                  if (_successMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green),
                          const SizedBox(width: 12),
                          Text(_successMessage!, style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                  // --- Блок: Доступ ---
                  _sectionTitle('🔐 Доступ в панель'),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _passwordCtrl,
                    label: 'Пароль администратора',
                    hint: 'Введите новый пароль',
                    icon: Icons.lock_outline_rounded,
                    obscure: !_showPassword,
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'После смены пароля новый администратор использует именно его при входе.',
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                  ),

                  const SizedBox(height: 32),

                  // --- Блок: Telegram ---
                  _sectionTitle('💬 Telegram уведомления'),
                  const SizedBox(height: 4),
                  Text(
                    'При каждом новом заказе вы получите уведомление в Telegram.',
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _tokenCtrl,
                    label: 'Bot Token',
                    hint: '123456:ABCdef...',
                    icon: Icons.smart_toy_outlined,
                    obscure: !_showToken,
                    suffixIcon: IconButton(
                      icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _chatIdCtrl,
                    label: 'Chat ID (ваш Telegram ID)',
                    hint: '123456789',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  // Кнопка теста
                  GestureDetector(
                    onTap: _testTelegram,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.send_rounded, color: Colors.blue, size: 18),
                          const SizedBox(width: 8),
                          Text('Отправить тест в Telegram',
                            style: GoogleFonts.outfit(color: Colors.blue, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Получить Chat ID: откройте @userinfobot в Telegram и напишите /start.',
                    style: GoogleFonts.outfit(color: Colors.white24, fontSize: 12),
                  ),

                  const SizedBox(height: 40),

                  // Кнопка сохранения
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A043),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text('Сохранить все настройки',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFFD4A043), size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF252525),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD4A043), width: 1.5),
            ),
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
        children: [
          Text('Настройки', style: GoogleFonts.outfit(
            color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }
}

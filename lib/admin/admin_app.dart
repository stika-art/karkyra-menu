import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/settings_service.dart';
import 'screens/admin_home.dart';

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  final _passwordController = TextEditingController();
  bool _authenticated = false;
  bool _error = false;
  bool _checkingPassword = false;

  Future<void> _login() async {
    setState(() => _checkingPassword = true);
    // Загружаем актуальный пароль из базы
    await SettingsService.load();
    final correct = _passwordController.text == SettingsService.adminPassword;
    setState(() {
      _authenticated = correct;
      _error = !correct;
      _checkingPassword = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Каркыра — Админ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4A043),
          surface: Color(0xFF1E1E1E),
        ),
        scaffoldBackgroundColor: const Color(0xFF141414),
      ),
      home: _authenticated ? const AdminHome() : _buildLogin(),
    );
  }

  Widget _buildLogin() {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A043).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.restaurant_rounded, color: Color(0xFFD4A043), size: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  'КАРКЫРА',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
                Text(
                  'Панель управления',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Пароль',
                    hintStyle: GoogleFonts.outfit(color: Colors.white38),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFFD4A043)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: _error
                          ? const BorderSide(color: Colors.red)
                          : BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: _error
                          ? const BorderSide(color: Colors.redAccent)
                          : BorderSide.none,
                    ),
                    errorText: _error ? 'Неверный пароль' : null,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A043),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Войти',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
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
}

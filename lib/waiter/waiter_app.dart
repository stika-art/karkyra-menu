import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/waiter_service.dart';
import 'screens/waiter_login_screen.dart';
import 'screens/waiter_tables_screen.dart';
import 'screens/waiter_orders_screen.dart';
import 'screens/waiter_calls_screen.dart';
import 'screens/waiter_reservations_screen.dart';

class WaiterApp extends StatefulWidget {
  const WaiterApp({super.key});

  @override
  State<WaiterApp> createState() => _WaiterAppState();
}

class _WaiterAppState extends State<WaiterApp> {
  Map<String, String>? _currentWaiter;
  bool _checkingSession = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final waiter = await WaiterService.getCurrentWaiter();
    setState(() {
      _currentWaiter = waiter;
      _checkingSession = false;
    });
  }

  void _onLoginSuccess(Map<String, String> waiter) {
    setState(() {
      _currentWaiter = waiter;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Выход из профиля', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Сменить текущего официанта?', style: GoogleFonts.outfit(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Выйти', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WaiterService.logoutCurrentWaiter();
      setState(() {
        _currentWaiter = null;
        _currentIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFD4A043))),
      );
    }

    if (_currentWaiter == null) {
      return WaiterLoginScreen(onLoginSuccess: _onLoginSuccess);
    }

    final screens = [
      WaiterTablesScreen(currentWaiter: _currentWaiter!),
      WaiterOrdersScreen(currentWaiter: _currentWaiter!),
      WaiterCallsScreen(currentWaiter: _currentWaiter!),
      WaiterReservationsScreen(currentWaiter: _currentWaiter!),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFD4A043).withOpacity(0.2),
              child: Text(
                (_currentWaiter!['name'] ?? 'W')[0].toUpperCase(),
                style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentWaiter!['name'] ?? 'Официант',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Панель Официанта',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Сменить официанта',
            icon: const Icon(Icons.logout_rounded, color: Colors.white54),
            onPressed: _logout,
          ),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1C1C1E),
        selectedItemColor: const Color(0xFFD4A043),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 12),
        items: const [
          BottomNavigationBarViewItem(
            icon: Icon(Icons.table_restaurant_outlined),
            activeIcon: Icon(Icons.table_restaurant_rounded),
            label: 'Столы',
          ),
          BottomNavigationBarViewItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Заказы',
          ),
          BottomNavigationBarViewItem(
            icon: Icon(Icons.notifications_none_rounded),
            activeIcon: Icon(Icons.notifications_active_rounded),
            label: 'Вызовы',
          ),
          BottomNavigationBarViewItem(
            icon: Icon(Icons.event_seat_outlined),
            activeIcon: Icon(Icons.event_seat_rounded),
            label: 'Брони',
          ),
        ],
      ),
    );
  }
}

class BottomNavigationBarViewItem extends BottomNavigationBarItem {
  const BottomNavigationBarViewItem({
    required super.icon,
    required super.activeIcon,
    required super.label,
  });
}

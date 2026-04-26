import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'menu_management_screen.dart';
import 'ingredients_screen.dart';
import 'orders_screen.dart';
import 'tables_screen.dart';
import 'banner_screen.dart';
import 'settings_screen.dart';
import 'banquet_screen.dart';
import 'waiters_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.receipt_long_rounded, label: 'Заказы'),
    _NavItem(icon: Icons.restaurant_menu_rounded, label: 'Меню'),
    _NavItem(icon: Icons.eco_rounded, label: 'Ингредиенты'),
    _NavItem(icon: Icons.table_restaurant_rounded, label: 'Столы'),
    _NavItem(icon: Icons.play_circle_outline_rounded, label: 'Баннер'),
    _NavItem(icon: Icons.celebration_rounded, label: 'Банкеты'),
    _NavItem(icon: Icons.people_alt_rounded, label: 'Официанты'),
    _NavItem(icon: Icons.settings_rounded, label: 'Настройки'),
  ];

  final List<Widget> _screens = [
    const OrdersScreen(),
    const MenuManagementScreen(),
    const IngredientsScreen(),
    const TablesScreen(),
    const BannerScreen(),
    const BanquetScreen(),
    const WaitersScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Боковая навигация
        Container(
          width: 220,
          color: const Color(0xFF1A1A1A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('КАРКЫРА', style: GoogleFonts.outfit(
                      color: const Color(0xFFD4A043),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    )),
                    Text('Администратор', style: GoogleFonts.outfit(
                      color: Colors.white38,
                      fontSize: 12,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ...List.generate(_navItems.length, (i) {
                final item = _navItems[i];
                final isSelected = _selectedIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFD4A043).withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: const Color(0xFFD4A043).withOpacity(0.3), width: 1)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon,
                          color: isSelected ? const Color(0xFFD4A043) : Colors.white38,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(item.label,
                          style: GoogleFonts.outfit(
                            color: isSelected ? const Color(0xFFD4A043) : Colors.white54,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // Основной контент
        Expanded(child: _screens[_selectedIndex]),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        Expanded(child: _screens[_selectedIndex]),
        BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          backgroundColor: const Color(0xFF1A1A1A),
          selectedItemColor: const Color(0xFFD4A043),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          items: _navItems.map((item) => BottomNavigationBarItem(
            icon: Icon(item.icon),
            label: item.label,
          )).toList(),
        ),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../services/cart_provider.dart';
import '../services/menu_data_service.dart';
import 'dart:ui';

class PizzaConstructorScreen extends StatefulWidget {
  const PizzaConstructorScreen({super.key});

  @override
  State<PizzaConstructorScreen> createState() => _PizzaConstructorScreenState();
}

class _PizzaConstructorScreenState extends State<PizzaConstructorScreen> {
  MenuItem? leftHalf;
  MenuItem? rightHalf;
  
  List<MenuItem> get availablePizzas => MenuDataService.items.where((item) {
    // Находим категорию "Пицца"
    final cat = MenuDataService.categories.firstWhere(
      (c) => c.id == item.categoryId,
      orElse: () => Category(id: '', title: ''),
    );
    return cat.title.toLowerCase().contains('пицц') || cat.title.toLowerCase().contains('pizza');
  }).toList();

  double get totalPrice {
    if (leftHalf == null && rightHalf == null) return 0;
    if (leftHalf != null && rightHalf == null) return leftHalf!.price;
    if (leftHalf == null && rightHalf != null) return rightHalf!.price;
    // Логика: цена самой дорогой половины + 50 рублей за сборку (условно)
    return (leftHalf!.price > rightHalf!.price ? leftHalf!.price : rightHalf!.price) + 50;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'КОНСТРУКТОР ПОЛОВИНОК',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // Interactive Pizza Visual
          Expanded(
            flex: 4,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Shadow/Glow
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4A043).withOpacity(0.2),
                          blurRadius: 40,
                          spreadRadius: 10,
                        )
                      ],
                    ),
                  ),
                  // The Pizza
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: Stack(
                      children: [
                        // Left Half
                        ClipRect(
                          clipper: _HalfClipper(isLeft: true),
                          child: leftHalf != null 
                            ? Image.network(leftHalf!.images[0], fit: BoxFit.cover, width: 300, height: 300)
                            : _buildEmptyHalf(isLeft: true),
                        ),
                        // Right Half
                        ClipRect(
                          clipper: _HalfClipper(isLeft: false),
                          child: rightHalf != null 
                            ? Image.network(rightHalf!.images[0], fit: BoxFit.cover, width: 300, height: 300)
                            : _buildEmptyHalf(isLeft: false),
                        ),
                        // Divider Line
                        Center(
                          child: Container(
                            width: 2,
                            height: 320,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFD4A043).withOpacity(0.5),
                                  const Color(0xFFD4A043),
                                  const Color(0xFFD4A043).withOpacity(0.5),
                                  Colors.transparent,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Selection Area
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ВЫБЕРИТЕ ЧАСТИ',
                    style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildHalfSelector(
                        title: 'Левая',
                        selected: leftHalf,
                        onTap: () => _showPicker(true),
                      ),
                      const SizedBox(width: 16),
                      _buildHalfSelector(
                        title: 'Правая',
                        selected: rightHalf,
                        onTap: () => _showPicker(false),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Price and Add Button
                  if (leftHalf != null && rightHalf != null)
                    _buildOrderPanel(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHalf({required bool isLeft}) {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.add_circle_outline_rounded,
          color: Colors.white24,
          size: 40,
        ),
      ),
    );
  }

  Widget _buildHalfSelector({required String title, MenuItem? selected, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected != null ? const Color(0xFFD4A043) : Colors.white10,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                title.toUpperCase(),
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                selected?.title ?? 'Выбрать',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: selected != null ? Colors.white : Colors.white24,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderPanel() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ИТОГО',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              Text(
                '${totalPrice.toInt()} ₽',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                final cart = Provider.of<CartProvider>(context, listen: false);
                // В реальности мы бы передали специальный ID или создали новый продукт
                // Но для прототипа добавим "правую" половину с измененным именем
                final combinedTitle = 'Половинки: ${leftHalf!.title} / ${rightHalf!.title}';
                // Временный хак: добавляем один из товаров, но в корзине потом можно будет обработать кастомное имя
                cart.addToCart(leftHalf!.id, 1); 
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Пицца из половинок добавлена в корзину'),
                    backgroundColor: const Color(0xFFD4A043),
                  ),
                );
                Navigator.pop(context);
              },
              child: const Text('ДОБАВИТЬ В КОРЗИНУ'),
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(bool isLeft) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ВЫБЕРИТЕ ПИЦЦУ',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: availablePizzas.length,
                  itemBuilder: (context, index) {
                    final pizza = availablePizzas[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(pizza.images[0], width: 50, height: 50, fit: BoxFit.cover),
                      ),
                      title: Text(pizza.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text('${pizza.price.toInt()} ₽', style: const TextStyle(color: Colors.white54)),
                      onTap: () {
                        setState(() {
                          if (isLeft) {
                            leftHalf = pizza;
                          } else {
                            rightHalf = pizza;
                          }
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HalfClipper extends CustomClipper<Rect> {
  final bool isLeft;
  _HalfClipper({required this.isLeft});

  @override
  Rect getClip(Size size) {
    if (isLeft) {
      return Rect.fromLTWH(0, 0, size.width / 2, size.height);
    } else {
      return Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);
    }
  }

  @override
  bool shouldReclip(_HalfClipper oldClipper) => isLeft != oldClipper.isLeft;
}

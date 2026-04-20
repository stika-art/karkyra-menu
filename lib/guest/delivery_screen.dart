import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../services/telegram_service.dart';
import '../services/cart_provider.dart';
import '../services/menu_data_service.dart';
import '../models/menu_item.dart';

/// Экран корзины для режима Доставки (без разделения счета)
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController(); // Новое поле для доставки
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _success = false;

  Future<void> _submit(CartProvider cart) async {
    if (!_formKey.currentState!.validate()) return;
    if (cart.items.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // Собираем данные в нужный формат
      final preparedItems = cart.items.map((it) {
        // Безопасный поиск блюда в кеше
        final menuItemList = MenuDataService.items;
        final menuItem = menuItemList.firstWhere(
          (m) => m.id == it.menuItemId,
          orElse: () => menuItemList.isNotEmpty 
              ? menuItemList.first 
              : MenuItem(id: '0', categoryId: '0', title: 'Unknown', description: 'No description', price: 0, images: ['assets/images/placeholder.png'], ingredients: []),
        );
        return {
          'id': it.menuItemId,
          'title': menuItem.title,
          'price': menuItem.price,
          'qty': it.quantity,
        };
      }).toList();

      final total = preparedItems.fold<double>(0, (sum, it) => sum + ((it['price'] as double) * (it['qty'] as int)));

      // 1. Сохраняем в БД
      await Supabase.instance.client.from('delivery_orders').insert({
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'items': preparedItems,
        'total': total,
        'status': 'new',
      });

      // 2. Уведомляем в Telegram
      try {
        final msgDetails = 'Адрес: ${_addressController.text.trim()}';
        await TelegramService.notifyDeliveryOrder(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim() + '\n' + msgDetails,
          items: preparedItems,
          total: total,
        );
      } catch (tgErr) {
        debugPrint('TG Notify error: $tgErr');
      }

      // 3. Очищаем корзину ПОСЛЕ того как всё успешно
      try {
        cart.clearCartLocally();
      } catch (cartErr) {
        debugPrint('Cart clear error: $cartErr');
      }

      if (mounted) {
        setState(() {
          _success = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Order submit error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Ошибка оформления: $e'),
             backgroundColor: Colors.red,
             behavior: SnackBarBehavior.floating,
           ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
            ),
            const SizedBox(height: 20),
            Text('Заказ в обработке!', style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Ожидайте звонка от нашего менеджера', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A043),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Закрыть', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF151515), // Темный премиальный фон корзины
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      // Ограничиваем максимальную высоту чтобы можно было скроллить корзину
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ручка
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          
          Text('Ваш заказ', style: GoogleFonts.outfit(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // Список блюд в корзине
          Flexible(
            child: Consumer<CartProvider>(
              builder: (context, cart, child) {
                if (cart.items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32.0),
                    child: Center(child: Text('Корзина пуста', style: GoogleFonts.outfit(color: Colors.white54))),
                  );
                }

                double totalSum = 0;
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final item = cart.items[idx];
                    final menuItem = MenuDataService.items.firstWhere(
                      (m) => m.id == item.menuItemId,
                      orElse: () => MenuDataService.items.first,
                    );
                    
                    final itemTotal = menuItem.price * item.quantity;
                    totalSum += itemTotal;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildImage(menuItem.images[0], 60),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(menuItem.title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                const SizedBox(height: 6),
                                Text('${itemTotal.toInt()} ₽', style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ),
                          // Кнопки + и -
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _qtyBtn(Icons.remove, () {
                                  if (item.quantity > 1) {
                                    cart.updateQuantity(item.id, item.quantity - 1);
                                  } else {
                                    cart.removeItem(item.id);
                                  }
                                }),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('${item.quantity}', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                _qtyBtn(Icons.add, () => cart.updateQuantity(item.id, item.quantity + 1)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 20),

          // Форма доставки
          Text('Данные доставки', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          
          Expanded(
            flex: 0,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildField(_nameController, 'Ваше имя', Icons.person_outline_rounded),
                    const SizedBox(height: 12),
                    _buildField(_phoneController, 'Номер телефона', Icons.phone_outlined, keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),
                    _buildField(_addressController, 'Адрес доставки', Icons.location_on_outlined),
                    const SizedBox(height: 20),
                    
                    // Итого и кнопка
                    Consumer<CartProvider>(
                      builder: (context, cart, child) {
                        double grandTotal = 0;
                        for (var it in cart.items) {
                          final menuItem = MenuDataService.items.firstWhere((m) => m.id == it.menuItemId, orElse: () => MenuDataService.items.first);
                          grandTotal += menuItem.price * it.quantity;
                        }

                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_isLoading || cart.items.isEmpty) ? null : () => _submit(cart),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4A043),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Оформить заказ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(width: 12),
                                    Text('•', style: TextStyle(color: Colors.black.withOpacity(0.5))),
                                    const SizedBox(width: 12),
                                    Text('${grandTotal.toInt()} ₽', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.transparent,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, {TextInputType? keyboardType}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: (v) => (v == null || v.isEmpty) ? 'Обязательное поле' : null,
      style: GoogleFonts.outfit(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white38),
        prefixIcon: Icon(icon, color: const Color(0xFFD4A043)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildImage(String url, double size) {
    if (url.startsWith('assets/')) {
      return Image.asset(url, width: size, height: size, fit: BoxFit.cover);
    }
    return Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width: size, height: size, color: Colors.white12));
  }
}

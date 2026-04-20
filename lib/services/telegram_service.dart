import 'package:http/http.dart' as http;
import 'settings_service.dart';

class TelegramService {
  // Токен и chat_id берутся из базы данных (SettingsService)
  // Менять можно в Админке -> Настройки, без правки кода!

  static Future<void> sendMessage(String text) async {
    final token = SettingsService.telegramToken;
    final chatId = SettingsService.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) return;

    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
        },
      );
    } catch (e) {
      // Не блокируем работу приложения если Telegram недоступен
    }
  }

  static Future<void> notifyNewOrder({
    required String tableId,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} ₽').join('\n');
    final message = '''
🍽 <b>Новый заказ!</b>

🪑 Стол: <b>№$tableId</b>
$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} ₽</b>
''';
    await sendMessage(message);
  }

  static Future<void> notifyDeliveryOrder({
    required String name,
    required String phone,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} ₽').join('\n');
    final message = '''
🚗 <b>Новый заказ на доставку!</b>

👤 Имя: <b>$name</b>
📞 Телефон: <b>$phone</b>

$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} ₽</b>
''';
    await sendMessage(message);
  }
}

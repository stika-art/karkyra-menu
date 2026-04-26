import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_service.dart';

class TelegramService {
  static Future<String?> getWaiterChatId(String tableId) async {
    try {
      final res = await Supabase.instance.client
          .from('restaurant_tables')
          .select('waiters(telegram_chat_id)')
          .eq('id', tableId)
          .maybeSingle();
      
      if (res != null && res['waiters'] != null) {
        return res['waiters']['telegram_chat_id']?.toString();
      }
    } catch (e) {
      print('Error fetching waiter chat id: $e');
    }
    return null;
  }
  // Токен и chat_id берутся из базы данных (SettingsService)
  // Менять можно в Админке -> Настройки, без правки кода!

  static Future<void> sendMessage(String text, {String? customChatId}) async {
    final token = SettingsService.telegramToken;
    final chatId = customChatId ?? SettingsService.telegramChatId;

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
    String? customChatId,
  }) async {
    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} сом').join('\n');
    final message = '''
🍽 <b>Новый заказ!</b>

🪑 Стол: <b>№$tableId</b>
$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} сом</b>
''';
    await sendMessage(message, customChatId: customChatId);
  }

  static Future<void> notifyDeliveryOrder({
    required String name,
    required String phone,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} сом').join('\n');
    final message = '''
🚗 <b>Новый заказ на доставку!</b>

👤 Имя: <b>$name</b>
📞 Телефон: <b>$phone</b>

$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} сом</b>
''';
    await sendMessage(message);
  }

  static Future<void> notifyWaiterCall({
    required String tableId,
    String? customChatId,
  }) async {
    final message = '''
🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>

🪑 Стол: <b>№$tableId</b>
⏰ Время: <b>${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}</b>
''';
    await sendMessage(message, customChatId: customChatId);
  }
}

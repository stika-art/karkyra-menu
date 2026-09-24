import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_service.dart';

class TelegramService {
  /// Получает chat_id официанта, закреплённого за столом.
  /// tableId — номер стола из URL (например "1"), ищем по label.
  /// Если не нашли по label — пробуем по UUID (для бронирования из админки).
  static Future<String?> getWaiterChatId(String tableId) async {
    try {
      // Сначала ищем по label (номер стола из URL гостя, например "1", "2")
      var res = await Supabase.instance.client
          .from('restaurant_tables')
          .select('waiter_id, waiters(telegram_chat_id)')
          .or('label.ilike.%$tableId%,label.eq.Стол $tableId')
          .maybeSingle();
      
      // Если не нашли по label — ищем по UUID (когда вызов из бронирования)
      if (res == null || res['waiters'] == null) {
        res = await Supabase.instance.client
            .from('restaurant_tables')
            .select('waiter_id, waiters(telegram_chat_id)')
            .eq('id', tableId)
            .maybeSingle();
      }
      
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

  /// Отправить простое текстовое сообщение (HTML)
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

  /// Отправить сообщение с кастомной inline-клавиатурой (кнопки с callback_data или url)
  static Future<void> sendMessageWithInlineKeyboard({
    required String text,
    required List<List<Map<String, dynamic>>> inlineKeyboard,
    String? customChatId,
  }) async {
    final token = SettingsService.telegramToken;
    final chatId = customChatId ?? SettingsService.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) return;

    try {
      final replyMarkup = jsonEncode({'inline_keyboard': inlineKeyboard});

      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
          'reply_markup': jsonDecode(replyMarkup),
        }),
      );
    } catch (e) {
      print('Telegram inline keyboard message error: $e');
    }
  }

  /// Отправить сообщение с inline-кнопкой (URL)
  static Future<void> sendMessageWithButton({
    required String text,
    required String buttonText,
    required String buttonUrl,
    String? customChatId,
  }) async {
    final token = SettingsService.telegramToken;
    final chatId = customChatId ?? SettingsService.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) return;

    try {
      final replyMarkup = jsonEncode({
        'inline_keyboard': [
          [
            {'text': buttonText, 'url': buttonUrl}
          ]
        ]
      });

      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
          'reply_markup': jsonDecode(replyMarkup),
        }),
      );
    } catch (e) {
      print('Telegram button message error: $e');
    }
  }

  static Future<void> notifyNewOrder({
    required String tableId,
    required List<Map<String, dynamic>> items,
    required double total,
    String? customChatId,
    bool withAcceptButton = false,
  }) async {
    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} сом').join('\n');
    final message = '''
🍽 <b>Новый заказ!</b>

🪑 Стол: <b>№$tableId</b>
$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} сом</b>
''';
    
    if (withAcceptButton) {
      final inlineKeyboard = [
        [
          {
            'text': '👨‍🍳 Готовится',
            'callback_data': 'order_status:$tableId:processing',
          },
          {
            'text': '🍽 Подано',
            'callback_data': 'order_status:$tableId:served',
          },
        ],
        [
          {
            'text': '🧾 Расчёт / Освободить',
            'callback_data': 'table_clear:$tableId',
          }
        ]
      ];

      await sendMessageWithInlineKeyboard(
        text: message,
        inlineKeyboard: inlineKeyboard,
        customChatId: customChatId,
      );
    } else {
      await sendMessage(message, customChatId: customChatId);
    }
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

  /// Уведомление о вызове официанта — с интерактивными кнопками «Иду!» и «Обслужен» в Telegram
  static Future<void> notifyWaiterCall({
    required String tableId,
    String? callId,
    String? customChatId,
  }) async {
    final message = '''
🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>

🪑 Стол: <b>№$tableId</b>
⏰ Время: <b>${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}</b>
''';

    if (callId != null && callId.isNotEmpty) {
      final isPersonal = customChatId != null && customChatId.isNotEmpty;
      final inlineKeyboard = [
        [
          {
            'text': isPersonal ? '🏃‍♂️ Иду к столу №$tableId!' : '🏃‍♂️ Я подойду! (Стол №$tableId)',
            'callback_data': 'call_accept:$callId:$tableId',
          },
          {
            'text': '✅ Обслужен',
            'callback_data': 'call_done:$callId:$tableId',
          }
        ]
      ];

      await sendMessageWithInlineKeyboard(
        text: message,
        inlineKeyboard: inlineKeyboard,
        customChatId: customChatId,
      );
    } else {
      await sendMessage(message, customChatId: customChatId);
    }
  }

  /// Принять вызов официанта (обновить статус в базе)
  static Future<bool> acceptWaiterCall(String callId) async {
    try {
      await Supabase.instance.client
          .from('waiter_calls')
          .update({'status': 'accepted'})
          .eq('id', callId);
      return true;
    } catch (e) {
      print('Accept call error: $e');
      return false;
    }
  }

  /// Принять заказ (обновить статус в базе)
  static Future<bool> acceptTableOrder(String tableId) async {
    try {
      final res = await Supabase.instance.client
          .from('orders_new')
          .update({'status': 'processing'})
          .eq('table_id', tableId)
          .inFilter('status', ['confirmed', 'ordering'])
          .select();
      return res.isNotEmpty;
    } catch (e) {
      print('Accept order error: $e');
      return false;
    }
  }
}

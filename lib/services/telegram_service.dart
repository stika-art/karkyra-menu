import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_service.dart';

class TelegramService {
  /// Очищает номер стола от посторонних символов (например, "Стол 2" -> "2")
  static String cleanTableNumber(String tableId) {
    final numOnly = tableId.replaceAll(RegExp(r'[^0-9]'), '');
    return numOnly.isNotEmpty ? numOnly : tableId.trim();
  }

  /// Получает chat_id официанта, закреплённого за столом.
  /// tableId — номер стола из URL (например "1"), ищем по label.
  /// Если не нашли по label — пробуем по UUID (для бронирования из админки).
  static Future<String?> getWaiterChatId(String tableId) async {
    try {
      final cleanNum = cleanTableNumber(tableId);

      // Сначала ищем по label (номер стола из URL гостя, например "1", "2")
      var res = await Supabase.instance.client
          .from('restaurant_tables')
          .select('waiter_id, waiters(telegram_chat_id)')
          .or('label.ilike.%$cleanNum%,label.eq.Стол $cleanNum')
          .maybeSingle();

      // Если не нашли по label — пробуем по исходному tableId
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

  /// Отправить простое текстовое сообщение (HTML)
  static Future<Map<String, dynamic>?> sendMessage(String text, {String? customChatId}) async {
    final token = SettingsService.telegramToken;
    final chatId = customChatId ?? SettingsService.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['result'] != null) {
          return {
            'chat_id': chatId,
            'message_id': data['result']['message_id'],
            'text': text,
          };
        }
      }
    } catch (e) {
      print('Telegram sendMessage error: $e');
    }
    return null;
  }

  /// Отправить сообщение с кастомной inline-клавиатурой (кнопки с callback_data или url)
  static Future<Map<String, dynamic>?> sendMessageWithInlineKeyboard({
    required String text,
    required List<List<Map<String, dynamic>>> inlineKeyboard,
    String? customChatId,
  }) async {
    final token = SettingsService.telegramToken;
    final chatId = customChatId ?? SettingsService.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
          'reply_markup': {'inline_keyboard': inlineKeyboard},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['result'] != null) {
          return {
            'chat_id': chatId,
            'message_id': data['result']['message_id'],
            'text': text,
          };
        }
      }
    } catch (e) {
      print('Telegram inline keyboard message error: $e');
    }
    return null;
  }

  /// Редактировать текст и кнопки существующего Telegram-сообщения
  static Future<bool> editTgMessage({
    required String chatId,
    required int messageId,
    required String text,
    List<List<Map<String, dynamic>>>? inlineKeyboard,
  }) async {
    final token = SettingsService.telegramToken;
    if (token.isEmpty || chatId.isEmpty || messageId <= 0) return false;

    try {
      final body = <String, dynamic>{
        'chat_id': chatId,
        'message_id': messageId,
        'text': text,
        'parse_mode': 'HTML',
      };
      if (inlineKeyboard != null) {
        body['reply_markup'] = {'inline_keyboard': inlineKeyboard};
      }

      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/editMessageText'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('editTgMessage error: $e');
      return false;
    }
  }

  /// Регистрация сообщений Telegram в базе admin_settings для последующего редактирования
  static Future<void> registerTgMessages(String key, List<Map<String, dynamic>> newMsgs) async {
    if (newMsgs.isEmpty) return;
    try {
      final existingRes = await Supabase.instance.client
          .from('admin_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();

      List<dynamic> list = [];
      if (existingRes != null && existingRes['value'] != null) {
        try {
          list = jsonDecode(existingRes['value']);
        } catch (_) {}
      }

      for (var msg in newMsgs) {
        list.removeWhere((item) =>
            item['chat_id']?.toString() == msg['chat_id']?.toString() &&
            item['message_id']?.toString() == msg['message_id']?.toString());
        list.add(msg);
      }

      await Supabase.instance.client
          .from('admin_settings')
          .upsert({'key': key, 'value': jsonEncode(list)});
    } catch (e) {
      print('registerTgMessages error: $e');
    }
  }

  /// Получение сохраненных сообщений Telegram из admin_settings
  static Future<List<Map<String, dynamic>>> getTgMessages(String key) async {
    try {
      final res = await Supabase.instance.client
          .from('admin_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      if (res != null && res['value'] != null) {
        final decoded = jsonDecode(res['value']);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (e) {
      print('getTgMessages error: $e');
    }
    return [];
  }

  /// Отправка вызова официанта и автоматическая регистрация в обоих чатах (общий + официант)
  static Future<void> sendAndRegisterWaiterCall({
    required String tableId,
    required String callId,
  }) async {
    if (!SettingsService.telegramNotify) return;
    final token = SettingsService.telegramToken;
    final generalChatId = SettingsService.telegramChatId;
    if (token.isEmpty) return;

    final cleanNum = cleanTableNumber(tableId);
    final waiterChatId = await getWaiterChatId(tableId);
    final now = DateTime.now();
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final messageText = '''
🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>

🪑 Стол: <b>№$tableId</b>
⏰ Время: <b>$timeStr</b>
''';

    final sentMessages = <Map<String, dynamic>>[];

    // 1. Отправляем в общий чат ресторана
    if (generalChatId.isNotEmpty) {
      final adminKb = [
        [
          {
            'text': '🏃‍♂️ Я подойду! (Стол №$tableId)',
            'callback_data': 'call_accept:$callId:$cleanNum',
          },
          {
            'text': '✅ Обслужен',
            'callback_data': 'call_done:$callId:$cleanNum',
          }
        ]
      ];
      final res = await sendMessageWithInlineKeyboard(
        text: messageText,
        inlineKeyboard: adminKb,
        customChatId: generalChatId,
      );
      if (res != null) {
        sentMessages.add({
          'chat_id': generalChatId,
          'message_id': res['message_id'],
          'is_general': true,
          'original_text': messageText,
          'table_id': cleanNum,
          'call_id': callId,
        });
      }
    }

    // 2. Отправляем в личный чат официанта
    if (waiterChatId != null && waiterChatId.isNotEmpty && waiterChatId != generalChatId) {
      final waiterKb = [
        [
          {
            'text': '🏃‍♂️ Иду к столу №$tableId!',
            'callback_data': 'call_accept:$callId:$cleanNum',
          },
          {
            'text': '✅ Обслужен',
            'callback_data': 'call_done:$callId:$cleanNum',
          }
        ]
      ];
      final res = await sendMessageWithInlineKeyboard(
        text: messageText,
        inlineKeyboard: waiterKb,
        customChatId: waiterChatId,
      );
      if (res != null) {
        sentMessages.add({
          'chat_id': waiterChatId,
          'message_id': res['message_id'],
          'is_general': false,
          'original_text': messageText,
          'table_id': cleanNum,
          'call_id': callId,
        });
      }
    }

    if (sentMessages.isNotEmpty) {
      await registerTgMessages('tg_call_$callId', sentMessages);
    }
  }

  /// Отправка нового заказа и автоматическая регистрация в обоих чатах
  static Future<void> sendAndRegisterNewOrder({
    required String tableId,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    final token = SettingsService.telegramToken;
    final generalChatId = SettingsService.telegramChatId;
    if (token.isEmpty) return;

    final cleanNum = cleanTableNumber(tableId);
    final waiterChatId = await getWaiterChatId(tableId);

    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} сом').join('\n');
    final messageText = '''
🍽 <b>Новый заказ!</b>

🪑 Стол: <b>№$tableId</b>
$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} сом</b>
''';

    final inlineKeyboard = [
      [
        {
          'text': '👨‍🍳 Готовится',
          'callback_data': 'order_status:$cleanNum:processing',
        },
        {
          'text': '🍽 Подано',
          'callback_data': 'order_status:$cleanNum:served',
        },
      ],
      [
        {
          'text': '🧾 Расчёт / Освободить',
          'callback_data': 'table_clear:$cleanNum',
        }
      ]
    ];

    final sentMessages = <Map<String, dynamic>>[];

    // 1. В общий чат
    if (generalChatId.isNotEmpty) {
      final res = await sendMessageWithInlineKeyboard(
        text: messageText,
        inlineKeyboard: inlineKeyboard,
        customChatId: generalChatId,
      );
      if (res != null) {
        sentMessages.add({
          'chat_id': generalChatId,
          'message_id': res['message_id'],
          'is_general': true,
          'original_text': messageText,
          'table_id': cleanNum,
        });
      }
    }

    // 2. Лично официанту
    if (waiterChatId != null && waiterChatId.isNotEmpty && waiterChatId != generalChatId) {
      final res = await sendMessageWithInlineKeyboard(
        text: messageText,
        inlineKeyboard: inlineKeyboard,
        customChatId: waiterChatId,
      );
      if (res != null) {
        sentMessages.add({
          'chat_id': waiterChatId,
          'message_id': res['message_id'],
          'is_general': false,
          'original_text': messageText,
          'table_id': cleanNum,
        });
      }
    }

    if (sentMessages.isNotEmpty) {
      await registerTgMessages('tg_order_$cleanNum', sentMessages);
    }
  }

  /// Синхронизация принятия вызова (кнопка «Иду» исчезает у всех, показывается имя принявшего)
  static Future<void> syncCallAccepted({
    required String callId,
    required String tableId,
    String acceptedBy = 'Администратор',
  }) async {
    final cleanNum = cleanTableNumber(tableId);
    final now = DateTime.now();
    final nowStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final messages = await getTgMessages('tg_call_$callId');

    final nextKb = [
      [
        {
          'text': '✅ Обслужен (Стол №$cleanNum)',
          'callback_data': 'call_done:$callId:$cleanNum',
        }
      ]
    ];

    for (var m in messages) {
      final cId = m['chat_id']?.toString() ?? '';
      final mId = int.tryParse(m['message_id']?.toString() ?? '') ?? 0;
      final orig = m['original_text'] ?? '🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>\n\n🪑 Стол: <b>№$tableId</b>';
      if (cId.isNotEmpty && mId > 0) {
        final cleanOrig = orig.replaceAll(RegExp(r'\n\n🏃‍♂️.*$', dotAll: true), '');
        final newText = '$cleanOrig\n\n🏃‍♂️ <b>ПРИНЯТ ($acceptedBy идет к столу) в $nowStr</b>';
        await editTgMessage(
          chatId: cId,
          messageId: mId,
          text: newText,
          inlineKeyboard: nextKb,
        );
      }
    }
  }

  /// Синхронизация завершения вызова (удаление всех кнопок у всех)
  static Future<void> syncCallCompleted({
    required String callId,
    required String tableId,
    String completedBy = 'Администратор',
  }) async {
    final now = DateTime.now();
    final nowStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final messages = await getTgMessages('tg_call_$callId');

    for (var m in messages) {
      final cId = m['chat_id']?.toString() ?? '';
      final mId = int.tryParse(m['message_id']?.toString() ?? '') ?? 0;
      final orig = m['original_text'] ?? '🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>\n\n🪑 Стол: <b>№$tableId</b>';
      if (cId.isNotEmpty && mId > 0) {
        final cleanOrig = orig.replaceAll(RegExp(r'\n\n🏃‍♂️.*$', dotAll: true), '');
        final newText = '$cleanOrig\n\n✅ <b>ОБСЛУЖЕН ($completedBy) в $nowStr</b>';
        await editTgMessage(
          chatId: cId,
          messageId: mId,
          text: newText,
          inlineKeyboard: [],
        );
      }
    }

    try {
      await Supabase.instance.client
          .from('admin_settings')
          .delete()
          .eq('key', 'tg_call_$callId');
    } catch (_) {}
  }

  /// Синхронизация принятия заказа (кнопка «Готовится» исчезает у всех, показывается имя принявшего)
  static Future<void> syncOrderAccepted({
    required String tableId,
    String acceptedBy = 'Администратор',
  }) async {
    final cleanNum = cleanTableNumber(tableId);
    final now = DateTime.now();
    final nowStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final messages = await getTgMessages('tg_order_$cleanNum');

    final nextKb = [
      [
        {
          'text': '🍽 Подано',
          'callback_data': 'order_status:$cleanNum:served',
        }
      ],
      [
        {
          'text': '🧾 Расчёт / Освободить',
          'callback_data': 'table_clear:$cleanNum',
        }
      ]
    ];

    for (var m in messages) {
      final cId = m['chat_id']?.toString() ?? '';
      final mId = int.tryParse(m['message_id']?.toString() ?? '') ?? 0;
      final orig = m['original_text'] ?? '🍽 <b>Новый заказ!</b>\n\n🪑 Стол: <b>№$cleanNum</b>';
      if (cId.isNotEmpty && mId > 0) {
        final cleanOrig = orig.replaceAll(RegExp(r'\n\n📌 <b>Статус:.*$', dotAll: true), '');
        final newText = '$cleanOrig\n\n📌 <b>Статус: 👨‍🍳 Готовится (Принял: $acceptedBy в $nowStr)</b>';
        await editTgMessage(
          chatId: cId,
          messageId: mId,
          text: newText,
          inlineKeyboard: nextKb,
        );
      }
    }
  }

  /// Синхронизация закрытия стола (удаление всех кнопок в Telegram)
  static Future<void> syncTableCleared({
    required String tableId,
    String clearedBy = 'Администратор',
  }) async {
    final cleanNum = cleanTableNumber(tableId);
    final now = DateTime.now();
    final nowStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final messages = await getTgMessages('tg_order_$cleanNum');

    for (var m in messages) {
      final cId = m['chat_id']?.toString() ?? '';
      final mId = int.tryParse(m['message_id']?.toString() ?? '') ?? 0;
      final orig = m['original_text'] ?? '🍽 <b>Новый заказ!</b>\n\n🪑 Стол: <b>№$cleanNum</b>';
      if (cId.isNotEmpty && mId > 0) {
        final cleanOrig = orig.replaceAll(RegExp(r'\n\n📌 <b>Статус:.*$', dotAll: true), '');
        final newText = '$cleanOrig\n\n🧾 <b>СТОЛ РАССЧИТАН И ЗАКРЫТ ($clearedBy в $nowStr)</b>';
        await editTgMessage(
          chatId: cId,
          messageId: mId,
          text: newText,
          inlineKeyboard: [],
        );
      }
    }

    try {
      await Supabase.instance.client
          .from('admin_settings')
          .delete()
          .eq('key', 'tg_order_$cleanNum');
    } catch (_) {}
  }

  /// Сохраняем методы обратной совместимости
  static Future<void> notifyDeliveryOrder({
    required String name,
    required String phone,
    required List<Map<String, dynamic>> items,
    required double total,
    String? orderId,
  }) async {
    final itemLines = items.map((it) => '  • ${it['title']} x${it['qty']} — ${it['price']} сом').join('\n');
    final message = '''
🛵 <b>НОВЫЙ ЗАКАЗ НА ДОСТАВКУ!</b>

👤 Имя: <b>$name</b>
📞 Телефон/Адрес: <b>$phone</b>

$itemLines

💰 <b>Итого: ${total.toStringAsFixed(0)} сом</b>
''';

    if (orderId != null && orderId.isNotEmpty) {
      final buttons = [
        [
          {
            'text': '👨‍🍳 Принять доставку',
            'callback_data': 'deliv_status:$orderId:processing',
          },
          {
            'text': '❌ Отменить',
            'callback_data': 'deliv_status:$orderId:cancelled',
          },
        ]
      ];
      await sendMessageWithInlineKeyboard(text: message, inlineKeyboard: buttons);
    } else {
      await sendMessage(message);
    }
  }

  static Future<void> notifyBooking({
    required String bookingId,
    required String tableLabel,
    required String name,
    required String phone,
    required int guests,
    required String timeRange,
    String? preorderInfo,
    String? customChatId,
  }) async {
    final message = '''
📅 <b>НОВАЯ БРОНЬ СТОЛА!</b>

🪑 Стол: <b>№$tableLabel</b>
👤 Гость: <b>$name</b>
📞 Телефон: <b>$phone</b>
👥 Количество гостей: <b>$guests чел.</b>
⏰ Время: <b>$timeRange</b>
${(preorderInfo != null && preorderInfo.isNotEmpty) ? '\n🍽 <b>Предзаказ:</b> $preorderInfo' : ''}
''';

    final buttons = [
      [
        {
          'text': '✅ Подтвердить бронь',
          'callback_data': 'book_status:$bookingId:accept',
        },
        {
          'text': '❌ Отклонить',
          'callback_data': 'book_status:$bookingId:cancel',
        },
      ]
    ];

    await sendMessageWithInlineKeyboard(text: message, inlineKeyboard: buttons, customChatId: customChatId);
  }

  static Future<void> notifyNewOrder({
    required String tableId,
    required List<Map<String, dynamic>> items,
    required double total,
    String? customChatId,
    bool withAcceptButton = false,
  }) async {
    await sendAndRegisterNewOrder(tableId: tableId, items: items, total: total);
  }

  static Future<void> notifyWaiterCall({
    required String tableId,
    String? callId,
    String? customChatId,
  }) async {
    if (callId != null && callId.isNotEmpty) {
      await sendAndRegisterWaiterCall(tableId: tableId, callId: callId);
    } else {
      await sendMessage('🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>\n\n🪑 Стол: <b>№$tableId</b>', customChatId: customChatId);
    }
  }

  static Future<bool> acceptWaiterCall(String callId, {String tableId = '', String acceptedBy = 'Администратор'}) async {
    try {
      await Supabase.instance.client
          .from('waiter_calls')
          .update({'status': 'accepted'})
          .eq('id', callId);
      if (tableId.isNotEmpty) {
        await syncCallAccepted(callId: callId, tableId: tableId, acceptedBy: acceptedBy);
      }
      return true;
    } catch (e) {
      print('Accept call error: $e');
      return false;
    }
  }

  static Future<bool> acceptTableOrder(String tableId, {String acceptedBy = 'Администратор'}) async {
    try {
      final res = await Supabase.instance.client
          .from('orders_new')
          .update({'status': 'processing'})
          .eq('table_id', tableId)
          .inFilter('status', ['confirmed', 'ordering'])
          .select();
      await syncOrderAccepted(tableId: tableId, acceptedBy: acceptedBy);
      return res.isNotEmpty;
    } catch (e) {
      print('Accept order error: $e');
      return false;
    }
  }
}

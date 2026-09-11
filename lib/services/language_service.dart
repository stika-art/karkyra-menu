import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _prefKey = 'app_language_code';
  static final ValueNotifier<String> currentLocale = ValueNotifier<String>('ru');

  static String get currentLanguage => currentLocale.value;

  static const Map<String, String> languages = {
    'ru': 'Русский',
    'kg': 'Кыргызча',
    'en': 'English',
  };

  static const Map<String, String> flags = {
    'ru': '🇷🇺',
    'kg': '🇰🇬',
    'en': '🇬🇧',
  };

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && languages.containsKey(saved)) {
        currentLocale.value = saved;
      }
    } catch (_) {}
  }

  static Future<void> setLanguage(String code) async {
    if (!languages.containsKey(code)) return;
    currentLocale.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }

  static String getFlag(String code) => flags[code] ?? '🌐';
  static String getName(String code) => languages[code] ?? code;

  // Локализованные строки
  static final Map<String, Map<String, String>> _translations = {
    'review': {
      'ru': 'Отзыв',
      'kg': 'Пикир',
      'en': 'Review',
    },
    'call_waiter': {
      'ru': 'Официант',
      'kg': 'Официант',
      'en': 'Waiter',
    },
    'rate_visit': {
      'ru': 'ОЦЕНИТЕ ВАШЕ ПОСЕЩЕНИЕ',
      'kg': 'КЕЛИШИҢИЗДИ БААЛАҢЫЗ',
      'en': 'RATE YOUR VISIT',
    },
    'rate_button': {
      'ru': 'ОЦЕНИТЬ БЛЮДА И СЕРВИС',
      'kg': 'ТАМАК ЖАНА СЕРВИСТИ БААЛОО',
      'en': 'RATE DISHES & SERVICE',
    },
    'your_name': {
      'ru': 'Ваше имя',
      'kg': 'Сиздин атыңыз',
      'en': 'Your name',
    },
    'comment_hint': {
      'ru': 'Что вам понравилось или что нам улучшить?',
      'kg': 'Сизге эмне жакты же эмнени жакшыртышыбыз керек?',
      'en': 'What did you like or what can we improve?',
    },
    'submit_review': {
      'ru': 'ОТПРАВИТЬ ОТЗЫВ',
      'kg': 'ПИКИРДИ ЖӨНӨТҮҮ',
      'en': 'SUBMIT REVIEW',
    },
    'thanks_review': {
      'ru': 'Спасибо за ваш отзыв! Мы ценим ваше мнение ❤️',
      'kg': 'Пикириңиз үчүн чоң рахмат! Биз сиздин бааңызды баалайбыз ❤️',
      'en': 'Thank you for your feedback! We appreciate your review ❤️',
    },
    'rate_5': {
      'ru': 'Великолепно! 😍',
      'kg': 'Эң сонун! 😍',
      'en': 'Excellent! 😍',
    },
    'rate_4': {
      'ru': 'Хорошо 👍',
      'kg': 'Жакшы 👍',
      'en': 'Good 👍',
    },
    'rate_3': {
      'ru': 'Нормально 🤔',
      'kg': 'Орточо 🤔',
      'en': 'Okay 🤔',
    },
    'rate_2': {
      'ru': 'Не понравилось 🙁',
      'kg': 'Жаккан жок 🙁',
      'en': 'Disliked 🙁',
    },
    'rate_1': {
      'ru': 'Ужасно 😡',
      'kg': 'Абдан начар 😡',
      'en': 'Terrible 😡',
    },
    'order_accepted': {
      'ru': 'ЗАКАЗ ПРИНЯТ',
      'kg': 'БУЮРТМА КАБЫЛ АЛЫНДЫ',
      'en': 'ORDER ACCEPTED',
    },
    'order_now': {
      'ru': 'ЗАКАЗАТЬ',
      'kg': 'БУЮРТМА БЕРҮҮ',
      'en': 'ORDER',
    },
    'cart_empty': {
      'ru': 'КОРЗИНА ПУСТА',
      'kg': 'СЕБЕТ БОШ',
      'en': 'CART IS EMPTY',
    },
    'today': {
      'ru': 'СЕГОДНЯ',
      'kg': 'БҮГҮН',
      'en': 'TODAY',
    },
  };

  static String tr(String key) {
    final lang = currentLanguage;
    if (_translations.containsKey(key)) {
      return _translations[key]?[lang] ?? _translations[key]?['ru'] ?? key;
    }
    return key;
  }
}

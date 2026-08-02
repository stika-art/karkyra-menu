import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

/// Сервис настроек — загружает конфиг из Supabase
/// чтобы при смене администратора не нужно было трогать код
class SettingsService {
  static Map<String, String> _cache = {};
  static bool _loaded = false;

  static Future<void> load() async {
    try {
      final res = await Supabase.instance.client
          .from('admin_settings')
          .select()
          .timeout(const Duration(seconds: 5));
      _cache = {
        for (final row in res as List) row['key'].toString(): row['value'].toString()
      };
      _loaded = true;
    } catch (_) {
      try {
        final res = await Supabase.instance.client
            .from('settings')
            .select()
            .timeout(const Duration(seconds: 5));
        _cache = {
          for (final row in res as List) row['key'].toString(): row['value'].toString()
        };
        _loaded = true;
      } catch (_) {
        _loaded = false;
      }
    }
  }

  static String get adminPassword => _cache['admin_password'] ?? '2026';
  static String get telegramToken => _cache['telegram_token'] ?? '';
  static String get telegramChatId => _cache['telegram_chat_id'] ?? '';
  static bool get telegramNotify => _cache['telegram_notify'] != 'false';
  static String get weeklySchedule => _cache['weekly_schedule'] ?? '{"Mon":"08:00-21:30","Tue":"08:00-21:30","Wed":"08:00-21:30","Thu":"08:00-21:30","Fri":"08:00-21:30","Sat":"08:00-21:30","Sun":"08:00-21:30"}';
  
  static String getTodaySchedule() {
    try {
      final now = DateTime.now();
      final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final dayKey = days[now.weekday % 7];
      final Map<String, dynamic> schedule = json.decode(weeklySchedule);
      return schedule[dayKey] ?? "08:00-21:30";
    } catch (_) {
      return "08:00-21:30";
    }
  }
  
  static bool get isLoaded => _loaded;

  static Future<void> update(String key, String value) async {
    await Supabase.instance.client
        .from('admin_settings')
        .upsert({'key': key, 'value': value});
    _cache[key] = value;
  }
}

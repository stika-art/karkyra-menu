import 'package:supabase_flutter/supabase_flutter.dart';

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
        for (final row in res as List) row['key'] as String: row['value'] as String
      };
      _loaded = true;
    } catch (_) {
      // Если база недоступна — используем значения по умолчанию
      _loaded = false;
    }
  }

  static String get adminPassword => _cache['admin_password'] ?? 'karkyra2025';
  static String get telegramToken => _cache['telegram_token'] ?? '';
  static String get telegramChatId => _cache['telegram_chat_id'] ?? '';
  static bool get isLoaded => _loaded;

  static Future<void> update(String key, String value) async {
    await Supabase.instance.client
        .from('admin_settings')
        .upsert({'key': key, 'value': value});
    _cache[key] = value;
  }
}

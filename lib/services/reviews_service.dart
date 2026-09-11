import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'telegram_service.dart';

class ReviewItem {
  final String id;
  final String tableId;
  final String guestName;
  final int rating; // 1 to 5
  final String comment;
  final DateTime createdAt;

  ReviewItem({
    required this.id,
    required this.tableId,
    required this.guestName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      id: json['id']?.toString() ?? '',
      tableId: json['table_id']?.toString() ?? '',
      guestName: json['guest_name']?.toString() ?? 'Гость',
      rating: (json['rating'] as num?)?.toInt() ?? 5,
      comment: json['comment']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'table_id': tableId,
      'guest_name': guestName,
      'rating': rating,
      'comment': comment,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

class ReviewsService {
  static const String _settingsKey = 'guest_reviews';
  static List<ReviewItem> _cache = [];

  static List<ReviewItem> get reviews => List.unmodifiable(_cache);

  /// Загрузка всех отзывов
  static Future<List<ReviewItem>> loadReviews() async {
    try {
      // 1. Проверяем, существует ли отдельная таблица 'reviews'
      try {
        final res = await Supabase.instance.client
            .from('reviews')
            .select()
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 4));

        _cache = (res as List).map((r) => ReviewItem.fromJson(r)).toList();
        return _cache;
      } catch (_) {
        // Таблицы 'reviews' пока нет в схеме — используем надежное хранилище admin_settings
      }

      // 2. Читаем из admin_settings
      final res = await Supabase.instance.client
          .from('admin_settings')
          .select('value')
          .eq('key', _settingsKey)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (res != null && res['value'] != null) {
        final String raw = res['value'].toString();
        if (raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            _cache = decoded.map((r) => ReviewItem.fromJson(Map<String, dynamic>.from(r))).toList();
            _cache.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return _cache;
          }
        }
      }

      _cache = [];
      return _cache;
    } catch (e) {
      debugPrint('Error loading reviews: $e');
      return _cache;
    }
  }

  /// Добавление нового отзыва от гостя
  static Future<bool> addReview({
    required String tableId,
    required String guestName,
    required int rating,
    required String comment,
  }) async {
    final now = DateTime.now();
    final newId = 'rev_${now.millisecondsSinceEpoch}_${(1000 + (now.microsecond % 9000))}';
    final newReview = ReviewItem(
      id: newId,
      tableId: tableId,
      guestName: guestName.trim().isEmpty ? 'Гость' : guestName.trim(),
      rating: rating.clamp(1, 5),
      comment: comment.trim(),
      createdAt: now,
    );

    try {
      // 1. Пробуем записать в таблицу 'reviews'
      bool savedToTable = false;
      try {
        await Supabase.instance.client.from('reviews').insert({
          'id': newReview.id,
          'table_id': newReview.tableId,
          'guest_name': newReview.guestName,
          'rating': newReview.rating,
          'comment': newReview.comment,
          'created_at': newReview.createdAt.toUtc().toIso8601String(),
        }).timeout(const Duration(seconds: 4));
        savedToTable = true;
      } catch (_) {
        savedToTable = false;
      }

      // 2. Если отдельной таблицы нет, пишем в admin_settings
      if (!savedToTable) {
        await loadReviews();
        _cache.insert(0, newReview);
        final jsonList = _cache.map((r) => r.toJson()).toList();
        await Supabase.instance.client.from('admin_settings').upsert({
          'key': _settingsKey,
          'value': jsonEncode(jsonList),
        });
      } else {
        _cache.insert(0, newReview);
      }

      // 3. Отправляем моментальное уведомление в Telegram заведения
      try {
        final stars = '⭐' * newReview.rating;
        final tableLabel = newReview.tableId.isEmpty ? 'Онлайн' : '№${newReview.tableId}';
        final isNegative = newReview.rating <= 3;
        final header = isNegative
            ? '⚠️ <b>ВНИМАНИЕ! НИЗКАЯ ОЦЕНКА ГОСТЯ:</b>'
            : '🌟 <b>НОВЫЙ ОТЗЫВ ГОСТЯ:</b>';

        final msg = '$header\n\n'
            '⭐ <b>Оценка:</b> $stars (${newReview.rating}/5)\n'
            '📍 <b>Стол:</b> $tableLabel\n'
            '👤 <b>Гость:</b> ${newReview.guestName}\n'
            '💬 <b>Комментарий:</b> ${newReview.comment.isEmpty ? '<i>(без комментария)</i>' : newReview.comment}';

        await TelegramService.sendMessage(msg);
      } catch (tgErr) {
        debugPrint('Telegram review notify error: $tgErr');
      }

      return true;
    } catch (e) {
      debugPrint('Error adding review: $e');
      return false;
    }
  }

  /// Удаление отзыва из админ-панели (для удаления неприятных / неадекватных отзывов)
  static Future<bool> deleteReview(String reviewId) async {
    try {
      // 1. Пробуем удалить из таблицы 'reviews'
      try {
        await Supabase.instance.client.from('reviews').delete().eq('id', reviewId);
      } catch (_) {}

      // 2. Удаляем из admin_settings
      await loadReviews();
      _cache.removeWhere((r) => r.id == reviewId);
      final jsonList = _cache.map((r) => r.toJson()).toList();
      await Supabase.instance.client.from('admin_settings').upsert({
        'key': _settingsKey,
        'value': jsonEncode(jsonList),
      });

      return true;
    } catch (e) {
      debugPrint('Error deleting review: $e');
      return false;
    }
  }
}

import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://vgzdpbwcenckmjtgfvfw.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZnemRwYndjZW5ja21qdGdmdmZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2NDkxODAsImV4cCI6MjA5MjIyNTE4MH0.pFmPP9A9Tov4b6URS-LP5b3lYyB0fVXTKDvLY_MR120',
  );

  print('Очистка старых данных...');
  try { await supabase.rpc('clear_all_data'); } catch (_) {} // Можем игнорировать или использовать raw sql ниже

  print('Загрузка картинок...');
  final uploadedUrls = <String, String>{};
  
  final imgs = Directory('assets/images').listSync().whereType<File>();
  for (var file in imgs) {
    final fileName = file.uri.pathSegments.last;
    final path = 'migrated_assets/$fileName';
    try {
      await supabase.storage.from('media').uploadBinary(
        path,
        file.readAsBytesSync(),
        fileOptions: const FileOptions(upsert: true),
      );
      final url = supabase.storage.from('media').getPublicUrl(path);
      uploadedUrls['assets/images/$fileName'] = url;
      print('Загружен $fileName -> $url');
    } catch (e) {
      print('Ошибка $fileName: $e');
    }
  }

  print('Загрузка видео...');
  final videoUrls = <String, String>{};
  final vids = Directory('assets/videos').listSync().whereType<File>();
  for (var file in vids) {
    final fileName = file.uri.pathSegments.last;
    final path = 'migrated_assets/$fileName';
    try {
      await supabase.storage.from('media').uploadBinary(
        path,
        file.readAsBytesSync(),
        fileOptions: const FileOptions(upsert: true),
      );
      final url = supabase.storage.from('media').getPublicUrl(path);
      videoUrls['assets/videos/$fileName'] = url;
      print('Загружен $fileName -> $url');
    } catch (e) {
      print('Ошибка $fileName: $e');
    }
  }

  // Генерация SQL скрипта
  final sb = StringBuffer();
  sb.writeln('-- SQL скрипт для Supabase');
  sb.writeln('TRUNCATE TABLE dish_ingredients CASCADE;');
  sb.writeln('TRUNCATE TABLE menu_items_db CASCADE;');
  sb.writeln('TRUNCATE TABLE categories CASCADE;');
  sb.writeln('TRUNCATE TABLE ingredients CASCADE;');
  sb.writeln('TRUNCATE TABLE banners CASCADE;');

  sb.writeln('\n-- Категории');
  sb.writeln("INSERT INTO categories (id, title, icon, sort_order) VALUES");
  sb.writeln("('11111111-1111-1111-1111-111111111111', 'Первые блюда', '🥣', 1),");
  sb.writeln("('22222222-2222-2222-2222-222222222222', 'Вторые блюда', '🍛', 2),");
  sb.writeln("('33333333-3333-3333-3333-333333333333', 'Завтраки', '🍳', 3),");
  sb.writeln("('44444444-4444-4444-4444-444444444444', 'Кыргызская кухня', '🇰🇬', 4),");
  sb.writeln("('55555555-5555-5555-5555-555555555555', 'Чай', '🫖', 5),");
  sb.writeln("('66666666-6666-6666-6666-666666666666', 'Напитки', '🥤', 6),");
  sb.writeln("('77777777-7777-7777-7777-777777777777', 'Пицца', '🍕', 7),");
  sb.writeln("('88888888-8888-8888-8888-888888888888', 'Суши', '🍣', 8);");

  String url(String assetPath) => uploadedUrls[assetPath] ?? 'https://cdn-icons-png.flaticon.com/512/3256/3256860.png';

  sb.writeln('\n-- Блюда');
  sb.writeln("INSERT INTO menu_items_db (id, category_id, title, description, price, photo_url, weight, calories, proteins, fats, carbs, spice_level, is_hit, is_new, is_chef_choice, sort_order) VALUES");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', '11111111-1111-1111-1111-111111111111', 'Шорпо из баранины', 'Традиционный наваристый суп с мясом молодого барашка и овощами.', 350, '${url('assets/images/shorpo.png')}', '350 г', 450, 25, 30, 15, 1, true, false, true, 1),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', '22222222-2222-2222-2222-222222222222', 'Стейк Рибай', 'Сочный стейк из мраморной говядины, приготовленный на углях.', 1200, '${url('assets/images/steak.png')}', '300 г', 750, 55, 60, 2, 0, true, false, false, 2),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', '33333333-3333-3333-3333-333333333333', 'Завтрак \"Каркыра\"', 'Домашние яйца, свежий каймак, горный мед и горячая лепешка.', 290, '${url('assets/images/breakfast.png')}', '320 г', 580, 18, 25, 70, 0, false, true, false, 3),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', '44444444-4444-4444-4444-444444444444', 'Бешбармак классический', 'Национальное блюдо из рубленного мяса и тонкого теста.', 480, '${url('assets/images/beshbarmak.png')}', '450 г', 620, 45, 35, 40, 1, true, false, true, 4),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5', '55555555-5555-5555-5555-555555555555', 'Фирменный черный чай', 'Насыщенный чай с добавлением горных трав и ягод.', 150, '${url('assets/images/tea.png')}', '600 мл', 10, 0, 0, 2, 0, false, false, false, 5),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6', '77777777-7777-7777-7777-777777777777', 'Пицца Маргарита', 'Классическая пицца на тонком тесте с томатами и моцареллой.', 550, '${url('assets/images/pizza.png')}', '500 г', 890, 35, 40, 95, 0, false, false, false, 6),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa7', '88888888-8888-8888-8888-888888888888', 'Сет Филадельфия', 'Классические роллы со свежим лососем и сливочным сыром.', 850, '${url('assets/images/sushi.png')}', '240 г', 560, 22, 28, 55, 2, false, false, false, 7);");

  sb.writeln('\n-- Ингредиенты');
  sb.writeln("INSERT INTO ingredients (id, name, photo_url) VALUES");
  sb.writeln("('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'Баранина', '${url('assets/images/meat.png')}'),");
  sb.writeln("('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'Картофель', '${url('assets/images/potato.png')}'),");
  sb.writeln("('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', 'Морковь', '${url('assets/images/carrot.png')}'),");
  sb.writeln("('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4', 'Мраморная говядина', '${url('assets/images/beef.png')}'),");
  sb.writeln("('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb5', 'Лепешка', '${url('assets/images/bread.png')}'),");
  sb.writeln("('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb6', 'Сыр', '${url('assets/images/cheese.png')}');");

  sb.writeln('\n-- Связи ингредиентов');
  sb.writeln("INSERT INTO dish_ingredients (dish_id, ingredient_id) VALUES");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1'),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4'),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb6'),");
  sb.writeln("('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb5');");

  sb.writeln('\n-- Баннер');
  String? vidUrl = videoUrls['assets/videos/test.mp4'] ?? videoUrls['assets/videos/test2.mp4'];
  if (vidUrl != null) {
      sb.writeln("INSERT INTO banners (url, type, is_active, filename) VALUES ('$vidUrl', 'video', true, 'promo.mp4');");
  } else {
      sb.writeln("-- Видео для баннера не найдено ;");
  }

  File('migration_sql.txt').writeAsStringSync(sb.toString());
  print('\\n--- ГОТОВО ---');
  print('SQL скрипт сохранен в migration_sql.txt');
}

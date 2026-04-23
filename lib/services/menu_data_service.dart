import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_item.dart';
import '../models/category.dart';
import '../data/mock_data.dart' as mock;

/// Сервис загрузки меню из Supabase.
/// Если база недоступна или пуста — возвращает моковые данные как запасной вариант.
class MenuDataService {
  static List<MenuItem> _cachedItems = [];
  static List<Category> _cachedCategories = [];
  static List<Map<String, String>> _cachedBanners = [];
  static bool _loaded = false;

  static List<MenuItem> get items => _cachedItems;
  static List<Category> get categories => _cachedCategories;
  static List<Map<String, String>> get banners => 
      _cachedBanners.isNotEmpty ? _cachedBanners : [{'url': 'assets/videos/test.mp4', 'type': 'video'}];

  static Future<void> load() async {
    try {
      // Загружаем категории
      final catsRes = await Supabase.instance.client
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('sort_order')
          .timeout(const Duration(seconds: 5));

      final cats = (catsRes as List).map<Category>((c) => Category(
        id: c['id'] as String,
        title: c['title'] as String,
        emoji: c['icon'] as String? ?? '🍽',
      )).toList();

      // Загружаем блюда (только доступные)
      final itemsRes = await Supabase.instance.client
          .from('menu_items_db')
          .select()
          .eq('is_available', true)
          .order('sort_order')
          .timeout(const Duration(seconds: 5));

      // Загружаем ингредиенты
      final ingredientsRes = await Supabase.instance.client.from('ingredients').select().timeout(const Duration(seconds: 5));
      final Map<String, Map<String, dynamic>> allIngredients = {
        for (var i in ingredientsRes) i['id']: i
      };

      // Загружаем связи
      final dishIngsRes = await Supabase.instance.client.from('dish_ingredients').select().timeout(const Duration(seconds: 5));
      final Map<String, List<String>> dishToIngredients = {};
      for (var row in dishIngsRes) {
        final dId = row['dish_id'] as String;
        final iId = row['ingredient_id'] as String;
        if (!dishToIngredients.containsKey(dId)) {
          dishToIngredients[dId] = [];
        }
        dishToIngredients[dId]!.add(iId);
      }

      final items = (itemsRes as List).map<MenuItem>((d) {
        final dId = d['id'] as String;
        final ingIds = dishToIngredients[dId] ?? [];
        final names = <String>[];
        final images = <String, String>{};

        for (var iId in ingIds) {
          final ingData = allIngredients[iId];
          if (ingData != null) {
            final name = ingData['name'] as String;
            names.add(name);
            if (ingData['photo_url'] != null) {
              images[name] = ingData['photo_url'] as String;
            }
          }
        }

        return MenuItem(
        id: d['id'] as String,
        categoryId: d['category_id'] as String? ?? '',
        title: d['title'] as String,
        description: d['description'] as String? ?? '',
        price: (d['price'] as num).toDouble(),
        images: () {
          final imgs = [
            if (d['photo_url'] != null) d['photo_url'] as String,
            if ((d as Map).containsKey('photo_url2') && d['photo_url2'] != null) d['photo_url2'] as String,
            if ((d as Map).containsKey('photo_url3') && d['photo_url3'] != null) d['photo_url3'] as String,
          ];
          return imgs.isEmpty ? ['assets/images/placeholder.png'] : imgs;
        }(),
        weight: d['weight'] as String?,
        ingredients: names,
        ingredientImages: images,
        calories: d['calories'] != null ? (d['calories'] as num).toDouble() : null,
        proteins: d['proteins'] != null ? (d['proteins'] as num).toDouble() : null,
        fats: d['fats'] != null ? (d['fats'] as num).toDouble() : null,
        carbs: d['carbs'] != null ? (d['carbs'] as num).toDouble() : null,
        spiciness: d['spice_level'] as int? ?? 0,
        isHit: d['is_hit'] as bool? ?? false,
        isNew: d['is_new'] as bool? ?? false,
        isChefChoice: d['is_chef_choice'] as bool? ?? false,
        isTop: d['is_top'] as bool? ?? false,
        isPromo: d['is_promo'] as bool? ?? false,
      );
      }).toList();

      // Загружаем баннеры
      final bannerRes = await Supabase.instance.client
          .from('banners')
          .select('url, type')
          .eq('is_active', true)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 5));
      
      if (bannerRes != null) {
        _cachedBanners = (bannerRes as List).map<Map<String, String>>((b) => {
          'url': (b['url'] ?? '').toString(),
          'type': (b['type'] ?? 'video').toString(),
        }).toList();
      }

      if (cats.isNotEmpty || items.isNotEmpty) {
        _cachedCategories = cats;
        _cachedItems = items;
        _loaded = true;
      }
    } catch (_) {
      // При ошибке используем моковые данные (fallback)
      _loaded = false;
    }
  }

  static void invalidate() {
    _loaded = false;
    _cachedItems = [];
    _cachedCategories = [];
    _cachedBanners = [];
  }
}

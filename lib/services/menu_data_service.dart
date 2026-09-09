import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_item.dart';
import '../models/category.dart';

/// Сервис загрузки меню из Supabase с мгновенным локальным кэшированием (Offline-First / Stale-While-Revalidate).
class MenuDataService {
  static List<MenuItem> _cachedItems = [];
  static List<Category> _cachedCategories = [];
  static List<Map<String, String>> _cachedBanners = [];
  static bool _loaded = false;

  static List<MenuItem> get items => _cachedItems;
  static List<Category> get categories => _cachedCategories;
  static List<Map<String, String>> get banners => _cachedBanners;
  static bool get isLoaded => _loaded;

  /// Мгновенная инициализация из локальной памяти браузера/устройства (0 миллисекунд)
  static void initFromStorage(SharedPreferences prefs) {
    try {
      final catsStr = prefs.getString('cached_categories_v2');
      if (catsStr != null && catsStr.isNotEmpty) {
        final List list = jsonDecode(catsStr);
        _cachedCategories = list.map<Category>((c) => Category(
          id: c['id'] as String,
          title: c['title'] as String,
          emoji: c['emoji'] as String? ?? '🍽',
        )).toList();
      }

      final itemsStr = prefs.getString('cached_items_v2');
      if (itemsStr != null && itemsStr.isNotEmpty) {
        final List list = jsonDecode(itemsStr);
        _cachedItems = list.map<MenuItem>((d) => MenuItem(
          id: d['id'] as String,
          categoryId: d['categoryId'] as String? ?? '',
          title: d['title'] as String,
          description: d['description'] as String? ?? '',
          price: (d['price'] as num).toDouble(),
          images: (d['images'] as List).map((e) => e.toString()).toList(),
          weight: d['weight'] as String?,
          ingredients: (d['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [],
          ingredientImages: (d['ingredientImages'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
          spiciness: d['spiciness'] as int? ?? 0,
          calories: d['calories'] != null ? (d['calories'] as num).toDouble() : null,
          proteins: d['proteins'] != null ? (d['proteins'] as num).toDouble() : null,
          fats: d['fats'] != null ? (d['fats'] as num).toDouble() : null,
          carbs: d['carbs'] != null ? (d['carbs'] as num).toDouble() : null,
          isHit: d['isHit'] as bool? ?? false,
          isNew: d['isNew'] as bool? ?? false,
          isChefChoice: d['isChefChoice'] as bool? ?? false,
          isTop: d['isTop'] as bool? ?? false,
          isPromo: d['isPromo'] as bool? ?? false,
        )).toList();
      }

      final bannersStr = prefs.getString('cached_banners_v2');
      if (bannersStr != null && bannersStr.isNotEmpty) {
        final List list = jsonDecode(bannersStr);
        _cachedBanners = list.map<Map<String, String>>((b) {
          return (b as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        }).toList();
      }

      if (_cachedItems.isNotEmpty) {
        _loaded = true;
      }
    } catch (_) {}
  }

  static Future<void> _saveToStorage(
    List<Category> cats,
    List<MenuItem> items,
    List<Map<String, String>> banners,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final catsJson = jsonEncode(cats.map((c) => {
        'id': c.id,
        'title': c.title,
        'emoji': c.emoji,
      }).toList());
      await prefs.setString('cached_categories_v2', catsJson);

      final itemsJson = jsonEncode(items.map((i) => {
        'id': i.id,
        'categoryId': i.categoryId,
        'title': i.title,
        'description': i.description,
        'price': i.price,
        'images': i.images,
        'weight': i.weight,
        'ingredients': i.ingredients,
        'ingredientImages': i.ingredientImages,
        'spiciness': i.spiciness,
        'calories': i.calories,
        'proteins': i.proteins,
        'fats': i.fats,
        'carbs': i.carbs,
        'isHit': i.isHit,
        'isNew': i.isNew,
        'isChefChoice': i.isChefChoice,
        'isTop': i.isTop,
        'isPromo': i.isPromo,
      }).toList());
      await prefs.setString('cached_items_v2', itemsJson);

      final bannersJson = jsonEncode(banners);
      await prefs.setString('cached_banners_v2', bannersJson);
    } catch (_) {}
  }

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
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 5));
      
      var loadedBanners = <Map<String, String>>[];
      if (bannerRes != null) {
        loadedBanners = (bannerRes as List).map<Map<String, String>>((b) {
          final map = <String, String>{};
          (b as Map<String, dynamic>).forEach((key, value) {
            map[key] = value?.toString() ?? '';
          });
          return map;
        }).toList();
        _cachedBanners = loadedBanners;
      }

      if (cats.isNotEmpty || items.isNotEmpty) {
        _cachedCategories = cats;
        _cachedItems = items;
        _loaded = true;
        _saveToStorage(cats, items, _cachedBanners);
      }
    } catch (_) {
      // При ошибке сохраняем кэш
    }
  }

  static void invalidate() {
    _loaded = false;
    _cachedItems = [];
    _cachedCategories = [];
    _cachedBanners = [];
  }
}

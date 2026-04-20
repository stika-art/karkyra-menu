class MenuItem {
  final String id;
  final String categoryId;
  final String title;
  final String description;
  final double price;
  final List<String> images;
  final String? weight;
  final List<String> ingredients;
  final Map<String, String> ingredientImages; // Name -> ImagePath
  final int spiciness; // 0 to 5
  final double? calories;
  final double? proteins;
  final double? fats;
  final double? carbs;
  final bool isHit;
  final bool isNew;
  final bool isChefChoice;
  final bool isVegan;
  final bool isGlutenFree;

  MenuItem({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.price,
    required this.images,
    this.weight,
    this.ingredients = const [],
    this.ingredientImages = const {},
    this.spiciness = 0,
    this.calories,
    this.proteins,
    this.fats,
    this.carbs,
    this.isHit = false,
    this.isNew = false,
    this.isChefChoice = false,
    this.isVegan = false,
    this.isGlutenFree = false,
  });
}

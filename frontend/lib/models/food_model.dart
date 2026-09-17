// [File: lib/models/food_model.dart]
class FoodModel {
  final String id;
  final String name;
  final double calories; // Calo trên 100g
  final double protein;
  final double carbs;
  final double fat;
  final List<String> tags; // [HIGH_CARB, HIGH_FAT...]

  FoodModel({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.tags,
  });

  factory FoodModel.fromJson(Map<String, dynamic> json) {
    // Helper parse số an toàn
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is int) return val.toDouble();
      if (val is double) return val;
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    return FoodModel(
      // Ưu tiên lấy id hoặc _id từ Mongo
      id: json['_id']?.toString() ??
          json['id']?.toString() ??
          '', // ← đọc cả 2, ưu tiên _id của Mongo
      name: (json['name'] ?? 'Unknown').toString(),
      calories: parseDouble(json['calories']),
      protein: parseDouble(json['protein']),
      carbs: parseDouble(json['carbs']),
      fat: parseDouble(json['fat']),
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
    );
  }
}

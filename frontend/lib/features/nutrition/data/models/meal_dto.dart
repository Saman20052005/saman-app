// lib/features/nutrition/data/models/meal_dto.dart
import '../../../../models/nutrition_model.dart';

class MealDto {
  final String foodId;
  final String name;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final int weightGrams;
  final String mealType;
  final String time;
  final bool isEaten;
  final List<String> tags;
  final String? image;
  final List<Map<String, dynamic>> foodsList;

  MealDto({
    required this.foodId,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.weightGrams,
    required this.mealType,
    required this.time,
    this.isEaten = false,
    this.tags = const [],
    this.image,
    this.foodsList = const [],
  });

  factory MealDto.fromJson(Map<String, dynamic> json) {
    final foods = json['foods'] as List<dynamic>?;
    final firstFood = (foods != null && foods.isNotEmpty)
        ? Map<String, dynamic>.from(foods[0] as Map)
        : json;

    final mealTotalCal = (json['total_calories'] as num?)?.toInt();
    final mealTotalPro = (json['total_protein'] as num?)?.toDouble();
    final mealTotalCarb = (json['total_carbs'] as num?)?.toDouble();
    final mealTotalFat = (json['total_fat'] as num?)?.toDouble();

    return MealDto(
      foodId: firstFood['food_id']?.toString() ?? '',
      name: firstFood['name']?.toString() ??
          json['name']?.toString() ??
          'Unknown Food',
      calories: mealTotalCal ?? (firstFood['calories'] as num?)?.toInt() ?? 0,
      protein: mealTotalPro ?? (firstFood['protein'] as num?)?.toDouble() ?? 0,
      carbs: mealTotalCarb ?? (firstFood['carbs'] as num?)?.toDouble() ?? 0,
      fat: mealTotalFat ?? (firstFood['fat'] as num?)?.toDouble() ?? 0,
      weightGrams: (firstFood['weight_grams'] as num?)?.toInt() ?? 100,
      mealType: json['meal_type']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      isEaten: json['isEaten'] ?? false,
      tags: List<String>.from(json['tags'] ?? []),
      image: firstFood['image']?.toString(),
      foodsList:
          foods?.map((f) => Map<String, dynamic>.from(f as Map)).toList() ?? [],
    );
  }

  Meal toEntity() {
    return Meal(
      foodId: foodId,
      name: name,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      weightGrams: weightGrams,
      mealType: mealType,
      time: time,
      isEaten: isEaten,
      tags: tags,
      image: image,
      foodsList: foodsList,
    );
  }
}

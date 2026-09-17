// lib/features/nutrition/data/models/nutrition_log_entry_dto.dart
import '../../../../models/nutrition_model.dart';

class NutritionLogEntryDto {
  final String logId;
  final String foodName;
  final String mealType;
  final int totalCalories;
  final double protein;
  final double carbs;
  final double fat;
  final List<Map<String, dynamic>> foods;

  NutritionLogEntryDto({
    required this.logId,
    required this.foodName,
    required this.mealType,
    required this.totalCalories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.foods = const [],
  });

  factory NutritionLogEntryDto.fromJson(Map<String, dynamic> json) {
    return NutritionLogEntryDto(
      logId: (json['log_id'] ?? json['_id'] ?? '').toString(),
      foodName: json['food_name'] ?? json['name'] ?? 'Unknown',
      mealType: json['meal_type'] ?? '',
      totalCalories: (json['calories'] as num?)?.toInt() ??
          (json['total_calories'] as num?)?.toInt() ??
          0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      foods: (json['foods'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  NutritionLogEntry toEntity() {
    return NutritionLogEntry(
      logId: logId,
      foodName: foodName,
      mealType: mealType,
      totalCalories: totalCalories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      foods: foods,
    );
  }
}

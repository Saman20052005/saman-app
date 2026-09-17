// lib/features/nutrition/domain/entities/nutrition_log_entry.dart
import 'package:equatable/equatable.dart';

class NutritionLogEntry extends Equatable {
  final String logId;
  final String foodName;
  final String mealType;
  final int totalCalories;
  final double protein;
  final double carbs;
  final double fat;
  final List<Map<String, dynamic>> foods;

  const NutritionLogEntry({
    required this.logId,
    required this.foodName,
    required this.mealType,
    required this.totalCalories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.foods = const [],
  });

  @override
  List<Object?> get props =>
      [logId, foodName, mealType, totalCalories, protein, carbs, fat, foods];
}

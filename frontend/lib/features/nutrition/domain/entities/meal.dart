// lib/features/nutrition/domain/entities/meal.dart
import 'package:equatable/equatable.dart';

class Meal extends Equatable {
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

  const Meal({
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

  @override
  List<Object?> get props => [
        foodId,
        name,
        calories,
        protein,
        carbs,
        fat,
        weightGrams,
        mealType,
        time,
        isEaten,
        tags,
        image,
        foodsList,
      ];

  Meal copyWith({
    String? foodId,
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    int? weightGrams,
    String? mealType,
    String? time,
    bool? isEaten,
    List<String>? tags,
    String? image,
    List<Map<String, dynamic>>? foodsList,
  }) {
    return Meal(
      foodId: foodId ?? this.foodId,
      name: name ?? this.name,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      weightGrams: weightGrams ?? this.weightGrams,
      mealType: mealType ?? this.mealType,
      time: time ?? this.time,
      isEaten: isEaten ?? this.isEaten,
      tags: tags ?? this.tags,
      image: image ?? this.image,
      foodsList: foodsList ?? this.foodsList,
    );
  }
}

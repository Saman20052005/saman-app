// lib/features/nutrition/domain/entities/nutrition_plan.dart
import 'package:equatable/equatable.dart';
import 'macro_targets.dart';
import 'meal.dart';
import 'supplement.dart';
import 'nutrition_log_entry.dart';

class NutritionPlan extends Equatable {
  final String? id;
  final String date;
  final List<Meal> meals;
  final List<NutritionLogEntry> entries;
  final List<Supplement> supplements;
  final int currentWater;
  final int targetWater;
  final int totalCaloriesConsumed;
  final int totalProteinConsumed;
  final int totalCarbsConsumed;
  final int totalFatConsumed;
  final int rolloverCalories;
  final MacroTargets macroTargets;

  const NutritionPlan({
    this.id,
    required this.date,
    required this.meals,
    this.entries = const [],
    this.supplements = const [],
    this.currentWater = 0,
    this.targetWater = 2000,
    this.totalCaloriesConsumed = 0,
    this.totalProteinConsumed = 0,
    this.totalCarbsConsumed = 0,
    this.totalFatConsumed = 0,
    this.rolloverCalories = 0,
    this.macroTargets = MacroTargets.defaultTargets,
  });

  @override
  List<Object?> get props => [
        id,
        date,
        meals,
        entries,
        supplements,
        currentWater,
        targetWater,
        totalCaloriesConsumed,
        totalProteinConsumed,
        totalCarbsConsumed,
        totalFatConsumed,
        rolloverCalories,
        macroTargets,
      ];

  NutritionPlan copyWith({
    String? id,
    String? date,
    List<Meal>? meals,
    List<NutritionLogEntry>? entries,
    List<Supplement>? supplements,
    int? currentWater,
    int? targetWater,
    int? totalCaloriesConsumed,
    int? totalProteinConsumed,
    int? totalCarbsConsumed,
    int? totalFatConsumed,
    int? rolloverCalories,
    MacroTargets? macroTargets,
  }) {
    return NutritionPlan(
      id: id ?? this.id,
      date: date ?? this.date,
      meals: meals ?? this.meals,
      entries: entries ?? this.entries,
      supplements: supplements ?? this.supplements,
      currentWater: currentWater ?? this.currentWater,
      targetWater: targetWater ?? this.targetWater,
      totalCaloriesConsumed:
          totalCaloriesConsumed ?? this.totalCaloriesConsumed,
      totalProteinConsumed: totalProteinConsumed ?? this.totalProteinConsumed,
      totalCarbsConsumed: totalCarbsConsumed ?? this.totalCarbsConsumed,
      totalFatConsumed: totalFatConsumed ?? this.totalFatConsumed,
      rolloverCalories: rolloverCalories ?? this.rolloverCalories,
      macroTargets: macroTargets ?? this.macroTargets,
    );
  }
}

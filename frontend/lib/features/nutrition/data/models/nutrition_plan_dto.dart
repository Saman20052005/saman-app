import '../../../../models/nutrition_model.dart';
import 'meal_dto.dart';
import 'supplement_dto.dart';
import 'nutrition_log_entry_dto.dart';
import 'macro_targets_dto.dart';

class NutritionPlanDto {
  final String? id;
  final String date;
  final List<MealDto> meals;
  final List<NutritionLogEntryDto> entries;
  final List<SupplementDto> supplements;
  final int currentWater;
  final int targetWater;
  final int waterVersion;
  final int totalCaloriesConsumed;
  final int totalProteinConsumed;
  final int totalCarbsConsumed;
  final int totalFatConsumed;
  final int rolloverCalories;
  final MacroTargetsDto macroTargets;

  NutritionPlanDto({
    this.id,
    required this.date,
    required this.meals,
    this.entries = const [],
    this.supplements = const [],
    this.currentWater = 0,
    this.targetWater = 2000,
    this.waterVersion = 0,
    this.totalCaloriesConsumed = 0,
    this.totalProteinConsumed = 0,
    this.totalCarbsConsumed = 0,
    this.totalFatConsumed = 0,
    this.rolloverCalories = 0,
    required this.macroTargets,
  });

  static int _parseInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ??
          double.tryParse(value)?.toInt() ??
          defaultValue;
    }
    return defaultValue;
  }

  factory NutritionPlanDto.fromJson(Map<String, dynamic> json) {
    return NutritionPlanDto(
      id: json['_id']?.toString(),
      date: json['date'] ?? '',
      currentWater: _parseInt(
        json['current_water'] ??
            json['currentWater'] ??
            json['water_intake'] ??
            json['waterIntake'],
        0,
      ),
      targetWater: _parseInt(
        json['water_target'] ??
            json['waterTarget'] ??
            json['target_water'] ??
            json['targetWater'] ??
            json['total_water_target'] ??
            json['totalWaterTarget'] ??
            json['water_target_ml'] ??
            json['waterTargetMl'],
        2000,
      ),
      waterVersion: _parseInt(
        json['water_version'] ?? json['waterVersion'],
        0,
      ),
      totalCaloriesConsumed: (json['total_calories'] as num?)?.toInt() ?? 0,
      totalProteinConsumed: (json['total_protein'] as num?)?.toInt() ?? 0,
      totalCarbsConsumed: (json['total_carbs'] as num?)?.toInt() ?? 0,
      totalFatConsumed: (json['total_fat'] as num?)?.toInt() ?? 0,
      rolloverCalories: (json['rollover_calories'] as num?)?.toInt() ?? 0,
      macroTargets: MacroTargetsDto.fromJson(
        Map<String, dynamic>.from((json['macro_targets'] ?? {}) as Map),
      ),
      meals: (json['meals'] as List<dynamic>?)
              ?.map((e) => MealDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) =>
                  NutritionLogEntryDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      supplements: (json['supplements'] as List<dynamic>?)
              ?.map((e) => SupplementDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  NutritionPlan toEntity() {
    return NutritionPlan(
      id: id,
      date: date,
      meals: meals.map((e) => e.toEntity()).toList(),
      entries: entries.map((e) => e.toEntity()).toList(),
      supplements: supplements.map((e) => e.toEntity()).toList(),
      currentWater: currentWater,
      targetWater: targetWater,
      waterVersion: waterVersion,
      totalCaloriesConsumed: totalCaloriesConsumed,
      totalProteinConsumed: totalProteinConsumed,
      totalCarbsConsumed: totalCarbsConsumed,
      totalFatConsumed: totalFatConsumed,
      rolloverCalories: rolloverCalories,
    );
  }
}

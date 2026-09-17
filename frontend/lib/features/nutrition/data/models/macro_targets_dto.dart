// lib/features/nutrition/data/models/macro_targets_dto.dart
import '../../domain/entities/macro_targets.dart';

class MacroTargetsDto {
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  MacroTargetsDto({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory MacroTargetsDto.fromJson(Map<String, dynamic> json) {
    return MacroTargetsDto(
      calories: (json['calories'] as num?)?.toInt() ?? 2000,
      protein: (json['protein'] as num?)?.toDouble() ?? 50,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 250,
      fat: (json['fat'] as num?)?.toDouble() ?? 65,
    );
  }

  MacroTargets toEntity() {
    return MacroTargets(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );
  }
}

// lib/features/nutrition/domain/entities/macro_targets.dart
import 'package:equatable/equatable.dart';

class MacroTargets extends Equatable {
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  const MacroTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  @override
  List<Object?> get props => [calories, protein, carbs, fat];

  static const defaultTargets = MacroTargets(
    calories: 2000,
    protein: 50.0,
    carbs: 250.0,
    fat: 65.0,
  );
}

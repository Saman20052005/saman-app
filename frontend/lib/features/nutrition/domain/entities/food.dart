// lib/features/nutrition/domain/entities/food.dart
import 'package:equatable/equatable.dart';

class Food extends Equatable {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final List<String> tags;

  const Food({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.tags,
  });

  @override
  List<Object?> get props => [id, name, calories, protein, carbs, fat, tags];
}

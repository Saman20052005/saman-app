// lib/features/nutrition/data/models/food_dto.dart
import '../../domain/entities/food.dart';

class FoodDto {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final List<String> tags;

  FoodDto({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.tags,
  });

  factory FoodDto.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is int) return val.toDouble();
      if (val is double) return val;
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    return FoodDto(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
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

  Food toEntity() {
    return Food(
      id: id,
      name: name,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      tags: tags,
    );
  }
}

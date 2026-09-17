// lib/models/meal_log.dart
import 'package:equatable/equatable.dart';

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack;

  static MealType fromString(String value) {
    return MealType.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => MealType.snack,
    );
  }

  String get displayName {
    switch (this) {
      case MealType.breakfast:
        return 'Bữa Sáng';
      case MealType.lunch:
        return 'Bữa Trưa';
      case MealType.dinner:
        return 'Bữa Tối';
      case MealType.snack:
        return 'Ăn Nhẹ';
    }
  }
}

class MealLog extends Equatable {
  final String id;
  final String foodName;
  final MealType mealType;
  final DateTime loggedAt;
  final String? imageUrl;
  final String? note;

  const MealLog({
    required this.id,
    required this.foodName,
    required this.mealType,
    required this.loggedAt,
    this.imageUrl,
    this.note,
  });

  @override
  List<Object?> get props => [id, foodName, mealType, loggedAt, imageUrl, note];
}

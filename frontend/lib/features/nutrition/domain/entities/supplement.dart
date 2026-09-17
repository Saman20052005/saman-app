// lib/features/nutrition/domain/entities/supplement.dart
import 'package:equatable/equatable.dart';

class Supplement extends Equatable {
  final String? id;
  final String name;
  final double amount;
  final String unit;
  final String time;

  const Supplement({
    this.id,
    required this.name,
    required this.amount,
    required this.unit,
    required this.time,
  });

  @override
  List<Object?> get props => [id, name, amount, unit, time];
}

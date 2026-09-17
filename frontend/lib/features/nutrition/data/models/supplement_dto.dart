// lib/features/nutrition/data/models/supplement_dto.dart
import '../../../../models/nutrition_model.dart';

class SupplementDto {
  final String? id;
  final String name;
  final double amount;
  final String unit;
  final String time;

  SupplementDto({
    this.id,
    required this.name,
    required this.amount,
    required this.unit,
    required this.time,
  });

  factory SupplementDto.fromJson(Map<String, dynamic> json) {
    return SupplementDto(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] ?? 'viên',
      time: json['time'] ?? '',
    );
  }

  Supplement toEntity() {
    return Supplement(
      id: id,
      name: name,
      amount: amount,
      unit: unit,
      time: time,
    );
  }
}

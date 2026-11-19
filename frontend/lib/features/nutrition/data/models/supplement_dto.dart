// lib/features/nutrition/data/models/supplement_dto.dart
import '../../../../models/nutrition_model.dart';

class SupplementDto {
  final String? id;
  final String name;
  final double amount;
  final String unit;
  final String time;
  final String? dosage;
  final String? notes;
  final String? date;

  SupplementDto({
    this.id,
    required this.name,
    required this.amount,
    required this.unit,
    required this.time,
    this.dosage,
    this.notes,
    this.date,
  });

  factory SupplementDto.fromJson(Map<String, dynamic> json) {
    return SupplementDto(
      id: json['id']?.toString(),
      name: (json['name'] ?? json['supplement_name'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 1.0,
      unit: (json['unit'] ?? 'viên').toString(),
      time: (json['time'] ?? json['timing'] ?? '').toString(),
      dosage: json['dosage']?.toString(),
      notes: json['notes']?.toString(),
      date: json['date']?.toString(),
    );
  }

  Supplement toEntity() {
    return Supplement(
      id: id,
      name: name,
      amount: amount,
      unit: unit,
      time: time,
      dosage: dosage,
      notes: notes,
      date: date,
    );
  }
}

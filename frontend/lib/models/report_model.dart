// [File: lib/models/report_model.dart]
class WeeklyReport {
  final List<DailyReportItem> items;

  WeeklyReport({required this.items});

  factory WeeklyReport.fromJson(Map<String, dynamic> json) {
    return WeeklyReport(
      items: (json['report'] as List<dynamic>?)
              ?.map((e) => DailyReportItem.fromJson(e))
              .toList() ??
          [],
    );
  }

  // Helper tính trung bình/tổng cho UI
  int get avgCalories => items.isEmpty
      ? 0
      : (items.fold(0, (sum, item) => sum + item.calories) / items.length)
          .round();
  int get totalWater => items.fold(0, (sum, item) => sum + item.water);
}

class DailyReportItem {
  final String date;
  final int calories;
  final double protein;
  final int water;

  DailyReportItem({
    required this.date,
    required this.calories,
    required this.protein,
    required this.water,
  });

  factory DailyReportItem.fromJson(Map<String, dynamic> json) {
    return DailyReportItem(
      date: json['date'] ?? '',
      // Map đúng tên field trả về từ Backend (app/schemas/nutrition.py)
      calories: json['total_calories'] ?? 0,
      protein: (json['total_protein'] is int)
          ? (json['total_protein'] as int).toDouble()
          : (json['total_protein'] ?? 0.0),
      water: json['current_water'] ?? 0,
    );
  }
}

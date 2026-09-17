// [File: lib/features/report/domain/entities/weekly_report_entity.dart]

class WeeklyReportEntity {
  final List<DailyStats> days;
  final double avgCaloriesIn;
  final double avgCaloriesBurned; // [NEW] Trường mới
  final double avgProtein;

  WeeklyReportEntity({
    required this.days,
    required this.avgCaloriesIn,
    required this.avgCaloriesBurned, // [NEW]
    required this.avgProtein,
  });
}

class DailyStats {
  final DateTime date;
  final double caloriesIn;
  final double caloriesBurned; // [NEW] Trường mới
  final double protein;

  DailyStats({
    required this.date,
    required this.caloriesIn,
    required this.caloriesBurned, // [NEW]
    required this.protein,
  });
}

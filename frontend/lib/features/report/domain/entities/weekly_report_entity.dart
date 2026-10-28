// [File: lib/features/report/domain/entities/weekly_report_entity.dart]

class WorkoutSessionItem {
  final String title;
  final String dayName;
  final DateTime date;
  final int durationMinutes;
  final int caloriesBurned;
  final double? rpe;

  const WorkoutSessionItem({
    required this.title,
    required this.dayName,
    required this.date,
    required this.durationMinutes,
    required this.caloriesBurned,
    this.rpe,
  });
}

class DailyStats {
  final DateTime date;
  final double caloriesIn;
  final double caloriesBurned;
  final double protein;
  final double carbs;
  final double fat;
  final int logCount;
  final bool isRecorded; // Whether nutrition was logged on this day
  final bool hasWorkout;
  final bool isRestDay; // Explicit rest day (0 kcal recorded)
  final int workoutDurationMinutes;
  final String? workoutTitle;
  final double? rpe;
  final int waterMl;

  DailyStats({
    required this.date,
    required this.caloriesIn,
    required this.caloriesBurned,
    required this.protein,
    this.carbs = 0.0,
    this.fat = 0.0,
    this.logCount = 0,
    this.isRecorded = false,
    this.hasWorkout = false,
    this.isRestDay = false,
    this.workoutDurationMinutes = 0,
    this.workoutTitle,
    this.rpe,
    this.waterMl = 0,
  });

  bool get isFuture {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return day.isAfter(today);
  }

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class WeeklyReportEntity {
  final List<DailyStats> days;
  final double avgCaloriesIn;
  final double avgCaloriesBurned;
  final double avgProtein;
  final double avgCarbs;
  final double avgFat;
  final int targetCalories;
  final int targetProtein;
  final int targetCarbs;
  final int targetFat;
  final int targetBurned;
  final int daysLogged; // Number of days nutrition was logged
  final int activeDays; // Number of days workouts were completed
  final double totalCaloriesBurned;
  final List<WorkoutSessionItem> workoutSessions;
  final int avgWaterMl;
  final int targetWaterMl;
  final String? takeaway;

  WeeklyReportEntity({
    required this.days,
    required this.avgCaloriesIn,
    required this.avgCaloriesBurned,
    required this.avgProtein,
    this.avgCarbs = 0.0,
    this.avgFat = 0.0,
    this.targetCalories = 0,
    this.targetProtein = 0,
    this.targetCarbs = 0,
    this.targetFat = 0,
    this.targetBurned = 0,
    this.daysLogged = 0,
    this.activeDays = 0,
    this.totalCaloriesBurned = 0.0,
    this.workoutSessions = const [],
    this.avgWaterMl = 0,
    this.targetWaterMl = 2000,
    this.takeaway,
  });
}

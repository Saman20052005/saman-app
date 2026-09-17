import '../../domain/entities/workout_plan.dart';

abstract class WorkoutRepository {
  Future<List<WorkoutPlan>> getWorkoutPlans();
  Future<List<bool>> getWeeklyStreak();
  Future<void> createWorkoutPlan(WorkoutPlan plan);
  Future<void> deleteWorkoutPlan(String planId);

  // 🔥 FIX: Đổi double -> int để khớp với class Impl
  Future<bool> logWorkout({
    required String planId,
    required int durationSeconds,
    required List<Map<String, dynamic>> exerciseLogs,
    required DateTime startTime,
    required DateTime endTime,
    required int caloriesBurned, // <--- SỬA TẠI ĐÂY
  });
}

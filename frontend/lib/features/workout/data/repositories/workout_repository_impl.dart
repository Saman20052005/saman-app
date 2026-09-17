import 'dart:convert';
import 'dart:developer';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/api_config.dart';
import '../../../../utils/auth_helper.dart';
import '../../../../services/api_client.dart';
import '../../domain/entities/workout_plan.dart';
import '../../domain/repositories/workout_repository.dart';
import '../models/workout_plan_model.dart';

// ✅ [FIX LỖI 3] Định nghĩa Provider tại đây để Controller tìm thấy
final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepositoryImpl();
});

class WorkoutRepositoryImpl implements WorkoutRepository {
  // --- 1. Lấy danh sách bài tập ---
  @override
  Future<List<WorkoutPlan>> getWorkoutPlans() async {
    final token = await AuthHelper.getToken();
    if (token == null) return [];

    try {
      final response = await ApiClient.dio.get(ApiConfig.workoutPlansEndpoint);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final List list = data['plans'] ?? [];
        return list
            .map((e) => WorkoutPlanModel.fromJson(e))
            .toList()
            .cast<WorkoutPlan>();
      }
    } catch (e) {
      log("❌ getWorkoutPlans Error: $e");
      rethrow;
    }
    return [];
  }

  // --- 2. Lấy Streak ---
  @override
  Future<List<bool>> getWeeklyStreak() async {
    final token = await AuthHelper.getToken();
    if (token == null) return List.filled(7, false);

    try {
      final response = await ApiClient.dio.get(ApiConfig.workoutStreakEndpoint);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return List<bool>.from(data['streak_days'] ?? List.filled(7, false));
      }
    } catch (_) {}
    return List.filled(7, false);
  }

  // --- 3. Log Workout ---
  @override
  Future<bool> logWorkout({
    required String planId,
    required int durationSeconds,
    required List<Map<String, dynamic>> exerciseLogs,
    required DateTime startTime,
    required DateTime endTime,
    required int caloriesBurned,
  }) async {
    final token = await AuthHelper.getToken();
    if (token == null) return false;

    final body = {
      "plan_id": planId,
      "start_time": startTime.toIso8601String(),
      "end_time": endTime.toIso8601String(),
      "completed_exercises": exerciseLogs,
      "duration_minutes": (durationSeconds / 60).ceil(),
      "calories_burned": caloriesBurned,
    };

    try {
      final response =
          await ApiClient.dio.post(ApiConfig.logWorkoutEndpoint, data: body);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      log("❌ logWorkout Error: $e");
      return false;
    }
  }

  // --- 4. Create Plan ---
  @override
  Future<void> createWorkoutPlan(WorkoutPlan plan) async {
    final token = await AuthHelper.getToken();
    if (token == null) throw Exception('Unauthorized');

    // Dùng Model để mapping đúng format
    final model = WorkoutPlanModel(
      title: plan.title,
      category: plan.category,
      level: plan.level,
      duration: plan.duration,
      kcal: plan.kcal,
      exercises: plan.exercises
          .map((e) => WorkoutExerciseModel(
                name: e.name,
                reps: e.reps,
                setCount: e.setCount,
              ))
          .toList(),
    );

    try {
      final response = await ApiClient.dio
          .post(ApiConfig.createPlanEndpoint, data: model.toJson());
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(response.data?['detail'] ?? "Failed to create plan");
      }
    } catch (e) {
      log("❌ createWorkoutPlan Error: $e");
      rethrow;
    }
  }

  // --- 5. Delete Plan ---
  @override
  Future<void> deleteWorkoutPlan(String planId) async {
    final token = await AuthHelper.getToken();
    if (token == null) throw Exception('Unauthorized');

    try {
      final response =
          await ApiClient.dio.delete("${ApiConfig.deletePlanEndpoint}/$planId");
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(response.data?['detail'] ?? "Failed to delete plan");
      }
    } catch (e) {
      log("❌ deleteWorkoutPlan Error: $e");
      rethrow;
    }
  }
}

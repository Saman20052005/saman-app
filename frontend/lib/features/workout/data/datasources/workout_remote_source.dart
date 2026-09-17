import 'dart:convert';
import '../../../../config/api_config.dart';
import '../../../../services/api_client.dart';
import '../../../../utils/auth_helper.dart';
import '../models/workout_plan_model.dart';

class WorkoutRemoteDataSource {
  Future<List<WorkoutPlanModel>> fetchPlans() async {
    final token = await AuthHelper.getToken();
    if (token == null) return [];

    final response = await ApiClient.dio.get(ApiConfig.workoutPlansEndpoint);

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final List list = data['plans'] ?? [];
      return list.map((e) => WorkoutPlanModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load plans');
    }
  }

  Future<List<bool>> fetchStreak() async {
    final token = await AuthHelper.getToken();
    if (token == null) return List.filled(7, false);

    try {
      final response = await ApiClient.dio.get(ApiConfig.workoutStreakEndpoint);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return List<bool>.from(data['streak']);
      }
    } catch (_) {}
    return List.filled(7, false);
  }

  Future<void> createPlan(Map<String, dynamic> planJson) async {
    final token = await AuthHelper.getToken();
    if (token == null) throw Exception('Unauthorized');

    try {
      final response = await ApiClient.dio
          .post(ApiConfig.createPlanEndpoint, data: planJson);
      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorMsg = response.data?['detail'] ?? 'Failed to create plan';
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Create Plan Error: $e');
    }
  }

  Future<void> deletePlan(String planId) async {
    final token = await AuthHelper.getToken();
    if (token == null) throw Exception('Unauthorized');

    try {
      final response =
          await ApiClient.dio.delete("${ApiConfig.deletePlanEndpoint}/$planId");
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete plan');
      }
    } catch (e) {
      throw Exception('Delete Plan Error: $e');
    }
  }

  Future<bool> logWorkout(Map<String, dynamic> logJson) async {
    final token = await AuthHelper.getToken();
    if (token == null) return false;

    final response =
        await ApiClient.dio.post(ApiConfig.logWorkoutEndpoint, data: logJson);
    return response.statusCode == 200 || response.statusCode == 201;
  }
}

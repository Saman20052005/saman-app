import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/api_config.dart';
import '../../data/models/muscle_group.dart';
import '../models/exercise.dart';
import '../models/workout_plan.dart';
import 'exercise_repository.dart';

class ExerciseRepositoryImpl implements ExerciseRepository {
  final Dio dio;

  const ExerciseRepositoryImpl({required this.dio});

  @override
  Future<List<MuscleGroup>> getMuscleGroups() async {
    final Response<dynamic> response =
        await dio.get(ApiConfig.muscleGroupsEndpoint);

    final dynamic data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;

    final List<dynamic> raw =
        (data as Map<String, dynamic>)['muscle_groups'] as List<dynamic>;
    return raw
        .map((e) => MuscleGroup.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<Exercise>> getExercisesByMuscleGroup({
    required String muscleGroupSlug,
    String? difficulty,
    String? search,
  }) async {
    final response = await dio.get(
      ApiConfig.exercisesEndpoint,
      queryParameters: {
        'muscle_group': muscleGroupSlug,
        if (difficulty != null && difficulty.isNotEmpty)
          'difficulty': difficulty,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );

    final dynamic data = response.data is Map<String, dynamic>
        ? (response.data as Map<String, dynamic>)['data'] ??
            (response.data as Map<String, dynamic>)['exercises'] ??
            []
        : response.data ?? [];
    final List<dynamic> items = data is List ? data : [];

    return items
        .map((json) => Exercise.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<Exercise>> getPopularExercises({int limit = 6}) async {
    final response = await dio.get(
      ApiConfig.exercisesEndpoint,
      queryParameters: {'limit': limit},
    );
    final List<dynamic> data = response.data['exercises'] ?? [];
    return data
        .map((json) => Exercise.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<WorkoutSession> saveAndReturnWorkoutSession(
      WorkoutSession session) async {
    final payload = session.toJson();
    payload['startedAt'] = session.startedAt.toUtc().toIso8601String();
    if (session.finishedAt != null) {
      payload['finishedAt'] = session.finishedAt!.toUtc().toIso8601String();
    }

    final response = await dio.post(
      ApiConfig.saveSessionEndpoint,
      data: payload,
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('Lưu session thất bại: status $status');
    }

    final dynamic resData = response.data;
    if (resData is Map<String, dynamic>) {
      final sessionJson = resData['session'];
      if (sessionJson is Map<String, dynamic>) {
        return WorkoutSession.fromJson(sessionJson);
      }
      final returnedId = resData['session_id'] as String?;
      if (returnedId != null && returnedId.isNotEmpty) {
        return session.copyWith(id: returnedId);
      }
    }
    return session;
  }

  @override
  Future<void> saveWorkoutSession(WorkoutSession session) async {
    await saveAndReturnWorkoutSession(session);
  }

  @override
  Future<List<WorkoutSession>> getWorkoutHistory() async {
    final response = await dio.get(ApiConfig.historyEndpoint);
    final dynamic resData = response.data;
    final List<dynamic> items;
    if (resData is Map<String, dynamic>) {
      items = (resData['sessions'] ?? []) as List<dynamic>;
    } else if (resData is List) {
      items = resData;
    } else {
      items = [];
    }
    return items
        .map((json) => WorkoutSession.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<WorkoutPlan>> getMyPlans() async {
    final response = await dio.get(ApiConfig.myPlansEndpoint);
    final List<dynamic> data = response.data['data'] ?? [];
    return data.map((e) => WorkoutPlan.fromJson(e)).toList();
  }

  @override
  Future<void> deletePlan(String planId) async {
    await dio.delete('${ApiConfig.myPlansEndpoint}/$planId');
  }

  @override
  Future<WorkoutPlan> getPlanById(String id) async {
    final response = await dio.get('${ApiConfig.myPlansEndpoint}/$id');
    return WorkoutPlan.fromJson(response.data['data']);
  }

  @override
  Future<Exercise> getExerciseById(String id) async {
    final response = await dio.get('${ApiConfig.exercisesEndpoint}/$id');
    return Exercise.fromJson(response.data['data']);
  }

  @override
  Future<WorkoutSession> getSessionById(String sessionId) async {
    final response =
        await dio.get('${ApiConfig.saveSessionEndpoint}/$sessionId');
    final dynamic resData = response.data;
    final Map<String, dynamic> item;
    if (resData is Map<String, dynamic>) {
      item = (resData['session'] ?? resData) as Map<String, dynamic>;
    } else {
      throw StateError('Phản hồi session detail không hợp lệ');
    }
    return WorkoutSession.fromJson(item);
  }
}

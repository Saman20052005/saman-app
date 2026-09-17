import '../models/muscle_group.dart';
import '../../config/api_config.dart';
import 'package:dio/dio.dart';

class MuscleGroupRepository {
  late final Dio _dio;

  MuscleGroupRepository() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  Future<List<MuscleGroup>> getFeaturedMuscleGroups({int limit = 4}) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.muscleGroupsEndpoint}/featured',
      );

      if (response.statusCode == 200) {
        final List<dynamic> data =
            response.data['muscleGroups'] ?? response.data['data'] ?? [];
        return data.map((json) => MuscleGroup.fromJson(json)).toList();
      }
      throw Exception('Failed to load muscle groups');
    } catch (e) {
      // Return mock data for development
      return _getMockMuscleGroups();
    }
  }

  Future<List<MuscleGroup>> getAllMuscleGroups() async {
    try {
      final response = await _dio.get('/api/muscle-groups');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((json) => MuscleGroup.fromJson(json)).toList();
      }
      throw Exception('Failed to load muscle groups');
    } catch (e) {
      // Return mock data for development
      return _getMockMuscleGroups();
    }
  }

  Future<MuscleGroup> getMuscleGroupBySlug(String slug) async {
    try {
      final response = await _dio.get('/api/muscle-groups/$slug');

      if (response.statusCode == 200) {
        return MuscleGroup.fromJson(response.data['data']);
      }
      throw Exception('Failed to load muscle group');
    } catch (e) {
      // Return mock data for development
      final mockGroups = _getMockMuscleGroups();
      return mockGroups.firstWhere(
        (group) => group.slug == slug,
        orElse: () => mockGroups.first,
      );
    }
  }

  List<MuscleGroup> _getMockMuscleGroups() {
    return [
      MuscleGroup(
        id: 1,
        name: 'Chest',
        nameVi: 'Ngực',
        slug: 'chest',
        description: 'Chest muscles and pectorals',
        icon: 'fitness_center',
        color: '#FF6B6B',
        exerciseCount: 45,
      ),
      MuscleGroup(
        id: 2,
        name: 'Back',
        nameVi: 'Lưng',
        slug: 'back',
        description: 'Back muscles and lats',
        icon: 'fitness_center',
        color: '#4ECDC4',
        exerciseCount: 38,
      ),
      MuscleGroup(
        id: 3,
        name: 'Legs',
        nameVi: 'Chân',
        slug: 'legs',
        description: 'Leg muscles and glutes',
        icon: 'fitness_center',
        color: '#45B7D1',
        exerciseCount: 52,
      ),
      MuscleGroup(
        id: 4,
        name: 'Shoulders',
        nameVi: 'Vai',
        slug: 'shoulders',
        description: 'Shoulder muscles and delts',
        icon: 'fitness_center',
        color: '#96CEB4',
        exerciseCount: 28,
      ),
      MuscleGroup(
        id: 5,
        name: 'Arms',
        nameVi: 'Tay',
        slug: 'arms',
        description: 'Biceps and triceps',
        icon: 'fitness_center',
        color: '#FFEAA7',
        exerciseCount: 34,
      ),
      MuscleGroup(
        id: 6,
        name: 'Core',
        nameVi: 'Core',
        slug: 'core',
        description: 'Abs and core muscles',
        icon: 'fitness_center',
        color: '#DDA0DD',
        exerciseCount: 41,
      ),
    ];
  }
}

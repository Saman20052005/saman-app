import '../../../../data/models/exercise.dart';
import '../../../../data/models/muscle_group.dart';
import '../../../../data/models/workout_plan.dart';
import '../../../../data/repositories/exercise_repository.dart';

/// Local demo storage. Lives only as long as its Riverpod container.
class MockExerciseRepository implements ExerciseRepository {
  MockExerciseRepository(this.exercises);

  final List<Exercise> exercises;
  final Map<String, WorkoutSession> _sessions = {};
  final Map<String, WorkoutPlan> _plans = {};
  int _nextPlanId = 0;

  Future<WorkoutPlan> savePlan({
    String? id,
    required String name,
    required List<String> exerciseIds,
  }) async {
    final plan = WorkoutPlan(
      id: id ?? 'demo-plan-${++_nextPlanId}',
      name: name,
      exerciseIds: List.unmodifiable(exerciseIds),
      createdAt: _plans[id]?.createdAt ?? DateTime.now(),
      totalExercises: exerciseIds.length,
    );
    _plans[plan.id] = plan;
    return plan;
  }

  @override
  Future<void> saveWorkoutSession(WorkoutSession session) async {
    _sessions.putIfAbsent(session.id, () => session);
  }

  @override
  Future<List<WorkoutSession>> getWorkoutHistory() async =>
      _sessions.values.toList().reversed.toList();

  @override
  Future<WorkoutSession> getSessionById(String sessionId) async =>
      _sessions[sessionId] ?? (throw StateError('Demo session not found'));

  @override
  Future<List<WorkoutPlan>> getMyPlans() async => _plans.values.toList();

  @override
  Future<WorkoutPlan> getPlanById(String id) async =>
      _plans[id] ?? (throw StateError('Demo plan not found'));

  @override
  Future<void> deletePlan(String planId) async => _plans.remove(planId);

  @override
  Future<Exercise> getExerciseById(String id) async =>
      exercises.firstWhere((exercise) => exercise.id == id);

  @override
  Future<List<Exercise>> getPopularExercises({int limit = 6}) async =>
      exercises.take(limit).toList();

  @override
  Future<List<Exercise>> getExercisesByMuscleGroup({
    required String muscleGroupSlug,
    String? difficulty,
    String? search,
  }) async =>
      exercises
          .where((exercise) =>
              (muscleGroupSlug == 'all' ||
                  exercise.muscleGroup.toLowerCase() ==
                      muscleGroupSlug.toLowerCase()) &&
              (difficulty == null || exercise.difficulty == difficulty) &&
              (search == null ||
                  exercise.name.toLowerCase().contains(search.toLowerCase())))
          .toList();

  @override
  Future<List<MuscleGroup>> getMuscleGroups() async => [];
}

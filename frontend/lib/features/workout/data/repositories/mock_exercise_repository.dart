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
  Future<Map<String, LastExercisePerformance>> getLastPerformances(
    List<String> exerciseIds,
  ) async {
    final requestedIds = exerciseIds.toSet();
    final performances = <String, LastExercisePerformance>{};
    final sessions = _sessions.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    for (final session in sessions) {
      for (final id in requestedIds) {
        if (performances.containsKey(id)) continue;
        final matchingLogs = session.exerciseLogs
            .where((log) => log.exerciseId == id || log.exerciseSlug == id)
            .toList();
        if (matchingLogs.isEmpty) continue;

        final allSetsCompleted = matchingLogs.every((log) => log.isCompleted);
        final candidates = matchingLogs.where((log) => log.isCompleted).toList();
        final selectedLogs = candidates.isEmpty ? matchingLogs : candidates;
        selectedLogs.sort((a, b) {
          final weightComparison = a.weightKg.compareTo(b.weightKg);
          if (weightComparison != 0) return weightComparison;
          final repsComparison = a.repsCompleted.compareTo(b.repsCompleted);
          if (repsComparison != 0) return repsComparison;
          return a.setNumber.compareTo(b.setNumber);
        });
        final bestLog = selectedLogs.last;
        final shouldIncrease = allSetsCompleted && bestLog.repsCompleted >= 8;
        performances[id] = LastExercisePerformance(
          exerciseId: id,
          lastWeightKg: bestLog.weightKg,
          lastReps: bestLog.repsCompleted,
          suggestedWeightKg:
              shouldIncrease ? bestLog.weightKg + 2.5 : bestLog.weightKg,
          suggestedReps: bestLog.repsCompleted,
          suggestionReason: shouldIncrease
              ? 'completed_target_add_weight'
              : 'maintain_current_load',
          lastDate: session.startedAt.toIso8601String().split('T').first,
        );
      }
    }
    return performances;
  }

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

  @override
  Future<List<MuscleRecoveryItem>> getMuscleRecovery() async => const [];
}

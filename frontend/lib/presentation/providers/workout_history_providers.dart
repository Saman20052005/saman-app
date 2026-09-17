import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'exercise_providers.dart';

part 'workout_history_providers.g.dart';

@riverpod
Future<List<WorkoutSession>> workoutHistory(WorkoutHistoryRef ref) async {
  final repo = ref.watch(exerciseRepositoryProvider);
  return repo.getWorkoutHistory();
}

@riverpod
class ActiveSessionSaver extends _$ActiveSessionSaver {
  @override
  AsyncValue<void> build() {
    return const AsyncValue.data(null);
  }

  Future<void> saveCurrentSession({
    required String planName,
    required DateTime startedAt,
    required List<ExerciseSetLog> exerciseLogs,
  }) async {
    state = const AsyncValue.loading();

    try {
      final repo = ref.read(exerciseRepositoryProvider);

      // Calculate total volume
      final totalVolume = exerciseLogs.fold<int>(
        0,
        (sum, log) => sum + (log.repsCompleted * log.weightKg).toInt(),
      );

      // Calculate duration
      final finishedAt = DateTime.now();
      final duration = finishedAt.difference(startedAt).inMinutes;

      final session = WorkoutSession(
        id: '', // Server will generate
        planName: planName,
        startedAt: startedAt,
        finishedAt: finishedAt,
        exerciseLogs: exerciseLogs,
        totalDurationMinutes: duration,
        totalVolumeKg: totalVolume,
      );

      await repo.saveWorkoutSession(session);
      state = const AsyncValue.data(null);

      // Invalidate history to refresh
      ref.invalidate(workoutHistoryProvider);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

@riverpod
class LastWeightProvider extends _$LastWeightProvider {
  @override
  double build(String exerciseId) {
    // TODO: Implement logic to get last weight from history
    // For now, return 0.0 as default
    return 0.0;
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'exercise_providers.dart';
import 'active_workout_providers.dart';

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

  Future<bool> saveCurrentSession() async {
    final active = ref.read(activeWorkoutSessionProvider);
    if (state.isLoading || active.isFinished || active.completedSetsCount == 0) {
      return false;
    }
    final notifier = ref.read(activeWorkoutSessionProvider.notifier);
    final logs = [
      for (final exercise in active.exercises)
        for (final set in exercise.sets.where((set) => set.isCompleted))
          ExerciseSetLog(
            exerciseId: exercise.id,
            exerciseSlug: exercise.slug.isEmpty ? exercise.id : exercise.slug,
            setNumber: set.setNumber,
            repsCompleted: set.reps!,
            weightKg: set.weightKg!,
            isCompleted: true,
          ),
    ];
    final session = WorkoutSession(
      id: notifier.sessionId,
      planName: active.title,
      startedAt: notifier.startedAt,
      finishedAt: DateTime.now(),
      exerciseLogs: logs,
      totalDurationMinutes: active.elapsedSeconds ~/ 60,
      totalVolumeKg: logs.fold<double>(
        0, (sum, log) => sum + log.repsCompleted * log.weightKg,
      ).round(),
    );
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() =>
        ref.read(exerciseRepositoryProvider).saveWorkoutSession(session));
    if (state.hasError) return false;
    notifier.markSaved();
    ref.invalidate(workoutHistoryProvider);
    return true;
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

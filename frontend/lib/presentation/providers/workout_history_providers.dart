import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/exercise_repository_impl.dart';
import '../../services/api_client.dart';
import 'active_workout_providers.dart';

part 'workout_history_providers.g.dart';

/// Represents the active user/account scope for workout data.
/// Updated during auth lifecycle to prevent cross-account data leaks.
final workoutAuthScopeProvider = StateProvider<int>((ref) => 0);

/// API-backed session repository provider for session save, history, and detail
final workoutSessionRepositoryProvider = Provider<ExerciseRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ExerciseRepositoryImpl(dio: dio);
});

@riverpod
Future<List<WorkoutSession>> workoutHistory(WorkoutHistoryRef ref) async {
  ref.watch(workoutAuthScopeProvider);
  final repo = ref.watch(workoutSessionRepositoryProvider);
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
            repsCompleted: set.unit == SetUnit.seconds ? 0 : set.reps!,
            unit: set.unit == SetUnit.seconds ? SetUnit.seconds : null,
            secondsCompleted: set.unit == SetUnit.seconds ? set.seconds : null,
            weightKg: set.weightKg!,
            isCompleted: true,
          ),
    ];
    final session = WorkoutSession(
      id: notifier.sessionId,
      planName: active.title,
      startedAt: notifier.startedAt.toUtc(),
      finishedAt: DateTime.now().toUtc(),
      exerciseLogs: logs,
      totalDurationMinutes: active.elapsedSeconds ~/ 60,
      totalVolumeKg: logs.fold<double>(
        0, (sum, log) => sum + log.volumeKg,
      ).round(),
    );
    state = const AsyncValue.loading();
    final repo = ref.read(workoutSessionRepositoryProvider);
    WorkoutSession? savedSession;
    state = await AsyncValue.guard(() async {
      if (repo is ExerciseRepositoryImpl) {
        savedSession = await repo.saveAndReturnWorkoutSession(session);
      } else {
        await repo.saveWorkoutSession(session);
        savedSession = session;
      }
    });
    if (state.hasError) return false;
    if (savedSession != null) {
      notifier.sessionId = savedSession!.id;
    }
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

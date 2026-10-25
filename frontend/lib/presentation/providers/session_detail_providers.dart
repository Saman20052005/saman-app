import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'workout_history_providers.dart';

part 'session_detail_providers.g.dart';

@riverpod
Future<WorkoutSession> sessionDetail(
    SessionDetailRef ref, String sessionId) async {
  ref.watch(workoutAuthScopeProvider);
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.getSessionById(sessionId);
}

class ExerciseGroupLogs {
  const ExerciseGroupLogs(this.exerciseId, this.sets);
  final String exerciseId;
  final List<ExerciseSetLog> sets;

  Iterable<ExerciseSetLog> get completed =>
      sets.where((set) => set.isCompleted);
  int get completedSetsCount => completed.length;
  int get totalReps => completed
      .where((set) => set.effectiveUnit == SetUnit.reps)
      .fold(0, (sum, set) => sum + set.repsCompleted);
  int get totalTimedSeconds => completed
      .where((set) => set.effectiveUnit == SetUnit.seconds)
      .fold(0, (sum, set) => sum + set.secondsCompleted!);
  double get totalVolumeKg =>
      completed.fold(0, (sum, set) => sum + set.volumeKg);
  bool get hasExternalLoad => completed
      .any((set) => set.effectiveUnit == SetUnit.reps && set.weightKg > 0);
}

class SessionDetailMetrics {
  SessionDetailMetrics.compute(WorkoutSession session)
      : durationSeconds = getSessionDurationSeconds(session) {
    final grouped = <String, List<ExerciseSetLog>>{};
    for (final log in session.exerciseLogs) {
      grouped.putIfAbsent(log.exerciseId, () => []).add(log);
    }
    exerciseGroups = [
      for (final entry in grouped.entries)
        ExerciseGroupLogs(entry.key, entry.value),
    ];
  }

  final int? durationSeconds;
  late final List<ExerciseGroupLogs> exerciseGroups;
  int get completedExercisesCount =>
      exerciseGroups.where((group) => group.completedSetsCount > 0).length;
  int get completedSetsCount =>
      exerciseGroups.fold(0, (sum, group) => sum + group.completedSetsCount);
  int get totalReps =>
      exerciseGroups.fold(0, (sum, group) => sum + group.totalReps);
  int get totalTimedSeconds =>
      exerciseGroups.fold(0, (sum, group) => sum + group.totalTimedSeconds);
  double get totalVolumeKg =>
      exerciseGroups.fold(0, (sum, group) => sum + group.totalVolumeKg);
}

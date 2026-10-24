import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/exercise_repository_impl.dart';
import '../../services/api_client.dart';
import 'active_workout_providers.dart';

import '../../utils/auth_helper.dart';

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
  final isLoggingOut = ref.watch(authLoggingOutProvider);
  if (isLoggingOut) return const [];
  final token = await AuthHelper.getToken();
  if (token == null || token.isEmpty) return const [];
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

/// Calendar values are UTC+7 wall-clock fields, independent of host timezone.
DateTime toVietnamTime(DateTime value) =>
    value.toUtc().add(const Duration(hours: 7));

int? getSessionDurationSeconds(WorkoutSession session) {
  final end = session.finishedAt;
  if (end != null && !end.isBefore(session.startedAt)) {
    return end.difference(session.startedAt).inSeconds;
  }
  return session.totalDurationMinutes == null
      ? null
      : session.totalDurationMinutes! * 60;
}

enum HistoryPeriod { thisWeek, thisMonth, allTime }

class WorkoutHistoryFilterState {
  const WorkoutHistoryFilterState({
    this.period = HistoryPeriod.allTime,
    required this.calendarMonth,
    this.selectedDate,
    this.searchQuery = '',
  });

  final HistoryPeriod period;
  final DateTime calendarMonth;
  final DateTime? selectedDate;
  final String searchQuery;
}

List<WorkoutSession> filterWorkoutHistory(List<WorkoutSession> sessions,
    WorkoutHistoryFilterState filter, DateTime now) {
  final today = toVietnamTime(now);
  final weekStart =
      DateTime.utc(today.year, today.month, today.day - today.weekday + 1);
  final query = filter.searchQuery.trim().toLowerCase();
  final result = sessions.where((session) {
    final date = toVietnamTime(session.startedAt);
    final selected = filter.selectedDate;
    if (selected != null) {
      if (date.year != selected.year ||
          date.month != selected.month ||
          date.day != selected.day) return false;
    } else {
      switch (filter.period) {
        case HistoryPeriod.thisWeek:
          if (date.isBefore(weekStart) ||
              !date.isBefore(weekStart.add(const Duration(days: 7)))) {
            return false;
          }
          break;
        case HistoryPeriod.thisMonth:
          if (date.year != filter.calendarMonth.year ||
              date.month != filter.calendarMonth.month) return false;
          break;
        case HistoryPeriod.allTime:
          break;
      }
    }
    return query.isEmpty ||
        session.planName.toLowerCase().contains(query) ||
        session.exerciseLogs
            .any((log) => log.exerciseSlug.toLowerCase().contains(query));
  }).toList();
  result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return result;
}

class WorkoutHistoryOverviewData {
  WorkoutHistoryOverviewData(List<WorkoutSession> sessions)
      : completedWorkouts = sessions.length,
        totalSets = sessions.fold(
            0,
            (sum, session) =>
                sum +
                session.exerciseLogs.where((log) => log.isCompleted).length),
        totalVolumeKg = sessions.fold(
            0,
            (sum, session) =>
                sum +
                session.exerciseLogs
                    .where((log) => log.isCompleted)
                    .fold<double>(0, (value, log) => value + log.volumeKg)),
        knownDurationSeconds = sessions.fold(0,
            (sum, session) => sum + (getSessionDurationSeconds(session) ?? 0)),
        unknownDurations = sessions
            .where((session) => getSessionDurationSeconds(session) == null)
            .length;

  final int completedWorkouts;
  final int totalSets;
  final double totalVolumeKg;
  final int knownDurationSeconds;
  final int unknownDurations;
}

final filteredWorkoutHistoryProvider = Provider.autoDispose
    .family<AsyncValue<List<WorkoutSession>>, WorkoutHistoryFilterState>(
        (ref, filter) {
  return ref.watch(workoutHistoryProvider).whenData(
      (sessions) => filterWorkoutHistory(sessions, filter, DateTime.now()));
});

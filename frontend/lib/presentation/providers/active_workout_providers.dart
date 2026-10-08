import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import '../../features/workout/domain/entities/workout_plan.dart' as domain;
import 'active_workout_state.dart';

part 'active_workout_providers.g.dart';

// Provider for last weight per exercise
final lastWeightProviderProvider =
    Provider.family<double, String>((ref, exerciseId) {
  return 20.0; // Default 20kg
});

/// Canonical Active Workout Session Provider (Single Source of Truth)
final activeWorkoutSessionProvider =
    StateNotifierProvider<ActiveWorkoutSessionNotifier, ActiveWorkoutSessionState>(
        (ref) {
  return ActiveWorkoutSessionNotifier();
});

class ActiveWorkoutSessionNotifier
    extends StateNotifier<ActiveWorkoutSessionState> {
  ActiveWorkoutSessionNotifier([ActiveWorkoutSessionState? initial])
      : super(initial ?? createDefaultUpperBodySession());

  static int _nextSessionId = 0;
  String sessionId = 'demo-session-${++_nextSessionId}';
  DateTime startedAt = DateTime.now();

  void _beginSession(ActiveWorkoutSessionState session) {
    sessionId = 'demo-session-${++_nextSessionId}';
    startedAt = DateTime.now();
    state = session;
  }

  void startScheduledSession({String title = 'Upper Body Strength'}) {
    _beginSession(createDefaultUpperBodySession().copyWith(title: title));
  }

  void markSaved() {
    state = state.copyWith(isFinished: true, isPaused: true);
  }

  /// Advances live timer and rest interval countdown
  void tick() {
    if (state.isPaused || state.isFinished) return;
    int newElapsed = state.elapsedSeconds + 1;
    bool newIsResting = state.isResting;
    int newRestSeconds = state.restSecondsLeft;
    if (newIsResting) {
      newRestSeconds -= 1;
      if (newRestSeconds <= 0) {
        newIsResting = false;
        newRestSeconds = 0;
      }
    }
    state = state.copyWith(
      elapsedSeconds: newElapsed,
      isResting: newIsResting,
      restSecondsLeft: newRestSeconds,
    );
  }

  void pauseWorkout() {
    state = state.copyWith(isPaused: true);
  }

  void resumeWorkout() {
    state = state.copyWith(isPaused: false);
  }

  void togglePause() {
    state = state.copyWith(isPaused: !state.isPaused);
  }

  void setDraftWeight(double weight) {
    final current = state.currentExercise;
    if (current == null) return;
    _updateCurrentExercise(current.copyWith(
        draftWeightKg: current.unit == SetUnit.seconds ? 0 : weight.clamp(0.0, 500.0)));
  }

  void setDraftReps(int reps) {
    final current = state.currentExercise;
    if (current == null) return;
    _updateCurrentExercise(current.copyWith(draftReps: reps.clamp(1, 999)));
  }

  void setDraftSeconds(int? seconds) {
    final current = state.currentExercise;
    if (current == null || current.unit != SetUnit.seconds) return;
    final valid = seconds != null && seconds >= 1 && seconds <= 999;
    _updateCurrentExercise(current.copyWith(
      draftSeconds: valid ? seconds : null,
      clearDraftSeconds: !valid,
    ));
  }

  void adjustDraftWeight(double delta) {
    final current = state.currentExercise;
    if (current == null) return;
    final newWeight = current.unit == SetUnit.seconds
        ? 0.0 : (current.draftWeightKg + delta).clamp(0.0, 500.0);
    _updateCurrentExercise(current.copyWith(draftWeightKg: newWeight));
  }

  void adjustDraftReps(int delta) {
    final current = state.currentExercise;
    if (current == null) return;
    final newReps = (current.draftReps + delta).clamp(1, 999);
    _updateCurrentExercise(current.copyWith(draftReps: newReps));
  }

  /// Single action contract: Log Set is the ONLY action that records the set
  void logActiveSet() {
    final current = state.currentExercise;
    if (current == null || !current.canLogSet) return;
    final sets = [...current.sets];
    int activeIdx = sets.indexWhere((s) => s.isActive);
    if (activeIdx == -1) {
      activeIdx = sets.indexWhere((s) => !s.isCompleted);
    }
    if (activeIdx == -1) return;

    // Log the active set
    final loggedSet = sets[activeIdx].copyWith(
      isCompleted: true,
      isActive: false,
      weightKg: current.unit == SetUnit.seconds ? 0 : current.draftWeightKg,
      reps: current.unit == SetUnit.seconds ? 0 : current.draftReps,
      seconds: current.unit == SetUnit.seconds ? current.draftSeconds : null,
    );
    sets[activeIdx] = loggedSet;

    // Prime next set
    final nextSetIdx = sets.indexWhere((s) => !s.isCompleted);
    double nextDraftWeight = current.draftWeightKg;
    int nextDraftReps = current.draftReps;
    int? nextDraftSeconds = current.draftSeconds;

    if (nextSetIdx != -1) {
      sets[nextSetIdx] = sets[nextSetIdx].copyWith(isActive: true);
      nextDraftWeight = sets[nextSetIdx].targetWeightKg;
      nextDraftReps = sets[nextSetIdx].targetReps;
      nextDraftSeconds = sets[nextSetIdx].targetSeconds;
    }

    final updatedExercise = current.copyWith(
      sets: sets,
      draftWeightKg: nextDraftWeight,
      draftReps: nextDraftReps,
      draftSeconds: nextDraftSeconds,
    );

    final updatedExercises = [...state.exercises];
    updatedExercises[state.currentExerciseIndex] = updatedExercise;

    state = state.copyWith(
      exercises: updatedExercises,
      isResting: true,
      restSecondsLeft: current.restSeconds,
    );
  }

  void addRestSeconds(int seconds) {
    state = state.copyWith(
      restSecondsLeft: state.restSecondsLeft + seconds,
    );
  }

  void skipRest() {
    state = state.copyWith(
      isResting: false,
      restSecondsLeft: 0,
    );
  }

  void addSet() {
    final current = state.currentExercise;
    if (current == null) return;
    final sets = [...current.sets];
    final newSetNumber = sets.length + 1;
    final hasActive = sets.any((s) => s.isActive);
    final newSet = ActiveWorkoutSetInfo(
      setNumber: newSetNumber,
      targetWeightKg: current.unit == SetUnit.seconds ? 0 : current.draftWeightKg,
      targetReps: current.draftReps,
      unit: current.unit,
      targetSeconds: current.unit == SetUnit.seconds
          ? current.draftSeconds ?? current.sets.firstWhere((set) =>
              set.targetSeconds != null &&
              set.targetSeconds! >= 1 && set.targetSeconds! <= 999).targetSeconds
          : current.draftSeconds,
      isActive: !hasActive && sets.every((s) => s.isCompleted),
    );
    sets.add(newSet);
    _updateCurrentExercise(current.copyWith(sets: sets));
  }

  void nextExercise() {
    if (state.currentExerciseIndex + 1 < state.exercises.length) {
      selectExercise(state.currentExerciseIndex + 1);
    }
  }

  void previousExercise() {
    if (state.currentExerciseIndex > 0) {
      state =
          state.copyWith(currentExerciseIndex: state.currentExerciseIndex - 1);
    }
  }

  void startSessionFromPlan(domain.WorkoutPlan plan) {
    final activeExercises = plan.exercises.asMap().entries.map((entry) {
      final index = entry.key;
      final e = entry.value;
      final setsCount = e.setCount > 0 ? e.setCount : 3;
      final defaultReps = int.tryParse(e.reps.split('-').first) ?? 10;
      final sets = List.generate(
        setsCount,
        (i) => ActiveWorkoutSetInfo(
          setNumber: i + 1,
          targetWeightKg: 20.0,
          targetReps: defaultReps,
          isActive: (index == 0 && i == 0),
        ),
      );
      return ActiveExerciseInfo(
        id: 'plan_ex_$index',
        name: e.name,
        subtitle: '$setsCount sets · ${e.reps} reps',
        imageUrl: '',
        restSeconds: 90,
        sets: sets,
        draftWeightKg: 20.0,
        draftReps: defaultReps,
      );
    }).toList();

    _beginSession(ActiveWorkoutSessionState(
      title: plan.title,
      exercises: activeExercises,
    ));
  }

  void _updateCurrentExercise(ActiveExerciseInfo updated) {
    if (state.currentExerciseIndex >= state.exercises.length) return;
    final updatedList = [...state.exercises];
    updatedList[state.currentExerciseIndex] = updated;
    state = state.copyWith(exercises: updatedList);
  }

  // Compatibility methods for legacy callers
  CurrentSetState get currentSetState {
    final curEx = state.currentExercise;
    return CurrentSetState(
      reps: curEx?.draftReps ?? 8,
      weight: curEx?.draftWeightKg ?? 20.0,
      isResting: state.isResting,
      restSecondsLeft: state.restSecondsLeft,
    );
  }

  void updateReps(int reps) => setDraftReps(reps);
  void updateWeight(double weight) => setDraftWeight(weight);
  void startRest() {
    state = state.copyWith(
      isResting: true,
      restSecondsLeft: state.currentExercise?.restSeconds ?? 90,
    );
  }
  void tickRest() {
    if (state.restSecondsLeft > 0) {
      final next = state.restSecondsLeft - 1;
      state = state.copyWith(
        restSecondsLeft: next,
        isResting: next > 0,
      );
    }
  }
  void completeCurrentSet() => logActiveSet();

  void startSession(List<Exercise> exercises, {String title = 'Workout Session'}) {
    _beginSession(ActiveWorkoutSessionState.fromExercises(exercises, title: title));
  }

  void selectExercise(int index) {
    if (index < 0 || index >= state.exercises.length) return;
    state = state.copyWith(currentExerciseIndex: index,
        isResting: false, restSecondsLeft: 0);
  }
}



/// Compatibility wrapper delegating to canonical session provider
@riverpod
class ActiveWorkoutNotifier extends _$ActiveWorkoutNotifier {
  @override
  ActiveWorkoutState build() {
    return const ActiveWorkoutState(
      exercises: [],
      currentExerciseIndex: 0,
      currentSetIndex: 0,
      completedLogs: [],
    );
  }

  CurrentSetState get currentSetState {
    final session = ref.read(activeWorkoutSessionProvider);
    final curEx = session.currentExercise;
    return CurrentSetState(
      reps: curEx?.draftReps ?? 8,
      weight: curEx?.draftWeightKg ?? 20.0,
      isResting: session.isResting,
      restSecondsLeft: session.restSecondsLeft,
    );
  }

  void updateReps(int reps) =>
      ref.read(activeWorkoutSessionProvider.notifier).setDraftReps(reps);
  void updateWeight(double weight) =>
      ref.read(activeWorkoutSessionProvider.notifier).setDraftWeight(weight);
  void startRest() =>
      ref.read(activeWorkoutSessionProvider.notifier).startRest();
  void tickRest() =>
      ref.read(activeWorkoutSessionProvider.notifier).tickRest();
  void completeCurrentSet() =>
      ref.read(activeWorkoutSessionProvider.notifier).logActiveSet();
  void skipRest() =>
      ref.read(activeWorkoutSessionProvider.notifier).skipRest();
  void startSession(List<Exercise> exercises) =>
      ref.read(activeWorkoutSessionProvider.notifier).startSession(exercises);
}

import 'dart:math';

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
final activeWorkoutSessionProvider = StateNotifierProvider<
    ActiveWorkoutSessionNotifier, ActiveWorkoutSessionState>((ref) {
  return ActiveWorkoutSessionNotifier();
});

class ActiveWorkoutSessionNotifier
    extends StateNotifier<ActiveWorkoutSessionState> {
  ActiveWorkoutSessionNotifier([ActiveWorkoutSessionState? initial])
      : super(initial ?? createDefaultUpperBodySession());

  static final Random _idRandom = Random.secure();
  int _supersetCounter = 0;

  String _nextSupersetGroupId() => 'ss_${++_supersetCounter}';

  /// 128-bit random client identity (`ws-<32 hex>`), unique across reloads.
  static String _newSessionId() {
    final buffer = StringBuffer('ws-');
    for (var i = 0; i < 16; i++) {
      buffer.write(_idRandom.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String sessionId = _newSessionId();
  DateTime startedAt = DateTime.now();

  /// Payload of the last unconfirmed Save, reused verbatim by Retry.
  WorkoutSession? pendingSaveSnapshot;

  /// Returns true when a Save request has started and is awaiting confirmation.
  bool get isSavePendingConfirmation => pendingSaveSnapshot != null;

  void clearPendingSave() {
    pendingSaveSnapshot = null;
  }

  void _beginSession(ActiveWorkoutSessionState session) {
    sessionId = _newSessionId();
    startedAt = DateTime.now();
    pendingSaveSnapshot = null;
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
    final newElapsed = state.elapsedSeconds + 1;
    bool newIsResting = state.isResting;
    int newRestSeconds = state.restSecondsLeft;
    int newRestFinishedCount = state.restFinishedCount;
    if (newIsResting) {
      newRestSeconds -= 1;
      if (newRestSeconds <= 0) {
        newIsResting = false;
        newRestSeconds = 0;
        newRestFinishedCount += 1;
      }
    }
    state = state.copyWith(
      elapsedSeconds: newElapsed,
      isResting: newIsResting,
      restSecondsLeft: newRestSeconds,
      restFinishedCount: newRestFinishedCount,
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
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null) return;
    _updateCurrentExercise(current.copyWith(
      draftWeightKg:
          current.unit == SetUnit.seconds ? 0 : weight.clamp(0.0, 500.0),
    ));
  }

  void setDraftReps(int reps) {
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null) return;
    _updateCurrentExercise(current.copyWith(draftReps: reps.clamp(1, 999)));
  }

  void setDraftSeconds(int? seconds) {
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null || current.unit != SetUnit.seconds) return;
    final valid = seconds != null && seconds >= 1 && seconds <= 999;
    _updateCurrentExercise(current.copyWith(
      draftSeconds: valid ? seconds : null,
      clearDraftSeconds: !valid,
    ));
  }

  void adjustDraftWeight(double delta) {
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null) return;
    final newWeight = current.unit == SetUnit.seconds
        ? 0.0
        : (current.draftWeightKg + delta).clamp(0.0, 500.0);
    _updateCurrentExercise(current.copyWith(draftWeightKg: newWeight));
  }

  void adjustDraftReps(int delta) {
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null) return;
    final newReps = (current.draftReps + delta).clamp(1, 999);
    _updateCurrentExercise(current.copyWith(draftReps: newReps));
  }

  static double _epley1Rm(double weightKg, int reps) {
    if (weightKg <= 0 || reps <= 0) return 0.0;
    return weightKg * (1.0 + reps / 30.0);
  }

  static List<ActiveWorkoutSetInfo> _recomputeExercisePrFlags(
    ActiveExerciseInfo exercise,
    List<ActiveWorkoutSetInfo> sets,
  ) {
    if (exercise.unit != SetUnit.reps) {
      return sets
          .map((s) => s.isPr ? s.copyWith(isPr: false) : s)
          .toList();
    }

    const eps = 1e-9;
    var hasBaseline = false;
    var maxWeight = 0.0;
    var max1Rm = 0.0;

    final perf = exercise.lastPerformance;
    if (perf != null && perf.lastWeightKg > 0) {
      hasBaseline = true;
      maxWeight = perf.lastWeightKg;
      if (perf.lastReps > 0) {
        max1Rm = _epley1Rm(perf.lastWeightKg, perf.lastReps);
      }
    }

    final result = <ActiveWorkoutSetInfo>[];
    for (final s in sets) {
      if (!s.isCompleted || s.setType == SetType.warmup) {
        result.add(s.isPr ? s.copyWith(isPr: false) : s);
        continue;
      }
      final w = s.weightKg ?? 0.0;
      final r = s.reps ?? 0;
      if (w <= 0 || r <= 0) {
        result.add(s.isPr ? s.copyWith(isPr: false) : s);
        continue;
      }
      final est = _epley1Rm(w, r);
      final isPr = hasBaseline && (w > maxWeight + eps || est > max1Rm + eps);
      result.add(s.isPr == isPr ? s : s.copyWith(isPr: isPr));
      hasBaseline = true;
      if (w > maxWeight) maxWeight = w;
      if (est > max1Rm) max1Rm = est;
    }
    return result;
  }

  void setSetType(int exIdx, int setIdx, SetType type) {
    if (isSavePendingConfirmation) return;
    if (exIdx < 0 || exIdx >= state.exercises.length) return;
    final exercise = state.exercises[exIdx];
    if (setIdx < 0 || setIdx >= exercise.sets.length) return;

    final sets = [...exercise.sets];
    sets[setIdx] = sets[setIdx].copyWith(setType: type);
    final recomputed = _recomputeExercisePrFlags(exercise, sets);

    final updatedExercises = [...state.exercises];
    updatedExercises[exIdx] = exercise.copyWith(sets: recomputed);
    state = state.copyWith(exercises: updatedExercises);
  }

  void setSetRpe(int exIdx, int setIdx, double? rpe) {
    if (isSavePendingConfirmation) return;
    if (exIdx < 0 || exIdx >= state.exercises.length) return;
    final exercise = state.exercises[exIdx];
    if (setIdx < 0 || setIdx >= exercise.sets.length) return;

    final sets = [...exercise.sets];
    sets[setIdx] = rpe == null
        ? sets[setIdx].copyWith(clearRpe: true)
        : sets[setIdx].copyWith(rpe: rpe.clamp(1.0, 10.0));

    final updatedExercises = [...state.exercises];
    updatedExercises[exIdx] = exercise.copyWith(sets: sets);
    state = state.copyWith(exercises: updatedExercises);
  }

  void setExerciseNote(int exIdx, String note) {
    if (isSavePendingConfirmation) return;
    if (exIdx < 0 || exIdx >= state.exercises.length) return;
    final exercise = state.exercises[exIdx];
    final normalized = note.trim().isEmpty ? '' : note;
    final updatedExercises = [...state.exercises];
    updatedExercises[exIdx] = exercise.copyWith(note: normalized);
    state = state.copyWith(exercises: updatedExercises);
  }

  void updateCompletedSet({
    int? exerciseIndex,
    required int setIndex,
    double? weightKg,
    int? reps,
    int? seconds,
    double? rpe,
    SetType? setType,
  }) {
    if (isSavePendingConfirmation) return;
    final exIdx = exerciseIndex ?? state.currentExerciseIndex;
    if (exIdx < 0 || exIdx >= state.exercises.length) return;
    final exercise = state.exercises[exIdx];
    if (setIndex < 0 || setIndex >= exercise.sets.length) return;
    final existing = exercise.sets[setIndex];
    if (!existing.isCompleted) return;

    final updatedWeight = exercise.unit == SetUnit.seconds
        ? 0.0
        : (weightKg ?? existing.weightKg ?? existing.targetWeightKg)
            .clamp(0.0, 500.0);
    final updatedReps = exercise.unit == SetUnit.seconds
        ? 0
        : (reps ?? existing.reps ?? existing.targetReps).clamp(1, 999);
    final updatedSeconds = exercise.unit == SetUnit.seconds
        ? (seconds ?? existing.seconds)
        : existing.seconds;

    final sets = [...exercise.sets];
    sets[setIndex] = existing.copyWith(
      weightKg: updatedWeight,
      reps: updatedReps,
      seconds: updatedSeconds,
      rpe: rpe?.clamp(1.0, 10.0),
      clearRpe: rpe == null,
      setType: setType ?? existing.setType,
    );

    final recomputed = _recomputeExercisePrFlags(exercise, sets);
    final updatedExercises = [...state.exercises];
    updatedExercises[exIdx] = exercise.copyWith(sets: recomputed);
    state = state.copyWith(exercises: updatedExercises);
  }

  List<ActiveExerciseInfo> _clearSingletonSupersets(
    List<ActiveExerciseInfo> exercises,
  ) {
    final counts = <String, int>{};
    for (final ex in exercises) {
      final gid = ex.supersetGroupId;
      if (gid != null && gid.isNotEmpty) {
        counts[gid] = (counts[gid] ?? 0) + 1;
      }
    }
    return exercises.map((ex) {
      final gid = ex.supersetGroupId;
      if (gid != null && gid.isNotEmpty && (counts[gid] ?? 0) < 2) {
        return ex.copyWith(clearSupersetGroup: true);
      }
      return ex;
    }).toList();
  }

  void toggleSupersetWithNext(int exIdx) {
    if (isSavePendingConfirmation) return;
    if (exIdx < 0 || exIdx + 1 >= state.exercises.length) return;

    final updated = [...state.exercises];
    final current = updated[exIdx];
    final next = updated[exIdx + 1];

    final currentGroup = current.supersetGroupId;
    final nextGroup = next.supersetGroupId;
    final alreadyLinked = currentGroup != null &&
        currentGroup.isNotEmpty &&
        currentGroup == nextGroup;

    if (alreadyLinked) {
      final prevSame =
          exIdx > 0 && updated[exIdx - 1].supersetGroupId == currentGroup;
      final nextSame = exIdx + 2 < updated.length &&
          updated[exIdx + 2].supersetGroupId == currentGroup;

      if (prevSame && nextSame) {
        final splitGroupId = _nextSupersetGroupId();
        for (var i = exIdx + 1; i < updated.length; i++) {
          if (updated[i].supersetGroupId == currentGroup) {
            updated[i] = updated[i].copyWith(supersetGroupId: splitGroupId);
          }
        }
      } else if (prevSame) {
        updated[exIdx + 1] = next.copyWith(clearSupersetGroup: true);
      } else if (nextSame) {
        updated[exIdx] = current.copyWith(clearSupersetGroup: true);
      } else {
        updated[exIdx] = current.copyWith(clearSupersetGroup: true);
        updated[exIdx + 1] = next.copyWith(clearSupersetGroup: true);
      }
    } else {
      final groupId = (currentGroup != null && currentGroup.isNotEmpty)
          ? currentGroup
          : ((nextGroup != null && nextGroup.isNotEmpty)
              ? nextGroup
              : _nextSupersetGroupId());
      updated[exIdx] = current.copyWith(supersetGroupId: groupId);
      updated[exIdx + 1] = next.copyWith(supersetGroupId: groupId);
    }

    state = state.copyWith(exercises: _clearSingletonSupersets(updated));
  }

  void reorderExercises(int oldIndex, int newIndex) {
    if (isSavePendingConfirmation) return;
    if (oldIndex < 0 || oldIndex >= state.exercises.length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 ||
        newIndex >= state.exercises.length ||
        oldIndex == newIndex) {
      return;
    }

    final updated = [...state.exercises];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);

    final oldCurrent = state.currentExerciseIndex;
    int nextCurrent = oldCurrent;
    if (oldCurrent == oldIndex) {
      nextCurrent = newIndex;
    } else if (oldIndex < oldCurrent && newIndex >= oldCurrent) {
      nextCurrent = oldCurrent - 1;
    } else if (oldIndex > oldCurrent && newIndex <= oldCurrent) {
      nextCurrent = oldCurrent + 1;
    }

    state = state.copyWith(
      exercises: updated,
      currentExerciseIndex: nextCurrent,
    );
  }

  /// Single action contract: Log Set is the ONLY action that records the set
  void logActiveSet() {
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null || !current.canLogSet) return;
    final sets = [...current.sets];
    int activeIdx = sets.indexWhere((s) => s.isActive);
    if (activeIdx == -1) {
      activeIdx = sets.indexWhere((s) => !s.isCompleted);
    }
    if (activeIdx == -1) return;

    final loggedWeight =
        current.unit == SetUnit.seconds ? 0.0 : current.draftWeightKg;
    final loggedReps =
        current.unit == SetUnit.seconds ? 0 : current.draftReps;
    final activeSetType = sets[activeIdx].setType;

    // Local PR check against lastPerformance and prior completed sets in this exercise
    var isPr = false;
    if (current.unit == SetUnit.reps &&
        loggedWeight > 0 &&
        loggedReps > 0 &&
        activeSetType != SetType.warmup) {
      var hasBaseline = false;
      var maxWeight = 0.0;
      var max1Rm = 0.0;

      final perf = current.lastPerformance;
      if (perf != null && perf.lastWeightKg > 0) {
        hasBaseline = true;
        maxWeight = perf.lastWeightKg;
        if (perf.lastReps > 0) {
          max1Rm = _epley1Rm(perf.lastWeightKg, perf.lastReps);
        }
      }

      for (var i = 0; i < sets.length; i++) {
        if (i == activeIdx) continue;
        final prev = sets[i];
        if (!prev.isCompleted || prev.setType == SetType.warmup) continue;
        final pw = prev.weightKg ?? 0.0;
        final pr = prev.reps ?? 0;
        if (pw <= 0 || pr <= 0) continue;
        hasBaseline = true;
        if (pw > maxWeight) maxWeight = pw;
        final p1Rm = _epley1Rm(pw, pr);
        if (p1Rm > max1Rm) max1Rm = p1Rm;
      }

      if (hasBaseline) {
        const eps = 1e-9;
        final current1Rm = _epley1Rm(loggedWeight, loggedReps);
        isPr = loggedWeight > maxWeight + eps || current1Rm > max1Rm + eps;
      }
    }

    // Log the active set
    final loggedSet = sets[activeIdx].copyWith(
      isCompleted: true,
      isActive: false,
      weightKg: loggedWeight,
      reps: loggedReps,
      seconds: current.unit == SetUnit.seconds ? current.draftSeconds : null,
      isPr: isPr,
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

    final exIdx = state.currentExerciseIndex;
    final updatedExercises = [...state.exercises];
    updatedExercises[exIdx] = updatedExercise;

    // Superset A1 -> A2 transition: skip rest and jump to next exercise if paired and incomplete
    final hasNext = exIdx + 1 < updatedExercises.length;
    final currentSuperset = current.supersetGroupId;
    if (hasNext &&
        currentSuperset != null &&
        currentSuperset.isNotEmpty &&
        updatedExercises[exIdx + 1].supersetGroupId == currentSuperset) {
      final partner = updatedExercises[exIdx + 1];
      final partnerNextSetIdx = partner.sets.indexWhere((s) => !s.isCompleted);
      if (partnerNextSetIdx != -1) {
        if (!partner.sets.any((s) => s.isActive)) {
          final partnerSets = [...partner.sets];
          partnerSets[partnerNextSetIdx] =
              partnerSets[partnerNextSetIdx].copyWith(isActive: true);
          updatedExercises[exIdx + 1] = partner.copyWith(sets: partnerSets);
        }
        state = state.copyWith(
          exercises: updatedExercises,
          currentExerciseIndex: exIdx + 1,
          isResting: false,
          restSecondsLeft: 0,
        );
        return;
      }
    }

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
    if (isSavePendingConfirmation) return;
    final current = state.currentExercise;
    if (current == null) return;
    final sets = [...current.sets];
    final newSetNumber = sets.length + 1;
    final hasActive = sets.any((s) => s.isActive);
    final newSet = ActiveWorkoutSetInfo(
      setNumber: newSetNumber,
      targetWeightKg:
          current.unit == SetUnit.seconds ? 0 : current.draftWeightKg,
      targetReps: current.draftReps,
      unit: current.unit,
      targetSeconds: current.unit == SetUnit.seconds
          ? current.draftSeconds ??
              current.sets
                  .firstWhere((set) =>
                      set.targetSeconds != null &&
                      set.targetSeconds! >= 1 &&
                      set.targetSeconds! <= 999)
                  .targetSeconds
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
      state = state.copyWith(
          currentExerciseIndex: state.currentExerciseIndex - 1);
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

  void startSession(List<Exercise> exercises,
      {String title = 'Workout Session'}) {
    _beginSession(
        ActiveWorkoutSessionState.fromExercises(exercises, title: title));
  }

  void selectExercise(int index) {
    if (index < 0 || index >= state.exercises.length) return;
    state = state.copyWith(
        currentExerciseIndex: index, isResting: false, restSecondsLeft: 0);
  }

  void attachCvFormSummary(
    String exerciseId,
    Map<String, dynamic> summary, {
    List<Map<String, dynamic>>? repTimeline,
    String? videoStoryId,
  }) {
    final updatedExercises = state.exercises.map((e) {
      if (e.id == exerciseId || (e.slug.isNotEmpty && e.slug == exerciseId)) {
        return e.copyWith(
          cvFormSummary: Map<String, dynamic>.from(summary),
          repTimeline: repTimeline == null
              ? e.repTimeline
              : repTimeline
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(growable: false),
          videoStoryId: videoStoryId ?? e.videoStoryId,
        );
      }
      return e;
    }).toList();
    state = state.copyWith(exercises: updatedExercises);
  }

  void applyLastPerformanceHints(Map<String, LastExercisePerformance> hints) {
    if (hints.isEmpty) return;
    final updatedExercises = state.exercises.map((e) {
      final hint = hints[e.id] ?? (e.slug.isNotEmpty ? hints[e.slug] : null);
      if (hint == null) return e;
      if (e.completedSetsCount == 0 &&
          e.unit == SetUnit.reps &&
          hint.suggestedReps > 0) {
        final suggestedWeight = hint.suggestedWeightKg.clamp(0.0, 500.0);
        final suggestedReps = hint.suggestedReps.clamp(1, 999);
        final updatedSets = e.sets
            .map(
              (s) => s.isCompleted
                  ? s
                  : s.copyWith(
                      targetWeightKg: suggestedWeight,
                      targetReps: suggestedReps,
                    ),
            )
            .toList();
        return e.copyWith(
          lastPerformance: hint,
          draftWeightKg: suggestedWeight,
          draftReps: suggestedReps,
          sets: updatedSets,
        );
      }
      return e.copyWith(lastPerformance: hint);
    }).toList();
    state = state.copyWith(exercises: updatedExercises);
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

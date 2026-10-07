import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/exercise.dart';

part 'active_workout_state.freezed.dart';

// --- State cho toàn bộ session ---
@freezed
class ActiveWorkoutState with _$ActiveWorkoutState {
  const factory ActiveWorkoutState({
    required List<Exercise> exercises,
    required int currentExerciseIndex,
    required int currentSetIndex,
    required List<ExerciseSetLog> completedLogs,
    @Default(false) bool isFinished,
  }) = _ActiveWorkoutState;

  factory ActiveWorkoutState.fromExercises(List<Exercise> exercises) {
    return ActiveWorkoutState(
      exercises: exercises,
      currentExerciseIndex: 0,
      currentSetIndex: 0,
      completedLogs: const [],
    );
  }

  const ActiveWorkoutState._(); // <- thêm dòng này

  Exercise? get currentExercise =>
      exercises.isNotEmpty ? exercises[currentExerciseIndex] : null;
  int get currentSetNumber => currentSetIndex + 1;
}

// --- State cho set đang thực hiện (riêng để dễ quản lý timer) ---
@freezed
class CurrentSetState with _$CurrentSetState {
  const factory CurrentSetState({
    required int reps,
    required double weight,
    @Default(false) bool isResting,
    @Default(0) int restSecondsLeft,
  }) = _CurrentSetState;
}

/// Detailed set info distinguishing planned targets from logged results
class ActiveWorkoutSetInfo {
  final int setNumber;
  final double targetWeightKg;
  final int targetReps;
  final double? weightKg;
  final int? reps;
  final bool isCompleted;
  final bool isActive;

  const ActiveWorkoutSetInfo({
    required this.setNumber,
    required this.targetWeightKg,
    required this.targetReps,
    this.weightKg,
    this.reps,
    this.isCompleted = false,
    this.isActive = false,
  });

  ActiveWorkoutSetInfo copyWith({
    int? setNumber,
    double? targetWeightKg,
    int? targetReps,
    double? weightKg,
    int? reps,
    bool? isCompleted,
    bool? isActive,
  }) {
    return ActiveWorkoutSetInfo(
      setNumber: setNumber ?? this.setNumber,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      targetReps: targetReps ?? this.targetReps,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      isCompleted: isCompleted ?? this.isCompleted,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Active exercise state tracking sets, active set index, and draft input values
class ActiveExerciseInfo {
  final String id;
  final String slug;
  final String name;
  final String subtitle;
  final String imageUrl;
  final int restSeconds;
  final List<ActiveWorkoutSetInfo> sets;
  final double draftWeightKg;
  final int draftReps;

  const ActiveExerciseInfo({
    required this.id,
    this.slug = '',
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    this.restSeconds = 90,
    required this.sets,
    required this.draftWeightKg,
    required this.draftReps,
  });

  int get completedSetsCount => sets.where((s) => s.isCompleted).length;
  int get totalSetsCount => sets.length;

  ActiveWorkoutSetInfo? get activeSet {
    final active = sets.where((s) => s.isActive);
    if (active.isNotEmpty) return active.first;
    final uncompleted = sets.where((s) => !s.isCompleted);
    if (uncompleted.isNotEmpty) return uncompleted.first;
    return null;
  }

  ActiveExerciseInfo copyWith({
    String? id,
    String? name,
    String? subtitle,
    String? imageUrl,
    int? restSeconds,
    List<ActiveWorkoutSetInfo>? sets,
    double? draftWeightKg,
    int? draftReps,
  }) {
    return ActiveExerciseInfo(
      id: id ?? this.id,
      slug: slug,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      restSeconds: restSeconds ?? this.restSeconds,
      sets: sets ?? this.sets,
      draftWeightKg: draftWeightKg ?? this.draftWeightKg,
      draftReps: draftReps ?? this.draftReps,
    );
  }
}

/// Active workout session model tracking live timer, pauses, rest, and exercise list
class ActiveWorkoutSessionState {
  final String title;
  final List<ActiveExerciseInfo> exercises;
  final int currentExerciseIndex;
  final int elapsedSeconds;
  final bool isPaused;
  final bool isResting;
  final int restSecondsLeft;
  final bool isFinished;

  const ActiveWorkoutSessionState({
    required this.title,
    required this.exercises,
    this.currentExerciseIndex = 0,
    this.elapsedSeconds = 0,
    this.isPaused = false,
    this.isResting = false,
    this.restSecondsLeft = 0,
    this.isFinished = false,
  });

  factory ActiveWorkoutSessionState.fromExercises(List<Exercise> exercises, {String title = 'Workout Session'}) {
    final activeExercises = exercises.asMap().entries.map((entry) {
      final index = entry.key;
      final ex = entry.value;
      final setsCount = ex.defaultSets > 0 ? ex.defaultSets : 3;
      final defaultReps = int.tryParse(ex.defaultReps.split('-').first) ?? 10;
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
        id: ex.id,
        slug: ex.slug,
        name: ex.name,
        subtitle: '${ex.equipment.isNotEmpty ? ex.equipment.first : "Free Weight"} · ${ex.muscleGroup}',
        imageUrl: ex.thumbnailUrl,
        restSeconds: ex.restSeconds > 0 ? ex.restSeconds : 90,
        sets: sets,
        draftWeightKg: 20.0,
        draftReps: defaultReps,
      );
    }).toList();

    return ActiveWorkoutSessionState(
      title: title,
      exercises: activeExercises,
    );
  }

  ActiveExerciseInfo? get currentExercise =>
      exercises.isNotEmpty && currentExerciseIndex < exercises.length
          ? exercises[currentExerciseIndex]
          : null;

  int get exerciseCount => exercises.length;
  int get currentExerciseNumber => currentExerciseIndex + 1;

  ActiveExerciseInfo? get nextExercise =>
      currentExerciseIndex + 1 < exercises.length
          ? exercises[currentExerciseIndex + 1]
          : null;

  int get totalSetsCount =>
      exercises.fold(0, (sum, e) => sum + e.totalSetsCount);
  int get completedSetsCount =>
      exercises.fold(0, (sum, e) => sum + e.completedSetsCount);

  ActiveWorkoutSessionState copyWith({
    String? title,
    List<ActiveExerciseInfo>? exercises,
    int? currentExerciseIndex,
    int? elapsedSeconds,
    bool? isPaused,
    bool? isResting,
    int? restSecondsLeft,
    bool? isFinished,
  }) {
    return ActiveWorkoutSessionState(
      title: title ?? this.title,
      exercises: exercises ?? this.exercises,
      currentExerciseIndex:
          currentExerciseIndex ?? this.currentExerciseIndex,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isPaused: isPaused ?? this.isPaused,
      isResting: isResting ?? this.isResting,
      restSecondsLeft: restSecondsLeft ?? this.restSecondsLeft,
      isFinished: isFinished ?? this.isFinished,
    );
  }
}

ActiveWorkoutSessionState createDefaultUpperBodySession() {
  return ActiveWorkoutSessionState(
    title: 'Upper Body Strength',
    exercises: [
      const ActiveExerciseInfo(
        id: 'ex_1',
        name: 'Dumbbell Bench Press',
        subtitle: 'Dumbbells · Flat bench',
        imageUrl:
            'https://lh3.googleusercontent.com/aida/AEtjO1XP4OGkrhkIOmOe0kvUvz55YkpHdPsvSaUU_OORjSWf_tiioZ-TCBYTJrB4GgWxlodGaMYLG4JcwLTZZn0rzDcbuMsqbBiYO_T1SxfA_eUBR5MB3njntef3lL7yE1f8fCxdqvv_JOLmH-WAF2EqGiHyUVtAxZrR-E_7mPmS7qEFSFUOsm-qMi8QM6tmj8I0fIb-8aHQt9GlrlYb0A0DOor8AUO_X8LlHfonLV7HHtF6FNk8BUu66V2yckM',
        restSeconds: 90,
        draftWeightKg: 26.0,
        draftReps: 8,
        sets: const [
          ActiveWorkoutSetInfo(
            setNumber: 1,
            targetWeightKg: 26.0,
            targetReps: 8,
            isActive: true,
          ),
          ActiveWorkoutSetInfo(
            setNumber: 2,
            targetWeightKg: 26.0,
            targetReps: 8,
          ),
          ActiveWorkoutSetInfo(
            setNumber: 3,
            targetWeightKg: 26.0,
            targetReps: 8,
          ),
          ActiveWorkoutSetInfo(
            setNumber: 4,
            targetWeightKg: 26.0,
            targetReps: 8,
          ),
        ],
      ),
      ActiveExerciseInfo(
        id: 'ex_2',
        name: 'Lat Pulldown (Wide Grip)',
        subtitle: '4 sets · Cable Machine',
        imageUrl:
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBgWvtzvWGeJfEEROJJeouakHsiO-tUOGhvcow8DiMS33mS03q7PVqlt6q-foe7bz7-Rp2AybLJM2ODNEeAajirmXdGgREKng-sy-3XrS0N78Cjd9dGR9qTQ2zusfsBEFLHiZFL3r0aMxrwNtyLdxbTf1QXbc7j_l-d4wDbA_MJ7J1q72jnieVdQg-blP8l-w6kDsaTCqxGhKCkFnfyyD1TXKUcxg3gyCmM-nouFckNoo2jDR-KOW6H',
        restSeconds: 90,
        draftWeightKg: 45.0,
        draftReps: 10,
        sets: List.generate(
          4,
          (i) => ActiveWorkoutSetInfo(
            setNumber: i + 1,
            targetWeightKg: 45.0,
            targetReps: 10,
          ),
        ),
      ),
      ActiveExerciseInfo(
        id: 'ex_3',
        name: 'Incline Dumbbell Flyes',
        subtitle: '3 sets · Incline Bench',
        imageUrl: '',
        restSeconds: 60,
        draftWeightKg: 16.0,
        draftReps: 12,
        sets: List.generate(
          3,
          (i) => ActiveWorkoutSetInfo(
            setNumber: i + 1,
            targetWeightKg: 16.0,
            targetReps: 12,
          ),
        ),
      ),
      ActiveExerciseInfo(
        id: 'ex_4',
        name: 'Overhead Triceps Extension',
        subtitle: '3 sets · Dumbbell',
        imageUrl: '',
        restSeconds: 60,
        draftWeightKg: 20.0,
        draftReps: 12,
        sets: List.generate(
          3,
          (i) => ActiveWorkoutSetInfo(
            setNumber: i + 1,
            targetWeightKg: 20.0,
            targetReps: 12,
          ),
        ),
      ),
      ActiveExerciseInfo(
        id: 'ex_5',
        name: 'Face Pulls',
        subtitle: '4 sets · Cable Machine',
        imageUrl: '',
        restSeconds: 60,
        draftWeightKg: 15.0,
        draftReps: 15,
        sets: List.generate(
          4,
          (i) => ActiveWorkoutSetInfo(
            setNumber: i + 1,
            targetWeightKg: 15.0,
            targetReps: 15,
          ),
        ),
      ),
    ],
  );
}

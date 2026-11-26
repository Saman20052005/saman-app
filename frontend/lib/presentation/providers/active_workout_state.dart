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
@immutable
class ActiveWorkoutSetInfo {
  final int setNumber;
  final double targetWeightKg;
  final int targetReps;
  final SetUnit unit;
  final int? targetSeconds;
  final int? seconds;
  final double? weightKg;
  final int? reps;
  final bool isCompleted;
  final bool isActive;
  final SetType setType;
  final double? rpe;
  final String? note;
  final String? supersetGroupId;
  final bool isPr;

  const ActiveWorkoutSetInfo({
    required this.setNumber,
    required this.targetWeightKg,
    required this.targetReps,
    this.unit = SetUnit.reps,
    this.targetSeconds,
    this.seconds,
    this.weightKg,
    this.reps,
    this.isCompleted = false,
    this.isActive = false,
    this.setType = SetType.normal,
    this.rpe,
    this.note,
    this.supersetGroupId,
    this.isPr = false,
  });

  double get volumeKg => workoutSetVolumeKg(
        unit: unit,
        repsCompleted: reps ?? 0,
        weightKg: weightKg ?? 0,
      );

  ActiveWorkoutSetInfo copyWith({
    int? setNumber,
    double? targetWeightKg,
    int? targetReps,
    SetUnit? unit,
    int? targetSeconds,
    int? seconds,
    double? weightKg,
    int? reps,
    bool? isCompleted,
    bool? isActive,
    SetType? setType,
    double? rpe,
    bool clearRpe = false,
    String? note,
    bool clearNote = false,
    String? supersetGroupId,
    bool clearSupersetGroup = false,
    bool? isPr,
  }) {
    return ActiveWorkoutSetInfo(
      setNumber: setNumber ?? this.setNumber,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      targetReps: targetReps ?? this.targetReps,
      unit: unit ?? this.unit,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      seconds: seconds ?? this.seconds,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      isCompleted: isCompleted ?? this.isCompleted,
      isActive: isActive ?? this.isActive,
      setType: setType ?? this.setType,
      rpe: clearRpe ? null : (rpe ?? this.rpe),
      note: clearNote ? null : (note ?? this.note),
      supersetGroupId:
          clearSupersetGroup ? null : (supersetGroupId ?? this.supersetGroupId),
      isPr: isPr ?? this.isPr,
    );
  }
}

/// Active exercise state tracking sets, active set index, and draft input values
@immutable
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
  final SetUnit unit;
  final int? draftSeconds;
  final Map<String, dynamic>? cvFormSummary;
  final List<Map<String, dynamic>>? repTimeline;
  final String? videoStoryId;
  final LastExercisePerformance? lastPerformance;
  final String note;
  final String? supersetGroupId;

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
    this.unit = SetUnit.reps,
    this.draftSeconds,
    this.cvFormSummary,
    this.repTimeline,
    this.videoStoryId,
    this.lastPerformance,
    this.note = '',
    this.supersetGroupId,
  });

  bool get canLogSet =>
      activeSet != null &&
      (unit == SetUnit.reps ||
          (draftSeconds != null && draftSeconds! >= 1 && draftSeconds! <= 999));

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
    String? slug,
    String? name,
    String? subtitle,
    String? imageUrl,
    int? restSeconds,
    List<ActiveWorkoutSetInfo>? sets,
    double? draftWeightKg,
    int? draftReps,
    SetUnit? unit,
    int? draftSeconds,
    bool clearDraftSeconds = false,
    Map<String, dynamic>? cvFormSummary,
    List<Map<String, dynamic>>? repTimeline,
    String? videoStoryId,
    LastExercisePerformance? lastPerformance,
    String? note,
    bool clearNote = false,
    String? supersetGroupId,
    bool clearSupersetGroup = false,
  }) {
    return ActiveExerciseInfo(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      restSeconds: restSeconds ?? this.restSeconds,
      sets: sets ?? this.sets,
      draftWeightKg: draftWeightKg ?? this.draftWeightKg,
      draftReps: draftReps ?? this.draftReps,
      unit: unit ?? this.unit,
      draftSeconds:
          clearDraftSeconds ? null : draftSeconds ?? this.draftSeconds,
      cvFormSummary: cvFormSummary ?? this.cvFormSummary,
      repTimeline: repTimeline ?? this.repTimeline,
      videoStoryId: videoStoryId ?? this.videoStoryId,
      lastPerformance: lastPerformance ?? this.lastPerformance,
      note: clearNote ? '' : (note ?? this.note),
      supersetGroupId:
          clearSupersetGroup ? null : (supersetGroupId ?? this.supersetGroupId),
    );
  }
}

/// Active workout session model tracking live timer, pauses, rest, and exercise list
@immutable
class ActiveWorkoutSessionState {
  final String title;
  final List<ActiveExerciseInfo> exercises;
  final int currentExerciseIndex;
  final int elapsedSeconds;
  final bool isPaused;
  final bool isResting;
  final int restSecondsLeft;
  final bool isFinished;
  final int restFinishedCount;

  const ActiveWorkoutSessionState({
    required this.title,
    required this.exercises,
    this.currentExerciseIndex = 0,
    this.elapsedSeconds = 0,
    this.isPaused = false,
    this.isResting = false,
    this.restSecondsLeft = 0,
    this.isFinished = false,
    this.restFinishedCount = 0,
  });

  factory ActiveWorkoutSessionState.fromExercises(
    List<Exercise> exercises, {
    String title = 'Workout Session',
  }) {
    final activeExercises = exercises.asMap().entries.map((entry) {
      final index = entry.key;
      final ex = entry.value;
      final setsCount = ex.defaultSets > 0 ? ex.defaultSets : 3;
      final unit = ex.repType == 'seconds' ? SetUnit.seconds : SetUnit.reps;
      final target = int.tryParse(ex.defaultReps.split('-').first) ?? 10;
      final defaultReps = unit == SetUnit.reps ? target : 0;
      final weight = unit == SetUnit.seconds ? 0.0 : 20.0;
      final sets = List.generate(
        setsCount,
        (i) => ActiveWorkoutSetInfo(
          setNumber: i + 1,
          targetWeightKg: weight,
          targetReps: defaultReps,
          unit: unit,
          targetSeconds: unit == SetUnit.seconds ? target : null,
          isActive: (index == 0 && i == 0),
        ),
      );
      return ActiveExerciseInfo(
        id: ex.id,
        slug: ex.slug,
        name: ex.name,
        subtitle:
            '${ex.equipment.isNotEmpty ? ex.equipment.first : "Free Weight"} · ${ex.muscleGroup}',
        imageUrl: ex.thumbnailUrl,
        restSeconds: ex.restSeconds > 0 ? ex.restSeconds : 90,
        sets: sets,
        draftWeightKg: weight,
        draftReps: defaultReps,
        unit: unit,
        draftSeconds: unit == SetUnit.seconds ? target : null,
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

  bool isInSuperset(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= exercises.length) return false;
    final groupId = exercises[exerciseIndex].supersetGroupId;
    if (groupId == null || groupId.isEmpty) return false;
    var count = 0;
    for (final ex in exercises) {
      if (ex.supersetGroupId == groupId) {
        count++;
        if (count >= 2) return true;
      }
    }
    return false;
  }

  String? supersetBadgeLabel(int exerciseIndex) {
    if (!isInSuperset(exerciseIndex)) return null;
    final targetGroupId = exercises[exerciseIndex].supersetGroupId!;

    final counts = <String, int>{};
    for (final ex in exercises) {
      final gid = ex.supersetGroupId;
      if (gid != null && gid.isNotEmpty) {
        counts[gid] = (counts[gid] ?? 0) + 1;
      }
    }

    final groupLetters = <String, String>{};
    var nextGroupOrdinal = 0;
    var memberNumber = 0;

    for (var i = 0; i < exercises.length; i++) {
      final gid = exercises[i].supersetGroupId;
      if (gid == null || gid.isEmpty || (counts[gid] ?? 0) < 2) continue;
      groupLetters.putIfAbsent(gid, () {
        final letter = nextGroupOrdinal < 26
            ? String.fromCharCode(65 + nextGroupOrdinal)
            : 'G${nextGroupOrdinal + 1}';
        nextGroupOrdinal++;
        return letter;
      });
      if (gid == targetGroupId) {
        memberNumber++;
        if (i == exerciseIndex) {
          return '${groupLetters[gid]}$memberNumber';
        }
      }
    }
    return null;
  }

  ActiveWorkoutSessionState copyWith({
    String? title,
    List<ActiveExerciseInfo>? exercises,
    int? currentExerciseIndex,
    int? elapsedSeconds,
    bool? isPaused,
    bool? isResting,
    int? restSecondsLeft,
    bool? isFinished,
    int? restFinishedCount,
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
      restFinishedCount: restFinishedCount ?? this.restFinishedCount,
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
        imageUrl: 'assets/images/exercises/dumbbell-bench-press-thumb.jpg',
        restSeconds: 90,
        draftWeightKg: 26.0,
        draftReps: 8,
        sets: [
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
        imageUrl: 'assets/images/exercises/lat-pulldown-thumb.jpg',
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
        imageUrl: 'assets/images/exercises/incline-dumbbell-flyes-thumb.jpg',
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
        imageUrl:
            'assets/images/exercises/overhead-triceps-extension-thumb.jpg',
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
        imageUrl: 'assets/images/exercises/face-pulls-thumb.jpg',
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

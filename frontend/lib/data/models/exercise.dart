import 'package:freezed_annotation/freezed_annotation.dart';

part 'exercise.freezed.dart';
part 'exercise.g.dart';

@freezed
class Exercise with _$Exercise {
  const factory Exercise({
    required String id,
    required String slug,
    required String name,
    required String nameVi,
    required String muscleGroup,
    @Default([]) List<String> targetMuscles,
    @Default([]) List<String> secondaryMuscles,
    @Default([]) List<String> equipment,
    required String difficulty, // "beginner", "intermediate", "advanced"
    required String thumbnailUrl,
    String? youtubeVideoId,
    @Default([]) List<String> cues,
    @Default([]) List<String> commonMistakes,
    required int defaultSets,
    required String defaultReps,
    required int restSeconds,
    required String repType,
    @Default(false) bool cvSupported,
    String? cvModuleId,
  }) = _Exercise;

  factory Exercise.fromJson(Map<String, dynamic> json) =>
      _$ExerciseFromJson(json);
}

enum SetUnit { reps, seconds }

double workoutSetVolumeKg({
  required SetUnit unit,
  required int repsCompleted,
  required double weightKg,
}) => unit == SetUnit.seconds ? 0 : repsCompleted * weightKg;

@Freezed(toJson: false)
class ExerciseSetLog with _$ExerciseSetLog {
  ExerciseSetLog._() {
    if (effectiveUnit == SetUnit.seconds &&
        (repsCompleted != 0 || secondsCompleted == null ||
            secondsCompleted! < 1 || secondsCompleted! > 999)) {
      throw ArgumentError('Timed sets require 1-999 seconds and zero reps');
    }
  }

  SetUnit get effectiveUnit => unit ?? SetUnit.reps;
  double get volumeKg => workoutSetVolumeKg(
    unit: effectiveUnit, repsCompleted: repsCompleted, weightKg: weightKg,
  );

  factory ExerciseSetLog({
    required String exerciseId,
    required String exerciseSlug,
    required int setNumber,
    required int repsCompleted,
    SetUnit? unit,
    int? secondsCompleted,
    required double weightKg,
    @Default(false) bool isCompleted,
    int? restTakenSeconds,
    @Default(false) bool cvDetected,
    Map<String, dynamic>? cvFormSummary,
  }) = _ExerciseSetLog;

  factory ExerciseSetLog.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSetLogFromJson(_validateJson(json));

  // Keep the legacy nullable key while omitting only the two new null keys.
  Map<String, dynamic> toJson() => {
    'exerciseId': exerciseId,
    'exerciseSlug': exerciseSlug,
    'setNumber': setNumber,
    'repsCompleted': repsCompleted,
    if (unit != null) 'unit': unit!.name,
    if (secondsCompleted != null) 'secondsCompleted': secondsCompleted,
    'weightKg': weightKg,
    'isCompleted': isCompleted,
    'restTakenSeconds': restTakenSeconds,
    'cvDetected': cvDetected,
    if (cvFormSummary != null) 'cvFormSummary': cvFormSummary,
  };

  static Map<String, dynamic> _validateJson(Map<String, dynamic> json) {
    final normalized = json['cvFormSummary'] == null &&
            json['cv_form_summary'] is Map
        ? Map<String, dynamic>.from(json)
        : json;
    if (!identical(normalized, json)) {
      normalized['cvFormSummary'] = normalized['cv_form_summary'];
    }
    // JSON numbers must not be truncated into valid timed results.
    if (normalized['unit'] == 'seconds' &&
        (normalized['secondsCompleted'] is! int ||
            normalized['repsCompleted'] != 0)) {
      throw const FormatException('Timed sets require integer seconds and zero reps');
    }
    return normalized;
  }
}

class LastExercisePerformance {
  final String exerciseId;
  final double lastWeightKg;
  final int lastReps;
  final double suggestedWeightKg;
  final int suggestedReps;
  final String suggestionReason;
  final String? lastDate;

  const LastExercisePerformance({
    required this.exerciseId,
    required this.lastWeightKg,
    required this.lastReps,
    required this.suggestedWeightKg,
    required this.suggestedReps,
    required this.suggestionReason,
    this.lastDate,
  });

  factory LastExercisePerformance.fromJson(Map<String, dynamic> json) {
    return LastExercisePerformance(
      exerciseId: (json['exercise_id'] ?? json['exerciseId'] ?? '').toString(),
      lastWeightKg: (json['last_weight_kg'] as num?)?.toDouble() ?? 0.0,
      lastReps: (json['last_reps'] as num?)?.toInt() ?? 0,
      suggestedWeightKg:
          (json['suggested_weight_kg'] as num?)?.toDouble() ?? 0.0,
      suggestedReps: (json['suggested_reps'] as num?)?.toInt() ?? 0,
      suggestionReason:
          (json['suggestion_reason'] ?? 'maintain_current_load').toString(),
      lastDate: json['last_date']?.toString(),
    );
  }
}

@freezed
class WorkoutSession with _$WorkoutSession {
  const factory WorkoutSession({
    required String id,
    required String planName,
    required DateTime startedAt,
    DateTime? finishedAt,
    required List<ExerciseSetLog> exerciseLogs,
    int? totalDurationMinutes,
    @Default(0) int totalVolumeKg,
  }) = _WorkoutSession;

  factory WorkoutSession.fromJson(Map<String, dynamic> json) =>
      _$WorkoutSessionFromJson(json);
}

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

enum SetType { warmup, normal, drop, failure }

SetType parseSetType(dynamic raw) {
  if (raw is SetType) return raw;
  if (raw is String) {
    switch (raw.trim().toLowerCase()) {
      case 'warmup':
        return SetType.warmup;
      case 'drop':
      case 'dropset':
      case 'drop_set':
        return SetType.drop;
      case 'failure':
        return SetType.failure;
      case 'normal':
      default:
        return SetType.normal;
    }
  }
  return SetType.normal;
}

double workoutSetVolumeKg({
  required SetUnit unit,
  required int repsCompleted,
  required double weightKg,
}) => unit == SetUnit.seconds ? 0 : repsCompleted * weightKg;

@Freezed(toJson: false)
class ExerciseSetLog with _$ExerciseSetLog {
  ExerciseSetLog._() {
    if (effectiveUnit == SetUnit.seconds &&
        (repsCompleted != 0 ||
            secondsCompleted == null ||
            secondsCompleted! < 1 ||
            secondsCompleted! > 999)) {
      throw ArgumentError('Timed sets require 1-999 seconds and zero reps');
    }
  }

  SetUnit get effectiveUnit => unit ?? SetUnit.reps;
  double get volumeKg => workoutSetVolumeKg(
        unit: effectiveUnit,
        repsCompleted: repsCompleted,
        weightKg: weightKg,
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
    @Default(SetType.normal) SetType setType,
    double? rpe,
    String? note,
    String? supersetGroupId,
    @Default(false) bool isPr,
  }) = _ExerciseSetLog;

  factory ExerciseSetLog.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSetLogFromJson(_validateJson(json));

  // Keep the legacy nullable key while omitting default/null optional keys.
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
        if (setType != SetType.normal) 'setType': setType.name,
        if (rpe != null) 'rpe': rpe,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (supersetGroupId != null) 'supersetGroupId': supersetGroupId,
        if (isPr) 'isPr': isPr,
      };

  static Map<String, dynamic> _validateJson(Map<String, dynamic> json) {
    final needsCv =
        json['cvFormSummary'] == null && json['cv_form_summary'] is Map;
    final needsSetType = json['setType'] == null && json['set_type'] != null;
    final rawSetType = needsSetType ? json['set_type'] : json['setType'];
    final needsSetTypeNormalization = rawSetType != null &&
        (rawSetType is! String ||
            !SetType.values.any((t) => t.name == rawSetType));
    final needsSuperset =
        json['supersetGroupId'] == null && json['superset_group_id'] != null;
    final needsIsPr = json['isPr'] == null && json['is_pr'] != null;
    final rawIsPr = needsIsPr ? json['is_pr'] : json['isPr'];
    final needsIsPrNormalization = rawIsPr != null && rawIsPr is! bool;

    final normalized = (needsCv ||
            needsSetType ||
            needsSetTypeNormalization ||
            needsSuperset ||
            needsIsPr ||
            needsIsPrNormalization)
        ? Map<String, dynamic>.from(json)
        : json;
    if (needsCv) {
      normalized['cvFormSummary'] = normalized['cv_form_summary'];
    }
    if (needsSetType || needsSetTypeNormalization) {
      normalized['setType'] = parseSetType(rawSetType).name;
    }
    if (needsSuperset) {
      normalized['supersetGroupId'] = normalized['superset_group_id'];
    }
    if (needsIsPr || needsIsPrNormalization) {
      normalized['isPr'] =
          rawIsPr is bool ? rawIsPr : (rawIsPr is num ? rawIsPr != 0 : false);
    }
    // JSON numbers must not be truncated into valid timed results.
    if (normalized['unit'] == 'seconds' &&
        (normalized['secondsCompleted'] is! int ||
            normalized['repsCompleted'] != 0)) {
      throw const FormatException(
        'Timed sets require integer seconds and zero reps',
      );
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
  final int? cvFormScore;
  final int? cvFastReps;

  const LastExercisePerformance({
    required this.exerciseId,
    required this.lastWeightKg,
    required this.lastReps,
    required this.suggestedWeightKg,
    required this.suggestedReps,
    required this.suggestionReason,
    this.lastDate,
    this.cvFormScore,
    this.cvFastReps,
  });

  factory LastExercisePerformance.fromJson(Map<String, dynamic> json) {
    final rawCvFormScore = json['cv_form_score'] ?? json['cvFormScore'];
    final rawCvFastReps = json['cv_fast_reps'] ?? json['cvFastReps'];
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
      cvFormScore: rawCvFormScore is num ? rawCvFormScore.toInt() : null,
      cvFastReps: rawCvFastReps is num ? rawCvFastReps.toInt() : null,
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
    @Default([]) List<Map<String, dynamic>> newPrs,
  }) = _WorkoutSession;

  factory WorkoutSession.fromJson(Map<String, dynamic> json) =>
      _$WorkoutSessionFromJson(json);
}

@immutable
class MuscleRecoveryItem {
  final String muscleGroup;
  final int recoveryPercent;
  final String status;
  final DateTime? lastTrainedAt;
  final double? hoursSinceLastTrained;
  final int recentSets;

  const MuscleRecoveryItem({
    required this.muscleGroup,
    required this.recoveryPercent,
    required this.status,
    this.lastTrainedAt,
    this.hoursSinceLastTrained,
    this.recentSets = 0,
  });

  factory MuscleRecoveryItem.fromJson(Map<String, dynamic> json) {
    final rawLastTrained = json['lastTrainedAt'] ?? json['last_trained_at'];
    DateTime? parsedLastTrained;
    if (rawLastTrained is DateTime) {
      parsedLastTrained = rawLastTrained;
    } else if (rawLastTrained is String && rawLastTrained.isNotEmpty) {
      parsedLastTrained = DateTime.tryParse(rawLastTrained);
    }

    final rawPercent = json['recoveryPercent'] ?? json['recovery_percent'];
    final percent = rawPercent is num ? rawPercent.round().clamp(0, 100) : 100;

    final rawHours =
        json['hoursSinceLastTrained'] ?? json['hours_since_last_trained'];
    final rawSets = json['recentSets'] ?? json['recent_sets'];

    return MuscleRecoveryItem(
      muscleGroup:
          (json['muscleGroup'] ?? json['muscle_group'] ?? '').toString(),
      recoveryPercent: percent,
      status: (json['status'] ??
              (percent >= 80
                  ? 'ready'
                  : percent >= 50
                      ? 'recovering'
                      : 'fatigued'))
          .toString(),
      lastTrainedAt: parsedLastTrained,
      hoursSinceLastTrained: rawHours is num ? rawHours.toDouble() : null,
      recentSets: rawSets is num ? rawSets.toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'muscleGroup': muscleGroup,
        'recoveryPercent': recoveryPercent,
        'status': status,
        if (lastTrainedAt != null)
          'lastTrainedAt': lastTrainedAt!.toUtc().toIso8601String(),
        if (hoursSinceLastTrained != null)
          'hoursSinceLastTrained': hoursSinceLastTrained,
        'recentSets': recentSets,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MuscleRecoveryItem &&
          runtimeType == other.runtimeType &&
          muscleGroup == other.muscleGroup &&
          recoveryPercent == other.recoveryPercent &&
          status == other.status &&
          lastTrainedAt == other.lastTrainedAt &&
          hoursSinceLastTrained == other.hoursSinceLastTrained &&
          recentSets == other.recentSets;

  @override
  int get hashCode => Object.hash(
        muscleGroup,
        recoveryPercent,
        status,
        lastTrainedAt,
        hoursSinceLastTrained,
        recentSets,
      );
}

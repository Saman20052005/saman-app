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

@freezed
class ExerciseSetLog with _$ExerciseSetLog {
  const factory ExerciseSetLog({
    required String exerciseId,
    required String exerciseSlug,
    required int setNumber,
    required int repsCompleted,
    required double weightKg,
    @Default(false) bool isCompleted,
    int? restTakenSeconds,
    @Default(false) bool cvDetected,
  }) = _ExerciseSetLog;

  factory ExerciseSetLog.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSetLogFromJson(json);
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

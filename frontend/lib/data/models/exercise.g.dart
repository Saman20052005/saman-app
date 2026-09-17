// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ExerciseImpl _$$ExerciseImplFromJson(Map<String, dynamic> json) =>
    _$ExerciseImpl(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      nameVi: json['nameVi'] as String,
      muscleGroup: json['muscleGroup'] as String,
      targetMuscles: (json['targetMuscles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      secondaryMuscles: (json['secondaryMuscles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      equipment: (json['equipment'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      difficulty: json['difficulty'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      cues:
          (json['cues'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      commonMistakes: (json['commonMistakes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      defaultSets: (json['defaultSets'] as num).toInt(),
      defaultReps: json['defaultReps'] as String,
      restSeconds: (json['restSeconds'] as num).toInt(),
      repType: json['repType'] as String,
      cvSupported: json['cvSupported'] as bool? ?? false,
      cvModuleId: json['cvModuleId'] as String?,
    );

Map<String, dynamic> _$$ExerciseImplToJson(_$ExerciseImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'slug': instance.slug,
      'name': instance.name,
      'nameVi': instance.nameVi,
      'muscleGroup': instance.muscleGroup,
      'targetMuscles': instance.targetMuscles,
      'secondaryMuscles': instance.secondaryMuscles,
      'equipment': instance.equipment,
      'difficulty': instance.difficulty,
      'thumbnailUrl': instance.thumbnailUrl,
      'youtubeVideoId': instance.youtubeVideoId,
      'cues': instance.cues,
      'commonMistakes': instance.commonMistakes,
      'defaultSets': instance.defaultSets,
      'defaultReps': instance.defaultReps,
      'restSeconds': instance.restSeconds,
      'repType': instance.repType,
      'cvSupported': instance.cvSupported,
      'cvModuleId': instance.cvModuleId,
    };

_$ExerciseSetLogImpl _$$ExerciseSetLogImplFromJson(Map<String, dynamic> json) =>
    _$ExerciseSetLogImpl(
      exerciseId: json['exerciseId'] as String,
      exerciseSlug: json['exerciseSlug'] as String,
      setNumber: (json['setNumber'] as num).toInt(),
      repsCompleted: (json['repsCompleted'] as num).toInt(),
      weightKg: (json['weightKg'] as num).toDouble(),
      isCompleted: json['isCompleted'] as bool? ?? false,
      restTakenSeconds: (json['restTakenSeconds'] as num?)?.toInt(),
      cvDetected: json['cvDetected'] as bool? ?? false,
    );

Map<String, dynamic> _$$ExerciseSetLogImplToJson(
        _$ExerciseSetLogImpl instance) =>
    <String, dynamic>{
      'exerciseId': instance.exerciseId,
      'exerciseSlug': instance.exerciseSlug,
      'setNumber': instance.setNumber,
      'repsCompleted': instance.repsCompleted,
      'weightKg': instance.weightKg,
      'isCompleted': instance.isCompleted,
      'restTakenSeconds': instance.restTakenSeconds,
      'cvDetected': instance.cvDetected,
    };

_$WorkoutSessionImpl _$$WorkoutSessionImplFromJson(Map<String, dynamic> json) =>
    _$WorkoutSessionImpl(
      id: json['id'] as String,
      planName: json['planName'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      exerciseLogs: (json['exerciseLogs'] as List<dynamic>)
          .map((e) => ExerciseSetLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalDurationMinutes: (json['totalDurationMinutes'] as num?)?.toInt(),
      totalVolumeKg: (json['totalVolumeKg'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$WorkoutSessionImplToJson(
        _$WorkoutSessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'planName': instance.planName,
      'startedAt': instance.startedAt.toIso8601String(),
      'finishedAt': instance.finishedAt?.toIso8601String(),
      'exerciseLogs': instance.exerciseLogs,
      'totalDurationMinutes': instance.totalDurationMinutes,
      'totalVolumeKg': instance.totalVolumeKg,
    };

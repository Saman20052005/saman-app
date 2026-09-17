// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exercise.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Exercise _$ExerciseFromJson(Map<String, dynamic> json) {
  return _Exercise.fromJson(json);
}

/// @nodoc
mixin _$Exercise {
  String get id => throw _privateConstructorUsedError;
  String get slug => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get nameVi => throw _privateConstructorUsedError;
  String get muscleGroup => throw _privateConstructorUsedError;
  List<String> get targetMuscles => throw _privateConstructorUsedError;
  List<String> get secondaryMuscles => throw _privateConstructorUsedError;
  List<String> get equipment => throw _privateConstructorUsedError;
  String get difficulty =>
      throw _privateConstructorUsedError; // "beginner", "intermediate", "advanced"
  String get thumbnailUrl => throw _privateConstructorUsedError;
  String? get youtubeVideoId => throw _privateConstructorUsedError;
  List<String> get cues => throw _privateConstructorUsedError;
  List<String> get commonMistakes => throw _privateConstructorUsedError;
  int get defaultSets => throw _privateConstructorUsedError;
  String get defaultReps => throw _privateConstructorUsedError;
  int get restSeconds => throw _privateConstructorUsedError;
  String get repType => throw _privateConstructorUsedError;
  bool get cvSupported => throw _privateConstructorUsedError;
  String? get cvModuleId => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ExerciseCopyWith<Exercise> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseCopyWith<$Res> {
  factory $ExerciseCopyWith(Exercise value, $Res Function(Exercise) then) =
      _$ExerciseCopyWithImpl<$Res, Exercise>;
  @useResult
  $Res call(
      {String id,
      String slug,
      String name,
      String nameVi,
      String muscleGroup,
      List<String> targetMuscles,
      List<String> secondaryMuscles,
      List<String> equipment,
      String difficulty,
      String thumbnailUrl,
      String? youtubeVideoId,
      List<String> cues,
      List<String> commonMistakes,
      int defaultSets,
      String defaultReps,
      int restSeconds,
      String repType,
      bool cvSupported,
      String? cvModuleId});
}

/// @nodoc
class _$ExerciseCopyWithImpl<$Res, $Val extends Exercise>
    implements $ExerciseCopyWith<$Res> {
  _$ExerciseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? slug = null,
    Object? name = null,
    Object? nameVi = null,
    Object? muscleGroup = null,
    Object? targetMuscles = null,
    Object? secondaryMuscles = null,
    Object? equipment = null,
    Object? difficulty = null,
    Object? thumbnailUrl = null,
    Object? youtubeVideoId = freezed,
    Object? cues = null,
    Object? commonMistakes = null,
    Object? defaultSets = null,
    Object? defaultReps = null,
    Object? restSeconds = null,
    Object? repType = null,
    Object? cvSupported = null,
    Object? cvModuleId = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      slug: null == slug
          ? _value.slug
          : slug // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      nameVi: null == nameVi
          ? _value.nameVi
          : nameVi // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      targetMuscles: null == targetMuscles
          ? _value.targetMuscles
          : targetMuscles // ignore: cast_nullable_to_non_nullable
              as List<String>,
      secondaryMuscles: null == secondaryMuscles
          ? _value.secondaryMuscles
          : secondaryMuscles // ignore: cast_nullable_to_non_nullable
              as List<String>,
      equipment: null == equipment
          ? _value.equipment
          : equipment // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as String,
      thumbnailUrl: null == thumbnailUrl
          ? _value.thumbnailUrl
          : thumbnailUrl // ignore: cast_nullable_to_non_nullable
              as String,
      youtubeVideoId: freezed == youtubeVideoId
          ? _value.youtubeVideoId
          : youtubeVideoId // ignore: cast_nullable_to_non_nullable
              as String?,
      cues: null == cues
          ? _value.cues
          : cues // ignore: cast_nullable_to_non_nullable
              as List<String>,
      commonMistakes: null == commonMistakes
          ? _value.commonMistakes
          : commonMistakes // ignore: cast_nullable_to_non_nullable
              as List<String>,
      defaultSets: null == defaultSets
          ? _value.defaultSets
          : defaultSets // ignore: cast_nullable_to_non_nullable
              as int,
      defaultReps: null == defaultReps
          ? _value.defaultReps
          : defaultReps // ignore: cast_nullable_to_non_nullable
              as String,
      restSeconds: null == restSeconds
          ? _value.restSeconds
          : restSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      repType: null == repType
          ? _value.repType
          : repType // ignore: cast_nullable_to_non_nullable
              as String,
      cvSupported: null == cvSupported
          ? _value.cvSupported
          : cvSupported // ignore: cast_nullable_to_non_nullable
              as bool,
      cvModuleId: freezed == cvModuleId
          ? _value.cvModuleId
          : cvModuleId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseImplCopyWith<$Res>
    implements $ExerciseCopyWith<$Res> {
  factory _$$ExerciseImplCopyWith(
          _$ExerciseImpl value, $Res Function(_$ExerciseImpl) then) =
      __$$ExerciseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String slug,
      String name,
      String nameVi,
      String muscleGroup,
      List<String> targetMuscles,
      List<String> secondaryMuscles,
      List<String> equipment,
      String difficulty,
      String thumbnailUrl,
      String? youtubeVideoId,
      List<String> cues,
      List<String> commonMistakes,
      int defaultSets,
      String defaultReps,
      int restSeconds,
      String repType,
      bool cvSupported,
      String? cvModuleId});
}

/// @nodoc
class __$$ExerciseImplCopyWithImpl<$Res>
    extends _$ExerciseCopyWithImpl<$Res, _$ExerciseImpl>
    implements _$$ExerciseImplCopyWith<$Res> {
  __$$ExerciseImplCopyWithImpl(
      _$ExerciseImpl _value, $Res Function(_$ExerciseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? slug = null,
    Object? name = null,
    Object? nameVi = null,
    Object? muscleGroup = null,
    Object? targetMuscles = null,
    Object? secondaryMuscles = null,
    Object? equipment = null,
    Object? difficulty = null,
    Object? thumbnailUrl = null,
    Object? youtubeVideoId = freezed,
    Object? cues = null,
    Object? commonMistakes = null,
    Object? defaultSets = null,
    Object? defaultReps = null,
    Object? restSeconds = null,
    Object? repType = null,
    Object? cvSupported = null,
    Object? cvModuleId = freezed,
  }) {
    return _then(_$ExerciseImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      slug: null == slug
          ? _value.slug
          : slug // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      nameVi: null == nameVi
          ? _value.nameVi
          : nameVi // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      targetMuscles: null == targetMuscles
          ? _value._targetMuscles
          : targetMuscles // ignore: cast_nullable_to_non_nullable
              as List<String>,
      secondaryMuscles: null == secondaryMuscles
          ? _value._secondaryMuscles
          : secondaryMuscles // ignore: cast_nullable_to_non_nullable
              as List<String>,
      equipment: null == equipment
          ? _value._equipment
          : equipment // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as String,
      thumbnailUrl: null == thumbnailUrl
          ? _value.thumbnailUrl
          : thumbnailUrl // ignore: cast_nullable_to_non_nullable
              as String,
      youtubeVideoId: freezed == youtubeVideoId
          ? _value.youtubeVideoId
          : youtubeVideoId // ignore: cast_nullable_to_non_nullable
              as String?,
      cues: null == cues
          ? _value._cues
          : cues // ignore: cast_nullable_to_non_nullable
              as List<String>,
      commonMistakes: null == commonMistakes
          ? _value._commonMistakes
          : commonMistakes // ignore: cast_nullable_to_non_nullable
              as List<String>,
      defaultSets: null == defaultSets
          ? _value.defaultSets
          : defaultSets // ignore: cast_nullable_to_non_nullable
              as int,
      defaultReps: null == defaultReps
          ? _value.defaultReps
          : defaultReps // ignore: cast_nullable_to_non_nullable
              as String,
      restSeconds: null == restSeconds
          ? _value.restSeconds
          : restSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      repType: null == repType
          ? _value.repType
          : repType // ignore: cast_nullable_to_non_nullable
              as String,
      cvSupported: null == cvSupported
          ? _value.cvSupported
          : cvSupported // ignore: cast_nullable_to_non_nullable
              as bool,
      cvModuleId: freezed == cvModuleId
          ? _value.cvModuleId
          : cvModuleId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ExerciseImpl implements _Exercise {
  const _$ExerciseImpl(
      {required this.id,
      required this.slug,
      required this.name,
      required this.nameVi,
      required this.muscleGroup,
      final List<String> targetMuscles = const [],
      final List<String> secondaryMuscles = const [],
      final List<String> equipment = const [],
      required this.difficulty,
      required this.thumbnailUrl,
      this.youtubeVideoId,
      final List<String> cues = const [],
      final List<String> commonMistakes = const [],
      required this.defaultSets,
      required this.defaultReps,
      required this.restSeconds,
      required this.repType,
      this.cvSupported = false,
      this.cvModuleId})
      : _targetMuscles = targetMuscles,
        _secondaryMuscles = secondaryMuscles,
        _equipment = equipment,
        _cues = cues,
        _commonMistakes = commonMistakes;

  factory _$ExerciseImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExerciseImplFromJson(json);

  @override
  final String id;
  @override
  final String slug;
  @override
  final String name;
  @override
  final String nameVi;
  @override
  final String muscleGroup;
  final List<String> _targetMuscles;
  @override
  @JsonKey()
  List<String> get targetMuscles {
    if (_targetMuscles is EqualUnmodifiableListView) return _targetMuscles;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_targetMuscles);
  }

  final List<String> _secondaryMuscles;
  @override
  @JsonKey()
  List<String> get secondaryMuscles {
    if (_secondaryMuscles is EqualUnmodifiableListView)
      return _secondaryMuscles;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_secondaryMuscles);
  }

  final List<String> _equipment;
  @override
  @JsonKey()
  List<String> get equipment {
    if (_equipment is EqualUnmodifiableListView) return _equipment;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_equipment);
  }

  @override
  final String difficulty;
// "beginner", "intermediate", "advanced"
  @override
  final String thumbnailUrl;
  @override
  final String? youtubeVideoId;
  final List<String> _cues;
  @override
  @JsonKey()
  List<String> get cues {
    if (_cues is EqualUnmodifiableListView) return _cues;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_cues);
  }

  final List<String> _commonMistakes;
  @override
  @JsonKey()
  List<String> get commonMistakes {
    if (_commonMistakes is EqualUnmodifiableListView) return _commonMistakes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_commonMistakes);
  }

  @override
  final int defaultSets;
  @override
  final String defaultReps;
  @override
  final int restSeconds;
  @override
  final String repType;
  @override
  @JsonKey()
  final bool cvSupported;
  @override
  final String? cvModuleId;

  @override
  String toString() {
    return 'Exercise(id: $id, slug: $slug, name: $name, nameVi: $nameVi, muscleGroup: $muscleGroup, targetMuscles: $targetMuscles, secondaryMuscles: $secondaryMuscles, equipment: $equipment, difficulty: $difficulty, thumbnailUrl: $thumbnailUrl, youtubeVideoId: $youtubeVideoId, cues: $cues, commonMistakes: $commonMistakes, defaultSets: $defaultSets, defaultReps: $defaultReps, restSeconds: $restSeconds, repType: $repType, cvSupported: $cvSupported, cvModuleId: $cvModuleId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.slug, slug) || other.slug == slug) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.nameVi, nameVi) || other.nameVi == nameVi) &&
            (identical(other.muscleGroup, muscleGroup) ||
                other.muscleGroup == muscleGroup) &&
            const DeepCollectionEquality()
                .equals(other._targetMuscles, _targetMuscles) &&
            const DeepCollectionEquality()
                .equals(other._secondaryMuscles, _secondaryMuscles) &&
            const DeepCollectionEquality()
                .equals(other._equipment, _equipment) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                other.thumbnailUrl == thumbnailUrl) &&
            (identical(other.youtubeVideoId, youtubeVideoId) ||
                other.youtubeVideoId == youtubeVideoId) &&
            const DeepCollectionEquality().equals(other._cues, _cues) &&
            const DeepCollectionEquality()
                .equals(other._commonMistakes, _commonMistakes) &&
            (identical(other.defaultSets, defaultSets) ||
                other.defaultSets == defaultSets) &&
            (identical(other.defaultReps, defaultReps) ||
                other.defaultReps == defaultReps) &&
            (identical(other.restSeconds, restSeconds) ||
                other.restSeconds == restSeconds) &&
            (identical(other.repType, repType) || other.repType == repType) &&
            (identical(other.cvSupported, cvSupported) ||
                other.cvSupported == cvSupported) &&
            (identical(other.cvModuleId, cvModuleId) ||
                other.cvModuleId == cvModuleId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        slug,
        name,
        nameVi,
        muscleGroup,
        const DeepCollectionEquality().hash(_targetMuscles),
        const DeepCollectionEquality().hash(_secondaryMuscles),
        const DeepCollectionEquality().hash(_equipment),
        difficulty,
        thumbnailUrl,
        youtubeVideoId,
        const DeepCollectionEquality().hash(_cues),
        const DeepCollectionEquality().hash(_commonMistakes),
        defaultSets,
        defaultReps,
        restSeconds,
        repType,
        cvSupported,
        cvModuleId
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseImplCopyWith<_$ExerciseImpl> get copyWith =>
      __$$ExerciseImplCopyWithImpl<_$ExerciseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExerciseImplToJson(
      this,
    );
  }
}

abstract class _Exercise implements Exercise {
  const factory _Exercise(
      {required final String id,
      required final String slug,
      required final String name,
      required final String nameVi,
      required final String muscleGroup,
      final List<String> targetMuscles,
      final List<String> secondaryMuscles,
      final List<String> equipment,
      required final String difficulty,
      required final String thumbnailUrl,
      final String? youtubeVideoId,
      final List<String> cues,
      final List<String> commonMistakes,
      required final int defaultSets,
      required final String defaultReps,
      required final int restSeconds,
      required final String repType,
      final bool cvSupported,
      final String? cvModuleId}) = _$ExerciseImpl;

  factory _Exercise.fromJson(Map<String, dynamic> json) =
      _$ExerciseImpl.fromJson;

  @override
  String get id;
  @override
  String get slug;
  @override
  String get name;
  @override
  String get nameVi;
  @override
  String get muscleGroup;
  @override
  List<String> get targetMuscles;
  @override
  List<String> get secondaryMuscles;
  @override
  List<String> get equipment;
  @override
  String get difficulty;
  @override // "beginner", "intermediate", "advanced"
  String get thumbnailUrl;
  @override
  String? get youtubeVideoId;
  @override
  List<String> get cues;
  @override
  List<String> get commonMistakes;
  @override
  int get defaultSets;
  @override
  String get defaultReps;
  @override
  int get restSeconds;
  @override
  String get repType;
  @override
  bool get cvSupported;
  @override
  String? get cvModuleId;
  @override
  @JsonKey(ignore: true)
  _$$ExerciseImplCopyWith<_$ExerciseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ExerciseSetLog _$ExerciseSetLogFromJson(Map<String, dynamic> json) {
  return _ExerciseSetLog.fromJson(json);
}

/// @nodoc
mixin _$ExerciseSetLog {
  String get exerciseId => throw _privateConstructorUsedError;
  String get exerciseSlug => throw _privateConstructorUsedError;
  int get setNumber => throw _privateConstructorUsedError;
  int get repsCompleted => throw _privateConstructorUsedError;
  double get weightKg => throw _privateConstructorUsedError;
  bool get isCompleted => throw _privateConstructorUsedError;
  int? get restTakenSeconds => throw _privateConstructorUsedError;
  bool get cvDetected => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ExerciseSetLogCopyWith<ExerciseSetLog> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseSetLogCopyWith<$Res> {
  factory $ExerciseSetLogCopyWith(
          ExerciseSetLog value, $Res Function(ExerciseSetLog) then) =
      _$ExerciseSetLogCopyWithImpl<$Res, ExerciseSetLog>;
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseSlug,
      int setNumber,
      int repsCompleted,
      double weightKg,
      bool isCompleted,
      int? restTakenSeconds,
      bool cvDetected});
}

/// @nodoc
class _$ExerciseSetLogCopyWithImpl<$Res, $Val extends ExerciseSetLog>
    implements $ExerciseSetLogCopyWith<$Res> {
  _$ExerciseSetLogCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseSlug = null,
    Object? setNumber = null,
    Object? repsCompleted = null,
    Object? weightKg = null,
    Object? isCompleted = null,
    Object? restTakenSeconds = freezed,
    Object? cvDetected = null,
  }) {
    return _then(_value.copyWith(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseSlug: null == exerciseSlug
          ? _value.exerciseSlug
          : exerciseSlug // ignore: cast_nullable_to_non_nullable
              as String,
      setNumber: null == setNumber
          ? _value.setNumber
          : setNumber // ignore: cast_nullable_to_non_nullable
              as int,
      repsCompleted: null == repsCompleted
          ? _value.repsCompleted
          : repsCompleted // ignore: cast_nullable_to_non_nullable
              as int,
      weightKg: null == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      restTakenSeconds: freezed == restTakenSeconds
          ? _value.restTakenSeconds
          : restTakenSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      cvDetected: null == cvDetected
          ? _value.cvDetected
          : cvDetected // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseSetLogImplCopyWith<$Res>
    implements $ExerciseSetLogCopyWith<$Res> {
  factory _$$ExerciseSetLogImplCopyWith(_$ExerciseSetLogImpl value,
          $Res Function(_$ExerciseSetLogImpl) then) =
      __$$ExerciseSetLogImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseSlug,
      int setNumber,
      int repsCompleted,
      double weightKg,
      bool isCompleted,
      int? restTakenSeconds,
      bool cvDetected});
}

/// @nodoc
class __$$ExerciseSetLogImplCopyWithImpl<$Res>
    extends _$ExerciseSetLogCopyWithImpl<$Res, _$ExerciseSetLogImpl>
    implements _$$ExerciseSetLogImplCopyWith<$Res> {
  __$$ExerciseSetLogImplCopyWithImpl(
      _$ExerciseSetLogImpl _value, $Res Function(_$ExerciseSetLogImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseSlug = null,
    Object? setNumber = null,
    Object? repsCompleted = null,
    Object? weightKg = null,
    Object? isCompleted = null,
    Object? restTakenSeconds = freezed,
    Object? cvDetected = null,
  }) {
    return _then(_$ExerciseSetLogImpl(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseSlug: null == exerciseSlug
          ? _value.exerciseSlug
          : exerciseSlug // ignore: cast_nullable_to_non_nullable
              as String,
      setNumber: null == setNumber
          ? _value.setNumber
          : setNumber // ignore: cast_nullable_to_non_nullable
              as int,
      repsCompleted: null == repsCompleted
          ? _value.repsCompleted
          : repsCompleted // ignore: cast_nullable_to_non_nullable
              as int,
      weightKg: null == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      restTakenSeconds: freezed == restTakenSeconds
          ? _value.restTakenSeconds
          : restTakenSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      cvDetected: null == cvDetected
          ? _value.cvDetected
          : cvDetected // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ExerciseSetLogImpl implements _ExerciseSetLog {
  const _$ExerciseSetLogImpl(
      {required this.exerciseId,
      required this.exerciseSlug,
      required this.setNumber,
      required this.repsCompleted,
      required this.weightKg,
      this.isCompleted = false,
      this.restTakenSeconds,
      this.cvDetected = false});

  factory _$ExerciseSetLogImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExerciseSetLogImplFromJson(json);

  @override
  final String exerciseId;
  @override
  final String exerciseSlug;
  @override
  final int setNumber;
  @override
  final int repsCompleted;
  @override
  final double weightKg;
  @override
  @JsonKey()
  final bool isCompleted;
  @override
  final int? restTakenSeconds;
  @override
  @JsonKey()
  final bool cvDetected;

  @override
  String toString() {
    return 'ExerciseSetLog(exerciseId: $exerciseId, exerciseSlug: $exerciseSlug, setNumber: $setNumber, repsCompleted: $repsCompleted, weightKg: $weightKg, isCompleted: $isCompleted, restTakenSeconds: $restTakenSeconds, cvDetected: $cvDetected)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseSetLogImpl &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseSlug, exerciseSlug) ||
                other.exerciseSlug == exerciseSlug) &&
            (identical(other.setNumber, setNumber) ||
                other.setNumber == setNumber) &&
            (identical(other.repsCompleted, repsCompleted) ||
                other.repsCompleted == repsCompleted) &&
            (identical(other.weightKg, weightKg) ||
                other.weightKg == weightKg) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            (identical(other.restTakenSeconds, restTakenSeconds) ||
                other.restTakenSeconds == restTakenSeconds) &&
            (identical(other.cvDetected, cvDetected) ||
                other.cvDetected == cvDetected));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      exerciseId,
      exerciseSlug,
      setNumber,
      repsCompleted,
      weightKg,
      isCompleted,
      restTakenSeconds,
      cvDetected);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseSetLogImplCopyWith<_$ExerciseSetLogImpl> get copyWith =>
      __$$ExerciseSetLogImplCopyWithImpl<_$ExerciseSetLogImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExerciseSetLogImplToJson(
      this,
    );
  }
}

abstract class _ExerciseSetLog implements ExerciseSetLog {
  const factory _ExerciseSetLog(
      {required final String exerciseId,
      required final String exerciseSlug,
      required final int setNumber,
      required final int repsCompleted,
      required final double weightKg,
      final bool isCompleted,
      final int? restTakenSeconds,
      final bool cvDetected}) = _$ExerciseSetLogImpl;

  factory _ExerciseSetLog.fromJson(Map<String, dynamic> json) =
      _$ExerciseSetLogImpl.fromJson;

  @override
  String get exerciseId;
  @override
  String get exerciseSlug;
  @override
  int get setNumber;
  @override
  int get repsCompleted;
  @override
  double get weightKg;
  @override
  bool get isCompleted;
  @override
  int? get restTakenSeconds;
  @override
  bool get cvDetected;
  @override
  @JsonKey(ignore: true)
  _$$ExerciseSetLogImplCopyWith<_$ExerciseSetLogImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

WorkoutSession _$WorkoutSessionFromJson(Map<String, dynamic> json) {
  return _WorkoutSession.fromJson(json);
}

/// @nodoc
mixin _$WorkoutSession {
  String get id => throw _privateConstructorUsedError;
  String get planName => throw _privateConstructorUsedError;
  DateTime get startedAt => throw _privateConstructorUsedError;
  DateTime? get finishedAt => throw _privateConstructorUsedError;
  List<ExerciseSetLog> get exerciseLogs => throw _privateConstructorUsedError;
  int? get totalDurationMinutes => throw _privateConstructorUsedError;
  int get totalVolumeKg => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WorkoutSessionCopyWith<WorkoutSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WorkoutSessionCopyWith<$Res> {
  factory $WorkoutSessionCopyWith(
          WorkoutSession value, $Res Function(WorkoutSession) then) =
      _$WorkoutSessionCopyWithImpl<$Res, WorkoutSession>;
  @useResult
  $Res call(
      {String id,
      String planName,
      DateTime startedAt,
      DateTime? finishedAt,
      List<ExerciseSetLog> exerciseLogs,
      int? totalDurationMinutes,
      int totalVolumeKg});
}

/// @nodoc
class _$WorkoutSessionCopyWithImpl<$Res, $Val extends WorkoutSession>
    implements $WorkoutSessionCopyWith<$Res> {
  _$WorkoutSessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? planName = null,
    Object? startedAt = null,
    Object? finishedAt = freezed,
    Object? exerciseLogs = null,
    Object? totalDurationMinutes = freezed,
    Object? totalVolumeKg = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      planName: null == planName
          ? _value.planName
          : planName // ignore: cast_nullable_to_non_nullable
              as String,
      startedAt: null == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      finishedAt: freezed == finishedAt
          ? _value.finishedAt
          : finishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      exerciseLogs: null == exerciseLogs
          ? _value.exerciseLogs
          : exerciseLogs // ignore: cast_nullable_to_non_nullable
              as List<ExerciseSetLog>,
      totalDurationMinutes: freezed == totalDurationMinutes
          ? _value.totalDurationMinutes
          : totalDurationMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      totalVolumeKg: null == totalVolumeKg
          ? _value.totalVolumeKg
          : totalVolumeKg // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WorkoutSessionImplCopyWith<$Res>
    implements $WorkoutSessionCopyWith<$Res> {
  factory _$$WorkoutSessionImplCopyWith(_$WorkoutSessionImpl value,
          $Res Function(_$WorkoutSessionImpl) then) =
      __$$WorkoutSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String planName,
      DateTime startedAt,
      DateTime? finishedAt,
      List<ExerciseSetLog> exerciseLogs,
      int? totalDurationMinutes,
      int totalVolumeKg});
}

/// @nodoc
class __$$WorkoutSessionImplCopyWithImpl<$Res>
    extends _$WorkoutSessionCopyWithImpl<$Res, _$WorkoutSessionImpl>
    implements _$$WorkoutSessionImplCopyWith<$Res> {
  __$$WorkoutSessionImplCopyWithImpl(
      _$WorkoutSessionImpl _value, $Res Function(_$WorkoutSessionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? planName = null,
    Object? startedAt = null,
    Object? finishedAt = freezed,
    Object? exerciseLogs = null,
    Object? totalDurationMinutes = freezed,
    Object? totalVolumeKg = null,
  }) {
    return _then(_$WorkoutSessionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      planName: null == planName
          ? _value.planName
          : planName // ignore: cast_nullable_to_non_nullable
              as String,
      startedAt: null == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      finishedAt: freezed == finishedAt
          ? _value.finishedAt
          : finishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      exerciseLogs: null == exerciseLogs
          ? _value._exerciseLogs
          : exerciseLogs // ignore: cast_nullable_to_non_nullable
              as List<ExerciseSetLog>,
      totalDurationMinutes: freezed == totalDurationMinutes
          ? _value.totalDurationMinutes
          : totalDurationMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      totalVolumeKg: null == totalVolumeKg
          ? _value.totalVolumeKg
          : totalVolumeKg // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WorkoutSessionImpl implements _WorkoutSession {
  const _$WorkoutSessionImpl(
      {required this.id,
      required this.planName,
      required this.startedAt,
      this.finishedAt,
      required final List<ExerciseSetLog> exerciseLogs,
      this.totalDurationMinutes,
      this.totalVolumeKg = 0})
      : _exerciseLogs = exerciseLogs;

  factory _$WorkoutSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$WorkoutSessionImplFromJson(json);

  @override
  final String id;
  @override
  final String planName;
  @override
  final DateTime startedAt;
  @override
  final DateTime? finishedAt;
  final List<ExerciseSetLog> _exerciseLogs;
  @override
  List<ExerciseSetLog> get exerciseLogs {
    if (_exerciseLogs is EqualUnmodifiableListView) return _exerciseLogs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exerciseLogs);
  }

  @override
  final int? totalDurationMinutes;
  @override
  @JsonKey()
  final int totalVolumeKg;

  @override
  String toString() {
    return 'WorkoutSession(id: $id, planName: $planName, startedAt: $startedAt, finishedAt: $finishedAt, exerciseLogs: $exerciseLogs, totalDurationMinutes: $totalDurationMinutes, totalVolumeKg: $totalVolumeKg)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WorkoutSessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.planName, planName) ||
                other.planName == planName) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.finishedAt, finishedAt) ||
                other.finishedAt == finishedAt) &&
            const DeepCollectionEquality()
                .equals(other._exerciseLogs, _exerciseLogs) &&
            (identical(other.totalDurationMinutes, totalDurationMinutes) ||
                other.totalDurationMinutes == totalDurationMinutes) &&
            (identical(other.totalVolumeKg, totalVolumeKg) ||
                other.totalVolumeKg == totalVolumeKg));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      planName,
      startedAt,
      finishedAt,
      const DeepCollectionEquality().hash(_exerciseLogs),
      totalDurationMinutes,
      totalVolumeKg);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WorkoutSessionImplCopyWith<_$WorkoutSessionImpl> get copyWith =>
      __$$WorkoutSessionImplCopyWithImpl<_$WorkoutSessionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WorkoutSessionImplToJson(
      this,
    );
  }
}

abstract class _WorkoutSession implements WorkoutSession {
  const factory _WorkoutSession(
      {required final String id,
      required final String planName,
      required final DateTime startedAt,
      final DateTime? finishedAt,
      required final List<ExerciseSetLog> exerciseLogs,
      final int? totalDurationMinutes,
      final int totalVolumeKg}) = _$WorkoutSessionImpl;

  factory _WorkoutSession.fromJson(Map<String, dynamic> json) =
      _$WorkoutSessionImpl.fromJson;

  @override
  String get id;
  @override
  String get planName;
  @override
  DateTime get startedAt;
  @override
  DateTime? get finishedAt;
  @override
  List<ExerciseSetLog> get exerciseLogs;
  @override
  int? get totalDurationMinutes;
  @override
  int get totalVolumeKg;
  @override
  @JsonKey(ignore: true)
  _$$WorkoutSessionImplCopyWith<_$WorkoutSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

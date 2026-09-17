// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'active_workout_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ActiveWorkoutState {
  List<Exercise> get exercises => throw _privateConstructorUsedError;
  int get currentExerciseIndex => throw _privateConstructorUsedError;
  int get currentSetIndex => throw _privateConstructorUsedError;
  List<ExerciseSetLog> get completedLogs => throw _privateConstructorUsedError;
  bool get isFinished => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $ActiveWorkoutStateCopyWith<ActiveWorkoutState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ActiveWorkoutStateCopyWith<$Res> {
  factory $ActiveWorkoutStateCopyWith(
          ActiveWorkoutState value, $Res Function(ActiveWorkoutState) then) =
      _$ActiveWorkoutStateCopyWithImpl<$Res, ActiveWorkoutState>;
  @useResult
  $Res call(
      {List<Exercise> exercises,
      int currentExerciseIndex,
      int currentSetIndex,
      List<ExerciseSetLog> completedLogs,
      bool isFinished});
}

/// @nodoc
class _$ActiveWorkoutStateCopyWithImpl<$Res, $Val extends ActiveWorkoutState>
    implements $ActiveWorkoutStateCopyWith<$Res> {
  _$ActiveWorkoutStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exercises = null,
    Object? currentExerciseIndex = null,
    Object? currentSetIndex = null,
    Object? completedLogs = null,
    Object? isFinished = null,
  }) {
    return _then(_value.copyWith(
      exercises: null == exercises
          ? _value.exercises
          : exercises // ignore: cast_nullable_to_non_nullable
              as List<Exercise>,
      currentExerciseIndex: null == currentExerciseIndex
          ? _value.currentExerciseIndex
          : currentExerciseIndex // ignore: cast_nullable_to_non_nullable
              as int,
      currentSetIndex: null == currentSetIndex
          ? _value.currentSetIndex
          : currentSetIndex // ignore: cast_nullable_to_non_nullable
              as int,
      completedLogs: null == completedLogs
          ? _value.completedLogs
          : completedLogs // ignore: cast_nullable_to_non_nullable
              as List<ExerciseSetLog>,
      isFinished: null == isFinished
          ? _value.isFinished
          : isFinished // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ActiveWorkoutStateImplCopyWith<$Res>
    implements $ActiveWorkoutStateCopyWith<$Res> {
  factory _$$ActiveWorkoutStateImplCopyWith(_$ActiveWorkoutStateImpl value,
          $Res Function(_$ActiveWorkoutStateImpl) then) =
      __$$ActiveWorkoutStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<Exercise> exercises,
      int currentExerciseIndex,
      int currentSetIndex,
      List<ExerciseSetLog> completedLogs,
      bool isFinished});
}

/// @nodoc
class __$$ActiveWorkoutStateImplCopyWithImpl<$Res>
    extends _$ActiveWorkoutStateCopyWithImpl<$Res, _$ActiveWorkoutStateImpl>
    implements _$$ActiveWorkoutStateImplCopyWith<$Res> {
  __$$ActiveWorkoutStateImplCopyWithImpl(_$ActiveWorkoutStateImpl _value,
      $Res Function(_$ActiveWorkoutStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exercises = null,
    Object? currentExerciseIndex = null,
    Object? currentSetIndex = null,
    Object? completedLogs = null,
    Object? isFinished = null,
  }) {
    return _then(_$ActiveWorkoutStateImpl(
      exercises: null == exercises
          ? _value._exercises
          : exercises // ignore: cast_nullable_to_non_nullable
              as List<Exercise>,
      currentExerciseIndex: null == currentExerciseIndex
          ? _value.currentExerciseIndex
          : currentExerciseIndex // ignore: cast_nullable_to_non_nullable
              as int,
      currentSetIndex: null == currentSetIndex
          ? _value.currentSetIndex
          : currentSetIndex // ignore: cast_nullable_to_non_nullable
              as int,
      completedLogs: null == completedLogs
          ? _value._completedLogs
          : completedLogs // ignore: cast_nullable_to_non_nullable
              as List<ExerciseSetLog>,
      isFinished: null == isFinished
          ? _value.isFinished
          : isFinished // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$ActiveWorkoutStateImpl extends _ActiveWorkoutState {
  const _$ActiveWorkoutStateImpl(
      {required final List<Exercise> exercises,
      required this.currentExerciseIndex,
      required this.currentSetIndex,
      required final List<ExerciseSetLog> completedLogs,
      this.isFinished = false})
      : _exercises = exercises,
        _completedLogs = completedLogs,
        super._();

  final List<Exercise> _exercises;
  @override
  List<Exercise> get exercises {
    if (_exercises is EqualUnmodifiableListView) return _exercises;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exercises);
  }

  @override
  final int currentExerciseIndex;
  @override
  final int currentSetIndex;
  final List<ExerciseSetLog> _completedLogs;
  @override
  List<ExerciseSetLog> get completedLogs {
    if (_completedLogs is EqualUnmodifiableListView) return _completedLogs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_completedLogs);
  }

  @override
  @JsonKey()
  final bool isFinished;

  @override
  String toString() {
    return 'ActiveWorkoutState(exercises: $exercises, currentExerciseIndex: $currentExerciseIndex, currentSetIndex: $currentSetIndex, completedLogs: $completedLogs, isFinished: $isFinished)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ActiveWorkoutStateImpl &&
            const DeepCollectionEquality()
                .equals(other._exercises, _exercises) &&
            (identical(other.currentExerciseIndex, currentExerciseIndex) ||
                other.currentExerciseIndex == currentExerciseIndex) &&
            (identical(other.currentSetIndex, currentSetIndex) ||
                other.currentSetIndex == currentSetIndex) &&
            const DeepCollectionEquality()
                .equals(other._completedLogs, _completedLogs) &&
            (identical(other.isFinished, isFinished) ||
                other.isFinished == isFinished));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_exercises),
      currentExerciseIndex,
      currentSetIndex,
      const DeepCollectionEquality().hash(_completedLogs),
      isFinished);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ActiveWorkoutStateImplCopyWith<_$ActiveWorkoutStateImpl> get copyWith =>
      __$$ActiveWorkoutStateImplCopyWithImpl<_$ActiveWorkoutStateImpl>(
          this, _$identity);
}

abstract class _ActiveWorkoutState extends ActiveWorkoutState {
  const factory _ActiveWorkoutState(
      {required final List<Exercise> exercises,
      required final int currentExerciseIndex,
      required final int currentSetIndex,
      required final List<ExerciseSetLog> completedLogs,
      final bool isFinished}) = _$ActiveWorkoutStateImpl;
  const _ActiveWorkoutState._() : super._();

  @override
  List<Exercise> get exercises;
  @override
  int get currentExerciseIndex;
  @override
  int get currentSetIndex;
  @override
  List<ExerciseSetLog> get completedLogs;
  @override
  bool get isFinished;
  @override
  @JsonKey(ignore: true)
  _$$ActiveWorkoutStateImplCopyWith<_$ActiveWorkoutStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$CurrentSetState {
  int get reps => throw _privateConstructorUsedError;
  double get weight => throw _privateConstructorUsedError;
  bool get isResting => throw _privateConstructorUsedError;
  int get restSecondsLeft => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $CurrentSetStateCopyWith<CurrentSetState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CurrentSetStateCopyWith<$Res> {
  factory $CurrentSetStateCopyWith(
          CurrentSetState value, $Res Function(CurrentSetState) then) =
      _$CurrentSetStateCopyWithImpl<$Res, CurrentSetState>;
  @useResult
  $Res call({int reps, double weight, bool isResting, int restSecondsLeft});
}

/// @nodoc
class _$CurrentSetStateCopyWithImpl<$Res, $Val extends CurrentSetState>
    implements $CurrentSetStateCopyWith<$Res> {
  _$CurrentSetStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reps = null,
    Object? weight = null,
    Object? isResting = null,
    Object? restSecondsLeft = null,
  }) {
    return _then(_value.copyWith(
      reps: null == reps
          ? _value.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      weight: null == weight
          ? _value.weight
          : weight // ignore: cast_nullable_to_non_nullable
              as double,
      isResting: null == isResting
          ? _value.isResting
          : isResting // ignore: cast_nullable_to_non_nullable
              as bool,
      restSecondsLeft: null == restSecondsLeft
          ? _value.restSecondsLeft
          : restSecondsLeft // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CurrentSetStateImplCopyWith<$Res>
    implements $CurrentSetStateCopyWith<$Res> {
  factory _$$CurrentSetStateImplCopyWith(_$CurrentSetStateImpl value,
          $Res Function(_$CurrentSetStateImpl) then) =
      __$$CurrentSetStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int reps, double weight, bool isResting, int restSecondsLeft});
}

/// @nodoc
class __$$CurrentSetStateImplCopyWithImpl<$Res>
    extends _$CurrentSetStateCopyWithImpl<$Res, _$CurrentSetStateImpl>
    implements _$$CurrentSetStateImplCopyWith<$Res> {
  __$$CurrentSetStateImplCopyWithImpl(
      _$CurrentSetStateImpl _value, $Res Function(_$CurrentSetStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reps = null,
    Object? weight = null,
    Object? isResting = null,
    Object? restSecondsLeft = null,
  }) {
    return _then(_$CurrentSetStateImpl(
      reps: null == reps
          ? _value.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      weight: null == weight
          ? _value.weight
          : weight // ignore: cast_nullable_to_non_nullable
              as double,
      isResting: null == isResting
          ? _value.isResting
          : isResting // ignore: cast_nullable_to_non_nullable
              as bool,
      restSecondsLeft: null == restSecondsLeft
          ? _value.restSecondsLeft
          : restSecondsLeft // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$CurrentSetStateImpl implements _CurrentSetState {
  const _$CurrentSetStateImpl(
      {required this.reps,
      required this.weight,
      this.isResting = false,
      this.restSecondsLeft = 0});

  @override
  final int reps;
  @override
  final double weight;
  @override
  @JsonKey()
  final bool isResting;
  @override
  @JsonKey()
  final int restSecondsLeft;

  @override
  String toString() {
    return 'CurrentSetState(reps: $reps, weight: $weight, isResting: $isResting, restSecondsLeft: $restSecondsLeft)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CurrentSetStateImpl &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.weight, weight) || other.weight == weight) &&
            (identical(other.isResting, isResting) ||
                other.isResting == isResting) &&
            (identical(other.restSecondsLeft, restSecondsLeft) ||
                other.restSecondsLeft == restSecondsLeft));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, reps, weight, isResting, restSecondsLeft);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CurrentSetStateImplCopyWith<_$CurrentSetStateImpl> get copyWith =>
      __$$CurrentSetStateImplCopyWithImpl<_$CurrentSetStateImpl>(
          this, _$identity);
}

abstract class _CurrentSetState implements CurrentSetState {
  const factory _CurrentSetState(
      {required final int reps,
      required final double weight,
      final bool isResting,
      final int restSecondsLeft}) = _$CurrentSetStateImpl;

  @override
  int get reps;
  @override
  double get weight;
  @override
  bool get isResting;
  @override
  int get restSecondsLeft;
  @override
  @JsonKey(ignore: true)
  _$$CurrentSetStateImplCopyWith<_$CurrentSetStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

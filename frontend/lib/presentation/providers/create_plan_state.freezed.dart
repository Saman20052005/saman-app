// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'create_plan_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$CreatePlanState {
  String get name => throw _privateConstructorUsedError;
  List<Exercise> get exercises => throw _privateConstructorUsedError;
  bool get isSaving => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $CreatePlanStateCopyWith<CreatePlanState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreatePlanStateCopyWith<$Res> {
  factory $CreatePlanStateCopyWith(
          CreatePlanState value, $Res Function(CreatePlanState) then) =
      _$CreatePlanStateCopyWithImpl<$Res, CreatePlanState>;
  @useResult
  $Res call(
      {String name, List<Exercise> exercises, bool isSaving, String? error});
}

/// @nodoc
class _$CreatePlanStateCopyWithImpl<$Res, $Val extends CreatePlanState>
    implements $CreatePlanStateCopyWith<$Res> {
  _$CreatePlanStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? exercises = null,
    Object? isSaving = null,
    Object? error = freezed,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      exercises: null == exercises
          ? _value.exercises
          : exercises // ignore: cast_nullable_to_non_nullable
              as List<Exercise>,
      isSaving: null == isSaving
          ? _value.isSaving
          : isSaving // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CreatePlanStateImplCopyWith<$Res>
    implements $CreatePlanStateCopyWith<$Res> {
  factory _$$CreatePlanStateImplCopyWith(_$CreatePlanStateImpl value,
          $Res Function(_$CreatePlanStateImpl) then) =
      __$$CreatePlanStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name, List<Exercise> exercises, bool isSaving, String? error});
}

/// @nodoc
class __$$CreatePlanStateImplCopyWithImpl<$Res>
    extends _$CreatePlanStateCopyWithImpl<$Res, _$CreatePlanStateImpl>
    implements _$$CreatePlanStateImplCopyWith<$Res> {
  __$$CreatePlanStateImplCopyWithImpl(
      _$CreatePlanStateImpl _value, $Res Function(_$CreatePlanStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? exercises = null,
    Object? isSaving = null,
    Object? error = freezed,
  }) {
    return _then(_$CreatePlanStateImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      exercises: null == exercises
          ? _value._exercises
          : exercises // ignore: cast_nullable_to_non_nullable
              as List<Exercise>,
      isSaving: null == isSaving
          ? _value.isSaving
          : isSaving // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$CreatePlanStateImpl implements _CreatePlanState {
  const _$CreatePlanStateImpl(
      {required this.name,
      required final List<Exercise> exercises,
      this.isSaving = false,
      this.error})
      : _exercises = exercises;

  @override
  final String name;
  final List<Exercise> _exercises;
  @override
  List<Exercise> get exercises {
    if (_exercises is EqualUnmodifiableListView) return _exercises;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exercises);
  }

  @override
  @JsonKey()
  final bool isSaving;
  @override
  final String? error;

  @override
  String toString() {
    return 'CreatePlanState(name: $name, exercises: $exercises, isSaving: $isSaving, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreatePlanStateImpl &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other._exercises, _exercises) &&
            (identical(other.isSaving, isSaving) ||
                other.isSaving == isSaving) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(runtimeType, name,
      const DeepCollectionEquality().hash(_exercises), isSaving, error);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CreatePlanStateImplCopyWith<_$CreatePlanStateImpl> get copyWith =>
      __$$CreatePlanStateImplCopyWithImpl<_$CreatePlanStateImpl>(
          this, _$identity);
}

abstract class _CreatePlanState implements CreatePlanState {
  const factory _CreatePlanState(
      {required final String name,
      required final List<Exercise> exercises,
      final bool isSaving,
      final String? error}) = _$CreatePlanStateImpl;

  @override
  String get name;
  @override
  List<Exercise> get exercises;
  @override
  bool get isSaving;
  @override
  String? get error;
  @override
  @JsonKey(ignore: true)
  _$$CreatePlanStateImplCopyWith<_$CreatePlanStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

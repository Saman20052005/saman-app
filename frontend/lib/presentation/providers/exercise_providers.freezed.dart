// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exercise_providers.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ExerciseFilterState {
  String get difficulty => throw _privateConstructorUsedError;
  String get search => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $ExerciseFilterStateCopyWith<ExerciseFilterState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseFilterStateCopyWith<$Res> {
  factory $ExerciseFilterStateCopyWith(
          ExerciseFilterState value, $Res Function(ExerciseFilterState) then) =
      _$ExerciseFilterStateCopyWithImpl<$Res, ExerciseFilterState>;
  @useResult
  $Res call({String difficulty, String search});
}

/// @nodoc
class _$ExerciseFilterStateCopyWithImpl<$Res, $Val extends ExerciseFilterState>
    implements $ExerciseFilterStateCopyWith<$Res> {
  _$ExerciseFilterStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? difficulty = null,
    Object? search = null,
  }) {
    return _then(_value.copyWith(
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as String,
      search: null == search
          ? _value.search
          : search // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseFilterStateImplCopyWith<$Res>
    implements $ExerciseFilterStateCopyWith<$Res> {
  factory _$$ExerciseFilterStateImplCopyWith(_$ExerciseFilterStateImpl value,
          $Res Function(_$ExerciseFilterStateImpl) then) =
      __$$ExerciseFilterStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String difficulty, String search});
}

/// @nodoc
class __$$ExerciseFilterStateImplCopyWithImpl<$Res>
    extends _$ExerciseFilterStateCopyWithImpl<$Res, _$ExerciseFilterStateImpl>
    implements _$$ExerciseFilterStateImplCopyWith<$Res> {
  __$$ExerciseFilterStateImplCopyWithImpl(_$ExerciseFilterStateImpl _value,
      $Res Function(_$ExerciseFilterStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? difficulty = null,
    Object? search = null,
  }) {
    return _then(_$ExerciseFilterStateImpl(
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as String,
      search: null == search
          ? _value.search
          : search // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ExerciseFilterStateImpl implements _ExerciseFilterState {
  const _$ExerciseFilterStateImpl({this.difficulty = 'all', this.search = ''});

  @override
  @JsonKey()
  final String difficulty;
  @override
  @JsonKey()
  final String search;

  @override
  String toString() {
    return 'ExerciseFilterState(difficulty: $difficulty, search: $search)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseFilterStateImpl &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            (identical(other.search, search) || other.search == search));
  }

  @override
  int get hashCode => Object.hash(runtimeType, difficulty, search);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseFilterStateImplCopyWith<_$ExerciseFilterStateImpl> get copyWith =>
      __$$ExerciseFilterStateImplCopyWithImpl<_$ExerciseFilterStateImpl>(
          this, _$identity);
}

abstract class _ExerciseFilterState implements ExerciseFilterState {
  const factory _ExerciseFilterState(
      {final String difficulty,
      final String search}) = _$ExerciseFilterStateImpl;

  @override
  String get difficulty;
  @override
  String get search;
  @override
  @JsonKey(ignore: true)
  _$$ExerciseFilterStateImplCopyWith<_$ExerciseFilterStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

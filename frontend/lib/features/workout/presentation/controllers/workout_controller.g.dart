// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$weeklyStreakHash() => r'aae51510b7a316fd01977df4eba26f21d390e34c';

/// See also [weeklyStreak].
@ProviderFor(weeklyStreak)
final weeklyStreakProvider = AutoDisposeFutureProvider<List<bool>>.internal(
  weeklyStreak,
  name: r'weeklyStreakProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$weeklyStreakHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef WeeklyStreakRef = AutoDisposeFutureProviderRef<List<bool>>;
String _$workoutControllerHash() => r'e69dc90cea45a110d583bf5d8f1225c60d3fa8ee';

/// See also [WorkoutController].
@ProviderFor(WorkoutController)
final workoutControllerProvider = AutoDisposeAsyncNotifierProvider<
    WorkoutController, List<WorkoutPlan>>.internal(
  WorkoutController.new,
  name: r'workoutControllerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$workoutControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WorkoutController = AutoDisposeAsyncNotifier<List<WorkoutPlan>>;
String _$workoutActionControllerHash() =>
    r'b1777058c2b4055f441f212be7a63fac5a9ceda9';

/// See also [WorkoutActionController].
@ProviderFor(WorkoutActionController)
final workoutActionControllerProvider =
    AutoDisposeAsyncNotifierProvider<WorkoutActionController, void>.internal(
  WorkoutActionController.new,
  name: r'workoutActionControllerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$workoutActionControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WorkoutActionController = AutoDisposeAsyncNotifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

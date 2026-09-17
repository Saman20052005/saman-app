// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_history_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$workoutHistoryHash() => r'c12a7cad7ac326ab96eb09c283748222ec41f0a9';

/// See also [workoutHistory].
@ProviderFor(workoutHistory)
final workoutHistoryProvider =
    AutoDisposeFutureProvider<List<WorkoutSession>>.internal(
  workoutHistory,
  name: r'workoutHistoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$workoutHistoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef WorkoutHistoryRef = AutoDisposeFutureProviderRef<List<WorkoutSession>>;
String _$activeSessionSaverHash() =>
    r'fce6792182481e2a80fa2ee0b1f32d9ca3bf7010';

/// See also [ActiveSessionSaver].
@ProviderFor(ActiveSessionSaver)
final activeSessionSaverProvider =
    AutoDisposeNotifierProvider<ActiveSessionSaver, AsyncValue<void>>.internal(
  ActiveSessionSaver.new,
  name: r'activeSessionSaverProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$activeSessionSaverHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ActiveSessionSaver = AutoDisposeNotifier<AsyncValue<void>>;
String _$lastWeightProviderHash() =>
    r'dd31eb7875cababec6afe7a01f0b4cf36ac8220b';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$LastWeightProvider
    extends BuildlessAutoDisposeNotifier<double> {
  late final String exerciseId;

  double build(
    String exerciseId,
  );
}

/// See also [LastWeightProvider].
@ProviderFor(LastWeightProvider)
const lastWeightProviderProvider = LastWeightProviderFamily();

/// See also [LastWeightProvider].
class LastWeightProviderFamily extends Family<double> {
  /// See also [LastWeightProvider].
  const LastWeightProviderFamily();

  /// See also [LastWeightProvider].
  LastWeightProviderProvider call(
    String exerciseId,
  ) {
    return LastWeightProviderProvider(
      exerciseId,
    );
  }

  @override
  LastWeightProviderProvider getProviderOverride(
    covariant LastWeightProviderProvider provider,
  ) {
    return call(
      provider.exerciseId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'lastWeightProviderProvider';
}

/// See also [LastWeightProvider].
class LastWeightProviderProvider
    extends AutoDisposeNotifierProviderImpl<LastWeightProvider, double> {
  /// See also [LastWeightProvider].
  LastWeightProviderProvider(
    String exerciseId,
  ) : this._internal(
          () => LastWeightProvider()..exerciseId = exerciseId,
          from: lastWeightProviderProvider,
          name: r'lastWeightProviderProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$lastWeightProviderHash,
          dependencies: LastWeightProviderFamily._dependencies,
          allTransitiveDependencies:
              LastWeightProviderFamily._allTransitiveDependencies,
          exerciseId: exerciseId,
        );

  LastWeightProviderProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.exerciseId,
  }) : super.internal();

  final String exerciseId;

  @override
  double runNotifierBuild(
    covariant LastWeightProvider notifier,
  ) {
    return notifier.build(
      exerciseId,
    );
  }

  @override
  Override overrideWith(LastWeightProvider Function() create) {
    return ProviderOverride(
      origin: this,
      override: LastWeightProviderProvider._internal(
        () => create()..exerciseId = exerciseId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        exerciseId: exerciseId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<LastWeightProvider, double>
      createElement() {
    return _LastWeightProviderProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LastWeightProviderProvider &&
        other.exerciseId == exerciseId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, exerciseId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin LastWeightProviderRef on AutoDisposeNotifierProviderRef<double> {
  /// The parameter `exerciseId` of this provider.
  String get exerciseId;
}

class _LastWeightProviderProviderElement
    extends AutoDisposeNotifierProviderElement<LastWeightProvider, double>
    with LastWeightProviderRef {
  _LastWeightProviderProviderElement(super.provider);

  @override
  String get exerciseId => (origin as LastWeightProviderProvider).exerciseId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

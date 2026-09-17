// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$lastWeightNotifierHash() =>
    r'8e22dac85214a2d57bcbdf8f59d0fddab2f846ab';

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

abstract class _$LastWeightNotifier
    extends BuildlessAutoDisposeNotifier<double> {
  late final String exerciseId;

  double build(
    String exerciseId,
  );
}

/// See also [LastWeightNotifier].
@ProviderFor(LastWeightNotifier)
const lastWeightNotifierProvider = LastWeightNotifierFamily();

/// See also [LastWeightNotifier].
class LastWeightNotifierFamily extends Family<double> {
  /// See also [LastWeightNotifier].
  const LastWeightNotifierFamily();

  /// See also [LastWeightNotifier].
  LastWeightNotifierProvider call(
    String exerciseId,
  ) {
    return LastWeightNotifierProvider(
      exerciseId,
    );
  }

  @override
  LastWeightNotifierProvider getProviderOverride(
    covariant LastWeightNotifierProvider provider,
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
  String? get name => r'lastWeightNotifierProvider';
}

/// See also [LastWeightNotifier].
class LastWeightNotifierProvider
    extends AutoDisposeNotifierProviderImpl<LastWeightNotifier, double> {
  /// See also [LastWeightNotifier].
  LastWeightNotifierProvider(
    String exerciseId,
  ) : this._internal(
          () => LastWeightNotifier()..exerciseId = exerciseId,
          from: lastWeightNotifierProvider,
          name: r'lastWeightNotifierProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$lastWeightNotifierHash,
          dependencies: LastWeightNotifierFamily._dependencies,
          allTransitiveDependencies:
              LastWeightNotifierFamily._allTransitiveDependencies,
          exerciseId: exerciseId,
        );

  LastWeightNotifierProvider._internal(
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
    covariant LastWeightNotifier notifier,
  ) {
    return notifier.build(
      exerciseId,
    );
  }

  @override
  Override overrideWith(LastWeightNotifier Function() create) {
    return ProviderOverride(
      origin: this,
      override: LastWeightNotifierProvider._internal(
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
  AutoDisposeNotifierProviderElement<LastWeightNotifier, double>
      createElement() {
    return _LastWeightNotifierProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LastWeightNotifierProvider &&
        other.exerciseId == exerciseId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, exerciseId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin LastWeightNotifierRef on AutoDisposeNotifierProviderRef<double> {
  /// The parameter `exerciseId` of this provider.
  String get exerciseId;
}

class _LastWeightNotifierProviderElement
    extends AutoDisposeNotifierProviderElement<LastWeightNotifier, double>
    with LastWeightNotifierRef {
  _LastWeightNotifierProviderElement(super.provider);

  @override
  String get exerciseId => (origin as LastWeightNotifierProvider).exerciseId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

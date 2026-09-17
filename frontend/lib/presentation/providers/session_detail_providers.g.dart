// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_detail_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sessionDetailHash() => r'849f10fbb8ffa97945c524060818788d753901cf';

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

/// See also [sessionDetail].
@ProviderFor(sessionDetail)
const sessionDetailProvider = SessionDetailFamily();

/// See also [sessionDetail].
class SessionDetailFamily extends Family<AsyncValue<WorkoutSession>> {
  /// See also [sessionDetail].
  const SessionDetailFamily();

  /// See also [sessionDetail].
  SessionDetailProvider call(
    String sessionId,
  ) {
    return SessionDetailProvider(
      sessionId,
    );
  }

  @override
  SessionDetailProvider getProviderOverride(
    covariant SessionDetailProvider provider,
  ) {
    return call(
      provider.sessionId,
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
  String? get name => r'sessionDetailProvider';
}

/// See also [sessionDetail].
class SessionDetailProvider extends AutoDisposeFutureProvider<WorkoutSession> {
  /// See also [sessionDetail].
  SessionDetailProvider(
    String sessionId,
  ) : this._internal(
          (ref) => sessionDetail(
            ref as SessionDetailRef,
            sessionId,
          ),
          from: sessionDetailProvider,
          name: r'sessionDetailProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sessionDetailHash,
          dependencies: SessionDetailFamily._dependencies,
          allTransitiveDependencies:
              SessionDetailFamily._allTransitiveDependencies,
          sessionId: sessionId,
        );

  SessionDetailProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.sessionId,
  }) : super.internal();

  final String sessionId;

  @override
  Override overrideWith(
    FutureOr<WorkoutSession> Function(SessionDetailRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SessionDetailProvider._internal(
        (ref) => create(ref as SessionDetailRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        sessionId: sessionId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<WorkoutSession> createElement() {
    return _SessionDetailProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SessionDetailProvider && other.sessionId == sessionId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, sessionId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin SessionDetailRef on AutoDisposeFutureProviderRef<WorkoutSession> {
  /// The parameter `sessionId` of this provider.
  String get sessionId;
}

class _SessionDetailProviderElement
    extends AutoDisposeFutureProviderElement<WorkoutSession>
    with SessionDetailRef {
  _SessionDetailProviderElement(super.provider);

  @override
  String get sessionId => (origin as SessionDetailProvider).sessionId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

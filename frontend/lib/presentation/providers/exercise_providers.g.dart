// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$exercisesByMuscleHash() => r'4c6ec5d4e1f9cb64ae84be73137c97760b648d97';

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

/// See also [exercisesByMuscle].
@ProviderFor(exercisesByMuscle)
const exercisesByMuscleProvider = ExercisesByMuscleFamily();

/// See also [exercisesByMuscle].
class ExercisesByMuscleFamily extends Family<AsyncValue<List<Exercise>>> {
  /// See also [exercisesByMuscle].
  const ExercisesByMuscleFamily();

  /// See also [exercisesByMuscle].
  ExercisesByMuscleProvider call({
    required String muscleGroupSlug,
    String difficulty = 'all',
    String search = '',
  }) {
    return ExercisesByMuscleProvider(
      muscleGroupSlug: muscleGroupSlug,
      difficulty: difficulty,
      search: search,
    );
  }

  @override
  ExercisesByMuscleProvider getProviderOverride(
    covariant ExercisesByMuscleProvider provider,
  ) {
    return call(
      muscleGroupSlug: provider.muscleGroupSlug,
      difficulty: provider.difficulty,
      search: provider.search,
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
  String? get name => r'exercisesByMuscleProvider';
}

/// See also [exercisesByMuscle].
class ExercisesByMuscleProvider
    extends AutoDisposeFutureProvider<List<Exercise>> {
  /// See also [exercisesByMuscle].
  ExercisesByMuscleProvider({
    required String muscleGroupSlug,
    String difficulty = 'all',
    String search = '',
  }) : this._internal(
          (ref) => exercisesByMuscle(
            ref as ExercisesByMuscleRef,
            muscleGroupSlug: muscleGroupSlug,
            difficulty: difficulty,
            search: search,
          ),
          from: exercisesByMuscleProvider,
          name: r'exercisesByMuscleProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$exercisesByMuscleHash,
          dependencies: ExercisesByMuscleFamily._dependencies,
          allTransitiveDependencies:
              ExercisesByMuscleFamily._allTransitiveDependencies,
          muscleGroupSlug: muscleGroupSlug,
          difficulty: difficulty,
          search: search,
        );

  ExercisesByMuscleProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.muscleGroupSlug,
    required this.difficulty,
    required this.search,
  }) : super.internal();

  final String muscleGroupSlug;
  final String difficulty;
  final String search;

  @override
  Override overrideWith(
    FutureOr<List<Exercise>> Function(ExercisesByMuscleRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ExercisesByMuscleProvider._internal(
        (ref) => create(ref as ExercisesByMuscleRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        muscleGroupSlug: muscleGroupSlug,
        difficulty: difficulty,
        search: search,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<Exercise>> createElement() {
    return _ExercisesByMuscleProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ExercisesByMuscleProvider &&
        other.muscleGroupSlug == muscleGroupSlug &&
        other.difficulty == difficulty &&
        other.search == search;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, muscleGroupSlug.hashCode);
    hash = _SystemHash.combine(hash, difficulty.hashCode);
    hash = _SystemHash.combine(hash, search.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ExercisesByMuscleRef on AutoDisposeFutureProviderRef<List<Exercise>> {
  /// The parameter `muscleGroupSlug` of this provider.
  String get muscleGroupSlug;

  /// The parameter `difficulty` of this provider.
  String get difficulty;

  /// The parameter `search` of this provider.
  String get search;
}

class _ExercisesByMuscleProviderElement
    extends AutoDisposeFutureProviderElement<List<Exercise>>
    with ExercisesByMuscleRef {
  _ExercisesByMuscleProviderElement(super.provider);

  @override
  String get muscleGroupSlug =>
      (origin as ExercisesByMuscleProvider).muscleGroupSlug;
  @override
  String get difficulty => (origin as ExercisesByMuscleProvider).difficulty;
  @override
  String get search => (origin as ExercisesByMuscleProvider).search;
}

String _$exerciseRepositoryHash() =>
    r'9912f72d7293b5f5d450deacddbb000a7b83ec9c';

/// See also [exerciseRepository].
@ProviderFor(exerciseRepository)
final exerciseRepositoryProvider =
    AutoDisposeProvider<ExerciseRepository>.internal(
  exerciseRepository,
  name: r'exerciseRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$exerciseRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ExerciseRepositoryRef = AutoDisposeProviderRef<ExerciseRepository>;
String _$exerciseFiltersHash() => r'05a071b13a160c940eea77f7766f2ac570ecde02';

/// See also [ExerciseFilters].
@ProviderFor(ExerciseFilters)
final exerciseFiltersProvider =
    AutoDisposeNotifierProvider<ExerciseFilters, ExerciseFilterState>.internal(
  ExerciseFilters.new,
  name: r'exerciseFiltersProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$exerciseFiltersHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ExerciseFilters = AutoDisposeNotifier<ExerciseFilterState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

/// Supported Computer Vision exercise modules for rep counting and form analysis.
enum CvExerciseModule {
  latPulldown,
  pullUp,
  squat,
  pushUp,
  overheadPress,
  bicepCurl,
}

/// Canonical registry mapping exercise IDs and slugs to CV analysis modules.
///
/// Only exercises listed in [_exerciseSlugMap] are eligible for CV tracking;
/// display names and generic `cvSupported` flags are never trusted directly.
class WorkoutCvExerciseRegistry {
  const WorkoutCvExerciseRegistry._();

  static const Map<String, CvExerciseModule> _exerciseSlugMap = {
    'lat-pulldown': CvExerciseModule.latPulldown,
    'pull-up': CvExerciseModule.pullUp,
    'barbell-back-squat': CvExerciseModule.squat,
    'goblet-squat': CvExerciseModule.squat,
    'push-up': CvExerciseModule.pushUp,
    'barbell-overhead-press': CvExerciseModule.overheadPress,
    'db-shoulder-press': CvExerciseModule.overheadPress,
    'dumbbell-shoulder-press': CvExerciseModule.overheadPress,
    'db-bicep-curl': CvExerciseModule.bicepCurl,
    'dumbbell-bicep-curl': CvExerciseModule.bicepCurl,
    'ez-bar-curl': CvExerciseModule.bicepCurl,
    'hammer-curl': CvExerciseModule.bicepCurl,
  };

  /// Resolves the [CvExerciseModule] for [id] and/or [slug], or null if unsupported.
  static CvExerciseModule? resolveModule({
    String id = '',
    String slug = '',
  }) {
    final normalizedSlug = slug.toLowerCase().trim();
    if (normalizedSlug.isNotEmpty) {
      final fromSlug = _exerciseSlugMap[normalizedSlug];
      if (fromSlug != null) return fromSlug;
    }

    final normalizedId = id.toLowerCase().trim();
    if (normalizedId.isNotEmpty) {
      return _exerciseSlugMap[normalizedId];
    }

    return null;
  }

  /// Returns true iff [id] or [slug] maps to a supported CV exercise module.
  static bool isSupported({
    required String id,
    required String slug,
  }) {
    return resolveModule(id: id, slug: slug) != null;
  }
}

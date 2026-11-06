import 'community_post.dart';

enum AttachmentType { workout, meal }

/// Immutable snapshot of an attached user activity for Community posts (R07).
/// Strictly adheres to privacy defaults: weight load and macros are OFF by default.
class PostAttachmentSnapshot {
  final Map<String, dynamic>? sharedSnapshot;
  final String? previewHash;
  final AttachmentType type;
  final String id;
  final String title;
  final String dateFormatted;
  final String category;
  
  // Privacy controlled flags
  final bool includeDuration;
  final bool includeExercisesOrFoods;
  final bool includeLoadOrMacros;

  // Values (only present if respective flag is enabled or public metadata)
  final String? durationFormatted;
  final int? exerciseCount;
  final int? setCount;
  final String? loadSummaryFormatted;
  final int? calories;
  final String? macrosSummaryFormatted;
  final List<ExerciseThumbnailPreview> exercises;
  final String? imageUrl;

  const PostAttachmentSnapshot({
    this.sharedSnapshot,
    this.previewHash,
    required this.type,
    required this.id,
    required this.title,
    required this.dateFormatted,
    this.category = 'Saman Kinetic',
    this.includeDuration = true,
    this.includeExercisesOrFoods = true,
    this.includeLoadOrMacros = false, // Privacy default: OFF
    this.durationFormatted,
    this.exerciseCount,
    this.setCount,
    this.loadSummaryFormatted,
    this.calories,
    this.macrosSummaryFormatted,
    this.exercises = const [],
    this.imageUrl,
  });

  factory PostAttachmentSnapshot.fromPreview(Map<String, dynamic> value) {
    final snapshot = Map<String, dynamic>.from(value['snapshot'] as Map);
    return PostAttachmentSnapshot(type: snapshot['kind'] == 'workout' ? AttachmentType.workout : AttachmentType.meal,
      id: value['source_id'] as String? ?? '', title: snapshot['title'] as String,
      dateFormatted: snapshot['date'] as String, category: snapshot['category'] as String,
      includeDuration: snapshot.containsKey('duration_minutes'),
      includeExercisesOrFoods: snapshot.containsKey('exercises') || snapshot.containsKey('foods'),
      includeLoadOrMacros: snapshot.containsKey('load_kg') || snapshot.containsKey('set_count') || snapshot.containsKey('calories'),
      sharedSnapshot: Map.unmodifiable(snapshot), previewHash: value['preview_hash'] as String?);
  }

  List<MapEntry<String,String>> get displayFields {
    final values = sharedSnapshot;
    if (values == null) return const [];
    return [for (final key in ['duration_minutes','exercise_count','exercises','foods','set_count','load_kg','calories','protein_grams','carbs_grams','fat_grams'])
      if (values.containsKey(key)) MapEntry(key, values[key] is List
        ? (values[key] as List).map((x) => (x as Map)['name']).join(', ') : values[key].toString())];
  }

  Map<String, dynamic> publicationSelection() {
    if (previewHash == null || id.isEmpty) throw UnsupportedError('community_attachment_review');
    return {'source_id':id, 'preview_hash':previewHash, 'include_duration':includeDuration,
      'include_exercises_or_foods':includeExercisesOrFoods, 'include_load_or_macros':includeLoadOrMacros};
  }

  PostAttachmentSnapshot sanitize() {
    return PostAttachmentSnapshot(
      sharedSnapshot: sharedSnapshot,
      previewHash: previewHash,
      type: type,
      id: id,
      title: title,
      dateFormatted: dateFormatted,
      category: category,
      includeDuration: includeDuration,
      includeExercisesOrFoods: includeExercisesOrFoods,
      includeLoadOrMacros: includeLoadOrMacros,
      durationFormatted: includeDuration ? durationFormatted : null,
      exerciseCount: includeExercisesOrFoods ? exerciseCount : null,
      setCount: includeLoadOrMacros ? setCount : null,
      loadSummaryFormatted: includeLoadOrMacros ? loadSummaryFormatted : null,
      calories: includeLoadOrMacros ? calories : null,
      macrosSummaryFormatted: includeLoadOrMacros ? macrosSummaryFormatted : null,
      exercises: includeExercisesOrFoods
          ? List<ExerciseThumbnailPreview>.unmodifiable(
              List.from(exercises),
            )
          : const [],
      imageUrl: imageUrl,
    );
  }

  PostAttachmentSnapshot copyWith({
    AttachmentType? type,
    String? id,
    String? title,
    String? dateFormatted,
    String? category,
    bool? includeDuration,
    bool? includeExercisesOrFoods,
    bool? includeLoadOrMacros,
    String? durationFormatted,
    int? exerciseCount,
    int? setCount,
    String? loadSummaryFormatted,
    int? calories,
    String? macrosSummaryFormatted,
    List<ExerciseThumbnailPreview>? exercises,
    String? imageUrl,
  }) {
    return PostAttachmentSnapshot(
      sharedSnapshot: sharedSnapshot,
      previewHash: previewHash,
      type: type ?? this.type,
      id: id ?? this.id,
      title: title ?? this.title,
      dateFormatted: dateFormatted ?? this.dateFormatted,
      category: category ?? this.category,
      includeDuration: includeDuration ?? this.includeDuration,
      includeExercisesOrFoods:
          includeExercisesOrFoods ?? this.includeExercisesOrFoods,
      includeLoadOrMacros: includeLoadOrMacros ?? this.includeLoadOrMacros,
      durationFormatted: durationFormatted ?? this.durationFormatted,
      exerciseCount: exerciseCount ?? this.exerciseCount,
      setCount: setCount ?? this.setCount,
      loadSummaryFormatted: loadSummaryFormatted ?? this.loadSummaryFormatted,
      calories: calories ?? this.calories,
      macrosSummaryFormatted:
          macrosSummaryFormatted ?? this.macrosSummaryFormatted,
      exercises: exercises ?? this.exercises,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

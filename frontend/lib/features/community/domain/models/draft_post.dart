import 'post_attachment_snapshot.dart';

/// Draft post model for community content composition and recovery (JCOM-03 & JCOM-04).
/// Separated by user ID to prevent data leakage across accounts.
class DraftPost {
  final String id;
  final String userId;
  final String caption;
  final List<String> mediaUrls;
  final String aspectRatio;
  final int rotation;
  final double brightness;
  final double contrast;
  final String audience;
  final String topic;
  final bool allowComments;
  final PostAttachmentSnapshot? attachment;
  final String? questionTitle;
  final String? questionDetails;
  final DateTime updatedAt;

  const DraftPost({
    required this.id,
    this.userId = 'current_user',
    this.caption = '',
    this.mediaUrls = const [],
    this.aspectRatio = '1:1',
    this.rotation = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.audience = 'Công khai',
    this.topic = '#BữaĂn',
    this.allowComments = true,
    this.attachment,
    this.questionTitle,
    this.questionDetails,
    required this.updatedAt,
  });

  bool get isQuestionDraft => questionTitle != null && questionTitle!.isNotEmpty;

  DraftPost copyWith({
    String? id,
    String? userId,
    String? caption,
    List<String>? mediaUrls,
    String? aspectRatio,
    int? rotation,
    double? brightness,
    double? contrast,
    String? audience,
    String? topic,
    bool? allowComments,
    PostAttachmentSnapshot? attachment,
    bool clearAttachment = false,
    String? questionTitle,
    String? questionDetails,
    DateTime? updatedAt,
  }) {
    return DraftPost(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      caption: caption ?? this.caption,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      rotation: rotation ?? this.rotation,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      audience: audience ?? this.audience,
      topic: topic ?? this.topic,
      allowComments: allowComments ?? this.allowComments,
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      questionTitle: questionTitle ?? this.questionTitle,
      questionDetails: questionDetails ?? this.questionDetails,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'caption': caption,
      'media_urls': mediaUrls,
      'aspect_ratio': aspectRatio,
      'rotation': rotation,
      'brightness': brightness,
      'contrast': contrast,
      'audience': audience,
      'topic': topic,
      'allow_comments': allowComments,
      'attachment': _attachmentToJson(attachment),
      if (questionTitle != null) 'question_title': questionTitle,
      if (questionDetails != null) 'question_details': questionDetails,
    };
  }

  factory DraftPost.fromJson(Map<String, dynamic> json) {
    final rawAttachment = json['attachment'];
    return DraftPost(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? 'current_user',
      caption: json['caption'] as String? ?? '',
      mediaUrls: (json['media_urls'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      aspectRatio: json['aspect_ratio'] as String? ?? '1:1',
      rotation: (json['rotation'] as num?)?.toInt() ?? 0,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      audience: json['audience'] as String? ?? 'Công khai',
      topic: json['topic'] as String? ?? '#BữaĂn',
      allowComments: json['allow_comments'] as bool? ?? true,
      attachment: rawAttachment is Map
          ? _attachmentFromJson(Map<String, dynamic>.from(rawAttachment))
          : null,
      questionTitle: json['question_title'] as String?,
      questionDetails: json['question_details'] as String?,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static Map<String, dynamic>? _attachmentToJson(
    PostAttachmentSnapshot? att,
  ) {
    if (att == null) return null;
    return {
      'type': att.type.name,
      'id': att.id,
      'title': att.title,
      'date_formatted': att.dateFormatted,
      'category': att.category,
      'include_duration': att.includeDuration,
      'include_exercises_or_foods': att.includeExercisesOrFoods,
      'include_load_or_macros': att.includeLoadOrMacros,
      if (att.durationFormatted != null)
        'duration_formatted': att.durationFormatted,
      if (att.exerciseCount != null) 'exercise_count': att.exerciseCount,
      if (att.setCount != null) 'set_count': att.setCount,
      if (att.loadSummaryFormatted != null)
        'load_summary_formatted': att.loadSummaryFormatted,
      if (att.calories != null) 'calories': att.calories,
      if (att.macrosSummaryFormatted != null)
        'macros_summary_formatted': att.macrosSummaryFormatted,
      if (att.imageUrl != null) 'image_url': att.imageUrl,
      if (att.previewHash != null) 'preview_hash': att.previewHash,
      if (att.sharedSnapshot != null) 'shared_snapshot': att.sharedSnapshot,
    };
  }

  static PostAttachmentSnapshot _attachmentFromJson(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'workout';
    final rawSnapshot = map['shared_snapshot'];
    return PostAttachmentSnapshot(
      type: typeStr == 'meal' ? AttachmentType.meal : AttachmentType.workout,
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      dateFormatted: map['date_formatted'] as String? ?? '',
      category: map['category'] as String? ?? 'Saman Kinetic',
      includeDuration: map['include_duration'] as bool? ?? true,
      includeExercisesOrFoods:
          map['include_exercises_or_foods'] as bool? ?? true,
      includeLoadOrMacros: map['include_load_or_macros'] as bool? ?? false,
      durationFormatted: map['duration_formatted'] as String?,
      exerciseCount: (map['exercise_count'] as num?)?.toInt(),
      setCount: (map['set_count'] as num?)?.toInt(),
      loadSummaryFormatted: map['load_summary_formatted'] as String?,
      calories: (map['calories'] as num?)?.toInt(),
      macrosSummaryFormatted: map['macros_summary_formatted'] as String?,
      imageUrl: map['image_url'] as String?,
      previewHash: map['preview_hash'] as String?,
      sharedSnapshot: rawSnapshot is Map
          ? Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(rawSnapshot),
            )
          : null,
    );
  }
}

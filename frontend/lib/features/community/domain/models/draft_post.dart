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
}

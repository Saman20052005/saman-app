import 'community_author.dart';
import 'post_attachment_snapshot.dart';
import 'community_comment.dart';

enum CommunityPostType {
  text,
  photo,
  workout,
  meal,
  qa,
}

enum CommunityFeedFilter {
  forYou,
  following,
  qa,
}

class ExerciseThumbnailPreview {
  final String title;
  final String? imageUrl;

  const ExerciseThumbnailPreview({
    required this.title,
    this.imageUrl,
  });
}

class PostWorkoutAttachment {
  final String title;
  final String category;
  final String durationFormatted;
  final int exerciseCount;
  final int setCount;
  final List<ExerciseThumbnailPreview> exercises;

  const PostWorkoutAttachment({
    required this.title,
    this.category = 'Saman Kinetic',
    required this.durationFormatted,
    required this.exerciseCount,
    required this.setCount,
    this.exercises = const [],
  });

  String get summaryFormatted =>
      '$durationFormatted • $exerciseCount bài tập • $setCount hiệp tập';
}

class PostNutritionInfo {
  final int calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final String? badgeLabel;
  final String? proTip;

  const PostNutritionInfo({
    required this.calories,
    required this.proteinGrams,
    this.carbsGrams = 0,
    this.fatGrams = 0,
    this.badgeLabel,
    this.proTip,
  });

  String get defaultBadge =>
      badgeLabel ?? '$calories kcal • ${proteinGrams.toStringAsFixed(0)}g Protein';
}

class PostQaInfo {
  final String question;
  final String categoryTag;
  final String? details;
  final int respondentCount;
  final String respondentsSummary;
  final List<String> respondentInitials;

  const PostQaInfo({
    required this.question,
    required this.categoryTag,
    this.details,
    this.respondentCount = 0,
    required this.respondentsSummary,
    this.respondentInitials = const [],
  });
  PostQaInfo withAnswerCount(int count) => PostQaInfo(question: question,
      categoryTag: categoryTag, details: details, respondentCount: count,
      respondentsSummary: '$count', respondentInitials: respondentInitials);

}

class CommunityPost {
  final String privacy;
  final String topic;
  final String id;
  final CommunityPostType type;
  final CommunityAuthor author;
  final String timeAgo;
  final String caption;
  final List<String> photoUrls;
  final PostNutritionInfo? nutritionInfo;
  final PostWorkoutAttachment? workoutAttachment;
  final PostQaInfo? qaInfo;
  final PostAttachmentSnapshot? activitySnapshot;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isBookmarked;
  final List<String> likedByNames;
  final String likedBySummary;
  final List<CommunityComment> comments;

  const CommunityPost({
    this.privacy = 'public',
    this.topic = '',
    required this.id,
    required this.type,
    required this.author,
    required this.timeAgo,
    required this.caption,
    this.photoUrls = const [],
    this.nutritionInfo,
    this.workoutAttachment,
    this.qaInfo,
    this.activitySnapshot,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.isBookmarked = false,
    this.likedByNames = const [],
    this.likedBySummary = '',
    this.comments = const [],
  });

  CommunityPost copyWith({
    String? privacy,
    String? topic,
    String? id,
    CommunityPostType? type,
    CommunityAuthor? author,
    String? timeAgo,
    String? caption,
    List<String>? photoUrls,
    PostNutritionInfo? nutritionInfo,
    PostWorkoutAttachment? workoutAttachment,
    PostQaInfo? qaInfo,
    PostAttachmentSnapshot? activitySnapshot,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isBookmarked,
    List<String>? likedByNames,
    String? likedBySummary,
    List<CommunityComment>? comments,
  }) {
    return CommunityPost(
      privacy: privacy ?? this.privacy, topic: topic ?? this.topic,
      id: id ?? this.id,
      type: type ?? this.type,
      author: author ?? this.author,
      timeAgo: timeAgo ?? this.timeAgo,
      caption: caption ?? this.caption,
      photoUrls: photoUrls ?? this.photoUrls,
      nutritionInfo: nutritionInfo ?? this.nutritionInfo,
      workoutAttachment: workoutAttachment ?? this.workoutAttachment,
      qaInfo: qaInfo ?? this.qaInfo,
      activitySnapshot: activitySnapshot ?? this.activitySnapshot,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      likedByNames: likedByNames ?? this.likedByNames,
      likedBySummary: likedBySummary ?? this.likedBySummary,
      comments: comments ?? this.comments,
    );
  }
}

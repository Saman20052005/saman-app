import 'community_author.dart';

class CommunityStory {
  final String id;
  final String userId;
  final String mediaType; // 'photo' | 'video' | 'text'
  final String? mediaUrl;
  final String caption;
  final String? backgroundColor;
  final String privacy; // 'public' | 'followers_only'
  final int viewCount;
  final bool isViewed;
  final String timeAgo;
  final DateTime createdAt;
  final DateTime expiresAt;

  const CommunityStory({
    required this.id,
    required this.userId,
    required this.mediaType,
    this.mediaUrl,
    this.caption = '',
    this.backgroundColor,
    this.privacy = 'public',
    this.viewCount = 0,
    this.isViewed = false,
    this.timeAgo = 'Vừa xong',
    required this.createdAt,
    required this.expiresAt,
  });

  CommunityStory copyWith({
    String? id,
    String? userId,
    String? mediaType,
    String? mediaUrl,
    String? caption,
    String? backgroundColor,
    String? privacy,
    int? viewCount,
    bool? isViewed,
    String? timeAgo,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return CommunityStory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      mediaType: mediaType ?? this.mediaType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      caption: caption ?? this.caption,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      privacy: privacy ?? this.privacy,
      viewCount: viewCount ?? this.viewCount,
      isViewed: isViewed ?? this.isViewed,
      timeAgo: timeAgo ?? this.timeAgo,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class CommunityStoryAuthorGroup {
  final CommunityAuthor author;
  final List<CommunityStory> stories;
  final bool hasUnviewed;
  final bool isSelf;
  final DateTime? latestCreatedAt;

  const CommunityStoryAuthorGroup({
    required this.author,
    this.stories = const [],
    this.hasUnviewed = false,
    this.isSelf = false,
    this.latestCreatedAt,
  });

  CommunityStoryAuthorGroup copyWith({
    CommunityAuthor? author,
    List<CommunityStory>? stories,
    bool? hasUnviewed,
    bool? isSelf,
    DateTime? latestCreatedAt,
  }) {
    return CommunityStoryAuthorGroup(
      author: author ?? this.author,
      stories: stories ?? this.stories,
      hasUnviewed: hasUnviewed ?? this.hasUnviewed,
      isSelf: isSelf ?? this.isSelf,
      latestCreatedAt: latestCreatedAt ?? this.latestCreatedAt,
    );
  }
}

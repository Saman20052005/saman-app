import 'community_author.dart';

class CommunityVisualGridItem {
  final String id;
  final String? postId;
  final String imageUrl;
  final int likeCount;
  final bool hasMultiPhoto;
  final bool hasVideo;
  final String? altText;

  const CommunityVisualGridItem({
    required this.id,
    this.postId,
    required this.imageUrl,
    this.likeCount = 0,
    this.hasMultiPhoto = false,
    this.hasVideo = false,
    this.altText,
  });

  String get formattedLikes {
    if (likeCount >= 1000) {
      final k = (likeCount / 1000).toStringAsFixed(1);
      return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
    }
    return '$likeCount';
  }
}

class CommunityTrendingTopic {
  final String id;
  final String hashtag;
  final String postCountFormatted;
  final String growthPercent;
  final bool isStable;
  final String iconName;

  const CommunityTrendingTopic({
    required this.id,
    required this.hashtag,
    required this.postCountFormatted,
    required this.growthPercent,
    this.isStable = false,
    required this.iconName,
  });
}

class CommunityDiscoverData {
  final List<String> topicChips;
  final String activeTopic;
  final List<CommunityVisualGridItem> gridItems;
  final List<CommunityTrendingTopic> trendingTopics;
  final List<CommunityAuthor> recommendedCreators;

  const CommunityDiscoverData({
    this.topicChips = const [
      'all',
      'workout',
      'meal',
      'recipe',
      'qna',
      'journey',
    ],
    this.activeTopic = 'all',
    this.gridItems = const [],
    this.trendingTopics = const [],
    this.recommendedCreators = const [],
  });
}

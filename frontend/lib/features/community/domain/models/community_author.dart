/// Domain model representing a member author in Saman Community.
class CommunityAuthor {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isVerified;
  final String? title;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final bool isFollowing;
  final String? handle;
  final String? bio;
  final List<String> interestTopics;
  final int workoutPostCount;
  final int mealPostCount;
  final int totalLikesReceived;

  const CommunityAuthor({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isVerified = false,
    this.title,
    this.followerCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
    this.isFollowing = false,
    this.handle,
    this.bio,
    this.interestTopics = const [],
    this.workoutPostCount = 0,
    this.mealPostCount = 0,
    this.totalLikesReceived = 0,
  });

  CommunityAuthor copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    bool? isVerified,
    String? title,
    int? followerCount,
    int? followingCount,
    int? postCount,
    bool? isFollowing,
    String? handle,
    String? bio,
    List<String>? interestTopics,
    int? workoutPostCount,
    int? mealPostCount,
    int? totalLikesReceived,
  }) {
    return CommunityAuthor(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified ?? this.isVerified,
      title: title ?? this.title,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      postCount: postCount ?? this.postCount,
      isFollowing: isFollowing ?? this.isFollowing,
      handle: handle ?? this.handle,
      bio: bio ?? this.bio,
      interestTopics: interestTopics ?? this.interestTopics,
      workoutPostCount: workoutPostCount ?? this.workoutPostCount,
      mealPostCount: mealPostCount ?? this.mealPostCount,
      totalLikesReceived: totalLikesReceived ?? this.totalLikesReceived,
    );
  }
}

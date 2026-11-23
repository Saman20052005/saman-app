import '../../domain/models/community_author.dart';
import '../../domain/models/community_comment.dart';
import '../../domain/models/community_discover_item.dart';
import '../../domain/models/community_notification.dart';
import '../../domain/models/community_post.dart';
import '../../domain/models/draft_post.dart';
import '../../domain/models/post_attachment_snapshot.dart';
import '../../domain/models/question_answer.dart';
import '../../domain/models/community_settings.dart';
import '../../domain/models/community_story.dart';
import '../../domain/models/community_dm.dart';

/// In-memory fake datasource for Saman Community (JCOM-02).
/// Maintains reactive state across Feed, Discover, and Post Detail.
class CommunityFakeDatasource {
  final String currentUserId;

  static final Map<String, List<DraftPost>> _sharedUserDrafts = {};
  static final Map<String, Set<String>> _sharedUserBookmarks = {};

  CommunitySettings _settings = const CommunitySettings();
  final Set<String> _blockedUserIds = <String>{};
  final Set<String> _mutedUserIds = <String>{};
  final List<CommunityStoryAuthorGroup> _storyGroups = [];
  final Map<String, DmConversation> _conversations = {};
  final Map<String, List<DmMessage>> _messagesByConv = {};

  static void resetStorage() {
    _sharedUserDrafts.clear();
    _sharedUserBookmarks.clear();
  }

  CommunityFakeDatasource({this.currentUserId = 'current_user'});

  static const CommunityAuthor authorLinh = CommunityAuthor(
    id: 'author_linh',
    name: 'Linh Nguyễn',
    isVerified: true,
    title: 'Thành viên chia sẻ (Mẫu)',
    bio:
        'Yêu thích rèn luyện thể chất và dinh dưỡng cân bằng. Chia sẻ hành trình tập luyện thực tế mỗi ngày cùng Saman.',
    followerCount: 1250,
    workoutPostCount: 42,
    mealPostCount: 18,
    totalLikesReceived: 1200,
  );

  static const CommunityAuthor authorKhang = CommunityAuthor(
    id: 'author_khang',
    name: 'Minh Khang',
    isVerified: true,
    title: 'Thành viên tập luyện (Mẫu)',
    followerCount: 3420,
  );

  static const CommunityAuthor authorHa = CommunityAuthor(
    id: 'author_ha',
    name: 'Thu Hà',
    isVerified: false,
    title: 'Yêu thích nấu ăn lành mạnh (Mẫu)',
    followerCount: 950,
  );

  static const CommunityAuthor creatorLong = CommunityAuthor(
    id: 'creator_long',
    name: 'Hoàng Long',
    isVerified: true,
    title: 'Người tập thể lực (Mẫu)',
    followerCount: 14800,
    isFollowing: false,
  );

  static const CommunityAuthor creatorMai = CommunityAuthor(
    id: 'creator_mai',
    name: 'Thảo Mai',
    isVerified: true,
    title: 'Chia sẻ công thức ăn sạch (Mẫu)',
    followerCount: 8900,
    isFollowing: false,
  );

  static List<CommunityPost> _defaultPosts() {
    return [
      const CommunityPost(
        id: 'post_01_meal',
        type: CommunityPostType.photo,
        author: authorLinh,
        timeAgo: '2 giờ trước',
        caption:
            'Hôm nay chuẩn bị hộp cơm trưa nhanh gọn: ức gà áp chảo sốt tiêu, bông cải xanh và khoai lang nướng. Đủ no và không bị buồn ngủ buổi chiều 🥗',
        photoUrls: [
          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&auto=format&fit=crop',
        ],
        nutritionInfo: PostNutritionInfo(
          calories: 510,
          proteinGrams: 48,
          carbsGrams: 38,
          fatGrams: 11,
          badgeLabel: '510 kcal • 48g Protein',
          proTip:
              'Mẹo nhỏ: Ướp gà trước với một chút dầu olive và tiêu đen giúp thịt mềm và thơm hơn nhiều.',
        ),
        likeCount: 142,
        commentCount: 18,
        isLiked: true,
        isBookmarked: false,
        likedByNames: ['Minh Khang'],
        likedBySummary: 'Được thích bởi Minh Khang và 141 người khác',
        comments: [
          CommunityComment(
            id: 'c1',
            postId: 'post_01_meal',
            author: authorKhang,
            content:
                'Khoai lang nướng nồi chiên không dầu bao nhiêu phút vậy bạn? Nhìn ngon quá!',
            timeAgo: '1 giờ trước',
            likeCount: 4,
            replies: [
              CommunityComment(
                id: 'c1_reply1',
                postId: 'post_01_meal',
                author: authorLinh,
                content:
                    'Mình set 180 độ trong 15 phút, lật mặt rồi thêm 5 phút nữa là dẻo thơm luôn nhé Khang ơi!',
                timeAgo: '45 phút trước',
                likeCount: 8,
                isAuthorReply: true,
                replyToAuthorName: 'Minh Khang',
              ),
            ],
          ),
          CommunityComment(
            id: 'c2',
            postId: 'post_01_meal',
            author: authorHa,
            content:
                'Gợi ý tuyệt vời cho người bận rộn như mình. Cảm ơn Linh đã chia sẻ!',
            timeAgo: '30 phút trước',
            likeCount: 2,
          ),
        ],
      ),
      const CommunityPost(
        id: 'post_02_workout',
        type: CommunityPostType.workout,
        author: authorKhang,
        timeAgo: '4 giờ trước',
        caption:
            'Hoàn thành buổi tập hôm nay. Tăng mức tạ bài bench press thêm 2.5kg, cảm giác cơ phát lực rất tốt.',
        workoutAttachment: PostWorkoutAttachment(
          title: 'Upper Body Hypertrophy',
          category: 'Saman Kinetic',
          durationFormatted: '45 phút',
          exerciseCount: 5,
          setCount: 12,
          exercises: [
            ExerciseThumbnailPreview(title: 'DB Bench Press'),
            ExerciseThumbnailPreview(title: 'Pull-up Reps'),
            ExerciseThumbnailPreview(title: 'Shoulder Press'),
          ],
        ),
        likeCount: 89,
        commentCount: 12,
        isLiked: false,
        isBookmarked: false,
        likedByNames: ['Linh Nguyễn'],
        likedBySummary: 'Được thích bởi Linh Nguyễn và 88 người khác',
        comments: [
          CommunityComment(
            id: 'c3',
            postId: 'post_02_workout',
            author: authorLinh,
            content: 'Chúc mừng Khang! Form đẩy tạ rất chuẩn.',
            timeAgo: '2 giờ trước',
            likeCount: 5,
          ),
        ],
      ),
      const CommunityPost(
        id: 'post_03_qa',
        type: CommunityPostType.qa,
        author: authorHa,
        timeAgo: 'Hôm qua',
        caption: '',
        qaInfo: PostQaInfo(
          question: 'Bạn thường chuẩn bị bữa ăn cho cả tuần như thế nào?',
          categoryTag: 'HỎI ĐÁP • MEAL PREP',
          details:
              'Mình đi làm cả ngày nên thường meal prep vào Chủ Nhật, nhưng đến thứ Tư là rau củ bắt đầu kém tươi. Mọi người có mẹo bảo quản nào chia sẻ với mình không?',
          respondentCount: 25,
          respondentsSummary: 'Minh Khang và 25 người đã đưa ra gợi ý',
          respondentInitials: ['NL', 'MK', '+24'],
        ),
        likeCount: 34,
        commentCount: 26,
        isLiked: false,
        isBookmarked: false,
        likedByNames: ['Hoàng Long'],
        likedBySummary: 'Được thích bởi Hoàng Long và 33 người khác',
        comments: [
          CommunityComment(
            id: 'c4',
            postId: 'post_03_qa',
            author: authorKhang,
            content:
                'Mình thường chia nhỏ vào hộp thủy tinh hút chân không, rau để riêng không trộn sốt trước, tươi được tới thứ Sáu luôn!',
            timeAgo: 'Hôm qua',
            likeCount: 12,
          ),
        ],
      ),
    ];
  }

  static List<CommunityVisualGridItem> _defaultGridItems() {
    return const [
      CommunityVisualGridItem(
        id: 'grid_1',
        postId: 'post_01_meal',
        imageUrl:
            'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500&auto=format&fit=crop',
        likeCount: 412,
        hasMultiPhoto: true,
        altText: 'Kettlebell swings',
      ),
      CommunityVisualGridItem(
        id: 'grid_2',
        imageUrl:
            'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=500&auto=format&fit=crop',
        likeCount: 820,
        altText: 'Meal prep glass boxes',
      ),
      CommunityVisualGridItem(
        id: 'grid_3',
        postId: 'post_02_workout',
        imageUrl:
            'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=500&auto=format&fit=crop',
        likeCount: 1100,
        altText: 'Barbell deadlift',
      ),
      CommunityVisualGridItem(
        id: 'grid_4',
        imageUrl:
            'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=500&auto=format&fit=crop',
        likeCount: 640,
        altText: 'Green spirulina protein smoothie',
      ),
      CommunityVisualGridItem(
        id: 'grid_5',
        imageUrl:
            'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=500&auto=format&fit=crop',
        likeCount: 954,
        hasVideo: true,
        altText: 'Runner stretching track',
      ),
      CommunityVisualGridItem(
        id: 'grid_6',
        imageUrl:
            'https://images.unsplash.com/photo-1546069901-d5bfd2cbfb1f?w=500&auto=format&fit=crop',
        likeCount: 530,
        altText: 'High protein salmon poke bowl',
      ),
      CommunityVisualGridItem(
        id: 'grid_7',
        imageUrl:
            'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=500&auto=format&fit=crop',
        likeCount: 1500,
        altText: 'Calisthenics flag',
      ),
      CommunityVisualGridItem(
        id: 'grid_8',
        imageUrl:
            'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=500&auto=format&fit=crop',
        likeCount: 789,
        altText: 'Overnight oats prep',
      ),
      CommunityVisualGridItem(
        id: 'grid_9',
        imageUrl:
            'https://images.unsplash.com/photo-1574680096145-d05b474e2155?w=500&auto=format&fit=crop',
        likeCount: 320,
        altText: 'Post workout gear & shaker',
      ),
    ];
  }

  static List<CommunityTrendingTopic> _defaultTrendingTopics() {
    return const [
      CommunityTrendingTopic(
        id: 'trend_1',
        hashtag: '#MealPrepCuoiTuan',
        postCountFormatted: '1.2k bài viết thảo luận',
        growthPercent: '+28%',
        iconName: 'bento',
      ),
      CommunityTrendingTopic(
        id: 'trend_2',
        hashtag: '#TangCoGiamMo',
        postCountFormatted: '3.4k bài viết thảo luận',
        growthPercent: '+45%',
        iconName: 'offline_bolt',
      ),
      CommunityTrendingTopic(
        id: 'trend_3',
        hashtag: '#HoiDapDinhDuong',
        postCountFormatted: '890 bài viết thảo luận',
        growthPercent: 'Ổn định',
        isStable: true,
        iconName: 'nutrition',
      ),
    ];
  }

  // Active in-memory state
  final List<CommunityPost> _posts = _defaultPosts();
  final List<CommunityAuthor> _creators = [creatorLong, creatorMai];

  List<CommunityPost> getFeedPosts(CommunityFeedFilter filter) {
    final bookmarks = _sharedUserBookmarks[currentUserId] ?? const <String>{};
    List<CommunityPost> list;
    switch (filter) {
      case CommunityFeedFilter.forYou:
        list = _posts;
        break;
      case CommunityFeedFilter.following:
        list = _posts
            .where((p) => p.author.isFollowing || p.id == 'post_01_meal')
            .toList();
        break;
      case CommunityFeedFilter.qa:
        list = _posts
            .where((p) => p.type == CommunityPostType.qa)
            .toList();
        break;
    }
    return list
        .map((p) => p.copyWith(isBookmarked: bookmarks.contains(p.id)))
        .toList();
  }

  CommunityPost getPostDetail(String postId) {
    final post = _posts.firstWhere(
      (p) => p.id == postId,
      orElse: () => _posts.first,
    );
    final bookmarks = _sharedUserBookmarks[currentUserId] ?? const <String>{};
    return post.copyWith(isBookmarked: bookmarks.contains(post.id));
  }

  bool toggleLike(String postId) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return false;
    final current = _posts[index];
    final newIsLiked = !current.isLiked;
    final newCount = newIsLiked ? current.likeCount + 1 : current.likeCount - 1;
    _posts[index] = current.copyWith(
      isLiked: newIsLiked,
      likeCount: newCount < 0 ? 0 : newCount,
    );
    return newIsLiked;
  }

  bool toggleBookmark(String postId) {
    final bookmarks =
        _sharedUserBookmarks.putIfAbsent(currentUserId, () => <String>{});
    final wasBookmarked = bookmarks.contains(postId);
    if (wasBookmarked) {
      bookmarks.remove(postId);
    } else {
      bookmarks.add(postId);
    }
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      _posts[index] = _posts[index].copyWith(isBookmarked: !wasBookmarked);
    }
    return !wasBookmarked;
  }

  bool toggleFollow(String authorId) {
    bool? newFollowState;
    // Update creators
    for (int i = 0; i < _creators.length; i++) {
      if (_creators[i].id == authorId) {
        final next = !_creators[i].isFollowing;
        _creators[i] = _creators[i].copyWith(isFollowing: next);
        newFollowState = next;
      }
    }
    // Update posts authored by this author
    for (int i = 0; i < _posts.length; i++) {
      if (_posts[i].author.id == authorId) {
        final next = newFollowState ?? !_posts[i].author.isFollowing;
        final updatedAuthor = _posts[i].author.copyWith(isFollowing: next);
        _posts[i] = _posts[i].copyWith(author: updatedAuthor);
        newFollowState = next;
      }
    }
    return newFollowState ?? false;
  }

  CommunityComment addComment({
    required String postId,
    required String content,
    String? parentCommentId,
    String? replyToAuthorName,
  }) {
    final index = _posts.indexWhere((p) => p.id == postId);
    final newComment = CommunityComment(
      id: 'comment_${DateTime.now().millisecondsSinceEpoch}',
      postId: postId,
      author: const CommunityAuthor(
        id: 'me',
        name: 'Bạn',
        title: 'Thành viên Saman',
      ),
      content: content,
      timeAgo: 'Vừa xong',
      likeCount: 0,
      replyToAuthorName: replyToAuthorName,
    );

    if (index != -1) {
      final current = _posts[index];
      final List<CommunityComment> updatedComments = List.from(current.comments);

      if (parentCommentId != null) {
        final parentIndex =
            updatedComments.indexWhere((c) => c.id == parentCommentId);
        if (parentIndex != -1) {
          final parent = updatedComments[parentIndex];
          final replies = List<CommunityComment>.from(parent.replies)
            ..add(newComment);
          updatedComments[parentIndex] = parent.copyWith(replies: replies);
        } else {
          updatedComments.insert(0, newComment);
        }
      } else {
        updatedComments.insert(0, newComment);
      }

      _posts[index] = current.copyWith(
        comments: updatedComments,
        commentCount: current.commentCount + 1,
      );
    }

    return newComment;
  }

  CommunityDiscoverData getDiscoverData({
    String topic = 'all',
    String? searchQuery,
  }) {
    final query = searchQuery?.trim().toLowerCase() ?? '';
    final allGrid = _defaultGridItems();
    final allTrending = _defaultTrendingTopics();
    final allCreators = List<CommunityAuthor>.unmodifiable(_creators);

    if (query.isEmpty) {
      return CommunityDiscoverData(
        activeTopic: topic,
        gridItems: allGrid,
        trendingTopics: allTrending,
        recommendedCreators: allCreators,
      );
    }

    return CommunityDiscoverData(
      activeTopic: topic,
      gridItems: allGrid
          .where((item) => (item.altText ?? '').toLowerCase().contains(query))
          .toList(),
      trendingTopics: allTrending
          .where((t) => t.hashtag.toLowerCase().contains(query))
          .toList(),
      recommendedCreators: allCreators
          .where((c) =>
              c.name.toLowerCase().contains(query) ||
              (c.title ?? '').toLowerCase().contains(query) ||
              (c.handle ?? '').toLowerCase().contains(query))
          .toList(),
    );
  }

  // JCOM-03 & JCOM-04 Methods & In-Memory Store
  final List<CommunityNotification> _notifications = List.from(_defaultNotifications());
  final Map<String, List<QuestionAnswer>> _questionAnswers = {
    'post_03_qa': List.from(_defaultAnswersForPost3()),
  };

  CommunityPost publishPost({
    required String caption,
    List<String> mediaUrls = const [],
    PostAttachmentSnapshot? attachment,
    String audience = 'Công khai',
    String topic = '#BữaĂn',
    bool allowComments = true,
  }) {
    final newId = 'post_${DateTime.now().millisecondsSinceEpoch}';
    final cleanAttachment = attachment?.sanitize();
    PostWorkoutAttachment? workoutAtt;
    PostNutritionInfo? nutritionInf;

    if (cleanAttachment != null) {
      if (cleanAttachment.type == AttachmentType.workout) {
        workoutAtt = PostWorkoutAttachment(
          title: cleanAttachment.title,
          category: cleanAttachment.category,
          durationFormatted: cleanAttachment.includeDuration
              ? (cleanAttachment.durationFormatted ?? '45 phút')
              : 'Đã hoàn thành',
          exerciseCount: cleanAttachment.includeExercisesOrFoods
              ? (cleanAttachment.exerciseCount ?? 5)
              : 0,
          setCount:
              cleanAttachment.includeLoadOrMacros ? (cleanAttachment.setCount ?? 12) : 0,
          exercises: cleanAttachment.includeExercisesOrFoods
              ? cleanAttachment.exercises
              : const [],
        );
      } else if (cleanAttachment.type == AttachmentType.meal) {
        nutritionInf = PostNutritionInfo(
          calories:
              cleanAttachment.includeLoadOrMacros ? (cleanAttachment.calories ?? 510) : 0,
          proteinGrams: cleanAttachment.includeLoadOrMacros ? 45 : 0,
          carbsGrams: cleanAttachment.includeLoadOrMacros ? 35 : 0,
          fatGrams: cleanAttachment.includeLoadOrMacros ? 12 : 0,
          badgeLabel: cleanAttachment.includeLoadOrMacros
              ? '${cleanAttachment.calories ?? 510} kcal'
              : 'Bữa ăn cân bằng (Mẫu)',
        );
      }
    }

    final newPost = CommunityPost(
      id: newId,
      type: workoutAtt != null
          ? CommunityPostType.workout
          : CommunityPostType.photo,
      author: const CommunityAuthor(
        id: 'me',
        name: 'Linh Nguyễn',
        isVerified: true,
        title: 'Thành viên chia sẻ (Mẫu)',
      ),
      timeAgo: 'Vừa xong',
      caption: caption,
      photoUrls: mediaUrls.isNotEmpty
          ? mediaUrls
          : (cleanAttachment?.imageUrl != null ? [cleanAttachment!.imageUrl!] : const []),
      workoutAttachment: workoutAtt,
      nutritionInfo: nutritionInf,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
      isBookmarked: false,
    );

    _posts.insert(0, newPost);
    return newPost;
  }

  CommunityPost publishQuestion({
    required String question,
    required String categoryTag,
    String? details,
  }) {
    final newId = 'post_qa_${DateTime.now().millisecondsSinceEpoch}';
    final newPost = CommunityPost(
      id: newId,
      type: CommunityPostType.qa,
      author: const CommunityAuthor(
        id: 'me',
        name: 'Linh Nguyễn',
        isVerified: true,
        title: 'Thành viên chia sẻ (Mẫu)',
      ),
      timeAgo: 'Vừa xong',
      caption: '',
      qaInfo: PostQaInfo(
        question: question,
        categoryTag: categoryTag,
        details: details,
        respondentCount: 0,
        respondentsSummary: 'Chưa có câu trả lời nào',
        respondentInitials: const [],
      ),
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
      isBookmarked: false,
    );

    _posts.insert(0, newPost);
    return newPost;
  }

  List<PostAttachmentSnapshot> getRecentWorkoutActivities() {
    return const [
      PostAttachmentSnapshot(
        type: AttachmentType.workout,
        id: 'workout_01',
        title: 'Upper Body Hypertrophy',
        dateFormatted: 'Hôm nay • 24 Tháng 10',
        category: 'Saman Kinetic',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false, // Default OFF
        durationFormatted: '45 phút',
        exerciseCount: 5,
        setCount: 12,
        loadSummaryFormatted: '3,420 kg tải trọng',
        exercises: [
          ExerciseThumbnailPreview(title: 'DB Bench Press'),
          ExerciseThumbnailPreview(title: 'Pull-up Reps'),
          ExerciseThumbnailPreview(title: 'Shoulder Press'),
        ],
        imageUrl:
            'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=800&auto=format&fit=crop',
      ),
      PostAttachmentSnapshot(
        type: AttachmentType.workout,
        id: 'workout_02',
        title: 'Phục hồi cơ bắp & Mobility',
        dateFormatted: 'Hôm nay • 24 Tháng 10',
        category: 'Saman Kinetic',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false,
        durationFormatted: '20 phút',
        exerciseCount: 4,
        setCount: 4,
        loadSummaryFormatted: 'Khởi động tự do',
        exercises: [
          ExerciseThumbnailPreview(title: 'Foam Rolling'),
          ExerciseThumbnailPreview(title: 'Band Pull Apart'),
        ],
        imageUrl:
            'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=800&auto=format&fit=crop',
      ),
      PostAttachmentSnapshot(
        type: AttachmentType.workout,
        id: 'workout_03',
        title: 'Leg Day & Posterior Chain',
        dateFormatted: 'Hôm qua • 23 Tháng 10',
        category: 'Saman Kinetic',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false,
        durationFormatted: '55 phút',
        exerciseCount: 6,
        setCount: 16,
        loadSummaryFormatted: '5,280 kg tải trọng',
        exercises: [
          ExerciseThumbnailPreview(title: 'Barbell Squat'),
          ExerciseThumbnailPreview(title: 'Romanian Deadlift'),
        ],
        imageUrl:
            'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&auto=format&fit=crop',
      ),
    ];
  }

  List<PostAttachmentSnapshot> getRecentMealActivities() {
    return const [
      PostAttachmentSnapshot(
        type: AttachmentType.meal,
        id: 'meal_01',
        title: 'Cơm trưa Bento Ức Gà & Khoai Lang',
        dateFormatted: 'Hôm nay • Trưa',
        category: 'Saman Nutrition',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false, // Default OFF
        calories: 510,
        macrosSummaryFormatted: '510 kcal • 48g P • 38g C • 11g F',
        imageUrl:
            'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&auto=format&fit=crop',
      ),
      PostAttachmentSnapshot(
        type: AttachmentType.meal,
        id: 'meal_02',
        title: 'Sinh tố Protein Matcha & Hạnh Nhân',
        dateFormatted: 'Hôm nay • Sau tập',
        category: 'Saman Nutrition',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false,
        calories: 280,
        macrosSummaryFormatted: '280 kcal • 30g P • 22g C • 6g F',
        imageUrl:
            'https://images.unsplash.com/photo-1553530666-ba11a7da3888?w=800&auto=format&fit=crop',
      ),
    ];
  }

  List<DraftPost> getDrafts() {
    final list = _sharedUserDrafts[currentUserId] ?? const [];
    return List.unmodifiable(list);
  }

  void saveDraft(DraftPost draft) {
    final cleanAttachment = draft.attachment?.sanitize();
    final cleanDraft = draft.copyWith(
      userId: currentUserId,
      attachment: cleanAttachment,
    );
    final userDrafts =
        _sharedUserDrafts.putIfAbsent(currentUserId, () => <DraftPost>[]);
    final idx = userDrafts.indexWhere((d) => d.id == cleanDraft.id);
    if (idx != -1) {
      userDrafts[idx] = cleanDraft;
    } else {
      userDrafts.insert(0, cleanDraft);
    }
  }

  void deleteDraft(String draftId) {
    final userDrafts = _sharedUserDrafts[currentUserId];
    if (userDrafts != null) {
      userDrafts.removeWhere(
        (d) => d.id == draftId && d.userId == currentUserId,
      );
    }
  }

  List<CommunityPost> getSavedPosts() {
    final bookmarks = _sharedUserBookmarks[currentUserId] ?? const <String>{};
    return _posts
        .where((p) => bookmarks.contains(p.id))
        .map((p) => p.copyWith(isBookmarked: true))
        .toList();
  }

  List<CommunityNotification> getNotifications() {
    return List.unmodifiable(_notifications);
  }

  void markNotificationRead(String id) {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notifications[idx] = _notifications[idx].copyWith(isUnread: false);
    }
  }

  void markAllNotificationsRead() {
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].isUnread) {
        _notifications[i] = _notifications[i].copyWith(isUnread: false);
      }
    }
  }

  CommunityAuthor? _customMyProfile;

  CommunityAuthor getAuthorProfile(String authorId) {
    if (authorId == 'author_linh' || authorId == 'me') {
      return _customMyProfile ?? authorLinh;
    }
    if (authorId == 'author_khang') return authorKhang;
    if (authorId == 'creator_long') return creatorLong;
    if (authorId == 'creator_mai') return creatorMai;
    return _customMyProfile ?? authorLinh;
  }

  List<CommunityPost> getAuthorPosts(
    String authorId, {
    String tab = 'all',
  }) {
    final bookmarks = _sharedUserBookmarks[currentUserId] ?? const <String>{};
    final isMe = authorId == 'me' || authorId == 'author_linh';
    final filtered = _posts.where((p) {
      final matchesAuthor = isMe
          ? (p.author.id == 'me' || p.author.id == 'author_linh')
          : p.author.id == authorId;
      if (!matchesAuthor) return false;
      if (tab == 'workout') {
        return p.type == CommunityPostType.workout ||
            p.workoutAttachment != null;
      }
      if (tab == 'meal') {
        return p.type == CommunityPostType.meal || p.nutritionInfo != null;
      }
      if (tab == 'qa') {
        return p.type == CommunityPostType.qa;
      }
      return true;
    });
    return filtered
        .map((p) => p.copyWith(isBookmarked: bookmarks.contains(p.id)))
        .toList();
  }

  CommunityAuthor updateProfile({
    String? name,
    String? handle,
    String? title,
    String? bio,
    List<String>? interestTopics,
    String? avatarUrl,
    bool removeAvatar = false,
  }) {
    final base = _customMyProfile ?? authorLinh;
    final updated = base.copyWith(
      name: name ?? base.name,
      handle: handle ?? base.handle,
      title: title ?? base.title,
      bio: bio ?? base.bio,
      interestTopics: interestTopics ?? base.interestTopics,
      avatarUrl: removeAvatar ? null : (avatarUrl ?? base.avatarUrl),
    );
    _customMyProfile = updated;
    return updated;
  }

  List<CommunityAuthor> getFollowers(String authorId) {
    return [authorKhang, creatorMai];
  }

  List<CommunityAuthor> getFollowing(String authorId) {
    return [authorHa, creatorLong];
  }

  List<QuestionAnswer> getQuestionAnswers(String questionId) {
    return _questionAnswers[questionId] ?? _defaultAnswersForPost3();
  }

  QuestionAnswer addQuestionAnswer({
    required String questionId,
    required String content,
  }) {
    final newAns = QuestionAnswer(
      id: 'ans_${DateTime.now().millisecondsSinceEpoch}',
      questionId: questionId,
      author: const CommunityAuthor(
        id: 'me',
        name: 'Linh Nguyễn',
        isVerified: true,
        title: 'Thành viên chia sẻ (Mẫu)',
      ),
      content: content,
      timeAgo: 'Vừa xong',
      upvoteCount: 0,
      isUpvoted: false,
    );
    final list = _questionAnswers[questionId] ?? _defaultAnswersForPost3();
    final updated = List<QuestionAnswer>.from(list)..insert(0, newAns);
    _questionAnswers[questionId] = updated;
    return newAns;
  }

  bool upvoteAnswer(String questionId, String answerId) {
    final list = _questionAnswers[questionId] ?? _defaultAnswersForPost3();
    final idx = list.indexWhere((a) => a.id == answerId);
    if (idx != -1) {
      final current = list[idx];
      final newUpvoted = !current.isUpvoted;
      final newCount =
          newUpvoted ? current.upvoteCount + 1 : current.upvoteCount - 1;
      final updatedList = List<QuestionAnswer>.from(list);
      updatedList[idx] = current.copyWith(
        isUpvoted: newUpvoted,
        upvoteCount: newCount < 0 ? 0 : newCount,
      );
      _questionAnswers[questionId] = updatedList;
      return newUpvoted;
    }
    return false;
  }

  // --- Wave 4 Fake Implementations ---

  CommunitySettings getSettings() => _settings;

  CommunitySettings updateSettings({
    bool? isPrivateAccount,
    String? whoCanDm,
    String? whoCanComment,
    bool? hideLikeCounts,
    bool? showActivityStatus,
    List<String>? mutedKeywords,
  }) {
    _settings = _settings.copyWith(
      isPrivateAccount: isPrivateAccount,
      whoCanDm: whoCanDm,
      whoCanComment: whoCanComment,
      hideLikeCounts: hideLikeCounts,
      showActivityStatus: showActivityStatus,
      mutedKeywords: mutedKeywords,
    );
    return _settings;
  }

  bool blockUser(String targetUserId) {
    _blockedUserIds.add(targetUserId);
    return true;
  }

  bool unblockUser(String targetUserId) {
    _blockedUserIds.remove(targetUserId);
    return false;
  }

  List<CommunityAuthor> getBlockedUsers() {
    return _blockedUserIds.map(getAuthorProfile).toList();
  }

  bool muteUser(String targetUserId) {
    _mutedUserIds.add(targetUserId);
    return true;
  }

  bool unmuteUser(String targetUserId) {
    _mutedUserIds.remove(targetUserId);
    return false;
  }

  List<CommunityAuthor> getMutedUsers() {
    return _mutedUserIds.map(getAuthorProfile).toList();
  }

  CommunityReportReceipt reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) {
    return CommunityReportReceipt(
      reportId: 'report_${DateTime.now().millisecondsSinceEpoch}',
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      status: 'received',
      createdAt: DateTime.now().toUtc(),
      alreadyReported: false,
    );
  }

  List<CommunityStoryAuthorGroup> getStories() {
    return List.unmodifiable(_storyGroups);
  }

  CommunityStory createStory({
    required String mediaType,
    String? mediaUrl,
    String caption = '',
    String? backgroundColor,
    String privacy = 'public',
  }) {
    final now = DateTime.now().toUtc();
    final story = CommunityStory(
      id: 'story_${now.millisecondsSinceEpoch}',
      userId: currentUserId,
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      caption: caption,
      backgroundColor: backgroundColor,
      privacy: privacy,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    final selfIdx = _storyGroups.indexWhere((g) => g.isSelf);
    if (selfIdx != -1) {
      final existing = _storyGroups[selfIdx];
      _storyGroups[selfIdx] = existing.copyWith(
        stories: [...existing.stories, story],
        hasUnviewed: true,
        latestCreatedAt: now,
      );
    } else {
      _storyGroups.insert(
        0,
        CommunityStoryAuthorGroup(
          author: getAuthorProfile('me'),
          stories: [story],
          hasUnviewed: true,
          isSelf: true,
          latestCreatedAt: now,
        ),
      );
    }
    return story;
  }

  int markStoryViewed(String storyId) {
    for (var i = 0; i < _storyGroups.length; i++) {
      final group = _storyGroups[i];
      final sIdx = group.stories.indexWhere((s) => s.id == storyId);
      if (sIdx != -1) {
        final s = group.stories[sIdx];
        final updatedStory = s.copyWith(
          isViewed: true,
          viewCount: s.isViewed ? s.viewCount : s.viewCount + 1,
        );
        final nextStories = List<CommunityStory>.from(group.stories);
        nextStories[sIdx] = updatedStory;
        _storyGroups[i] = group.copyWith(
          stories: nextStories,
          hasUnviewed: nextStories.any((st) => !st.isViewed),
        );
        return updatedStory.viewCount;
      }
    }
    return 1;
  }

  bool deleteStory(String storyId) {
    for (var i = 0; i < _storyGroups.length; i++) {
      final group = _storyGroups[i];
      final nextStories = group.stories.where((s) => s.id != storyId).toList();
      if (nextStories.length != group.stories.length) {
        if (nextStories.isEmpty) {
          _storyGroups.removeAt(i);
        } else {
          _storyGroups[i] = group.copyWith(stories: nextStories);
        }
        return true;
      }
    }
    return false;
  }

  int sharePost(String postId) {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx != -1) {
      final updated = _posts[idx].copyWith(shareCount: _posts[idx].shareCount + 1);
      _posts[idx] = updated;
      return updated.shareCount;
    }
    return 1;
  }

  DmConversation createOrGetConversation(String targetUserId) {
    final existing = _conversations.values.where((c) => c.peer.id == targetUserId).toList();
    if (existing.isNotEmpty) return existing.first;
    final author = getAuthorProfile(targetUserId);
    final now = DateTime.now().toUtc();
    final conv = DmConversation(
      id: 'conv_$targetUserId',
      peer: DmParticipant(
        id: author.id,
        name: author.name,
        avatarUrl: author.avatarUrl,
        isVerified: author.isVerified,
      ),
      updatedAt: now,
    );
    _conversations[conv.id] = conv;
    _messagesByConv.putIfAbsent(conv.id, () => []);
    return conv;
  }

  DmConversationsPage getConversations() {
    final items = _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final totalUnread = items.fold<int>(0, (sum, c) => sum + c.unreadCount);
    return DmConversationsPage(items: items, totalUnreadCount: totalUnread);
  }

  DmMessagesPage getMessages(String conversationId) {
    final msgs = List<DmMessage>.from(_messagesByConv[conversationId] ?? const []);
    return DmMessagesPage(items: msgs);
  }

  DmMessage sendMessage({
    required String conversationId,
    required DmMessageType type,
    String content = '',
    String? mediaUrl,
    double? durationSeconds,
    String? sharedPostId,
    String? replyToMessageId,
  }) {
    final now = DateTime.now().toUtc();
    final msg = DmMessage(
      id: 'msg_${now.millisecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: currentUserId,
      type: type,
      content: content,
      mediaUrl: mediaUrl,
      durationSeconds: durationSeconds,
      sharedPostId: sharedPostId,
      replyToMessageId: replyToMessageId,
      createdAt: now,
    );
    _messagesByConv.putIfAbsent(conversationId, () => []).insert(0, msg);
    final conv = _conversations[conversationId];
    if (conv != null) {
      _conversations[conversationId] = conv.copyWith(
        lastMessagePreview: content.isNotEmpty ? content : type.toApiValue(),
        lastMessageType: type.toApiValue(),
        lastMessageAt: now,
        updatedAt: now,
      );
    }
    return msg;
  }

  void markConversationRead(String conversationId) {
    final conv = _conversations[conversationId];
    if (conv != null) {
      _conversations[conversationId] = conv.copyWith(unreadCount: 0);
    }
  }

  bool deleteMessage(String messageId) {
    for (final entry in _messagesByConv.entries) {
      final idx = entry.value.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        entry.value[idx] = entry.value[idx].copyWith(
          isDeleted: true,
          content: '',
          mediaUrl: null,
        );
        return true;
      }
    }
    return false;
  }

  int getDmUnreadCount() {
    return _conversations.values.fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  DmMediaUploadResult uploadDmMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    final kind = mimeType.startsWith('audio/')
        ? 'audio'
        : (mimeType.startsWith('video/') ? 'video' : 'image');
    return DmMediaUploadResult(
      mediaUrl: '/static/community_dm/$filename',
      mediaKind: kind,
      contentType: mimeType,
      fileName: filename,
      sizeBytes: bytes.length,
    );
  }

  static List<CommunityNotification> _defaultNotifications() {
    return const [
      CommunityNotification(
        id: 'notif_01',
        actorName: 'Minh Khang',
        actionText: 'đã thích bài viết của bạn',
        targetSnippet: 'Hôm nay chuẩn bị hộp cơm trưa nhanh gọn...',
        timeAgo: '15 phút trước',
        isUnread: true,
        type: CommunityNotificationType.like,
        targetPostId: 'post_01_meal',
      ),
      CommunityNotification(
        id: 'notif_02',
        actorName: 'Thu Hà',
        actionText: 'đã bình luận về bài viết của bạn',
        targetSnippet: 'Gợi ý tuyệt vời cho người bận rộn...',
        timeAgo: '1 giờ trước',
        isUnread: false,
        type: CommunityNotificationType.comment,
        targetPostId: 'post_01_meal',
      ),
      CommunityNotification(
        id: 'notif_03',
        actorName: 'Hoàng Long',
        actionText: 'đã bắt đầu theo dõi bạn',
        timeAgo: 'Hôm qua',
        isUnread: false,
        type: CommunityNotificationType.follow,
      ),
    ];
  }

  static List<QuestionAnswer> _defaultAnswersForPost3() {
    return const [
      QuestionAnswer(
        id: 'ans_01',
        questionId: 'post_03_qa',
        author: authorKhang,
        content:
            'Mình thường chia nhỏ vào hộp thủy tinh hút chân không, rau để riêng không trộn sốt trước, tươi được tới thứ Sáu luôn!',
        timeAgo: 'Hôm qua',
        upvoteCount: 14,
        isUpvoted: false,
        isPinnedBest: true,
      ),
      QuestionAnswer(
        id: 'ans_02',
        questionId: 'post_03_qa',
        author: authorLinh,
        content:
            'Mẹo của mình: các loại rau xanh như xà lách rửa sạch rồi quay thật ráo nước, bọc trong khăn giấy ẩm trước khi bỏ hộp là giòn lâu lắm.',
        timeAgo: '18 giờ trước',
        upvoteCount: 8,
        isUpvoted: false,
        isPinnedBest: false,
      ),
    ];
  }
}

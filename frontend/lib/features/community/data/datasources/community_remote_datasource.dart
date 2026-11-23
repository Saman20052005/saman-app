import 'package:dio/dio.dart';
import '../../domain/models/community_notification.dart';
import '../../domain/models/draft_post.dart';
import 'package:http_parser/http_parser.dart';
import '../../../../config/api_config.dart';
import '../../domain/models/community_author.dart';
import '../../domain/models/community_comment.dart';
import '../../domain/models/community_discover_item.dart';
import '../../domain/models/community_post.dart';
import '../../domain/models/question_answer.dart';
import '../../domain/models/post_attachment_snapshot.dart';
import '../../domain/models/community_settings.dart';
import '../../domain/models/community_story.dart';
import '../../domain/models/community_dm.dart';

abstract class CommunityRemoteDatasource {
  Future<List<CommunityPost>> getFeedPosts({
    required CommunityFeedFilter filter,
    int limit = 20,
    String? cursor,
  });

  Future<List<PostAttachmentSnapshot>> getAttachmentSources(String kind);
  Future<PostAttachmentSnapshot> previewActivity(String kind, String sourceId, Map<String,dynamic> options);
  Future<CommunityPost> getPostDetail(String postId);
  Future<CommunityPost> publishPost(Map<String, dynamic> body, String requestKey);

  Future<CommunityCommentsPage> getComments(String postId, {String? cursor});
  Future<CommunityCommentReceipt> createComment(String postId, String content,
      {String? parentCommentId, required String requestKey});

  Future<QuestionAnswersPage> getAnswerPage(String questionId, {String? cursor, int limit = 20});
  Future<QuestionAnswerReceipt> createAnswer(String questionId, String content, String requestKey);
  Future<QuestionAnswer> getAnswer(String questionId, String answerId);
  Future<QuestionAnswer> setAnswerHelpful(String questionId, String answerId, bool desired);

  Future<List<QuestionAnswer>> getQuestionAnswers(
    String questionId, {
    int limit = 20,
    String? cursor,
  });

  Future<Map<String, dynamic>> likePost(String postId);
  Future<Map<String, dynamic>> unlikePost(String postId);
  Future<bool> savePost(String postId);
  Future<bool> unsavePost(String postId);
  Future<List<CommunityPost>> getSavedPosts();

  Future<Map<String, dynamic>> followAuthor(String authorId);
  Future<Map<String, dynamic>> unfollowAuthor(String authorId);
  Future<CommunityAuthor> getAuthorProfile(String authorId);
  Future<List<CommunityAuthor>> getFollowers(String authorId, {int limit = 20, String? cursor});
  Future<List<CommunityAuthor>> getFollowing(String authorId, {int limit = 20, String? cursor});
}

extension CommunityRemoteDatasourceMediaExtension on CommunityRemoteDatasource {
  Future<bool> deletePost(String postId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).deletePost(postId);
    }
    throw UnsupportedError('Post deletion is not supported by this datasource double');
  }

  Future<Map<String, dynamic>> uploadMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).uploadMedia(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
    }
    throw UnsupportedError('Media upload is not supported by this datasource double');
  }
}

extension CommunityRemoteDatasourceWave2Extension on CommunityRemoteDatasource {
  Future<List<CommunityNotification>> getNotifications({
    String filter = 'all',
    int limit = 20,
    String? cursor,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getNotifications(
        filter: filter,
        limit: limit,
        cursor: cursor,
      );
    }
    throw UnsupportedError('Notifications are not supported by this datasource double');
  }

  Future<void> markNotificationRead(String notificationId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).markNotificationRead(notificationId);
    }
    throw UnsupportedError('Notifications are not supported by this datasource double');
  }

  Future<void> markAllNotificationsRead() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).markAllNotificationsRead();
    }
    throw UnsupportedError('Notifications are not supported by this datasource double');
  }

  Future<List<DraftPost>> getDrafts() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getDrafts();
    }
    throw UnsupportedError('Drafts are not supported by this datasource double');
  }

  Future<DraftPost> saveDraft(DraftPost draft) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).saveDraft(draft);
    }
    throw UnsupportedError('Drafts are not supported by this datasource double');
  }

  Future<void> deleteDraft(String draftId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).deleteDraft(draftId);
    }
    throw UnsupportedError('Drafts are not supported by this datasource double');
  }

  Future<List<CommunityPost>> getAuthorPosts(
    String authorId, {
    String tab = 'all',
    int limit = 20,
    String? cursor,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getAuthorPosts(
        authorId,
        tab: tab,
        limit: limit,
        cursor: cursor,
      );
    }
    throw UnsupportedError('Author posts are not supported by this datasource double');
  }

  Future<CommunityAuthor> updateProfile(Map<String, dynamic> body) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).updateProfile(body);
    }
    throw UnsupportedError('Profile update is not supported by this datasource double');
  }

  Future<CommunityDiscoverData> getDiscoverData({
    String topic = 'all',
    String? searchQuery,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getDiscoverData(
        topic: topic,
        searchQuery: searchQuery,
      );
    }
    throw UnsupportedError('Discover is not supported by this datasource double');
  }
}

class CommunityRemoteDatasourceImpl implements CommunityRemoteDatasource {
  final Dio dio;

  CommunityRemoteDatasourceImpl({required this.dio});

  @override
  Future<List<PostAttachmentSnapshot>> getAttachmentSources(String kind) async {
    final response = await dio.get('/api/community/attachment-sources/$kind');
    return (response.data['items'] as List).map((x) => PostAttachmentSnapshot.fromPreview(Map<String,dynamic>.from(x as Map))).toList();
  }
  @override
  Future<PostAttachmentSnapshot> previewActivity(String kind, String sourceId, Map<String,dynamic> options) async {
    final response = await dio.get('/api/community/attachment-sources/$kind/$sourceId', queryParameters: options);
    return PostAttachmentSnapshot.fromPreview(Map<String,dynamic>.from(response.data as Map));
  }

  @override
  Future<CommunityPost> publishPost(Map<String, dynamic> body, String requestKey) async {
    final response = await dio.post('/api/community/posts', data: body,
        options: Options(headers: {'X-Idempotency-Key': requestKey}));
    return _parsePost(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> uploadMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    });
    final response = await dio.post('/api/community/media/upload', data: formData);
    return response.data as Map<String, dynamic>;
  }

  Future<bool> deletePost(String postId) async {
    final response = await dio.delete('/api/community/posts/$postId');
    return response.statusCode == 200;
  }

  @override
  Future<CommunityCommentsPage> getComments(String postId, {String? cursor}) async {
    final response = await dio.get('/api/community/posts/$postId/comments',
        queryParameters: {'limit': 20, if (cursor != null) 'cursor': cursor});
    final data = response.data as Map<String, dynamic>;
    return CommunityCommentsPage(
      items: (data['items'] as List).map((c) => _parseComment(c as Map<String, dynamic>, postId)).toList(),
      nextCursor: data['next_cursor'] as String?,
      commentCount: data['comment_count'] as int,
    );
  }

  @override
  Future<CommunityCommentReceipt> createComment(String postId, String content,
      {String? parentCommentId, required String requestKey}) async {
    final response = await dio.post('/api/community/posts/$postId/comments',
      data: {'content': content, 'parent_comment_id': parentCommentId},
      options: Options(headers: {'X-Idempotency-Key': requestKey}));
    final data = response.data as Map<String, dynamic>;
    return CommunityCommentReceipt(comment: _parseComment(data['comment'] as Map<String, dynamic>, postId),
        commentCount: data['comment_count'] as int);
  }

  @override
  Future<List<CommunityPost>> getFeedPosts({
    required CommunityFeedFilter filter,
    int limit = 20,
    String? cursor,
  }) async {
    String tabValue;
    switch (filter) {
      case CommunityFeedFilter.forYou:
        tabValue = 'for_you';
        break;
      case CommunityFeedFilter.following:
        tabValue = 'following';
        break;
      case CommunityFeedFilter.qa:
        tabValue = 'qa';
        break;
    }

    final queryParams = <String, dynamic>{
      'tab': tabValue,
      'limit': limit,
    };
    if (cursor != null) {
      queryParams['cursor'] = cursor;
    }

    final response = await dio.get(
      '/api/community/feed',
      queryParameters: queryParams,
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch community feed: HTTP ${response.statusCode}',
      );
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Invalid response format from /api/community/feed',
      );
    }

    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw.map((raw) => _parsePost(raw as Map<String, dynamic>)).toList();
  }

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    final response = await dio.get('/api/community/posts/$postId');

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch post detail: HTTP ${response.statusCode}',
      );
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Invalid response format from /api/community/posts/$postId',
      );
    }

    return _parsePost(data);
  }

  @override
  Future<List<QuestionAnswer>> getQuestionAnswers(String questionId, {int limit = 20, String? cursor}) async =>
      (await getAnswerPage(questionId, limit: limit, cursor: cursor)).items;

  @override
  Future<QuestionAnswersPage> getAnswerPage(String questionId, {String? cursor, int limit = 20}) async {
    final response = await dio.get('/api/community/questions/$questionId/answers',
        queryParameters: {'limit': limit, if (cursor != null) 'cursor': cursor});
    final data = response.data as Map<String, dynamic>;
    return QuestionAnswersPage(items: (data['items'] as List)
        .map((a) => _parseAnswer(a as Map<String, dynamic>)).toList(),
        answerCount: data['answer_count'] as int? ?? (data['items'] as List).length,
        nextCursor: data['next_cursor'] as String?);
  }

  @override
  Future<QuestionAnswerReceipt> createAnswer(String questionId, String content, String requestKey) async {
    final response = await dio.post('/api/community/questions/$questionId/answers',
        data: {'content': content}, options: Options(headers: {'X-Idempotency-Key': requestKey}));
    final data = response.data as Map<String, dynamic>;
    return QuestionAnswerReceipt(answer: _parseAnswer(data['answer'] as Map<String, dynamic>),
        answerCount: data['answer_count'] as int);
  }

  @override
  Future<QuestionAnswer> getAnswer(String questionId, String answerId) async =>
      _parseAnswer((await dio.get('/api/community/questions/$questionId/answers/$answerId')).data as Map<String, dynamic>);

  @override
  Future<QuestionAnswer> setAnswerHelpful(String questionId, String answerId, bool desired) async =>
      _parseAnswer((await dio.request('/api/community/questions/$questionId/answers/$answerId/helpful',
          options: Options(method: desired ? 'PUT' : 'DELETE'))).data as Map<String, dynamic>);

  @override
  Future<Map<String, dynamic>> likePost(String postId) async {
    final response = await dio.put('/api/community/posts/$postId/like');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to like post: HTTP ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<Map<String, dynamic>> unlikePost(String postId) async {
    final response = await dio.delete('/api/community/posts/$postId/like');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to unlike post: HTTP ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<bool> savePost(String postId) async {
    final response = await dio.put('/api/community/posts/$postId/save');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to save post: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    return data['is_saved'] as bool? ?? true;
  }

  @override
  Future<bool> unsavePost(String postId) async {
    final response = await dio.delete('/api/community/posts/$postId/save');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to unsave post: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    return data['is_saved'] as bool? ?? false;
  }

  @override
  Future<List<CommunityPost>> getSavedPosts() async {
    final response = await dio.get('/api/community/saved');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch saved posts: HTTP ${response.statusCode}',
      );
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Invalid response format from /api/community/saved',
      );
    }
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw.map((raw) => _parsePost(raw as Map<String, dynamic>)).toList();
  }

  @override
  Future<Map<String, dynamic>> followAuthor(String authorId) async {
    final response = await dio.put('/api/community/authors/$authorId/follow');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to follow author: HTTP ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<Map<String, dynamic>> unfollowAuthor(String authorId) async {
    final response = await dio.delete('/api/community/authors/$authorId/follow');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to unfollow author: HTTP ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<CommunityAuthor> getAuthorProfile(String authorId) async {
    final response = await dio.get('/api/community/authors/$authorId');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch author profile: HTTP ${response.statusCode}',
      );
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Invalid response format from /api/community/authors/$authorId',
      );
    }
    return _parseAuthor(data);
  }

  @override
  Future<List<CommunityAuthor>> getFollowers(
    String authorId, {
    int limit = 20,
    String? cursor,
  }) async {
    final queryParams = <String, dynamic>{'limit': limit};
    if (cursor != null) {
      queryParams['cursor'] = cursor;
    }
    final response = await dio.get(
      '/api/community/authors/$authorId/followers',
      queryParameters: queryParams,
    );
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch followers: HTTP ${response.statusCode}',
      );
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Invalid response format from /api/community/authors/$authorId/followers',
      );
    }
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw.map((raw) => _parseAuthor(raw as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<CommunityAuthor>> getFollowing(
    String authorId, {
    int limit = 20,
    String? cursor,
  }) async {
    final queryParams = <String, dynamic>{'limit': limit};
    if (cursor != null) {
      queryParams['cursor'] = cursor;
    }
    final response = await dio.get(
      '/api/community/authors/$authorId/following',
      queryParameters: queryParams,
    );
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch following: HTTP ${response.statusCode}',
      );
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Invalid response format from /api/community/authors/$authorId/following',
      );
    }
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw.map((raw) => _parseAuthor(raw as Map<String, dynamic>)).toList();
  }

  CommunityPost _parsePost(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'photo';
    CommunityPostType type;
    switch (typeStr) {
      case 'meal': type = CommunityPostType.meal; break;
      case 'text': type = CommunityPostType.text; break;
      case 'workout':
        type = CommunityPostType.workout;
        break;
      case 'qa':
        type = CommunityPostType.qa;
        break;
      case 'photo':
      default:
        type = CommunityPostType.photo;
        break;
    }

    final author = _parseAuthor(json['author'] as Map<String, dynamic>? ?? {});

    PostNutritionInfo? nutrition;
    if (json['nutrition_info'] != null) {
      final n = json['nutrition_info'] as Map<String, dynamic>;
      nutrition = PostNutritionInfo(
        calories: n['calories'] as int? ?? 0,
        proteinGrams: ((n['protein_grams'] as num?) ?? 0).toDouble(),
        carbsGrams: ((n['carbs_grams'] as num?) ?? 0).toDouble(),
        fatGrams: ((n['fat_grams'] as num?) ?? 0).toDouble(),
        badgeLabel: n['badge_label'] as String?,
        proTip: n['pro_tip'] as String?,
      );
    }

    PostWorkoutAttachment? workout;
    if (json['workout_attachment'] != null) {
      final w = json['workout_attachment'] as Map<String, dynamic>;
      final exercisesRaw = w['exercises'] as List<dynamic>? ?? [];
      final exercises = exercisesRaw.map((e) {
        final em = e as Map<String, dynamic>;
        return ExerciseThumbnailPreview(
          title: em['title'] as String? ?? '',
          imageUrl: em['image_url'] as String?,
        );
      }).toList();

      workout = PostWorkoutAttachment(
        title: w['title'] as String? ?? 'Saman Workout',
        category: w['category'] as String? ?? 'Saman Kinetic',
        durationFormatted: w['duration_formatted'] as String? ?? '0 phút',
        exerciseCount: w['exercise_count'] as int? ?? 0,
        setCount: w['set_count'] as int? ?? 0,
        exercises: exercises,
      );
    }

    PostQaInfo? qa;
    if (json['qa_info'] != null) {
      final q = json['qa_info'] as Map<String, dynamic>;
      qa = PostQaInfo(
        question: q['question'] as String? ?? '',
        categoryTag: q['category_tag'] as String? ?? '#HỏiĐáp',
        details: q['details'] as String?,
        respondentCount: q['respondent_count'] as int? ?? 0,
        respondentsSummary: q['respondents_summary'] as String? ?? '',
        respondentInitials: List<String>.from(q['respondent_initials'] as List<dynamic>? ?? []),
      );
    }

    final postId = json['id'] as String? ?? '';
    final rawComments = json['comments'] as List<dynamic>? ?? [];
    final comments = rawComments.map((c) => _parseComment(c as Map<String, dynamic>, postId)).toList();

    return CommunityPost(
      activitySnapshot: json['attachment_snapshot'] == null ? null : PostAttachmentSnapshot.fromPreview({'snapshot':json['attachment_snapshot']}),
      id: postId,
      type: type,
      privacy: json['privacy'] as String? ?? 'public', topic: json['topic'] as String? ?? '',
      author: author,
      timeAgo: json['time_ago'] as String? ?? 'Hôm nay',
      caption: json['caption'] as String? ?? '',
      photoUrls: (json['photo_urls'] as List<dynamic>? ?? [])
          .map((e) => _resolveMediaUrl(e as String?))
          .whereType<String>()
          .toList(),
      nutritionInfo: nutrition,
      workoutAttachment: workout,
      qaInfo: qa,
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? comments.length,
      shareCount: json['share_count'] as int? ?? 0,
      isLikeCountHidden: json['is_like_count_hidden'] as bool? ?? false,
      isLiked: json['is_liked'] as bool? ?? false,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
      likedByNames: List<String>.from(json['liked_by_names'] as List<dynamic>? ?? []),
      likedBySummary: json['liked_by_summary'] as String? ?? '',
      comments: comments,
    );
  }

  String? _resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '${ApiConfig.baseUrl}$url';
    }
    if (url.startsWith('static/')) {
      return '${ApiConfig.baseUrl}/$url';
    }
    return url;
  }

  CommunityAuthor _parseAuthor(Map<String, dynamic> json) {
    return CommunityAuthor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Saman Athlete',
      avatarUrl: _resolveMediaUrl(json['avatar_url'] as String?),
      title: json['title'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      followerCount: json['follower_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      postCount: json['post_count'] as int? ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
      handle: json['handle'] as String?,
      bio: json['bio'] as String?,
      interestTopics: (json['interest_topics'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      workoutPostCount: json['workout_post_count'] as int? ?? 0,
      mealPostCount: json['meal_post_count'] as int? ?? 0,
      totalLikesReceived: json['total_likes_received'] as int? ?? 0,
    );
  }

  CommunityNotification _parseNotification(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String? ?? 'system').toLowerCase();
    CommunityNotificationType type;
    switch (typeStr) {
      case 'like':
        type = CommunityNotificationType.like;
        break;
      case 'comment':
        type = CommunityNotificationType.comment;
        break;
      case 'follow':
        type = CommunityNotificationType.follow;
        break;
      case 'answer':
        type = CommunityNotificationType.answer;
        break;
      case 'system':
      default:
        type = CommunityNotificationType.system;
        break;
    }
    return CommunityNotification(
      id: json['id'] as String? ?? '',
      actorId: json['actor_id'] as String?,
      actorName: json['actor_name'] as String? ?? 'Saman',
      actorAvatarUrl: _resolveMediaUrl(json['actor_avatar_url'] as String?),
      actionText: json['action_text'] as String? ?? '',
      targetSnippet: json['target_snippet'] as String?,
      timeAgo: json['time_ago'] as String? ?? 'Vừa xong',
      isUnread: json['is_unread'] as bool? ?? true,
      type: type,
      targetPostId: json['target_post_id'] as String?,
      targetPostType: json['target_post_type'] as String?,
    );
  }

  Future<List<CommunityNotification>> getNotifications({
    String filter = 'all',
    int limit = 20,
    String? cursor,
  }) async {
    final response = await dio.get(
      '/api/community/notifications',
      queryParameters: {
        'filter': filter,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw
        .map((raw) => _parseNotification(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await dio.patch('/api/community/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await dio.post('/api/community/notifications/read-all');
  }

  Future<List<DraftPost>> getDrafts() async {
    final response = await dio.get('/api/community/drafts');
    final data = response.data as Map<String, dynamic>;
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw
        .map((raw) => DraftPost.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<DraftPost> saveDraft(DraftPost draft) async {
    final response = draft.id.isNotEmpty
        ? await dio.put(
            '/api/community/drafts/${draft.id}',
            data: draft.toJson(),
          )
        : await dio.post(
            '/api/community/drafts',
            data: draft.toJson(),
          );
    return DraftPost.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> deleteDraft(String draftId) async {
    await dio.delete('/api/community/drafts/$draftId');
  }

  Future<List<CommunityPost>> getAuthorPosts(
    String authorId, {
    String tab = 'all',
    int limit = 20,
    String? cursor,
  }) async {
    final response = await dio.get(
      '/api/community/authors/$authorId/posts',
      queryParameters: {
        'tab': tab,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return itemsRaw
        .map((raw) => _parsePost(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<CommunityAuthor> updateProfile(Map<String, dynamic> body) async {
    final response = await dio.patch('/api/community/profile', data: body);
    return _parseAuthor(Map<String, dynamic>.from(response.data as Map));
  }

  Future<CommunityDiscoverData> getDiscoverData({
    String topic = 'all',
    String? searchQuery,
  }) async {
    final trimmedQuery = searchQuery?.trim();
    final response = await dio.get(
      '/api/community/discover',
      queryParameters: {
        'topic': topic,
        if (trimmedQuery != null && trimmedQuery.isNotEmpty) 'q': trimmedQuery,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final topicChips = (data['topic_chips'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    final activeTopic = data['active_topic'] as String? ?? topic;

    final gridRaw = data['grid_items'] as List<dynamic>? ?? const [];
    final gridItems = gridRaw.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      return CommunityVisualGridItem(
        id: item['id'] as String? ?? '',
        postId: item['post_id'] as String?,
        imageUrl: _resolveMediaUrl(item['image_url'] as String?) ?? '',
        likeCount: (item['like_count'] as num?)?.toInt() ?? 0,
        hasMultiPhoto: item['has_multi_photo'] as bool? ?? false,
        hasVideo: item['has_video'] as bool? ?? false,
        altText: item['alt_text'] as String?,
      );
    }).toList();

    final trendingRaw = data['trending_topics'] as List<dynamic>? ?? const [];
    final trendingTopics = trendingRaw.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      return CommunityTrendingTopic(
        id: item['id'] as String? ?? '',
        hashtag: item['hashtag'] as String? ?? '',
        postCountFormatted: item['post_count_formatted'] as String? ?? '',
        growthPercent: item['growth_percent'] as String? ?? 'Ổn định',
        isStable: item['is_stable'] as bool? ?? true,
        iconName: item['icon_name'] as String? ?? 'tag',
      );
    }).toList();

    final creatorsRaw = data['recommended_creators'] as List<dynamic>? ?? const [];
    final recommendedCreators = creatorsRaw
        .map((raw) => _parseAuthor(Map<String, dynamic>.from(raw as Map)))
        .toList();

    return CommunityDiscoverData(
      topicChips: topicChips.isNotEmpty
          ? topicChips
          : const ['all', 'workout', 'meal', 'recipe', 'qna', 'journey'],
      activeTopic: activeTopic,
      gridItems: gridItems,
      trendingTopics: trendingTopics,
      recommendedCreators: recommendedCreators,
    );
  }

  CommunityComment _parseComment(Map<String, dynamic> json, String postId) {
    final repliesRaw = json['replies'] as List<dynamic>? ?? [];
    final replies = repliesRaw.map((r) => _parseComment(r as Map<String, dynamic>, postId)).toList();

    return CommunityComment(
      id: json['id'] as String? ?? '',
      postId: postId,
      author: _parseAuthor(json['author'] as Map<String, dynamic>? ?? {}),
      timeAgo: json['time_ago'] as String? ?? 'Vừa xong',
      content: json['content'] as String? ?? '',
      parentCommentId: json['parent_comment_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      likeCount: json['like_count'] as int? ?? 0,
      isLiked: json['is_liked'] as bool? ?? false,
      isAuthorReply: json['is_author_reply'] as bool? ?? false,
      replyToAuthorName: json['reply_to_author_name'] as String?,
      replies: replies,
    );
  }

  QuestionAnswer _parseAnswer(Map<String, dynamic> json) {
    return QuestionAnswer(
      id: json['id'] as String? ?? '',
      questionId: json['question_id'] as String? ?? '',
      author: _parseAuthor(json['author'] as Map<String, dynamic>? ?? {}),
      content: json['content'] as String? ?? '',
      timeAgo: json['time_ago'] as String? ?? 'Gần đây',
      upvoteCount: json['upvote_count'] as int? ?? 0,
      isUpvoted: json['is_upvoted'] as bool? ?? false,
      isPinnedBest: json['is_pinned_best'] as bool? ?? false,
    );
  }

  // --- Wave 4: Social Settings, Block/Mute/Report, Stories 24h, Share ---

  Future<CommunitySettings> getSettings() async {
    final response = await dio.get('/api/community/settings');
    return CommunitySettings.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<CommunitySettings> updateSettings(Map<String, dynamic> body) async {
    final response = await dio.patch('/api/community/settings', data: body);
    return CommunitySettings.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<bool> blockUser(String targetUserId) async {
    final response = await dio.put('/api/community/users/$targetUserId/block');
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['is_blocked'] as bool? ?? true;
  }

  Future<bool> unblockUser(String targetUserId) async {
    final response = await dio.delete('/api/community/users/$targetUserId/block');
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['is_blocked'] as bool? ?? false;
  }

  Future<List<CommunityAuthor>> getBlockedUsers() async {
    final response = await dio.get('/api/community/settings/blocked');
    final data = Map<String, dynamic>.from(response.data as Map);
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((raw) => _parseAuthor(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<bool> muteUser(String targetUserId) async {
    final response = await dio.put('/api/community/users/$targetUserId/mute');
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['is_muted'] as bool? ?? true;
  }

  Future<bool> unmuteUser(String targetUserId) async {
    final response = await dio.delete('/api/community/users/$targetUserId/mute');
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['is_muted'] as bool? ?? false;
  }

  Future<List<CommunityAuthor>> getMutedUsers() async {
    final response = await dio.get('/api/community/settings/muted');
    final data = Map<String, dynamic>.from(response.data as Map);
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((raw) => _parseAuthor(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<CommunityReportReceipt> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    final response = await dio.post(
      '/api/community/reports',
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'details': details,
      },
    );
    return CommunityReportReceipt.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  CommunityStory _parseStory(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now().toUtc();
    final expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '') ??
        createdAt.add(const Duration(hours: 24));
    return CommunityStory(
      id: json['id'] as String? ?? '',
      userId: (json['user_id'] ?? json['author_id'] ?? '') as String,
      mediaType: json['media_type'] as String? ?? 'text',
      mediaUrl: _resolveMediaUrl(json['media_url'] as String?),
      caption: json['caption'] as String? ?? '',
      backgroundColor: json['background_color'] as String?,
      privacy: json['privacy'] as String? ?? 'public',
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      isViewed: json['is_viewed'] as bool? ?? false,
      timeAgo: json['time_ago'] as String? ?? 'Vừa xong',
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  Future<List<CommunityStoryAuthorGroup>> getStories() async {
    final response = await dio.get('/api/community/stories');
    final data = Map<String, dynamic>.from(response.data as Map);
    final itemsRaw = data['items'] as List<dynamic>? ?? const [];
    return itemsRaw.map((raw) {
      final group = Map<String, dynamic>.from(raw as Map);
      final storiesRaw = group['stories'] as List<dynamic>? ?? const [];
      return CommunityStoryAuthorGroup(
        author: _parseAuthor(
          Map<String, dynamic>.from(group['author'] as Map? ?? const {}),
        ),
        isSelf: group['is_self'] as bool? ?? false,
        hasUnviewed: group['has_unviewed'] as bool? ?? false,
        latestCreatedAt: group['latest_created_at'] != null
            ? DateTime.tryParse(group['latest_created_at'].toString())
            : null,
        stories: storiesRaw
            .map((s) => _parseStory(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
    }).toList();
  }

  Future<CommunityStory> createStory({
    required String mediaType,
    String? mediaUrl,
    String caption = '',
    String? backgroundColor,
    String privacy = 'public',
  }) async {
    final response = await dio.post(
      '/api/community/stories',
      data: {
        'media_type': mediaType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        'caption': caption,
        if (backgroundColor != null) 'background_color': backgroundColor,
        'privacy': privacy,
      },
    );
    return _parseStory(Map<String, dynamic>.from(response.data as Map));
  }

  Future<int> markStoryViewed(String storyId) async {
    final response = await dio.post('/api/community/stories/$storyId/view');
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['view_count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> deleteStory(String storyId) async {
    final response = await dio.delete('/api/community/stories/$storyId');
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['success'] as bool? ?? true;
  }

  Future<int> sharePost(String postId) async {
    final response = await dio.post('/api/community/posts/$postId/share');
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['share_count'] as num?)?.toInt() ?? 0;
  }

  // --- Wave 4: Direct Messages (Messenger-Lite) ---

  DmConversation _parseConversation(Map<String, dynamic> json) {
    final peerRaw = Map<String, dynamic>.from(json['peer'] as Map? ?? const {});
    final peer = DmParticipant(
      id: peerRaw['id'] as String? ?? '',
      name: peerRaw['name'] as String? ?? 'Saman Athlete',
      avatarUrl: _resolveMediaUrl(peerRaw['avatar_url'] as String?),
      isVerified: peerRaw['is_verified'] as bool? ?? false,
      showActivityStatus: peerRaw['show_activity_status'] as bool? ?? true,
    );
    return DmConversation(
      id: json['id'] as String? ?? '',
      peer: peer,
      lastMessagePreview: json['last_message_preview'] as String? ?? '',
      lastMessageType: json['last_message_type'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'].toString())
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  Future<DmConversation> createOrGetConversation(String targetUserId) async {
    final response = await dio.post(
      '/api/community/dm/conversations',
      data: {'target_user_id': targetUserId},
    );
    return _parseConversation(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<DmConversationsPage> getConversations({
    int limit = 20,
    String? cursor,
  }) async {
    final response = await dio.get(
      '/api/community/dm/conversations',
      queryParameters: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final itemsRaw = data['items'] as List<dynamic>? ?? const [];
    return DmConversationsPage(
      items: itemsRaw
          .map((raw) => _parseConversation(Map<String, dynamic>.from(raw as Map)))
          .toList(),
      totalUnreadCount: (data['total_unread_count'] as num?)?.toInt() ?? 0,
      nextCursor: data['next_cursor'] as String?,
    );
  }

  Future<DmMessagesPage> getMessages(
    String conversationId, {
    int limit = 30,
    String? cursor,
  }) async {
    final response = await dio.get(
      '/api/community/dm/conversations/$conversationId/messages',
      queryParameters: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final itemsRaw = data['items'] as List<dynamic>? ?? const [];
    return DmMessagesPage(
      items: itemsRaw
          .map(
            (raw) => dmMessageFromJson(
              Map<String, dynamic>.from(raw as Map),
              resolveMediaUrl: _resolveMediaUrl,
            ),
          )
          .toList(),
      nextCursor: data['next_cursor'] as String?,
    );
  }

  Future<DmMessage> sendMessage({
    required String conversationId,
    required DmMessageType type,
    String content = '',
    String? mediaUrl,
    double? durationSeconds,
    String? sharedPostId,
    String? replyToMessageId,
    String? idempotencyKey,
  }) async {
    final response = await dio.post(
      '/api/community/dm/conversations/$conversationId/messages',
      data: {
        'type': type.toApiValue(),
        'content': content,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (sharedPostId != null) 'shared_post_id': sharedPostId,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      },
      options: idempotencyKey != null
          ? Options(headers: {'X-Idempotency-Key': idempotencyKey})
          : null,
    );
    return dmMessageFromJson(
      Map<String, dynamic>.from(response.data as Map),
      resolveMediaUrl: _resolveMediaUrl,
    );
  }

  Future<void> markConversationRead(String conversationId) async {
    await dio.post('/api/community/dm/conversations/$conversationId/read');
  }

  Future<bool> deleteMessage(String messageId) async {
    final response = await dio.delete('/api/community/dm/messages/$messageId');
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['is_deleted'] as bool? ?? true;
  }

  Future<int> getDmUnreadCount() async {
    final response = await dio.get('/api/community/dm/unread-count');
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['unread_count'] as num?)?.toInt() ?? 0;
  }

  Future<DmMediaUploadResult> uploadDmMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    });
    final response = await dio.post(
      '/api/community/dm/media/upload',
      data: formData,
    );
    final raw = Map<String, dynamic>.from(response.data as Map);
    final result = DmMediaUploadResult.fromJson(raw);
    return DmMediaUploadResult(
      mediaUrl: _resolveMediaUrl(result.mediaUrl) ?? result.mediaUrl,
      mediaKind: result.mediaKind,
      contentType: result.contentType,
      fileName: result.fileName,
      sizeBytes: result.sizeBytes,
    );
  }
}

extension CommunityRemoteDatasourceWave4Extension on CommunityRemoteDatasource {
  Future<CommunitySettings> getSettings() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getSettings();
    }
    throw UnsupportedError('Settings not supported by this datasource double');
  }

  Future<CommunitySettings> updateSettings(Map<String, dynamic> body) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).updateSettings(body);
    }
    throw UnsupportedError('Settings not supported by this datasource double');
  }

  Future<bool> blockUser(String targetUserId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).blockUser(targetUserId);
    }
    throw UnsupportedError('Block not supported by this datasource double');
  }

  Future<bool> unblockUser(String targetUserId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).unblockUser(targetUserId);
    }
    throw UnsupportedError('Unblock not supported by this datasource double');
  }

  Future<List<CommunityAuthor>> getBlockedUsers() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getBlockedUsers();
    }
    throw UnsupportedError('Blocked list not supported by this datasource double');
  }

  Future<bool> muteUser(String targetUserId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).muteUser(targetUserId);
    }
    throw UnsupportedError('Mute not supported by this datasource double');
  }

  Future<bool> unmuteUser(String targetUserId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).unmuteUser(targetUserId);
    }
    throw UnsupportedError('Unmute not supported by this datasource double');
  }

  Future<List<CommunityAuthor>> getMutedUsers() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getMutedUsers();
    }
    throw UnsupportedError('Muted list not supported by this datasource double');
  }

  Future<CommunityReportReceipt> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).reportContent(
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        details: details,
      );
    }
    throw UnsupportedError('Report not supported by this datasource double');
  }

  Future<List<CommunityStoryAuthorGroup>> getStories() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getStories();
    }
    throw UnsupportedError('Stories not supported by this datasource double');
  }

  Future<CommunityStory> createStory({
    required String mediaType,
    String? mediaUrl,
    String caption = '',
    String? backgroundColor,
    String privacy = 'public',
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).createStory(
        mediaType: mediaType,
        mediaUrl: mediaUrl,
        caption: caption,
        backgroundColor: backgroundColor,
        privacy: privacy,
      );
    }
    throw UnsupportedError('Create story not supported by this datasource double');
  }

  Future<int> markStoryViewed(String storyId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).markStoryViewed(storyId);
    }
    throw UnsupportedError('Story view not supported by this datasource double');
  }

  Future<bool> deleteStory(String storyId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).deleteStory(storyId);
    }
    throw UnsupportedError('Delete story not supported by this datasource double');
  }

  Future<int> sharePost(String postId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).sharePost(postId);
    }
    throw UnsupportedError('Share post not supported by this datasource double');
  }

  Future<DmConversation> createOrGetConversation(String targetUserId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).createOrGetConversation(targetUserId);
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<DmConversationsPage> getConversations({int limit = 20, String? cursor}) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getConversations(
        limit: limit,
        cursor: cursor,
      );
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<DmMessagesPage> getMessages(
    String conversationId, {
    int limit = 30,
    String? cursor,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getMessages(
        conversationId,
        limit: limit,
        cursor: cursor,
      );
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<DmMessage> sendMessage({
    required String conversationId,
    required DmMessageType type,
    String content = '',
    String? mediaUrl,
    double? durationSeconds,
    String? sharedPostId,
    String? replyToMessageId,
    String? idempotencyKey,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).sendMessage(
        conversationId: conversationId,
        type: type,
        content: content,
        mediaUrl: mediaUrl,
        durationSeconds: durationSeconds,
        sharedPostId: sharedPostId,
        replyToMessageId: replyToMessageId,
        idempotencyKey: idempotencyKey,
      );
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<void> markConversationRead(String conversationId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).markConversationRead(conversationId);
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<bool> deleteMessage(String messageId) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).deleteMessage(messageId);
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<int> getDmUnreadCount() {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).getDmUnreadCount();
    }
    throw UnsupportedError('DM not supported by this datasource double');
  }

  Future<DmMediaUploadResult> uploadDmMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    if (this is CommunityRemoteDatasourceImpl) {
      return (this as CommunityRemoteDatasourceImpl).uploadDmMedia(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
    }
    throw UnsupportedError('DM media upload not supported by this datasource double');
  }
}

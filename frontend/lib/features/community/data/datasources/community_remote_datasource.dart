import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../../domain/models/community_author.dart';
import '../../domain/models/community_comment.dart';
import '../../domain/models/community_post.dart';
import '../../domain/models/question_answer.dart';
import '../../domain/models/post_attachment_snapshot.dart';

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
      photoUrls: List<String>.from(json['photo_urls'] as List<dynamic>? ?? []),
      nutritionInfo: nutrition,
      workoutAttachment: workout,
      qaInfo: qa,
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? comments.length,
      isLiked: json['is_liked'] as bool? ?? false,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
      likedByNames: List<String>.from(json['liked_by_names'] as List<dynamic>? ?? []),
      likedBySummary: json['liked_by_summary'] as String? ?? '',
      comments: comments,
    );
  }

  CommunityAuthor _parseAuthor(Map<String, dynamic> json) {
    return CommunityAuthor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Saman Athlete',
      avatarUrl: json['avatar_url'] as String?,
      title: json['title'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      followerCount: json['follower_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      postCount: json['post_count'] as int? ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
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
}

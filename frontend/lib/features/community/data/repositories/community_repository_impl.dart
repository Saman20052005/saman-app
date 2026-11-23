import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

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
import '../../domain/repositories/community_repository.dart';
import '../datasources/community_fake_datasource.dart';
import '../datasources/community_remote_datasource.dart';

class IndeterminateMutationException implements Exception {
  final String postId;
  final bool desiredState;
  final dynamic originalError;

  IndeterminateMutationException({
    required this.postId,
    required this.desiredState,
    this.originalError,
  });

  @override
  String toString() =>
      'IndeterminateMutationException(postId: $postId, desiredState: $desiredState, error: $originalError)';
}

class CommunityRepositoryImpl implements CommunityRepository {
  final CommunityFakeDatasource _fakeDatasource;
  final CommunityRemoteDatasource? _remoteDatasource;
  final bool _useRemote;
  final Map<String, int> _commentCounts = {};
  final Map<String, int> _answerCounts = {};
  int? answerCountFor(String questionId) => _answerCounts[questionId];
  void _rememberAnswerCount(String id, int count) {
    if (count > (_answerCounts[id] ?? -1)) _answerCounts[id] = count;
  }
  int? commentCountFor(String postId) => _commentCounts[postId];

  final Set<String> _remoteLikedPostIds = <String>{};
  final Set<String> _remoteBookmarkedPostIds = <String>{};
  final Set<String> _remoteFollowedAuthorIds = <String>{};

  String? _activeUserId;
  int _generation = 0;

  CommunityRepositoryImpl({
    CommunityFakeDatasource? fakeDatasource,
    CommunityFakeDatasource? datasource,
    CommunityRemoteDatasource? remoteDatasource,
    bool useRemote = false,
    String? activeUserId,
  })  : _fakeDatasource = fakeDatasource ?? datasource ?? CommunityFakeDatasource(),
        _remoteDatasource = remoteDatasource,
        _useRemote = useRemote,
        _activeUserId = activeUserId;

  bool get isRemote => _useRemote && _remoteDatasource != null;
  int get generation => _generation;
  @override
  String? get activeUserId => _activeUserId;
  Set<String> get remoteFollowedAuthorIds => Set.unmodifiable(_remoteFollowedAuthorIds);

  void resetState() {
    _commentCounts.clear();
    _answerCounts.clear();
    _remoteLikedPostIds.clear();
    _remoteBookmarkedPostIds.clear();
    _remoteFollowedAuthorIds.clear();
  }

  void resetForUser(String? userId) {
    _activeUserId = userId;
    _generation++;
    resetState();
  }

  bool _isIndeterminateNetworkError(dynamic error) {
    if (error is DioException) {
      if (error.response == null) {
        return error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError;
      }
      final status = error.response?.statusCode;
      if (status == 500 || status == 502 || status == 503 || status == 504) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<CommunityPost>> getFeedPosts({
    required CommunityFeedFilter filter,
  }) async {
    final currentGen = _generation;
    if (isRemote) {
      final posts = await _remoteDatasource!.getFeedPosts(filter: filter);
      if (currentGen != _generation) {
        return [];
      }
      for (final p in posts) {
        if (p.isLiked) {
          _remoteLikedPostIds.add(p.id);
        } else {
          _remoteLikedPostIds.remove(p.id);
        }
        if (p.isBookmarked) {
          _remoteBookmarkedPostIds.add(p.id);
        } else {
          _remoteBookmarkedPostIds.remove(p.id);
        }
        if (p.author.isFollowing) {
          _remoteFollowedAuthorIds.add(p.author.id);
        } else {
          _remoteFollowedAuthorIds.remove(p.author.id);
        }
      }
      return posts.map((p) => p.copyWith(qaInfo: p.qaInfo?.withAnswerCount(
          (_answerCounts[p.id] ?? 0) > (p.qaInfo?.respondentCount ?? 0) ? _answerCounts[p.id]! : p.qaInfo!.respondentCount), commentCount:
          (_commentCounts[p.id] ?? 0) > p.commentCount ? _commentCounts[p.id] : p.commentCount)).toList();
    }
    return _fakeDatasource.getFeedPosts(filter);
  }

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    final currentGen = _generation;
    if (isRemote) {
      final post = await _remoteDatasource!.getPostDetail(postId);
      if (currentGen != _generation) {
        return post;
      }
      if (post.isLiked) {
        _remoteLikedPostIds.add(post.id);
      } else {
        _remoteLikedPostIds.remove(post.id);
      }
      if (post.isBookmarked) {
        _remoteBookmarkedPostIds.add(post.id);
      } else {
        _remoteBookmarkedPostIds.remove(post.id);
      }
      if (post.author.isFollowing) {
        _remoteFollowedAuthorIds.add(post.author.id);
      } else {
        _remoteFollowedAuthorIds.remove(post.author.id);
      }
      return post;
    }
    return _fakeDatasource.getPostDetail(postId);
  }

  @override
  Future<bool> deletePost(String postId) async {
    if (isRemote) {
      return await _remoteDatasource!.deletePost(postId);
    }
    return true;
  }

  @override
  Future<bool> toggleLike(String postId) async {
    final currentGen = _generation;
    if (isRemote) {
      final isCurrentlyLiked = _remoteLikedPostIds.contains(postId);
      final desiredIsLiked = !isCurrentlyLiked;
      try {
        if (isCurrentlyLiked) {
          final res = await _remoteDatasource!.unlikePost(postId);
          if (currentGen != _generation) return false;
          _remoteLikedPostIds.remove(postId);
          return res['is_liked'] as bool? ?? false;
        } else {
          final res = await _remoteDatasource!.likePost(postId);
          if (currentGen != _generation) return false;
          _remoteLikedPostIds.add(postId);
          return res['is_liked'] as bool? ?? true;
        }
      } catch (e) {
        if (currentGen != _generation) {
          return false;
        }
        if (_isIndeterminateNetworkError(e)) {
          // Attempt reconciliation with canonical server state
          try {
            final canonicalPost = await _remoteDatasource!.getPostDetail(postId);
            if (currentGen != _generation) return false;
            if (canonicalPost.isLiked) {
              _remoteLikedPostIds.add(postId);
            } else {
              _remoteLikedPostIds.remove(postId);
            }
            return canonicalPost.isLiked;
          } catch (reconcileErr) {
            if (currentGen != _generation) return false;
            if (reconcileErr is DioException) {
              final status = reconcileErr.response?.statusCode;
              if (status == 401 || status == 404) {
                _remoteLikedPostIds.remove(postId);
                rethrow;
              }
            }
            throw IndeterminateMutationException(
              postId: postId,
              desiredState: desiredIsLiked,
              originalError: e,
            );
          }
        }
        rethrow;
      }
    }
    return _fakeDatasource.toggleLike(postId);
  }

  @override
  Future<bool> toggleBookmark(String postId) async {
    final currentGen = _generation;
    if (isRemote) {
      final isCurrentlyBookmarked = _remoteBookmarkedPostIds.contains(postId);
      final desiredIsBookmarked = !isCurrentlyBookmarked;
      try {
        if (isCurrentlyBookmarked) {
          final res = await _remoteDatasource!.unsavePost(postId);
          if (currentGen != _generation) return false;
          _remoteBookmarkedPostIds.remove(postId);
          return res;
        } else {
          final res = await _remoteDatasource!.savePost(postId);
          if (currentGen != _generation) return false;
          _remoteBookmarkedPostIds.add(postId);
          return res;
        }
      } catch (e) {
        if (currentGen != _generation) {
          return false;
        }
        if (_isIndeterminateNetworkError(e)) {
          // Attempt reconciliation with canonical server state
          try {
            final canonicalPost = await _remoteDatasource!.getPostDetail(postId);
            if (currentGen != _generation) return false;
            if (canonicalPost.isBookmarked) {
              _remoteBookmarkedPostIds.add(postId);
            } else {
              _remoteBookmarkedPostIds.remove(postId);
            }
            return canonicalPost.isBookmarked;
          } catch (reconcileErr) {
            if (currentGen != _generation) return false;
            if (reconcileErr is DioException) {
              final status = reconcileErr.response?.statusCode;
              if (status == 401 || status == 404) {
                _remoteBookmarkedPostIds.remove(postId);
                rethrow;
              }
            }
            throw IndeterminateMutationException(
              postId: postId,
              desiredState: desiredIsBookmarked,
              originalError: e,
            );
          }
        }
        rethrow;
      }
    }
    return _fakeDatasource.toggleBookmark(postId);
  }

  @override
  Future<bool> toggleFollow(String authorId) async {
    final currentGen = _generation;
    if (isRemote) {
      final isCurrentlyFollowed = _remoteFollowedAuthorIds.contains(authorId);
      final desiredIsFollowed = !isCurrentlyFollowed;
      try {
        if (isCurrentlyFollowed) {
          final res = await _remoteDatasource!.unfollowAuthor(authorId);
          if (currentGen != _generation) return false;
          _remoteFollowedAuthorIds.remove(authorId);
          return res['is_following'] as bool? ?? false;
        } else {
          final res = await _remoteDatasource!.followAuthor(authorId);
          if (currentGen != _generation) return false;
          _remoteFollowedAuthorIds.add(authorId);
          return res['is_following'] as bool? ?? true;
        }
      } catch (e) {
        if (currentGen != _generation) {
          return false;
        }
        if (_isIndeterminateNetworkError(e)) {
          // Attempt reconciliation with canonical server state
          try {
            final canonicalProfile = await _remoteDatasource!.getAuthorProfile(authorId);
            if (currentGen != _generation) return false;
            if (canonicalProfile.isFollowing) {
              _remoteFollowedAuthorIds.add(authorId);
            } else {
              _remoteFollowedAuthorIds.remove(authorId);
            }
            return canonicalProfile.isFollowing;
          } catch (reconcileErr) {
            if (currentGen != _generation) return false;
            if (reconcileErr is DioException) {
              final status = reconcileErr.response?.statusCode;
              if (status == 401 || status == 404) {
                _remoteFollowedAuthorIds.remove(authorId);
                rethrow;
              }
            }
            throw IndeterminateMutationException(
              postId: authorId,
              desiredState: desiredIsFollowed,
              originalError: e,
            );
          }
        }
        rethrow;
      }
    }
    return _fakeDatasource.toggleFollow(authorId);
  }

  @override
  Future<CommunityCommentsPage> getComments(String postId, {String? cursor}) async {
    final gen = _generation;
    if (isRemote) {
      final page = await _remoteDatasource!.getComments(postId, cursor: cursor);
      if (gen != _generation) throw StateError('Community identity changed');
      _commentCounts[postId] = page.commentCount;
      return page;
    }
    final post = _fakeDatasource.getPostDetail(postId);
    return CommunityCommentsPage(items: post.comments, commentCount: post.commentCount);
  }

  @override
  Future<CommunityComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
    String? replyToAuthorName,
    String? requestKey,
  }) async {
    if (isRemote) {
      if (requestKey == null) throw ArgumentError('Stable requestKey required');
      final gen = _generation;
      final receipt = await _remoteDatasource!.createComment(postId, content,
          parentCommentId: parentCommentId, requestKey: requestKey);
      if (gen != _generation) throw StateError('Community identity changed');
      _commentCounts[postId] = receipt.commentCount;
      return receipt.comment;
    }
    return _fakeDatasource.addComment(
      postId: postId,
      content: content,
      parentCommentId: parentCommentId,
      replyToAuthorName: replyToAuthorName,
    );
  }

  @override
  Future<CommunityDiscoverData> getDiscoverData({
    String topic = 'all',
    String? searchQuery,
  }) async {
    final currentGen = _generation;
    if (isRemote) {
      final data = await _remoteDatasource!.getDiscoverData(
        topic: topic,
        searchQuery: searchQuery,
      );
      if (currentGen != _generation) {
        return const CommunityDiscoverData();
      }
      for (final c in data.recommendedCreators) {
        if (c.isFollowing) {
          _remoteFollowedAuthorIds.add(c.id);
        } else {
          _remoteFollowedAuthorIds.remove(c.id);
        }
      }
      return data;
    }
    return _fakeDatasource.getDiscoverData(
      topic: topic,
      searchQuery: searchQuery,
    );
  }

  // JCOM-03: Publishing & Activity Attachments
  static String publicationPrivacy(String audience) {
    const values = {'Công khai':'public','Người theo dõi':'followers_only','Chỉ mình tôi':'private',
      'public':'public','followers_only':'followers_only','private':'private'};
    final value = values[audience];
    if (value == null) throw UnsupportedError('community_publish_audience_unsupported');
    return value;
  }

  @override
  Future<CommunityPost> publishPost({
    required String caption,
    String? requestKey,
    List<String> mediaUrls = const [],
    PostAttachmentSnapshot? attachment,
    String audience = 'Công khai',
    String topic = '#BữaĂn',
    bool allowComments = true,
  }) async {
    if (isRemote) {
      if (mediaUrls.isNotEmpty) {
        if (mediaUrls.length > 10) {
          throw UnsupportedError('community_publish_media_unsupported');
        }
        if (attachment != null) {
          throw UnsupportedError('community_publish_media_attachment_conflict');
        }
      }
      if (requestKey == null) throw ArgumentError('Stable publication request key required');
      final List<String> resolvedPhotoUrls = [];
      for (final item in mediaUrls) {
        if (item.startsWith('http://') || item.startsWith('https://') || item.startsWith('/static/')) {
          resolvedPhotoUrls.add(item);
        } else {
          final xfile = XFile(item);
          final bytes = await xfile.readAsBytes();
          final filename = xfile.name.isNotEmpty ? xfile.name : 'photo.jpg';
          final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'jpg';
          final mimeType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
          final uploadRes = await _remoteDatasource!.uploadMedia(
            bytes: bytes,
            filename: filename,
            mimeType: mimeType,
          );
          final uploadedUrl = uploadRes['media_url'] as String;
          resolvedPhotoUrls.add(uploadedUrl);
        }
      }

      final postType = attachment != null
          ? attachment.type.name
          : (resolvedPhotoUrls.isNotEmpty ? 'photo' : 'text');

      return _remoteDatasource!.publishPost({
        'type': postType,
        'content': caption,
        if (resolvedPhotoUrls.isNotEmpty) 'photo_urls': resolvedPhotoUrls,
          if (attachment != null) 'attachment':attachment.publicationSelection(),
          'privacy':publicationPrivacy(audience),'topic':topic,'allow_comments':allowComments},requestKey);
    }
    return _fakeDatasource.publishPost(
      caption: caption,
      mediaUrls: mediaUrls,
      attachment: attachment,
      audience: audience,
      topic: topic,
      allowComments: allowComments,
    );
  }

  @override
  Future<CommunityPost> publishQuestion({
    required String question,
    required String categoryTag,
    String? details,
    String audience = 'Công khai',
    String? requestKey,
  }) async {
    if (isRemote) {
      if (requestKey == null) throw ArgumentError('Stable publication request key required');
      return _remoteDatasource!.publishPost({'type':'qa','title':question,'body':details ?? '',
          'privacy':publicationPrivacy(audience),'topic':categoryTag},requestKey);
    }
    return _fakeDatasource.publishQuestion(
      question: question,
      categoryTag: categoryTag,
      details: details,
    );
  }

  @override
  Future<PostAttachmentSnapshot> previewActivity(PostAttachmentSnapshot source, {required bool duration, required bool items, required bool sensitive}) async {
    if (!isRemote) return source.copyWith(includeDuration:duration,includeExercisesOrFoods:items,includeLoadOrMacros:sensitive).sanitize();
    final gen = _generation;
    final result = await _remoteDatasource!.previewActivity(source.type.name,source.id,
      {'include_duration':duration,'include_exercises_or_foods':items,'include_load_or_macros':sensitive});
    if (gen != _generation) throw StateError('Community identity changed'); return result;
  }

  @override
  Future<List<PostAttachmentSnapshot>> getRecentWorkoutActivities() async {
    if (isRemote) {
      final gen = _generation; final result = await _remoteDatasource!.getAttachmentSources('workout');
      if (gen != _generation) throw StateError('Community identity changed'); return result;
    }
    return _fakeDatasource.getRecentWorkoutActivities();
  }

  @override
  Future<List<PostAttachmentSnapshot>> getRecentMealActivities() async {
    if (isRemote) {
      final gen = _generation; final result = await _remoteDatasource!.getAttachmentSources('meal');
      if (gen != _generation) throw StateError('Community identity changed'); return result;
    }
    return _fakeDatasource.getRecentMealActivities();
  }

  @override
  Future<List<DraftPost>> getDrafts() async {
    final currentGen = _generation;
    if (isRemote) {
      final drafts = await _remoteDatasource!.getDrafts();
      if (currentGen != _generation) return [];
      return drafts;
    }
    return _fakeDatasource.getDrafts();
  }

  @override
  Future<void> saveDraft(DraftPost draft) async {
    if (isRemote) {
      await _remoteDatasource!.saveDraft(draft);
      return;
    }
    _fakeDatasource.saveDraft(draft);
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    if (isRemote) {
      await _remoteDatasource!.deleteDraft(draftId);
      return;
    }
    _fakeDatasource.deleteDraft(draftId);
  }

  // JCOM-04: Profile, Notifications, Saved, Q&A
  @override
  Future<List<CommunityPost>> getSavedPosts() async {
    final currentGen = _generation;
    if (isRemote) {
      final posts = await _remoteDatasource!.getSavedPosts();
      if (currentGen != _generation) {
        return [];
      }
      for (final p in posts) {
        _remoteBookmarkedPostIds.add(p.id);
        if (p.isLiked) {
          _remoteLikedPostIds.add(p.id);
        }
      }
      return posts;
    }
    return _fakeDatasource.getSavedPosts();
  }

  @override
  Future<List<CommunityNotification>> getNotifications() async {
    final currentGen = _generation;
    if (isRemote) {
      final notifs = await _remoteDatasource!.getNotifications();
      if (currentGen != _generation) return [];
      return notifs;
    }
    return _fakeDatasource.getNotifications();
  }

  @override
  Future<void> markNotificationRead(String id) async {
    if (isRemote) {
      await _remoteDatasource!.markNotificationRead(id);
      return;
    }
    _fakeDatasource.markNotificationRead(id);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    if (isRemote) {
      await _remoteDatasource!.markAllNotificationsRead();
      return;
    }
    _fakeDatasource.markAllNotificationsRead();
  }

  @override
  Future<CommunityAuthor> getAuthorProfile(String authorId) async {
    final currentGen = _generation;
    if (isRemote) {
      final author = await _remoteDatasource!.getAuthorProfile(authorId);
      if (currentGen != _generation) return author;
      if (author.isFollowing) {
        _remoteFollowedAuthorIds.add(author.id);
      } else {
        _remoteFollowedAuthorIds.remove(author.id);
      }
      return author;
    }
    return _fakeDatasource.getAuthorProfile(authorId);
  }

  @override
  Future<List<CommunityPost>> getAuthorPosts(
    String authorId, {
    String tab = 'all',
    String? cursor,
  }) async {
    final currentGen = _generation;
    if (isRemote) {
      final posts = await _remoteDatasource!.getAuthorPosts(
        authorId,
        tab: tab,
        cursor: cursor,
      );
      if (currentGen != _generation) return [];
      for (final p in posts) {
        if (p.isLiked) {
          _remoteLikedPostIds.add(p.id);
        } else {
          _remoteLikedPostIds.remove(p.id);
        }
        if (p.isBookmarked) {
          _remoteBookmarkedPostIds.add(p.id);
        } else {
          _remoteBookmarkedPostIds.remove(p.id);
        }
      }
      return posts;
    }
    return _fakeDatasource.getAuthorPosts(authorId, tab: tab);
  }

  @override
  Future<CommunityAuthor> updateProfile({
    String? name,
    String? handle,
    String? title,
    String? bio,
    List<String>? interestTopics,
    String? avatarUrl,
    String? localAvatarPath,
    bool removeAvatar = false,
  }) async {
    if (isRemote) {
      String? resolvedAvatarUrl;
      if (removeAvatar) {
        resolvedAvatarUrl = '';
      } else if (localAvatarPath != null && localAvatarPath.isNotEmpty) {
        final xfile = XFile(localAvatarPath);
        final bytes = await xfile.readAsBytes();
        final filename = xfile.name.isNotEmpty ? xfile.name : 'avatar.jpg';
        final ext =
            filename.contains('.') ? filename.split('.').last.toLowerCase() : 'jpg';
        final mimeType = ext == 'png'
            ? 'image/png'
            : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final uploadRes = await _remoteDatasource!.uploadMedia(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        );
        resolvedAvatarUrl = uploadRes['media_url'] as String?;
      } else if (avatarUrl != null) {
        resolvedAvatarUrl = avatarUrl;
      }

      final body = <String, dynamic>{
        if (name != null) 'name': name,
        if (handle != null) 'handle': handle,
        if (title != null) 'title': title,
        if (bio != null) 'bio': bio,
        if (interestTopics != null) 'interest_topics': interestTopics,
        if (resolvedAvatarUrl != null) 'avatar_url': resolvedAvatarUrl,
      };
      return _remoteDatasource!.updateProfile(body);
    }
    return _fakeDatasource.updateProfile(
      name: name,
      handle: handle,
      title: title,
      bio: bio,
      interestTopics: interestTopics,
      avatarUrl: avatarUrl,
      removeAvatar: removeAvatar,
    );
  }

  @override
  Future<List<CommunityAuthor>> getFollowers(String authorId) async {
    final currentGen = _generation;
    if (isRemote) {
      final followers = await _remoteDatasource!.getFollowers(authorId);
      if (currentGen != _generation) return [];
      for (final f in followers) {
        if (f.isFollowing) {
          _remoteFollowedAuthorIds.add(f.id);
        }
      }
      return followers;
    }
    return _fakeDatasource.getFollowers(authorId);
  }

  @override
  Future<List<CommunityAuthor>> getFollowing(String authorId) async {
    final currentGen = _generation;
    if (isRemote) {
      final following = await _remoteDatasource!.getFollowing(authorId);
      if (currentGen != _generation) return [];
      for (final f in following) {
        if (f.isFollowing) {
          _remoteFollowedAuthorIds.add(f.id);
        }
      }
      return following;
    }
    return _fakeDatasource.getFollowing(authorId);
  }

  @override
  Future<List<QuestionAnswer>> getQuestionAnswers(String questionId) async => (await getAnswerPage(questionId)).items;

  @override
  Future<QuestionAnswersPage> getAnswerPage(String questionId, {String? cursor}) async {
    final gen = _generation;
    if (isRemote) {
      final page = await _remoteDatasource!.getAnswerPage(questionId, cursor: cursor);
      if (gen == _generation) _rememberAnswerCount(questionId, page.answerCount);
      return page;
    }
    final items = _fakeDatasource.getQuestionAnswers(questionId);
    return QuestionAnswersPage(items: items, answerCount: items.length);
  }

  @override
  Future<QuestionAnswer> addQuestionAnswer({required String questionId, required String content, String? requestKey}) async {
    final gen = _generation;
    if (isRemote) {
      if (requestKey == null) throw ArgumentError('Stable answer request key required');
      final receipt = await _remoteDatasource!.createAnswer(questionId, content, requestKey);
      if (gen == _generation) _rememberAnswerCount(questionId, receipt.answerCount);
      return receipt.answer;
    }
    return _fakeDatasource.addQuestionAnswer(questionId: questionId, content: content);
  }

  @override
  Future<QuestionAnswer> getAnswer(String questionId, String answerId) async {
    if (isRemote) return _remoteDatasource!.getAnswer(questionId, answerId);
    return (await getQuestionAnswers(questionId)).firstWhere((a) => a.id == answerId);
  }

  @override
  Future<QuestionAnswer> setAnswerHelpful(String questionId, String answerId, bool desired) async {
    if (isRemote) return _remoteDatasource!.setAnswerHelpful(questionId, answerId, desired);
    final old = await getAnswer(questionId, answerId);
    if (old.isUpvoted != desired) _fakeDatasource.upvoteAnswer(questionId, answerId);
    return getAnswer(questionId, answerId);
  }

  @override
  Future<bool> upvoteAnswer(String questionId, String answerId) async {
    final old = await getAnswer(questionId, answerId);
    return (await setAnswerHelpful(questionId, answerId, !old.isUpvoted)).isUpvoted;
  }

  // --- Wave 4: Social Settings, Block/Mute/Report, Stories 24h, Share ---

  @override
  Future<CommunitySettings> getSettings() async {
    if (isRemote) {
      return _remoteDatasource!.getSettings();
    }
    return _fakeDatasource.getSettings();
  }

  @override
  Future<CommunitySettings> updateSettings({
    bool? isPrivateAccount,
    String? whoCanDm,
    String? whoCanComment,
    String? whoCanReplyStory,
    String? allowMentions,
    bool? hideLikeCounts,
    bool? showActivityStatus,
    bool? autoPromptShareWorkout,
    bool? autoPromptShareMeal,
    List<String>? mutedKeywords,
  }) async {
    if (isRemote) {
      final body = <String, dynamic>{
        if (isPrivateAccount != null) 'is_private_account': isPrivateAccount,
        if (whoCanDm != null) 'who_can_dm': whoCanDm,
        if (whoCanComment != null) 'who_can_comment': whoCanComment,
        if (whoCanReplyStory != null)
          'who_can_reply_story': whoCanReplyStory,
        if (allowMentions != null) 'allow_mentions': allowMentions,
        if (hideLikeCounts != null) 'hide_like_counts': hideLikeCounts,
        if (showActivityStatus != null)
          'show_activity_status': showActivityStatus,
        if (autoPromptShareWorkout != null)
          'auto_prompt_share_workout': autoPromptShareWorkout,
        if (autoPromptShareMeal != null)
          'auto_prompt_share_meal': autoPromptShareMeal,
        if (mutedKeywords != null) 'muted_keywords': mutedKeywords,
      };
      return _remoteDatasource!.updateSettings(body);
    }
    return _fakeDatasource.updateSettings(
      isPrivateAccount: isPrivateAccount,
      whoCanDm: whoCanDm,
      whoCanComment: whoCanComment,
      whoCanReplyStory: whoCanReplyStory,
      allowMentions: allowMentions,
      hideLikeCounts: hideLikeCounts,
      showActivityStatus: showActivityStatus,
      autoPromptShareWorkout: autoPromptShareWorkout,
      autoPromptShareMeal: autoPromptShareMeal,
      mutedKeywords: mutedKeywords,
    );
  }

  @override
  Future<bool> blockUser(String targetUserId) async {
    if (isRemote) {
      final blocked = await _remoteDatasource!.blockUser(targetUserId);
      if (blocked) {
        _remoteFollowedAuthorIds.remove(targetUserId);
      }
      return blocked;
    }
    return _fakeDatasource.blockUser(targetUserId);
  }

  @override
  Future<bool> unblockUser(String targetUserId) async {
    if (isRemote) {
      return _remoteDatasource!.unblockUser(targetUserId);
    }
    return _fakeDatasource.unblockUser(targetUserId);
  }

  @override
  Future<List<CommunityAuthor>> getBlockedUsers() async {
    if (isRemote) {
      return _remoteDatasource!.getBlockedUsers();
    }
    return _fakeDatasource.getBlockedUsers();
  }

  @override
  Future<bool> muteUser(String targetUserId) async {
    if (isRemote) {
      return _remoteDatasource!.muteUser(targetUserId);
    }
    return _fakeDatasource.muteUser(targetUserId);
  }

  @override
  Future<bool> unmuteUser(String targetUserId) async {
    if (isRemote) {
      return _remoteDatasource!.unmuteUser(targetUserId);
    }
    return _fakeDatasource.unmuteUser(targetUserId);
  }

  @override
  Future<List<CommunityAuthor>> getMutedUsers() async {
    if (isRemote) {
      return _remoteDatasource!.getMutedUsers();
    }
    return _fakeDatasource.getMutedUsers();
  }

  @override
  Future<CommunityReportReceipt> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    if (isRemote) {
      return _remoteDatasource!.reportContent(
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        details: details,
      );
    }
    return _fakeDatasource.reportContent(
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
    );
  }

  @override
  Future<List<CommunityStoryAuthorGroup>> getStories() async {
    if (isRemote) {
      return _remoteDatasource!.getStories();
    }
    return _fakeDatasource.getStories();
  }

  @override
  Future<CommunityStoriesArchivePage> getArchivedStories({
    bool includeActive = false,
    int limit = 30,
    String? cursor,
  }) async {
    if (isRemote) {
      return _remoteDatasource!.getArchivedStories(
        includeActive: includeActive,
        limit: limit,
        cursor: cursor,
      );
    }
    return _fakeDatasource.getArchivedStories(
      includeActive: includeActive,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<CommunityStory> createStory({
    required String mediaType,
    String? mediaUrl,
    String caption = '',
    String? backgroundColor,
    String privacy = 'public',
  }) async {
    if (isRemote) {
      return _remoteDatasource!.createStory(
        mediaType: mediaType,
        mediaUrl: mediaUrl,
        caption: caption,
        backgroundColor: backgroundColor,
        privacy: privacy,
      );
    }
    return _fakeDatasource.createStory(
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      caption: caption,
      backgroundColor: backgroundColor,
      privacy: privacy,
    );
  }

  @override
  Future<int> markStoryViewed(String storyId) async {
    if (isRemote) {
      return _remoteDatasource!.markStoryViewed(storyId);
    }
    return _fakeDatasource.markStoryViewed(storyId);
  }

  @override
  Future<bool> deleteStory(String storyId) async {
    if (isRemote) {
      return _remoteDatasource!.deleteStory(storyId);
    }
    return _fakeDatasource.deleteStory(storyId);
  }

  @override
  Future<int> sharePost(String postId) async {
    if (isRemote) {
      return _remoteDatasource!.sharePost(postId);
    }
    return _fakeDatasource.sharePost(postId);
  }

  // --- Wave 4: Direct Messages (Messenger-Lite) ---

  @override
  Future<DmConversation> createOrGetConversation(String targetUserId) async {
    if (isRemote) {
      return _remoteDatasource!.createOrGetConversation(targetUserId);
    }
    return _fakeDatasource.createOrGetConversation(targetUserId);
  }

  @override
  Future<DmConversationsPage> getConversations({
    int limit = 20,
    String? cursor,
  }) async {
    if (isRemote) {
      return _remoteDatasource!.getConversations(limit: limit, cursor: cursor);
    }
    return _fakeDatasource.getConversations();
  }

  @override
  Future<DmMessagesPage> getMessages(
    String conversationId, {
    int limit = 30,
    String? cursor,
  }) async {
    if (isRemote) {
      return _remoteDatasource!.getMessages(
        conversationId,
        limit: limit,
        cursor: cursor,
      );
    }
    return _fakeDatasource.getMessages(conversationId);
  }

  @override
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
    if (isRemote) {
      return _remoteDatasource!.sendMessage(
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
    return _fakeDatasource.sendMessage(
      conversationId: conversationId,
      type: type,
      content: content,
      mediaUrl: mediaUrl,
      durationSeconds: durationSeconds,
      sharedPostId: sharedPostId,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    if (isRemote) {
      return _remoteDatasource!.markConversationRead(conversationId);
    }
    _fakeDatasource.markConversationRead(conversationId);
  }

  @override
  Future<bool> deleteMessage(String messageId) async {
    if (isRemote) {
      return _remoteDatasource!.deleteMessage(messageId);
    }
    return _fakeDatasource.deleteMessage(messageId);
  }

  @override
  Future<int> getDmUnreadCount() async {
    if (isRemote) {
      return _remoteDatasource!.getDmUnreadCount();
    }
    return _fakeDatasource.getDmUnreadCount();
  }

  @override
  Future<DmMediaUploadResult> uploadDmMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (isRemote) {
      return _remoteDatasource!.uploadDmMedia(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
    }
    return _fakeDatasource.uploadDmMedia(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }
}

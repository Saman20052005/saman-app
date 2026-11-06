import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/domain/models/community_comment.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/question_answer.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';

class MockFollowRemoteDatasource implements CommunityRemoteDatasource {
  @override
  Future<List<PostAttachmentSnapshot>> getAttachmentSources(String kind) => throw UnimplementedError();
  @override
  Future<PostAttachmentSnapshot> previewActivity(String kind, String sourceId, Map<String,dynamic> options) => throw UnimplementedError();

  bool simulateTimeout = false;
  bool simulateDefinitiveError = false;
  Completer<void>? delayCompleter;

  // Server-side authoritative state
  final Map<String, bool> serverFollows = {};
  final Map<String, int> serverFollowerCounts = {'author_b': 5, 'author_c': 12};

  @override
  Future<CommunityPost> publishPost(Map<String, dynamic> body, String requestKey) => throw UnsupportedError('Publication not simulated by this read/interaction double');

  @override
  Future<QuestionAnswersPage> getAnswerPage(String questionId, {String? cursor, int limit = 20}) async {
    final items = await getQuestionAnswers(questionId, cursor: cursor, limit: limit);
    return QuestionAnswersPage(items: items, answerCount: items.length);
  }
  @override
  Future<QuestionAnswerReceipt> createAnswer(String questionId, String content, String requestKey) => throw UnimplementedError();
  @override
  Future<QuestionAnswer> getAnswer(String questionId, String answerId) => throw UnimplementedError();
  @override
  Future<QuestionAnswer> setAnswerHelpful(String questionId, String answerId, bool desired) => throw UnimplementedError();

  @override
  Future<CommunityCommentsPage> getComments(String postId, {String? cursor}) async =>
      const CommunityCommentsPage(items: [], commentCount: 0);

  @override
  Future<CommunityCommentReceipt> createComment(String postId, String content,
      {String? parentCommentId, required String requestKey}) async =>
      throw UnsupportedError('This test double does not simulate comment writes');

  @override
  Future<Map<String, dynamic>> followAuthor(String authorId) async {
    if (delayCompleter != null) await delayCompleter!.future;
    if (simulateDefinitiveError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/authors/$authorId/follow'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/authors/$authorId/follow'),
          statusCode: 404,
        ),
      );
    }
    if (simulateTimeout) {
      serverFollows[authorId] = true;
      serverFollowerCounts[authorId] = (serverFollowerCounts[authorId] ?? 0) + 1;
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/authors/$authorId/follow'),
        type: DioExceptionType.connectionTimeout,
        error: 'Connection timed out',
      );
    }
    serverFollows[authorId] = true;
    serverFollowerCounts[authorId] = (serverFollowerCounts[authorId] ?? 0) + 1;
    return {
      'target_author_id': authorId,
      'is_following': true,
      'follower_count': serverFollowerCounts[authorId]!,
      'following_count': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> unfollowAuthor(String authorId) async {
    if (delayCompleter != null) await delayCompleter!.future;
    if (simulateDefinitiveError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/authors/$authorId/follow'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/authors/$authorId/follow'),
          statusCode: 404,
        ),
      );
    }
    serverFollows[authorId] = false;
    serverFollowerCounts[authorId] = ((serverFollowerCounts[authorId] ?? 1) - 1).clamp(0, 999999);
    return {
      'target_author_id': authorId,
      'is_following': false,
      'follower_count': serverFollowerCounts[authorId]!,
      'following_count': 0,
    };
  }

  @override
  Future<CommunityAuthor> getAuthorProfile(String authorId) async {
    return CommunityAuthor(
      id: authorId,
      name: 'Author $authorId',
      isFollowing: serverFollows[authorId] ?? false,
      followerCount: serverFollowerCounts[authorId] ?? 0,
      followingCount: 3,
      postCount: 10,
    );
  }

  @override
  Future<List<CommunityAuthor>> getFollowers(String authorId, {int limit = 20, String? cursor}) async {
    return [
      CommunityAuthor(
        id: 'follower_1',
        name: 'Follower One',
        isFollowing: serverFollows['follower_1'] ?? false,
      ),
    ];
  }

  @override
  Future<List<CommunityAuthor>> getFollowing(String authorId, {int limit = 20, String? cursor}) async {
    return [
      CommunityAuthor(
        id: 'author_b',
        name: 'Author B',
        isFollowing: serverFollows['author_b'] ?? false,
      ),
    ];
  }

  @override
  Future<List<CommunityPost>> getFeedPosts({
    required CommunityFeedFilter filter,
    int limit = 20,
    String? cursor,
  }) async {
    if (delayCompleter != null) await delayCompleter!.future;

    final allPosts = [
      CommunityPost(
        id: 'post_b1',
        type: CommunityPostType.photo,
        author: CommunityAuthor(
          id: 'author_b',
          name: 'Author B',
          isFollowing: serverFollows['author_b'] ?? false,
          followerCount: serverFollowerCounts['author_b'] ?? 5,
        ),
        timeAgo: '10 phút trước',
        caption: 'Post by Author B',
        likeCount: 3,
      ),
      CommunityPost(
        id: 'post_c1',
        type: CommunityPostType.photo,
        author: CommunityAuthor(
          id: 'author_c',
          name: 'Author C',
          isFollowing: serverFollows['author_c'] ?? false,
          followerCount: serverFollowerCounts['author_c'] ?? 12,
        ),
        timeAgo: '1 giờ trước',
        caption: 'Post by Author C',
        likeCount: 8,
      ),
    ];

    if (filter == CommunityFeedFilter.following) {
      return allPosts.where((p) => serverFollows[p.author.id] == true).toList();
    }
    return allPosts;
  }

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    return CommunityPost(
      id: postId,
      type: CommunityPostType.photo,
      author: CommunityAuthor(
        id: 'author_b',
        name: 'Author B',
        isFollowing: serverFollows['author_b'] ?? false,
        followerCount: serverFollowerCounts['author_b'] ?? 5,
      ),
      timeAgo: '10 phút trước',
      caption: 'Detail post',
    );
  }

  @override
  Future<Map<String, dynamic>> likePost(String postId) async => {'is_liked': true, 'like_count': 1};

  @override
  Future<Map<String, dynamic>> unlikePost(String postId) async => {'is_liked': false, 'like_count': 0};

  @override
  Future<bool> savePost(String postId) async => true;

  @override
  Future<bool> unsavePost(String postId) async => false;

  @override
  Future<List<CommunityPost>> getSavedPosts({int limit = 20, String? cursor}) async => [];

  @override
  Future<List<QuestionAnswer>> getQuestionAnswers(
    String questionId, {
    int limit = 20,
    String? cursor,
  }) async =>
      [];
}

void main() {
  group('JCOM-05-05 Follow Relationships & Following Feed Unit/Widget Tests', () {
    late MockFollowRemoteDatasource mockDs;
    late CommunityRepositoryImpl repo;
    late ProviderContainer container;

    setUp(() {
      mockDs = MockFollowRemoteDatasource();
      repo = CommunityRepositoryImpl(
        remoteDatasource: mockDs,
        useRemote: true,
      );
      container = ProviderContainer(
        overrides: [
          useRemoteCommunityProvider.overrideWith((ref) => true),
          communityRemoteDatasourceProvider.overrideWithValue(mockDs),
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('1. Follow toggle calls remote API and updates repository cached followed state', () async {
      // Initially not following author_b
      expect(mockDs.serverFollows['author_b'], null);

      // Follow author_b
      final followResult = await repo.toggleFollow('author_b');
      expect(followResult, true);
      expect(mockDs.serverFollows['author_b'], true);
      expect(mockDs.serverFollowerCounts['author_b'], 6);

      // Unfollow author_b
      final unfollowResult = await repo.toggleFollow('author_b');
      expect(unfollowResult, false);
      expect(mockDs.serverFollows['author_b'], false);
      expect(mockDs.serverFollowerCounts['author_b'], 5);
    });

    test('2. Feed synchronization: updateAuthorFollow updates all posts by author in feed', () async {
      final feedNotifier = container.read(communityFeedProvider.notifier);

      // Load feed
      await feedNotifier.loadPosts(CommunityFeedFilter.forYou);
      final initialPosts = container.read(communityFeedProvider).posts;
      expect(initialPosts.length, 2);
      expect(initialPosts.firstWhere((p) => p.author.id == 'author_b').author.isFollowing, false);

      // Update follow state via notifier
      feedNotifier.updateAuthorFollow(authorId: 'author_b', isFollowing: true);

      final updatedPosts = container.read(communityFeedProvider).posts;
      final postB = updatedPosts.firstWhere((p) => p.author.id == 'author_b');
      expect(postB.author.isFollowing, true);

      // Author C remains unchanged
      final postC = updatedPosts.firstWhere((p) => p.author.id == 'author_c');
      expect(postC.author.isFollowing, false);
    });

    test('3. Following feed returns only posts from authors that the viewer follows', () async {
      final feedNotifier = container.read(communityFeedProvider.notifier);

      // When following no one, following tab is empty
      await feedNotifier.loadPosts(CommunityFeedFilter.following);
      expect(container.read(communityFeedProvider).posts, isEmpty);

      // Follow author_c on the server
      mockDs.serverFollows['author_c'] = true;

      // Reload following feed
      await feedNotifier.loadPosts(CommunityFeedFilter.following);
      final followingPosts = container.read(communityFeedProvider).posts;
      expect(followingPosts.length, 1);
      expect(followingPosts.first.author.id, 'author_c');
      expect(followingPosts.first.author.isFollowing, true);
    });

    test('4. Post Detail follow sync: updateAuthorFollow updates post detail author state', () async {
      final detailNotifier = container.read(communityPostDetailProvider('post_b1').notifier);

      await detailNotifier.loadPost();
      expect(container.read(communityPostDetailProvider('post_b1')).post?.author.isFollowing, false);

      detailNotifier.updateAuthorFollow(authorId: 'author_b', isFollowing: true);
      expect(container.read(communityPostDetailProvider('post_b1')).post?.author.isFollowing, true);
    });

    test('5. Definitive error (404/400) rolls back follow mutation immediately', () async {
      mockDs.simulateDefinitiveError = true;

      expect(() async => await repo.toggleFollow('author_b'), throwsA(isA<DioException>()));
    });

    test('6. Timeout reconciliation: adopts canonical state from getAuthorProfile', () async {
      mockDs.simulateTimeout = true;

      // Server persists before timeout dropped response
      final result = await repo.toggleFollow('author_b');

      // Reconciles with server and adopts canonical true
      expect(result, true);
      expect(mockDs.serverFollows['author_b'], true);
    });

    test('7. Identity Guard: switching user clears cached followed author IDs', () async {
      // User A follows author_b
      await repo.toggleFollow('author_b');
      expect(mockDs.serverFollows['author_b'], true);
      expect(repo.remoteFollowedAuthorIds.contains('author_b'), true);

      // Reset state / switch to User B
      resetCommunityStateInContainer(container, 'athlete_b');

      // Session switch verified clean
      expect(repo.remoteFollowedAuthorIds, isEmpty);
    });

    test('8. R09 Author Profile and R10 Followers/Following contracts return authoritative data', () async {
      final profile = await repo.getAuthorProfile('author_b');
      expect(profile.id, 'author_b');
      expect(profile.followerCount, 5);
      expect(profile.followingCount, 3);
      expect(profile.postCount, 10);

      final followers = await repo.getFollowers('author_b');
      expect(followers.isNotEmpty, true);
      expect(followers.first.id, 'follower_1');

      final following = await repo.getFollowing('author_b');
      expect(following.isNotEmpty, true);
      expect(following.first.id, 'author_b');
    });
  });
}

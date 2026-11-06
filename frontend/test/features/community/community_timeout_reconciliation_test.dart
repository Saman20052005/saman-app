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

class TimeoutReconcileMockRemoteDatasource implements CommunityRemoteDatasource {
  @override
  Future<List<PostAttachmentSnapshot>> getAttachmentSources(String kind) => throw UnimplementedError();
  @override
  Future<PostAttachmentSnapshot> previewActivity(String kind, String sourceId, Map<String,dynamic> options) => throw UnimplementedError();

  bool simulateTimeoutOnLike = false;
  bool simulateTimeoutOnSave = false;
  bool simulateDefinitiveError = false;
  bool simulateReconciliationFailure = false;
  bool simulateHttp500OnLike = false;
  int? reconciliationStatusCode;
  Completer<void>? delayInFlightCompleter;

  bool serverPersistedLike = false;
  bool serverPersistedSave = false;
  int serverLikeCount = 10;

  CommunityPost _buildCanonicalPost(String postId) {
    return CommunityPost(
      id: postId,
      type: CommunityPostType.photo,
      author: const CommunityAuthor(id: 'author_01', name: 'Author One'),
      timeAgo: '1 giờ trước',
      caption: 'Test Post Caption',
      likeCount: serverLikeCount,
      isLiked: serverPersistedLike,
      isBookmarked: serverPersistedSave,
    );
  }

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
  Future<List<CommunityPost>> getFeedPosts({
    required CommunityFeedFilter filter,
    int limit = 20,
    String? cursor,
  }) async {
    if (delayInFlightCompleter != null) {
      await delayInFlightCompleter!.future;
    }
    return [_buildCanonicalPost('post_reconcile_01')];
  }

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    if (reconciliationStatusCode != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
          statusCode: reconciliationStatusCode!,
        ),
      );
    }
    if (simulateReconciliationFailure) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
        type: DioExceptionType.connectionTimeout,
        error: 'Reconciliation timed out',
      );
    }
    return _buildCanonicalPost(postId);
  }

  @override
  Future<Map<String, dynamic>> likePost(String postId) async {
    if (delayInFlightCompleter != null) {
      await delayInFlightCompleter!.future;
    }
    if (simulateHttp500OnLike) {
      serverPersistedLike = true;
      serverLikeCount = 11;
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
          statusCode: 500,
        ),
      );
    }
    if (simulateDefinitiveError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
          statusCode: 404,
        ),
      );
    }
    if (simulateTimeoutOnLike) {
      // Server persisted before dropping the response!
      serverPersistedLike = true;
      serverLikeCount = 11;
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
        type: DioExceptionType.receiveTimeout,
        error: 'Receive timeout on like response',
      );
    }
    serverPersistedLike = true;
    serverLikeCount = 11;
    return {'is_liked': true, 'like_count': serverLikeCount};
  }

  @override
  Future<Map<String, dynamic>> unlikePost(String postId) async {
    if (delayInFlightCompleter != null) {
      await delayInFlightCompleter!.future;
    }
    serverPersistedLike = false;
    serverLikeCount = 10;
    return {'is_liked': false, 'like_count': serverLikeCount};
  }

  @override
  Future<bool> savePost(String postId) async {
    if (delayInFlightCompleter != null) {
      await delayInFlightCompleter!.future;
    }
    if (simulateDefinitiveError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/save'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/posts/$postId/save'),
          statusCode: 403,
        ),
      );
    }
    if (simulateTimeoutOnSave) {
      serverPersistedSave = true;
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/save'),
        type: DioExceptionType.connectionError,
        error: 'Network connection dropped after persist',
      );
    }
    serverPersistedSave = true;
    return true;
  }

  @override
  Future<bool> unsavePost(String postId) async {
    serverPersistedSave = false;
    return false;
  }

  @override
  Future<List<CommunityPost>> getSavedPosts() async {
    if (delayInFlightCompleter != null) {
      await delayInFlightCompleter!.future;
    }
    if (serverPersistedSave) {
      return [_buildCanonicalPost('post_reconcile_01')];
    }
    return [];
  }

  @override
  Future<List<QuestionAnswer>> getQuestionAnswers(
    String questionId, {
    int limit = 20,
    String? cursor,
  }) async => [];

  @override
  Future<Map<String, dynamic>> followAuthor(String authorId) async => {
        'target_author_id': authorId,
        'is_following': true,
        'follower_count': 1,
        'following_count': 0,
      };

  @override
  Future<Map<String, dynamic>> unfollowAuthor(String authorId) async => {
        'target_author_id': authorId,
        'is_following': false,
        'follower_count': 0,
        'following_count': 0,
      };

  @override
  Future<CommunityAuthor> getAuthorProfile(String authorId) async =>
      CommunityAuthor(id: authorId, name: 'Author $authorId');

  @override
  Future<List<CommunityAuthor>> getFollowers(String authorId,
          {int limit = 20, String? cursor}) async =>
      [];

  @override
  Future<List<CommunityAuthor>> getFollowing(String authorId,
          {int limit = 20, String? cursor}) async =>
      [];
}

void main() {
  group('JCOM-05-04A Timeout Reconciliation & Concurrency Acceptance', () {
    late TimeoutReconcileMockRemoteDatasource mockDs;
    late CommunityRepositoryImpl repo;
    late ProviderContainer container;

    setUp(() {
      mockDs = TimeoutReconcileMockRemoteDatasource();
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

    test('1. Server persists Like but response drops with timeout -> client reconciles to canonical state', () async {
      mockDs.simulateTimeoutOnLike = true; // Simulates server persist + network drop

      // Initialize Feed
      await container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);
      expect(container.read(communityFeedProvider).posts.first.isLiked, false);
      expect(container.read(communityFeedProvider).posts.first.likeCount, 10);

      // Trigger Like
      await container.read(communityFeedProvider.notifier).toggleLike('post_reconcile_01');

      // The client must reconcile with server and NOT blindly rollback:
      final feedPost = container.read(communityFeedProvider).posts.first;
      expect(feedPost.isLiked, true, reason: 'Must adopt canonical state from server reconciliation');
      expect(mockDs.serverPersistedLike, true);
    });

    test('2. Server persists Save but network connection drops -> client reconciles to canonical saved state', () async {
      mockDs.simulateTimeoutOnSave = true;

      await container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);
      await container.read(communityFeedProvider.notifier).toggleBookmark('post_reconcile_01');

      final feedPost = container.read(communityFeedProvider).posts.first;
      expect(feedPost.isBookmarked, true);
      expect(mockDs.serverPersistedSave, true);
    });

    test('3. Definitive error (404/403) -> immediate rollback to previous state', () async {
      mockDs.simulateDefinitiveError = true;

      await container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);
      expect(container.read(communityFeedProvider).posts.first.isLiked, false);

      try {
        await container.read(communityFeedProvider.notifier).toggleLike('post_reconcile_01');
      } catch (_) {}

      final feedPost = container.read(communityFeedProvider).posts.first;
      expect(feedPost.isLiked, false, reason: 'Definitive error must rollback immediately');
      expect(feedPost.likeCount, 10);
    });

    test('4. Indeterminate error where reconciliation also times out -> keeps optimistic state without false failure', () async {
      mockDs.simulateTimeoutOnLike = true;
      mockDs.simulateReconciliationFailure = true;

      await container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);
      expect(container.read(communityFeedProvider).posts.first.isLiked, false);

      await container.read(communityFeedProvider.notifier).toggleLike('post_reconcile_01');

      // Because it was indeterminate, it does not rollback to false and does not crash
      final feedPost = container.read(communityFeedProvider).posts.first;
      expect(feedPost.isLiked, true, reason: 'Optimistic state retained under indeterminate error');
    });

    test('5. Identity Guard: In-flight request from Athlete A does not taint Athlete B on account switch', () async {
      mockDs.delayInFlightCompleter = Completer<void>();

      // Athlete A starts loading feed
      final loadFuture = container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);

      // Identity switches to Athlete B before response finishes
      resetCommunityStateInContainer(container, 'athlete_b');

      // Now Athlete A's delayed response finishes
      mockDs.delayInFlightCompleter!.complete();
      await loadFuture;

      // Athlete B must have empty/reset state, not polluted by Athlete A's in-flight response
      final bState = container.read(communityFeedProvider);
      expect(bState.posts, isEmpty, reason: "Athlete B state must never be tainted by Athlete A's in-flight response");
    });

    test('6. HTTP 500 treated as indeterminate error -> reconciles with canonical state', () async {
      mockDs.simulateHttp500OnLike = true;

      await container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);
      expect(container.read(communityFeedProvider).posts.first.isLiked, false);

      await container.read(communityFeedProvider.notifier).toggleLike('post_reconcile_01');

      final feedPost = container.read(communityFeedProvider).posts.first;
      expect(feedPost.isLiked, true, reason: 'HTTP 500 must trigger reconciliation and adopt canonical state');
    });

    test('7. Reconciliation returns 404 (deleted/unauthorized) -> evicts cached interaction', () async {
      mockDs.simulateTimeoutOnLike = true;
      mockDs.reconciliationStatusCode = 404;

      await container.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou);
      expect(container.read(communityFeedProvider).posts.first.isLiked, false);

      try {
        await container.read(communityFeedProvider.notifier).toggleLike('post_reconcile_01');
      } catch (_) {}

      final feedPost = container.read(communityFeedProvider).posts.first;
      expect(feedPost.isLiked, false, reason: '404 reconciliation error must evict local like state');
    });
  });
}

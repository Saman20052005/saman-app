import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/domain/models/community_comment.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/question_answer.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';

class MockRemoteCommunityDatasource implements CommunityRemoteDatasource {
  @override
  Future<List<PostAttachmentSnapshot>> getAttachmentSources(String kind) => throw UnimplementedError();
  @override
  Future<PostAttachmentSnapshot> previewActivity(String kind, String sourceId, Map<String,dynamic> options) => throw UnimplementedError();

  bool shouldThrowLikeError = false;
  bool shouldThrowSaveError = false;

  Map<String, int> postLikes = {'post_01': 10, 'post_02': 5};
  Set<String> likedPosts = {};
  Set<String> savedPosts = {};

  List<CommunityPost> posts = [];

  MockRemoteCommunityDatasource() {
    _initPosts();
  }

  void _initPosts() {
    posts = [
      CommunityPost(
        id: 'post_01',
        type: CommunityPostType.photo,
        author: const CommunityAuthor(id: 'author_01', name: 'Athlete A'),
        timeAgo: '1 giờ trước',
        caption: 'Post 1 Caption',
        likeCount: postLikes['post_01'] ?? 10,
        isLiked: likedPosts.contains('post_01'),
        isBookmarked: savedPosts.contains('post_01'),
      ),
      CommunityPost(
        id: 'post_02',
        type: CommunityPostType.photo,
        author: const CommunityAuthor(id: 'author_02', name: 'Athlete B'),
        timeAgo: '2 giờ trước',
        caption: 'Post 2 Caption',
        likeCount: postLikes['post_02'] ?? 5,
        isLiked: likedPosts.contains('post_02'),
        isBookmarked: savedPosts.contains('post_02'),
      ),
    ];
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
    return posts.map((p) => p.copyWith(
      isLiked: likedPosts.contains(p.id),
      likeCount: postLikes[p.id] ?? p.likeCount,
      isBookmarked: savedPosts.contains(p.id),
    )).toList();
  }

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    final p = posts.firstWhere((element) => element.id == postId);
    return p.copyWith(
      isLiked: likedPosts.contains(p.id),
      likeCount: postLikes[p.id] ?? p.likeCount,
      isBookmarked: savedPosts.contains(p.id),
    );
  }

  @override
  Future<Map<String, dynamic>> likePost(String postId) async {
    if (shouldThrowLikeError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
        error: 'Network Timeout / Server Error',
      );
    }
    likedPosts.add(postId);
    final count = (postLikes[postId] ?? 0) + 1;
    postLikes[postId] = count;
    return {'post_id': postId, 'is_liked': true, 'like_count': count};
  }

  @override
  Future<Map<String, dynamic>> unlikePost(String postId) async {
    if (shouldThrowLikeError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/like'),
        error: 'Network Timeout / Server Error',
      );
    }
    likedPosts.remove(postId);
    final count = ((postLikes[postId] ?? 1) - 1).clamp(0, 999999);
    postLikes[postId] = count;
    return {'post_id': postId, 'is_liked': false, 'like_count': count};
  }

  @override
  Future<bool> savePost(String postId) async {
    if (shouldThrowSaveError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/save'),
        error: 'Network Timeout / Server Error',
      );
    }
    savedPosts.add(postId);
    return true;
  }

  @override
  Future<bool> unsavePost(String postId) async {
    if (shouldThrowSaveError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId/save'),
        error: 'Network Timeout / Server Error',
      );
    }
    savedPosts.remove(postId);
    return false;
  }

  @override
  Future<List<CommunityPost>> getSavedPosts() async {
    return posts.where((p) => savedPosts.contains(p.id)).map((p) => p.copyWith(
      isLiked: likedPosts.contains(p.id),
      likeCount: postLikes[p.id] ?? p.likeCount,
      isBookmarked: true,
    )).toList();
  }

  @override
  Future<List<QuestionAnswer>> getQuestionAnswers(
    String questionId, {
    int limit = 20,
    String? cursor,
  }) async {
    return [];
  }

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
  late MockRemoteCommunityDatasource mockDatasource;
  late CommunityRepositoryImpl repository;

  setUp(() {
    mockDatasource = MockRemoteCommunityDatasource();
    repository = CommunityRepositoryImpl(
      remoteDatasource: mockDatasource,
      useRemote: true,
    );
  });

  group('JCOM-05-04 Remote Repository Interactions', () {
    test('likePost and unlikePost update local state and count correctly', () async {
      // 1. Initial state
      final posts = await repository.getFeedPosts(filter: CommunityFeedFilter.forYou);
      expect(posts.first.isLiked, isFalse);
      expect(posts.first.likeCount, equals(10));

      // 2. Toggle like -> should be liked
      final liked = await repository.toggleLike('post_01');
      expect(liked, isTrue);
      expect(mockDatasource.likedPosts.contains('post_01'), isTrue);
      expect(mockDatasource.postLikes['post_01'], equals(11));

      // 3. Toggle unlike -> should be unliked
      final unliked = await repository.toggleLike('post_01');
      expect(unliked, isFalse);
      expect(mockDatasource.likedPosts.contains('post_01'), isFalse);
      expect(mockDatasource.postLikes['post_01'], equals(10));
    });

    test('savePost and unsavePost update bookmark state and saved posts', () async {
      // 1. Initially saved list empty
      var saved = await repository.getSavedPosts();
      expect(saved.isEmpty, isTrue);

      // 2. Toggle bookmark
      final isSaved = await repository.toggleBookmark('post_01');
      expect(isSaved, isTrue);
      expect(mockDatasource.savedPosts.contains('post_01'), isTrue);

      // 3. Check saved list
      saved = await repository.getSavedPosts();
      expect(saved.length, equals(1));
      expect(saved.first.id, equals('post_01'));

      // 4. Toggle unbookmark
      final isUnsaved = await repository.toggleBookmark('post_01');
      expect(isUnsaved, isFalse);
      expect(mockDatasource.savedPosts.contains('post_01'), isFalse);

      saved = await repository.getSavedPosts();
      expect(saved.isEmpty, isTrue);
    });
  });

  group('JCOM-05-04 Provider Synchronization & Optimistic Rollback', () {
    testWidgets('Feed like syncs to detail and updates count optimistically', (tester) async {
      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      // Initialize feed
      final feedNotifier = container.read(communityFeedProvider.notifier);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final feedPosts = container.read(communityFeedProvider).posts;
      expect(feedPosts.first.isLiked, isFalse);
      expect(feedPosts.first.likeCount, equals(10));

      // Pre-read detail provider to simulate open detail screen
      container.read(communityPostDetailProvider('post_01'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(communityPostDetailProvider('post_01')).post?.isLiked, isFalse);

      // Like via Feed
      await feedNotifier.toggleLike('post_01');
      await tester.pump();

      // State in Feed updated
      final updatedFeedPosts = container.read(communityFeedProvider).posts;
      expect(updatedFeedPosts.first.isLiked, isTrue);
      expect(updatedFeedPosts.first.likeCount, equals(11));

      // Check PostDetail provider state for post_01 is synchronized
      final detailState = container.read(communityPostDetailProvider('post_01'));
      expect(detailState.post?.isLiked, isTrue);
      expect(detailState.post?.likeCount, equals(11));
    });

    testWidgets('Rollback occurs when remote like fails', (tester) async {
      mockDatasource.shouldThrowLikeError = true;

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final feedNotifier = container.read(communityFeedProvider.notifier);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final initialPost = container.read(communityFeedProvider).posts.first;
      expect(initialPost.isLiked, isFalse);

      // Attempt like -> should catch error and rollback
      try {
        await feedNotifier.toggleLike('post_01');
      } catch (_) {}

      await tester.pump();

      // Post should be reverted back to isLiked: false, likeCount: 10
      final postAfterRollback = container.read(communityFeedProvider).posts.first;
      expect(postAfterRollback.isLiked, isFalse);
      expect(postAfterRollback.likeCount, equals(10));
    });

    testWidgets('Feed save syncs to SavedScreen and unbookmark in SavedScreen syncs back', (tester) async {
      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final feedNotifier = container.read(communityFeedProvider.notifier);
      final savedNotifier = container.read(communitySavedProvider.notifier);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(communitySavedProvider).posts.isEmpty, isTrue);

      // Bookmark post_01 from feed
      await feedNotifier.toggleBookmark('post_01');
      await tester.pump();

      // Check saved screen has post_01
      final savedList = container.read(communitySavedProvider).posts;
      expect(savedList.length, equals(1));
      expect(savedList.first.id, equals('post_01'));
      expect(savedList.first.isBookmarked, isTrue);

      // Now unbookmark from saved screen
      await savedNotifier.unbookmark('post_01');
      await tester.pump();

      // Saved list should now be empty
      expect(container.read(communitySavedProvider).posts.isEmpty, isTrue);

      // Feed should also reflect isBookmarked = false
      final feedPost = container.read(communityFeedProvider).posts.firstWhere((p) => p.id == 'post_01');
      expect(feedPost.isBookmarked, isFalse);
    });
  });
}

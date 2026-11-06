import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/domain/models/community_comment.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/question_answer.dart';
import 'package:health_ai_app/features/community/domain/repositories/community_repository.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/qa/community_question_detail_screen.dart';

class MockRemoteCommunityDatasource implements CommunityRemoteDatasource {
  @override
  Future<List<PostAttachmentSnapshot>> getAttachmentSources(String kind) => throw UnimplementedError();
  @override
  Future<PostAttachmentSnapshot> previewActivity(String kind, String sourceId, Map<String,dynamic> options) => throw UnimplementedError();

  bool shouldThrowError = false;
  List<CommunityPost> mockPosts = [];
  CommunityPost? mockPostDetail;
  List<QuestionAnswer> mockAnswers = [];

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
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/feed'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/feed'),
          statusCode: 500,
        ),
        error: 'Internal Server Error',
      );
    }
    if (filter == CommunityFeedFilter.qa) {
      return mockPosts.where((p) => p.type == CommunityPostType.qa).toList();
    }
    return mockPosts;
  }

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
          statusCode: 404,
        ),
        error: 'Post Not Found',
      );
    }
    if (mockPostDetail != null && mockPostDetail!.id == postId) {
      return mockPostDetail!;
    }
    throw DioException(
      requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/community/posts/$postId'),
        statusCode: 404,
      ),
      error: 'Post Not Found',
    );
  }

  @override
  Future<List<QuestionAnswer>> getQuestionAnswers(
    String questionId, {
    int limit = 20,
    String? cursor,
  }) async {
    if (shouldThrowError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/community/questions/$questionId/answers'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/community/questions/$questionId/answers'),
          statusCode: 500,
        ),
        error: 'Failed to fetch answers',
      );
    }
    return mockAnswers;
  }

  @override
  Future<Map<String, dynamic>> likePost(String postId) async {
    return {'post_id': postId, 'is_liked': true, 'like_count': 1};
  }

  @override
  Future<Map<String, dynamic>> unlikePost(String postId) async {
    return {'post_id': postId, 'is_liked': false, 'like_count': 0};
  }

  @override
  Future<bool> savePost(String postId) async {
    return true;
  }

  @override
  Future<bool> unsavePost(String postId) async {
    return false;
  }

  @override
  Future<List<CommunityPost>> getSavedPosts() async {
    return mockPosts;
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
  group('JCOM-05-03 — Community Remote Read & Repository Invariants', () {
    late MockRemoteCommunityDatasource mockRemote;
    late CommunityRepository repository;

    const sampleAuthor = CommunityAuthor(
      id: 'author_01',
      name: 'Nguyen Van A',
      avatarUrl: 'https://example.com/a.jpg',
      title: 'Kip 2 Athlete',
      isVerified: true,
      followerCount: 15,
    );

    const samplePost = CommunityPost(
      id: 'remote_post_01',
      type: CommunityPostType.photo,
      author: sampleAuthor,
      timeAgo: '1 giờ trước',
      caption: 'Buổi chạy sáng nhẹ nhàng 5km quanh hồ.',
      photoUrls: ['https://example.com/p1.jpg'],
      likeCount: 12,
      commentCount: 3,
    );

    const sampleQaPost = CommunityPost(
      id: 'remote_qa_02',
      type: CommunityPostType.qa,
      author: sampleAuthor,
      timeAgo: '2 giờ trước',
      caption: 'Hỏi về dinh dưỡng phục hồi',
      qaInfo: PostQaInfo(
        question: 'Sau khi chạy dài nên nạp carb hay protein trước?',
        categoryTag: '#DinhDưỡng',
        respondentsSummary: '3 người đã trả lời',
      ),
      likeCount: 5,
    );

    const sampleAnswer = QuestionAnswer(
      id: 'ans_01',
      questionId: 'remote_qa_02',
      author: sampleAuthor,
      content: 'Nên nạp tỷ lệ 3:1 hoặc 4:1 Carb:Protein trong vòng 30 phút đầu!',
      timeAgo: '30 phút trước',
      upvoteCount: 8,
      isPinnedBest: true,
    );

    setUp(() {
      mockRemote = MockRemoteCommunityDatasource();
      mockRemote.mockPosts = [samplePost, sampleQaPost];
      mockRemote.mockPostDetail = samplePost;
      mockRemote.mockAnswers = [sampleAnswer];

      repository = CommunityRepositoryImpl(
        remoteDatasource: mockRemote,
        fakeDatasource: CommunityFakeDatasource(),
        useRemote: true,
      );
    });

    test('Repository in remote mode delegates getFeedPosts to remote datasource', () async {
      final posts = await repository.getFeedPosts(filter: CommunityFeedFilter.forYou);
      expect(posts.length, 2);
      expect(posts.first.id, 'remote_post_01');
      expect(posts.first.caption, 'Buổi chạy sáng nhẹ nhàng 5km quanh hồ.');
    });

    test('Repository in remote mode propagates errors without silent fake fallback', () async {
      mockRemote.shouldThrowError = true;
      expect(
        () async => await repository.getFeedPosts(filter: CommunityFeedFilter.forYou),
        throwsA(isA<DioException>()),
      );
    });

    test('Repository in remote mode rejects unreleased mutations with UnsupportedError', () async {
      // Like, bookmark, and follow are now supported in JCOM-05-04 and JCOM-05-05
      expect(await repository.toggleLike('remote_post_01'), isTrue);
      expect(await repository.toggleBookmark('remote_post_01'), isTrue);
      expect(await repository.toggleFollow('author_01'), isTrue);

      // Media publishing remains unsupported; text publishing has its own contract tests.
      expect(
        () async => await repository.publishPost(caption: 'Đăng bài thử', mediaUrls: ['unsupported.jpg']),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('R03 Community Feed renders remote posts and preview notice', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            useRemoteCommunityProvider.overrideWith((ref) => true),
            communityRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CommunityFeedScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Saman Community'), findsOneWidget);
      expect(
        find.text('Saman Community (Chế độ máy chủ) • Đã kích hoạt Thích & Lưu'),
        findsOneWidget,
      );
      expect(find.text('Buổi chạy sáng nhẹ nhàng 5km quanh hồ.'), findsOneWidget);
      expect(find.text('Nguyen Van A'), findsWidgets);
    });

    testWidgets('R03 Community Feed shows error view on failure and recovers on retry', (tester) async {
      mockRemote.shouldThrowError = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            useRemoteCommunityProvider.overrideWith((ref) => true),
            communityRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: CommunityFeedScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Không thể tải bảng tin cộng đồng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      // Now recover remote and tap retry
      mockRemote.shouldThrowError = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Buổi chạy sáng nhẹ nhàng 5km quanh hồ.'), findsOneWidget);
    });

    testWidgets('R15 Question Detail renders remote answers properly', (tester) async {
      mockRemote.mockPostDetail = sampleQaPost;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            useRemoteCommunityProvider.overrideWith((ref) => true),
            communityRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: CommunityQuestionDetailScreen(
              questionId: 'remote_qa_02',
              initialPost: sampleQaPost,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Nên nạp tỷ lệ 3:1 hoặc 4:1 Carb:Protein trong vòng 30 phút đầu!'), findsOneWidget);
      expect(find.text('1 câu trả lời'), findsOneWidget);
      expect(find.text('Câu trả lời hữu ích nhất'), findsOneWidget);
    });
  });
}

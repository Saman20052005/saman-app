import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/widgets/post_card_view.dart';

class MockDeletionTransport {
  final Dio dio = Dio();
  final List<String> deletedPostIds = [];
  bool failDeletion = false;
  int statusCode = 200;

  MockDeletionTransport() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.method == 'DELETE' && options.path.startsWith('/api/community/posts/')) {
          final postId = options.path.split('/').last;
          if (failDeletion) {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: statusCode,
                data: {'detail': statusCode == 403 ? 'community_delete_forbidden_not_author' : 'community_post_not_found'},
              ),
            ));
            return;
          }
          deletedPostIds.add(postId);
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'success': true, 'post_id': postId},
          ));
        } else if (options.method == 'GET' && options.path == '/api/community/feed') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'items': []},
          ));
        }
      },
    ));
  }
}

const testAuthorA = CommunityAuthor(
  id: 'author_a',
  name: 'Athlete A',
  isVerified: true,
);

const testAuthorB = CommunityAuthor(
  id: 'author_b',
  name: 'Athlete B',
  isVerified: false,
);

const samplePostA = CommunityPost(
  id: 'post_a_101',
  type: CommunityPostType.text,
  author: testAuthorA,
  timeAgo: '10 phút trước',
  caption: 'Morning discipline routine',
  likeCount: 5,
  commentCount: 2,
  isLiked: false,
  isBookmarked: false,
);

const samplePostB = CommunityPost(
  id: 'post_b_202',
  type: CommunityPostType.photo,
  author: testAuthorB,
  timeAgo: '1 giờ trước',
  caption: 'B workout progress',
  photoUrls: ['/static/community/sample.jpg'],
  likeCount: 12,
  commentCount: 3,
  isLiked: false,
  isBookmarked: false,
);

void main() {
  group('JCOM-05-11 Post Deletion & Ownership Enforcement Tests', () {
    test('1. CommunityRemoteDatasource sends DELETE request and returns true on 200', () async {
      final transport = MockDeletionTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);

      final result = await datasource.deletePost('post_a_101');
      expect(result, isTrue);
      expect(transport.deletedPostIds, ['post_a_101']);
    });

    test('2. CommunityRepositoryImpl delegates deletePost to remote datasource', () async {
      final transport = MockDeletionTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: datasource,
        useRemote: true,
      );

      final result = await repo.deletePost('post_a_101');
      expect(result, isTrue);
      expect(transport.deletedPostIds, ['post_a_101']);
    });

    test('3. CommunityFeedNotifier.deletePost removes post from feed state on success', () async {
      final transport = MockDeletionTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: datasource,
        useRemote: true,
      );

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final feedNotifier = container.read(communityFeedProvider.notifier);

      // Pre-populate feed state with 2 posts
      feedNotifier.acceptPublished(samplePostA);
      feedNotifier.acceptPublished(samplePostB);

      final initialPosts = container.read(communityFeedProvider).posts;
      expect(initialPosts.any((p) => p.id == samplePostA.id), isTrue);
      expect(initialPosts.any((p) => p.id == samplePostB.id), isTrue);

      // Delete post A
      final deleteSuccess = await feedNotifier.deletePost(samplePostA.id);
      expect(deleteSuccess, isTrue);

      // Verify post A is removed while post B remains
      final updatedPosts = container.read(communityFeedProvider).posts;
      expect(updatedPosts.any((p) => p.id == samplePostA.id), isFalse);
      expect(updatedPosts.any((p) => p.id == samplePostB.id), isTrue);
    });

    testWidgets('4. PostCardView shows delete option only for author and handles confirm dialog', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool deletionTriggered = false;

      // Case A: Viewer is non-author ('author_b' viewing post by 'author_a')
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostCardView(
              post: samplePostA,
              currentUserId: 'author_b',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open options bottom sheet
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // Ensure "Xóa bài viết" is NOT visible to non-author
      expect(find.byKey(const ValueKey('post-options-delete-tile')), findsNothing);
      expect(find.text('Xóa bài viết'), findsNothing);

      // Dismiss sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Case B: Viewer IS the author ('author_a' viewing post by 'author_a')
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCardView(
              post: samplePostA,
              currentUserId: 'author_a',
              onDelete: () async {
                deletionTriggered = true;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open options bottom sheet
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // "Xóa bài viết" must be visible
      final deleteTile = find.byKey(const ValueKey('post-options-delete-tile'));
      expect(deleteTile, findsOneWidget);
      expect(find.text('Xóa bài viết'), findsOneWidget);

      // Tap "Xóa bài viết" -> confirmation dialog opens
      await tester.tap(deleteTile);
      await tester.pumpAndSettle();

      expect(find.text('Bạn có chắc chắn muốn xóa bài viết này?'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel-delete-post-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-delete-post-button')), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.byKey(const ValueKey('confirm-delete-post-button')));
      await tester.pumpAndSettle();

      // Verification: deletion was triggered and success snackbar displayed
      expect(deletionTriggered, isTrue);
      expect(find.text('Đã xóa bài viết thành công.'), findsOneWidget);
    });
  });
}

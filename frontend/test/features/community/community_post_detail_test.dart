import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_post_detail_screen.dart';

class MockDetailTransport {
  final Dio dio = Dio();
  final Map<String, Map<String, dynamic>> posts = {};
  final List<String> deletedIds = [];
  bool failDelete = false;

  MockDetailTransport() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.method == 'GET' && options.path.startsWith('/api/community/posts/')) {
          final id = options.path.split('/').last;
          if (id.contains('comments')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'items': [], 'comment_count': 0},
            ));
            return;
          }
          if (posts.containsKey(id)) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: posts[id],
            ));
          } else {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 404,
                data: {'detail': 'Post not found'},
              ),
            ));
          }
        } else if (options.method == 'DELETE' && options.path.startsWith('/api/community/posts/')) {
          final id = options.path.split('/').last;
          if (failDelete) {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 403,
                data: {'detail': 'community_delete_forbidden_not_author'},
              ),
            ));
            return;
          }
          deletedIds.add(id);
          posts.remove(id);
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'success': true, 'post_id': id},
          ));
        } else if (options.method == 'GET' && options.path == '/api/community/feed') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'items': posts.values.toList()},
          ));
        }
      },
    ));
  }
}

const authorMe = CommunityAuthor(
  id: 'user_me_123',
  name: 'Athlete Me',
  isVerified: true,
);

const authorOther = CommunityAuthor(
  id: 'user_other_456',
  name: 'Athlete Other',
  isVerified: false,
);

const singlePhotoPost = CommunityPost(
  id: 'post_photo_1',
  type: CommunityPostType.photo,
  author: authorMe,
  timeAgo: '5 phút trước',
  caption: 'Healthy meal prep for leg day',
  photoUrls: ['https://images.unsplash.com/photo-1546069901-ba9599a7e63c'],
  likeCount: 15,
  commentCount: 4,
  isLiked: false,
  isBookmarked: false,
);

const otherUserPost = CommunityPost(
  id: 'post_other_2',
  type: CommunityPostType.text,
  author: authorOther,
  timeAgo: '1 giờ trước',
  caption: 'Other user thoughts on marathon recovery',
  likeCount: 8,
  commentCount: 1,
  isLiked: false,
  isBookmarked: false,
);

void main() {
  group('JCOM-05-12 Community Post Detail & Two-way Sync Tests', () {
    testWidgets('1. Render Test: PostDetailScreen renders single photo image widget and post body', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = MockDetailTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(remoteDatasource: datasource, useRemote: true);

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CommunityPostDetailScreen(
              postId: 'post_photo_1',
              initialPost: singlePhotoPost,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify post caption renders
      expect(find.text('Healthy meal prep for leg day'), findsOneWidget);
      // Verify Image widget is rendered for single photo
      expect(find.byType(Image), findsWidgets);
      // Verify author name renders
      expect(find.text('Athlete Me'), findsOneWidget);
    });

    testWidgets('2. Author Actions Test: Delete option shows only for author, hidden for non-author', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = MockDetailTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(remoteDatasource: datasource, useRemote: true);
      // Set active user to authorMe
      repo.resetForUser('user_me_123');

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // Case A: User views someone else's post ('otherUserPost')
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CommunityPostDetailScreen(
              postId: 'post_other_2',
              initialPost: otherUserPost,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open options sheet via AppBar button
      await tester.tap(find.byKey(const ValueKey('app-bar-post-options-button')));
      await tester.pumpAndSettle();

      // Verify Delete option is NOT shown for non-author
      expect(find.byKey(const ValueKey('post-detail-delete-tile')), findsNothing);
      expect(find.text('Xóa bài viết'), findsNothing);

      // Dismiss sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Case B: User views own post ('singlePhotoPost')
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CommunityPostDetailScreen(
              postId: 'post_photo_1',
              initialPost: singlePhotoPost,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open options sheet via AppBar button
      await tester.tap(find.byKey(const ValueKey('app-bar-post-options-button')));
      await tester.pumpAndSettle();

      // Verify Delete option IS shown for author
      expect(find.byKey(const ValueKey('post-detail-delete-tile')), findsOneWidget);
      expect(find.text('Xóa bài viết'), findsOneWidget);
    });

    testWidgets('3. Delete from Detail Flow: confirms deletion, pops screen, updates feed state', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = MockDetailTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(remoteDatasource: datasource, useRemote: true);
      repo.resetForUser('user_me_123');

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // Populate feed state with singlePhotoPost
      container.read(communityFeedProvider.notifier).acceptPublished(singlePhotoPost);
      expect(container.read(communityFeedProvider).posts.any((p) => p.id == singlePhotoPost.id), isTrue);

      bool popped = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const ValueKey('open-detail-btn'),
                  onPressed: () async {
                    final res = await Navigator.push<bool>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const CommunityPostDetailScreen(
                          postId: 'post_photo_1',
                          initialPost: singlePhotoPost,
                        ),
                      ),
                    );
                    if (res == true) popped = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to detail
      await tester.tap(find.byKey(const ValueKey('open-detail-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityPostDetailScreen), findsOneWidget);

      // Open options bottom sheet
      await tester.tap(find.byKey(const ValueKey('app-bar-post-options-button')));
      await tester.pumpAndSettle();

      // Tap Delete tile
      await tester.tap(find.byKey(const ValueKey('post-detail-delete-tile')));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Bạn có chắc chắn muốn xóa bài viết này?'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel-delete-post-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-delete-post-button')), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.byKey(const ValueKey('confirm-delete-post-button')));
      await tester.pumpAndSettle();

      // Verify popped back to previous screen
      expect(popped, isTrue);
      expect(find.byType(CommunityPostDetailScreen), findsNothing);

      // Verify post is removed from Feed state
      expect(container.read(communityFeedProvider).posts.any((p) => p.id == singlePhotoPost.id), isFalse);
    });

    testWidgets('4. 404 / Deleted Post Handling: displays not-found state without exceptions', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = MockDetailTransport(); // empty transport, any post returns 404
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(remoteDatasource: datasource, useRemote: true);

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CommunityPostDetailScreen(
              postId: 'nonexistent_deleted_999',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify not-found message is displayed
      expect(find.text('Bài viết này không tồn tại hoặc đã bị xóa'), findsOneWidget);
      // Verify "Quay lại Bảng tin" button exists
      expect(find.byKey(const ValueKey('back-to-feed-button')), findsOneWidget);
      expect(find.text('Quay lại Bảng tin'), findsOneWidget);

      // Tapping back button does not crash
      await tester.tap(find.byKey(const ValueKey('back-to-feed-button')));
      await tester.pumpAndSettle();
    });
  });
}


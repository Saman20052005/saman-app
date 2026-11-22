import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_notification.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/draft_post.dart';
import 'package:health_ai_app/features/community/domain/repositories/community_repository.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/drafts/community_drafts_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/notifications/community_notifications_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/post_card_view.dart';

typedef _MockHandler = ResponseBody Function(RequestOptions options);

class _MockDioAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final _MockHandler handler;

  _MockDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Object data, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _Wave2TestRepository extends CommunityRepositoryImpl {
  final CommunityAuthor profile;
  final List<CommunityPost> authorPosts;
  final List<CommunityNotification> notifs;
  final List<DraftPost> draftsList;

  _Wave2TestRepository({
    required this.profile,
    required this.authorPosts,
    this.notifs = const [],
    this.draftsList = const [],
    super.activeUserId,
  });

  @override
  Future<CommunityAuthor> getAuthorProfile(String authorId) async => profile;

  @override
  Future<List<CommunityPost>> getAuthorPosts(
    String authorId, {
    String tab = 'all',
    String? cursor,
  }) async =>
      authorPosts;

  @override
  Future<List<CommunityNotification>> getNotifications() async => notifs;

  @override
  Future<List<DraftPost>> getDrafts() async => draftsList;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave 2 Remote Datasource (Mock Dio)', () {
    test('Notifications: get, markRead, markAllRead', () async {
      late _MockDioAdapter adapter;
      final dio = Dio();
      adapter = _MockDioAdapter((opts) {
        if (opts.method == 'GET' && opts.path == '/api/community/notifications') {
          return _jsonResponse({
            'items': [
              {
                'id': 'n1',
                'actor_id': 'u2',
                'actor_name': 'Minh Khang',
                'action_text': 'đã trả lời câu hỏi của bạn',
                'target_snippet': 'Meal prep',
                'time_ago': '5 phút trước',
                'is_unread': true,
                'type': 'answer',
                'target_post_id': 'q1',
                'target_post_type': 'qa',
              },
            ],
            'unread_count': 1,
          });
        }
        if (opts.method == 'PATCH' &&
            opts.path == '/api/community/notifications/n1/read') {
          return _jsonResponse({'id': 'n1', 'is_unread': false, 'unread_count': 0});
        }
        if (opts.method == 'POST' &&
            opts.path == '/api/community/notifications/read-all') {
          return _jsonResponse({'unread_count': 0});
        }
        return _jsonResponse({'detail': 'Not found'}, statusCode: 404);
      });
      dio.httpClientAdapter = adapter;

      final ds = CommunityRemoteDatasourceImpl(dio: dio);
      final items = await ds.getNotifications();
      expect(items.length, 1);
      expect(items.first.id, 'n1');
      expect(items.first.actorId, 'u2');
      expect(items.first.type, CommunityNotificationType.answer);
      expect(items.first.targetPostId, 'q1');
      expect(items.first.targetPostType, 'qa');

      await ds.markNotificationRead('n1');
      await ds.markAllNotificationsRead();

      expect(adapter.requests.map((r) => '${r.method} ${r.path}').toList(), [
        'GET /api/community/notifications',
        'PATCH /api/community/notifications/n1/read',
        'POST /api/community/notifications/read-all',
      ]);
    });

    test('Drafts: getDrafts, saveDraft (PUT), deleteDraft', () async {
      late _MockDioAdapter adapter;
      final dio = Dio();
      adapter = _MockDioAdapter((opts) {
        if (opts.method == 'GET' && opts.path == '/api/community/drafts') {
          return _jsonResponse({
            'items': [
              {
                'id': 'd1',
                'user_id': 'u1',
                'caption': 'Nháp tập chân',
                'media_urls': <String>[],
                'aspect_ratio': '1:1',
                'rotation': 0,
                'brightness': 0.0,
                'contrast': 0.0,
                'audience': 'Công khai',
                'topic': '#TậpLuyện',
                'allow_comments': true,
                'updated_at': '2026-11-22T10:00:00Z',
              },
            ],
          });
        }
        if (opts.method == 'PUT' && opts.path == '/api/community/drafts/d1') {
          return _jsonResponse({
            'id': 'd1',
            'user_id': 'u1',
            'caption': 'Nháp tập chân updated',
            'media_urls': <String>[],
            'aspect_ratio': '1:1',
            'rotation': 0,
            'brightness': 0.0,
            'contrast': 0.0,
            'audience': 'Công khai',
            'topic': '#TậpLuyện',
            'allow_comments': true,
            'updated_at': '2026-11-22T10:05:00Z',
          });
        }
        if (opts.method == 'DELETE' && opts.path == '/api/community/drafts/d1') {
          return _jsonResponse({'success': true, 'id': 'd1'});
        }
        return _jsonResponse({'detail': 'Not found'}, statusCode: 404);
      });
      dio.httpClientAdapter = adapter;

      final ds = CommunityRemoteDatasourceImpl(dio: dio);
      final drafts = await ds.getDrafts();
      expect(drafts.length, 1);
      expect(drafts.first.caption, 'Nháp tập chân');

      final saved = await ds.saveDraft(
        drafts.first.copyWith(caption: 'Nháp tập chân updated'),
      );
      expect(saved.caption, 'Nháp tập chân updated');

      await ds.deleteDraft('d1');
      expect(adapter.requests.map((r) => '${r.method} ${r.path}').toList(), [
        'GET /api/community/drafts',
        'PUT /api/community/drafts/d1',
        'DELETE /api/community/drafts/d1',
      ]);
    });

    test('Author Profile, Author Posts, and Update Profile', () async {
      late _MockDioAdapter adapter;
      final dio = Dio();
      adapter = _MockDioAdapter((opts) {
        if (opts.method == 'GET' && opts.path == '/api/community/authors/me') {
          return _jsonResponse({
            'id': 'u1',
            'name': 'Lan Anh',
            'handle': 'lan.anh',
            'title': 'Runner',
            'bio': 'Chạy bộ mỗi sáng',
            'interest_topics': ['Tập luyện', 'Phục hồi'],
            'follower_count': 12,
            'following_count': 5,
            'post_count': 10,
            'workout_post_count': 7,
            'meal_post_count': 3,
            'total_likes_received': 2500,
          });
        }
        if (opts.method == 'GET' &&
            opts.path == '/api/community/authors/me/posts') {
          return _jsonResponse({
            'items': [
              {
                'id': 'p_author_1',
                'type': 'workout',
                'author': {'id': 'u1', 'name': 'Lan Anh'},
                'time_ago': '1 giờ trước',
                'caption': 'Buổi chạy 10km sáng nay',
                'photo_urls': <String>[],
                'like_count': 25,
                'comment_count': 2,
              },
            ],
            'next_cursor': null,
          });
        }
        if (opts.method == 'PATCH' && opts.path == '/api/community/profile') {
          return _jsonResponse({
            'id': 'u1',
            'name': 'Lan Anh Pro',
            'handle': 'lan.anh',
            'title': 'Marathoner',
            'bio': 'Bio mới',
            'interest_topics': ['Tập luyện'],
            'workout_post_count': 7,
            'meal_post_count': 3,
            'total_likes_received': 2500,
          });
        }
        return _jsonResponse({'detail': 'Not found'}, statusCode: 404);
      });
      dio.httpClientAdapter = adapter;

      final ds = CommunityRemoteDatasourceImpl(dio: dio);
      final author = await ds.getAuthorProfile('me');
      expect(author.handle, 'lan.anh');
      expect(author.bio, 'Chạy bộ mỗi sáng');
      expect(author.interestTopics, ['Tập luyện', 'Phục hồi']);
      expect(author.workoutPostCount, 7);
      expect(author.mealPostCount, 3);
      expect(author.totalLikesReceived, 2500);

      final posts = await ds.getAuthorPosts('me');
      expect(posts.length, 1);
      expect(posts.first.id, 'p_author_1');
      expect(posts.first.type, CommunityPostType.workout);

      final updated = await ds.updateProfile({'name': 'Lan Anh Pro'});
      expect(updated.name, 'Lan Anh Pro');
      expect(updated.title, 'Marathoner');
    });
  });

  group('Wave 2 Profile, Drafts & Notifications UI', () {
    Widget buildApp({
      required CommunityRepository repo,
      required Widget home,
    }) {
      return ProviderScope(
        overrides: [
          useRemoteCommunityProvider.overrideWith((ref) => false),
          communityRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: {
            AppRoutes.communityDrafts: (_) => const CommunityDraftsScreen(),
            AppRoutes.communityNotifications: (_) =>
                const CommunityNotificationsScreen(),
          },
          home: home,
        ),
      );
    }

    testWidgets(
      'CommunityProfileScreen displays real stats (no 42/18/1.2k), toggles Grid/List, and opens Drafts & Notifications without SnackBar',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const author = CommunityAuthor(
          id: 'u_real',
          name: 'Hải Đăng',
          handle: 'haidang.fit',
          title: 'HLV Calisthenics',
          bio: 'Tập luyện bền vững mỗi ngày',
          interestTopics: ['Tập luyện', 'Dinh dưỡng'],
          followerCount: 18,
          followingCount: 9,
          workoutPostCount: 7,
          mealPostCount: 3,
          totalLikesReceived: 2500,
        );

        const posts = [
          CommunityPost(
            id: 'p_real_1',
            type: CommunityPostType.workout,
            author: author,
            timeAgo: '1 giờ trước',
            caption: 'Bài tập pull-up sáng nay',
            likeCount: 15,
          ),
        ];

        final repo = _Wave2TestRepository(
          profile: author,
          authorPosts: posts,
          notifs: const [
            CommunityNotification(
              id: 'n_1',
              actorName: 'Minh Khang',
              actionText: 'đã thích bài viết của bạn',
              timeAgo: '10 phút trước',
              type: CommunityNotificationType.like,
            ),
          ],
          draftsList: [
            DraftPost(
              id: 'd_1',
              caption: 'Bản nháp bài tập',
              updatedAt: DateTime.now(),
            ),
          ],
        );

        await tester.pumpWidget(
          buildApp(repo: repo, home: const CommunityProfileScreen(authorId: 'me')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hải Đăng'), findsOneWidget);
        expect(find.text('@haidang.fit'), findsOneWidget);
        expect(find.text('Tập luyện bền vững mỗi ngày'), findsOneWidget);
        expect(find.text('Tập luyện'), findsOneWidget);
        expect(find.text('Dinh dưỡng'), findsOneWidget);

        // Real stats shown; hardcoded 42 / 18 (meal) / 1.2k absent
        expect(find.text('7'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('2.5k'), findsOneWidget);
        expect(find.text('42'), findsNothing);
        expect(find.text('1.2k'), findsNothing);

        // Toggle Grid -> List (PostCardView)
        expect(find.byType(PostCardView), findsNothing);
        await tester.tap(find.byKey(const ValueKey('profile-view-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(PostCardView), findsOneWidget);
        expect(find.text('Bài tập pull-up sáng nay'), findsOneWidget);

        // Tap Bản nháp -> navigates to CommunityDraftsScreen, no blocking SnackBar
        await tester.tap(find.text('Bản nháp'));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp bài viết'), findsOneWidget);
        expect(find.text('Bản nháp bài tập'), findsOneWidget);
        expect(
          find.text('Tính năng đang hoàn thiện, sẽ sớm ra mắt!'),
          findsNothing,
        );

        // Pop back to Profile
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();

        // Tap Thông báo in CommunityBottomNavigationBar -> navigates to Notifications
        await tester.tap(find.text('Thông báo'));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityNotificationsScreen), findsOneWidget);
        expect(
          find.text('Tính năng đang hoàn thiện, sẽ sớm ra mắt!'),
          findsNothing,
        );
      },
    );
  });

  group('Wave 2 User Isolation Reset', () {
    test('resetCommunityStateInContainer clears notifications and drafts', () async {
      final repo = _Wave2TestRepository(
        profile: const CommunityAuthor(id: 'u1', name: 'User A'),
        authorPosts: const [],
        notifs: const [
          CommunityNotification(
            id: 'n_a',
            actorName: 'User B',
            actionText: 'đã thích',
            timeAgo: '1 phút trước',
            type: CommunityNotificationType.like,
          ),
        ],
        draftsList: [
          DraftPost(
            id: 'd_a',
            userId: 'u1',
            caption: 'Draft of User A',
            updatedAt: DateTime.now(),
          ),
        ],
        activeUserId: 'u1',
      );

      final container = ProviderContainer(
        overrides: [
          useRemoteCommunityProvider.overrideWith((ref) => false),
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(communityNotificationsProvider.notifier).loadNotifications();
      await container.read(communityDraftsProvider.notifier).loadDrafts();

      expect(container.read(communityNotificationsProvider).allNotifications.length, 1);
      expect(container.read(communityDraftsProvider).drafts.length, 1);

      resetCommunityStateInContainer(container, 'u2');

      expect(container.read(communityNotificationsProvider).allNotifications, isEmpty);
      expect(container.read(communityDraftsProvider).drafts, isEmpty);
    });
  });
}

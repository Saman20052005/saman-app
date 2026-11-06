import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_post_detail_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_select_attachment_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_album_order_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_edit_media_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/drafts/community_drafts_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_edit_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_follow_list_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_profile_screen.dart';

// Test mock HTTP client for Image.network resolution without network errors
class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => kTransparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final Uint8List kTransparentImage = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

Widget _buildTestWrapper({
  required Widget child,
  CommunityFakeDatasource? datasource,
  ProviderContainer? container,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(393, 852),
}) {
  final ds = datasource ?? CommunityFakeDatasource();
  final repo = CommunityRepositoryImpl(datasource: ds);

  final inner = MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: textScaler,
      padding: const EdgeInsets.only(top: 44, bottom: 34),
    ),
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: child,
    ),
  );

  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: inner,
    );
  }

  return ProviderScope(
    overrides: [
      communityFakeDatasourceProvider.overrideWithValue(ds),
      communityRepositoryProvider.overrideWithValue(repo),
    ],
    child: inner,
  );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  setUp(() {
    CommunityFakeDatasource.resetStorage();
  });

  group('JCOM-04B Interactive Acceptance & Behavioral Assertions', () {
    testWidgets('R06B: Change photo editing parameters and verify composer state & limits', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Pre-seed 1 media item
      container.read(communityComposerProvider.notifier).setInitialMedia(['https://example.com/photo1.jpg']);

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const PostEditMediaScreen(),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chỉnh ảnh'), findsOneWidget);

      // 1. Change Aspect Ratio to 4:5
      final ratioBtn45 = find.textContaining('4:5');
      expect(ratioBtn45, findsOneWidget);
      await tester.ensureVisible(ratioBtn45);
      await tester.tap(ratioBtn45);
      await tester.pumpAndSettle();
      expect(container.read(communityComposerProvider).aspectRatio, '4:5');

      // 2. Rotate photo 90 degrees
      final rotateBtn = find.byIcon(Icons.rotate_90_degrees_cw_rounded);
      expect(rotateBtn, findsOneWidget);
      await tester.ensureVisible(rotateBtn);
      await tester.tap(rotateBtn);
      await tester.pumpAndSettle();
      expect(container.read(communityComposerProvider).rotation, 90);

      // Rotate again to 180 degrees
      await tester.tap(rotateBtn);
      await tester.pumpAndSettle();
      expect(container.read(communityComposerProvider).rotation, 180);

      // 3. Verify disclaimer about preview limits is rendered
      final disclaimerFinder = find.textContaining('Bộ lọc và xoay ảnh hiển thị trực quan trong trình soạn thảo');
      await tester.ensureVisible(disclaimerFinder);
      expect(disclaimerFinder, findsOneWidget);
    });

    testWidgets('R06C: Change album order and verify cover badge and preserved sequence', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(communityComposerProvider.notifier).setInitialMedia([
        'https://example.com/photoA.jpg',
        'https://example.com/photoB.jpg',
      ]);

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const PostAlbumOrderScreen(),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sắp xếp ảnh'), findsOneWidget);
      // First card has the cover badge
      expect(find.text('Ảnh bìa'), findsOneWidget);

      // Reorder media: move second item to first
      container.read(communityComposerProvider.notifier).reorderMedia(1, 0);
      await tester.pumpAndSettle();

      final urls = container.read(communityComposerProvider).selectedMediaUrls;
      expect(urls.first, 'https://example.com/photoB.jpg');
      expect(urls.last, 'https://example.com/photoA.jpg');

      // Cover badge is still rendered on index 0
      expect(find.text('Ảnh bìa'), findsOneWidget);
    });

    testWidgets('R10: Open from profile, toggle follow and verify reactive state change', (tester) async {
      final ds = CommunityFakeDatasource();
      await tester.pumpWidget(
        _buildTestWrapper(
          child: const CommunityFollowListScreen(authorName: 'Linh Nguyễn', initialTabIndex: 0),
          datasource: ds,
        ),
      );
      await tester.pumpAndSettle();

      // Find initial follow button for author_khang ('Minh Khang')
      expect(find.text('Minh Khang'), findsOneWidget);
      final followBtn = find.widgetWithText(ElevatedButton, 'Theo dõi').first;
      expect(followBtn, findsOneWidget);

      // Tap follow button
      await tester.tap(followBtn);
      await tester.pumpAndSettle();

      // Button must immediately update to "Đang theo dõi" (OutlinedButton)
      final followingBtn = find.widgetWithText(OutlinedButton, 'Đang theo dõi');
      expect(followingBtn, findsOneWidget);

      // Tap again to unfollow
      await tester.tap(followingBtn);
      await tester.pumpAndSettle();

      // Button switches back to "Theo dõi"
      expect(find.widgetWithText(ElevatedButton, 'Theo dõi'), findsWidgets);
    });

    testWidgets('R14: Edit sample profile, save, and verify updated bio on profile screen', (tester) async {
      await tester.pumpWidget(
        _buildTestWrapper(
          child: const CommunityProfileScreen(authorId: 'me'),
        ),
      );
      await tester.pumpAndSettle();

      // Initial bio present
      expect(find.textContaining('Yêu thích rèn luyện thể chất'), findsOneWidget);

      // Tap 'Chỉnh sửa hồ sơ'
      final editBtn = find.text('Chỉnh sửa hồ sơ');
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // We are now on CommunityEditProfileScreen
      expect(find.text('Chỉnh sửa hồ sơ'), findsWidgets);
      final bioField = find.widgetWithText(TextField, 'Yêu thích rèn luyện thể chất và dinh dưỡng cân bằng. Chia sẻ hành trình tập luyện thực tế mỗi ngày cùng Saman.');
      expect(bioField, findsOneWidget);

      // Enter new bio
      await tester.enterText(bioField, 'Tập gym 5 buổi mỗi tuần & dinh dưỡng Eat Clean.');
      await tester.pumpAndSettle();

      // Tap 'Lưu'
      final saveBtn = find.text('Lưu');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify we returned to Profile screen and the new bio is rendered
      expect(find.text('Tập gym 5 buổi mỗi tuần & dinh dưỡng Eat Clean.'), findsOneWidget);
    });

    testWidgets('Flow A: Compose post -> save draft -> re-open draft -> verify restored state', (tester) async {
      final ds = CommunityFakeDatasource(currentUserId: 'flow_user_a');
      final repo = CommunityRepositoryImpl(datasource: ds);
      final container = ProviderContainer(
        overrides: [
          communityFakeDatasourceProvider.overrideWithValue(ds),
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // 1. Manually set up composer state as if user typed
      final composerNotifier = container.read(communityComposerProvider.notifier);
      composerNotifier.setCaption('Bữa sáng yến mạch và quả mọng');
      composerNotifier.setTopic('#ĂnSạch');
      composerNotifier.setAudience('Bạn bè');
      composerNotifier.setInitialMedia(['https://example.com/oatmeal.jpg']);
      const sampleAttachment = PostAttachmentSnapshot(
        type: AttachmentType.meal,
        id: 'meal_draft_01',
        title: 'Bát yến mạch dinh dưỡng',
        dateFormatted: '07:30 Sáng',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false,
      );
      composerNotifier.setAttachment(sampleAttachment);

      // 2. Save draft into repository
      final draft = composerNotifier.toDraft();
      await repo.saveDraft(draft);

      // 3. Clear/reset composer
      composerNotifier.reset();
      expect(container.read(communityComposerProvider).caption, isEmpty);
      expect(container.read(communityComposerProvider).attachedActivity, isNull);

      // 4. Pump CommunityDraftsScreen
      await tester.pumpWidget(
        _buildTestWrapper(
          child: const CommunityDraftsScreen(),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Assert draft item is visible
      expect(find.text('Bữa sáng yến mạch và quả mọng'), findsOneWidget);

      // 5. Tap on draft item to restore
      await tester.tap(find.text('Bữa sáng yến mạch và quả mọng'));
      await tester.pumpAndSettle();

      // 6. Verify full restored state in composer
      final restored = container.read(communityComposerProvider);
      expect(restored.caption, 'Bữa sáng yến mạch và quả mọng');
      expect(restored.topic, '#ĂnSạch');
      expect(restored.audience, 'Bạn bè');
      expect(restored.selectedMediaUrls, ['https://example.com/oatmeal.jpg']);
      expect(restored.attachedActivity?.id, 'meal_draft_01');
      expect(restored.attachedActivity?.title, 'Bát yến mạch dinh dưỡng');
    });

    testWidgets('Flow B: Publish post -> feed insertion -> open detail: 1 post, matching ID & content', (tester) async {
      final ds = CommunityFakeDatasource(currentUserId: 'flow_user_b');
      final repo = CommunityRepositoryImpl(datasource: ds);
      final container = ProviderContainer(
        overrides: [
          communityFakeDatasourceProvider.overrideWithValue(ds),
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final initialFeed = await repo.getFeedPosts(filter: CommunityFeedFilter.forYou);
      final initialCount = initialFeed.length;

      // 1. Publish new post
      final published = await repo.publishPost(
        caption: 'Hôm nay chinh phục PR Bench Press 100kg!',
        mediaUrls: ['https://example.com/pr.jpg'],
        attachment: const PostAttachmentSnapshot(
          type: AttachmentType.workout,
          id: 'bench_pr_01',
          title: 'Chest Day PR',
          dateFormatted: '18:00',
          includeDuration: true,
          includeExercisesOrFoods: true,
          includeLoadOrMacros: false,
        ),
      );

      // Verify feed has exactly 1 new post at index 0
      final updatedFeed = await repo.getFeedPosts(filter: CommunityFeedFilter.forYou);
      expect(updatedFeed.length, initialCount + 1);
      expect(updatedFeed.first.id, published.id);
      expect(updatedFeed.first.caption, 'Hôm nay chinh phục PR Bench Press 100kg!');

      // 2. Open Post Detail with that published ID
      await tester.pumpWidget(
        _buildTestWrapper(
          child: CommunityPostDetailScreen(postId: published.id),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // 3. Assert matching content, author, and attachment in detail view
      expect(find.text('Hôm nay chinh phục PR Bench Press 100kg!'), findsOneWidget);
      expect(find.text('Linh Nguyễn'), findsWidgets);
      expect(find.text('Chest Day PR'), findsOneWidget);
    });

    testWidgets('Flutter Text Scaling 200%: verify zero RenderFlex overflow across modified screens', (tester) async {
      final ds = CommunityFakeDatasource();
      final container = ProviderContainer(
        overrides: [
          communityFakeDatasourceProvider.overrideWithValue(ds),
          communityRepositoryProvider.overrideWithValue(CommunityRepositoryImpl(datasource: ds)),
        ],
      );
      addTearDown(container.dispose);

      final screens = <String, Widget>{
        'PostEditMediaScreen': const PostEditMediaScreen(),
        'CommunitySelectAttachmentScreen': const CommunitySelectAttachmentScreen(),
        'CommunityProfileScreen': const CommunityProfileScreen(authorId: 'me'),
        'CommunityFollowListScreen': const CommunityFollowListScreen(),
        'CommunityEditProfileScreen': const CommunityEditProfileScreen(),
        'PostAlbumOrderScreen': const PostAlbumOrderScreen(),
      };

      for (final entry in screens.entries) {
        // Test with real system text scale 2.0x (200%)
        await tester.pumpWidget(
          _buildTestWrapper(
            child: entry.value,
            container: container,
            textScaler: const TextScaler.linear(2.0),
            size: const Size(393, 852),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} must render under TextScaler.linear(2.0) with 0 RenderFlex overflow',
        );

        // Test with narrow 360px viewport + 200% text scale
        await tester.pumpWidget(
          _buildTestWrapper(
            child: entry.value,
            container: container,
            textScaler: const TextScaler.linear(2.0),
            size: const Size(360, 780),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} must render under 360px + TextScaler.linear(2.0) with 0 RenderFlex overflow',
        );
      }
    });
  });
}

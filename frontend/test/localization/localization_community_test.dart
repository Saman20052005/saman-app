import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_comment.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_post_detail_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_select_media_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/post_card_view.dart';

Widget _buildLocalizedTestApp({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(languageProvider);
        return MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: child),
        );
      },
    ),
  );
}

const _testAuthor = CommunityAuthor(
  id: 'author_loc_1',
  name: 'Athlete Loc',
  isVerified: true,
);

const _testPost = CommunityPost(
  id: 'post_loc_101',
  type: CommunityPostType.text,
  author: _testAuthor,
  timeAgo: '15 phút trước',
  caption: 'Testing localization switching across components',
  likeCount: 7,
  commentCount: 0,
  isLiked: false,
  isBookmarked: false,
);

class _MockDetailRepo extends CommunityRepositoryImpl {
  final CommunityPost? mockPost;
  _MockDetailRepo({this.mockPost});

  @override
  Future<CommunityPost> getPostDetail(String postId) async {
    if (mockPost == null) {
      throw Exception('Not found');
    }
    return mockPost!;
  }

  @override
  Future<CommunityCommentsPage> getComments(String postId, {String? cursor}) async {
    return const CommunityCommentsPage(items: [], commentCount: 0);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'language_mode': 'en',
      'language_code': 'en',
    });
  });

  group('Checkpoint LOC-02: AppTranslations Community Dictionary Parity', () {
    test('en and vi translation maps contain identical keys for Community & Journal', () {
      final requiredCommunityKeys = [
        // Feed & Filter Tabs
        'community_tab_all',
        'community_tab_following',
        'community_tab_qa',
        'community_empty_feed',
        'community_create_post_hint',
        'community_title',
        'community_all_caught_up',

        // Post Card & Actions
        'post_action_like',
        'post_action_comment',
        'post_action_save',
        'post_action_share',
        'post_action_delete',
        'post_action_report',
        'delete_post_confirm_title',
        'delete_post_confirm_msg',
        'delete_post_success',

        // Post Detail
        'post_detail_title',
        'post_detail_comments_header',
        'post_detail_write_comment',
        'post_detail_empty_comments',
        'post_not_found_title',
        'post_back_to_feed',

        // Compose Flow (R06A / R06D)
        'compose_post_title',
        'compose_publish_btn',
        'compose_audience_public',
        'compose_audience_followers',
        'compose_audience_private',
        'compose_discard_draft_title',
        'compose_discard_draft_msg',
        'compose_keep_editing',
        'compose_discard',
        'select_media_title',
      ];

      for (final key in requiredCommunityKeys) {
        final enVal = AppTranslations.text(key, const Locale('en'));
        final viVal = AppTranslations.text(key, const Locale('vi'));

        expect(enVal, isNotEmpty, reason: 'Key "$key" should have non-empty EN translation');
        expect(viVal, isNotEmpty, reason: 'Key "$key" should have non-empty VI translation');
        expect(enVal, isNot(equals(key)), reason: 'Key "$key" should not return raw key for EN');
        expect(viVal, isNot(equals(key)), reason: 'Key "$key" should not return raw key for VI');
      }
    });
  });

  group('Checkpoint LOC-02: CommunityFeedScreen Reactive Localization Switch', () {
    testWidgets('Toggles Feed tabs and banner between EN and VI reactively', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const CommunityFeedScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial English State
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Q&A'), findsOneWidget);
      expect(find.text('Saman Community'), findsOneWidget);

      // 2. Switch to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Đang theo dõi'), findsOneWidget);
      expect(find.text('Hỏi & Đáp'), findsOneWidget);
      expect(find.text('Saman Community'), findsOneWidget);

      // 3. Switch back to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Q&A'), findsOneWidget);
    });
  });

  group('Checkpoint LOC-02: PostCardView & Deletion Dialog Reactive Localization Switch', () {
    testWidgets('Toggles PostCardView options sheet and delete dialog between VI and EN', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Start in Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const PostCardView(
            post: _testPost,
            currentUserId: 'author_loc_1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open options sheet
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // Verify Vietnamese action items
      expect(find.text('Xóa bài viết'), findsOneWidget);
      expect(find.text('Lưu'), findsOneWidget);
      expect(find.text('Chia sẻ'), findsOneWidget);
      expect(find.text('Báo cáo nội dung'), findsOneWidget);

      // Tap delete option to open confirmation dialog
      await tester.tap(find.byKey(const ValueKey('post-options-delete-tile')));
      await tester.pumpAndSettle();

      // Verify Vietnamese dialog content
      expect(find.text('Xóa bài viết'), findsWidgets);
      expect(find.text('Bạn có chắc chắn muốn xóa bài viết này không?'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.byKey(const ValueKey('cancel-delete-post-button')));
      await tester.pumpAndSettle();

      // Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // Re-open options sheet in English
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // Verify English action items
      expect(find.text('Delete post'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Report post'), findsOneWidget);

      // Tap delete option to open confirmation dialog
      await tester.tap(find.byKey(const ValueKey('post-options-delete-tile')));
      await tester.pumpAndSettle();

      // Verify English dialog content
      expect(find.text('Delete Post'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this post?'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byKey(const ValueKey('cancel-delete-post-button')));
      await tester.pumpAndSettle();
    });
  });

  group('Checkpoint LOC-02: CommunityPostDetailScreen Reactive Localization Switch', () {
    testWidgets('Toggles PostDetail title, comments header, empty comments and 404 state between VI and EN', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(_MockDetailRepo(mockPost: _testPost)),
        ],
      );
      addTearDown(container.dispose);

      // Start in Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const CommunityPostDetailScreen(
            postId: 'post_loc_101',
            initialPost: _testPost,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Vietnamese Detail elements
      expect(find.text('Bài viết'), findsOneWidget);
      expect(find.text('Bình luận'), findsOneWidget);
      expect(find.text('Chưa có bình luận nào. Hãy là người đầu tiên!'), findsOneWidget);

      // Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // Verify English Detail elements
      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('No comments yet. Be the first to comment!'), findsOneWidget);

      // Test 404 not found state with empty/throwing repository
      final notFoundContainer = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(_MockDetailRepo(mockPost: null)),
        ],
      );
      addTearDown(notFoundContainer.dispose);

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: notFoundContainer,
          child: const CommunityPostDetailScreen(
            postId: 'nonexistent_post_999',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In English
      expect(find.text('This post does not exist or has been deleted'), findsOneWidget);
      expect(find.text('Back to Feed'), findsOneWidget);

      // Switch to Vietnamese
      await notFoundContainer.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Bài viết này không tồn tại hoặc đã bị xóa'), findsOneWidget);
      expect(find.text('Quay lại Bảng tin'), findsOneWidget);
    });
  });

  group('Checkpoint LOC-02: PostComposePublishScreen & PostSelectMediaScreen Localization Switch', () {
    testWidgets('Toggles Compose AppBar, Publish button and Audience options between VI and EN', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Start in Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const PostComposePublishScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Vietnamese Compose elements
      expect(find.text('Tạo bài viết'), findsOneWidget);
      expect(find.text('Đăng'), findsOneWidget);
      expect(find.text('Ai có thể xem?'), findsOneWidget);

      // Open Audience bottom sheet
      await tester.tap(find.text('Ai có thể xem?'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Công khai')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Chỉ người theo dõi')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Riêng tư')), findsOneWidget);

      // Close sheet
      await tester.tap(find.descendant(of: sheet, matching: find.text('Công khai')));
      await tester.pumpAndSettle();

      // Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // Verify English Compose elements
      expect(find.text('Create Post'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Who can see this?'), findsOneWidget);

      // Open Audience bottom sheet in English
      await tester.tap(find.text('Who can see this?'));
      await tester.pumpAndSettle();

      final sheetEn = find.byType(BottomSheet);
      expect(find.descendant(of: sheetEn, matching: find.text('Public')), findsOneWidget);
      expect(find.descendant(of: sheetEn, matching: find.text('Followers only')), findsOneWidget);
      expect(find.descendant(of: sheetEn, matching: find.text('Private')), findsOneWidget);

      // Close sheet
      await tester.tap(find.descendant(of: sheetEn, matching: find.text('Public')));
      await tester.pumpAndSettle();
    });

    testWidgets('Toggles PostSelectMediaScreen AppBar title between VI and EN', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Start in Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const PostSelectMediaScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chọn ảnh'), findsOneWidget);

      // Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Select Photo'), findsOneWidget);
    });
  });
}

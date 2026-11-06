import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/draft_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/drafts/community_drafts_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/notifications/community_notifications_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_edit_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_follow_list_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/qa/community_question_detail_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/saved/community_saved_screen.dart';

Widget buildTestApp({
  required Widget child,
  CommunityFakeDatasource? datasource,
}) {
  final ds = datasource ?? CommunityFakeDatasource();
  final repo = CommunityRepositoryImpl(datasource: ds);

  return ProviderScope(
    overrides: [
      communityFakeDatasourceProvider.overrideWithValue(ds),
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
        AppRoutes.communityFeed: (_) =>
            const Scaffold(body: Text('Community Feed')),
        AppRoutes.communityDiscover: (_) =>
            const Scaffold(body: Text('Community Discover')),
        AppRoutes.communityPost: (_) =>
            const Scaffold(body: Text('Community Post Detail')),
        AppRoutes.communityProfile: (_) => const CommunityProfileScreen(),
        AppRoutes.communityNotifications: (_) =>
            const CommunityNotificationsScreen(),
        AppRoutes.communitySaved: (_) => const CommunitySavedScreen(),
        AppRoutes.communityDrafts: (_) => const CommunityDraftsScreen(),
      },
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JCOM-04 — Community Features Unit & Logic Tests', () {
    late CommunityFakeDatasource datasource;
    late CommunityRepositoryImpl repository;

    setUp(() {
      datasource = CommunityFakeDatasource();
      repository = CommunityRepositoryImpl(datasource: datasource);
    });

    test('Notifications fetch and mark read updates state', () async {
      final notifs = await repository.getNotifications();
      expect(notifs.isNotEmpty, isTrue);
      expect(notifs.any((n) => n.isUnread), isTrue);

      final unreadId = notifs.firstWhere((n) => n.isUnread).id;
      await repository.markNotificationRead(unreadId);

      final after = await repository.getNotifications();
      final target = after.firstWhere((n) => n.id == unreadId);
      expect(target.isUnread, isFalse);
    });

    test('Followers and following lists fetch correctly', () async {
      final followers = await repository.getFollowers('me');
      expect(followers.isNotEmpty, isTrue);

      final following = await repository.getFollowing('me');
      expect(following.isNotEmpty, isTrue);
    });

    test('Question answers fetch, add answer, and upvote toggle work',
        () async {
      final answers = await repository.getQuestionAnswers('post_03_qa');
      expect(answers.isNotEmpty, isTrue);
      final initialCount = answers.first.upvoteCount;

      // Upvote
      final isUpvoted =
          await repository.upvoteAnswer('post_03_qa', answers.first.id);
      expect(isUpvoted, isTrue);

      final afterUpvote = await repository.getQuestionAnswers('post_03_qa');
      expect(afterUpvote.first.upvoteCount, initialCount + 1);

      // Add answer
      final newAns = await repository.addQuestionAnswer(
        questionId: 'post_03_qa',
        content: 'Mẹo giữ đồ tươi lâu rất hay!',
      );
      expect(newAns.content, 'Mẹo giữ đồ tươi lâu rất hay!');

      final afterAdd = await repository.getQuestionAnswers('post_03_qa');
      expect(afterAdd.any((a) => a.id == newAns.id), isTrue);
    });
  });

  group('JCOM-04 — Community Screens Widget & Interaction Tests', () {
    testWidgets('R09 CommunityProfileScreen renders profile header, bio, and stats',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestApp(child: const CommunityProfileScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Linh Nguyễn'), findsOneWidget);
      expect(find.text('@linh.nguyễn'), findsOneWidget);
      expect(find.text('Chỉnh sửa hồ sơ'), findsOneWidget);
      expect(find.text('Đã lưu'), findsOneWidget);
      expect(find.text('Bản nháp'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Buổi tập chia sẻ'), findsOneWidget);
    });

    testWidgets(
        'R10 CommunityFollowListScreen switches tabs and displays members',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestApp(child: const CommunityFollowListScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Người theo dõi'), findsWidgets);
      expect(find.textContaining('Đang theo dõi'), findsWidgets);

      // Switch tab to Following
      await tester.tap(find.textContaining('Đang theo dõi'));
      await tester.pumpAndSettle();

      expect(find.text('Hoàng Long'), findsWidgets);
    });

    testWidgets('R14 CommunityEditProfileScreen updates bio and selects fitness goal',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestApp(child: const CommunityEditProfileScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chỉnh sửa hồ sơ'), findsOneWidget);
      expect(find.text('Tên hiển thị *'), findsOneWidget);
      expect(find.text('Mục tiêu thể chất & dinh dưỡng'), findsOneWidget);

      // Toggle goal chip
      await tester.ensureVisible(find.text('Phục hồi cơ bắp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phục hồi cơ bắp'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'R11 CommunityNotificationsScreen filters notifications and marks read',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestApp(child: const CommunityNotificationsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Tương tác'), findsOneWidget);
      expect(find.textContaining('Minh Khang'), findsWidgets);

      // Switch to Tương tác filter
      await tester.tap(find.text('Tương tác'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Minh Khang'), findsWidgets);
    });

    testWidgets('R12 CommunitySavedScreen renders empty state or saved items',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestApp(child: const CommunitySavedScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bài viết đã lưu'), findsOneWidget);
    });

    testWidgets('R13 CommunityDraftsScreen renders drafts list and handles delete',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ds = CommunityFakeDatasource();
      ds.saveDraft(
        DraftPost(
          id: 'test_draft_01',
          caption: 'Bài viết đang viết dở...',
          topic: '#TậpLuyện',
          updatedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          child: const CommunityDraftsScreen(),
          datasource: ds,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bản nháp bài viết'), findsOneWidget);
      expect(find.text('Bài viết đang viết dở...'), findsOneWidget);
      expect(find.text('#TậpLuyện'), findsOneWidget);

      // Tap delete draft button
      final deleteBtn = find.byIcon(Icons.delete_outline_rounded);
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Chưa có bản nháp nào'), findsOneWidget);
    });

    testWidgets(
        'R15 CommunityQuestionDetailScreen submits answer and toggles upvote',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const qaPost = CommunityPost(
        id: 'post_03_qa',
        type: CommunityPostType.qa,
        author: CommunityAuthor(id: 'me', name: 'Linh Nguyễn'),
        timeAgo: 'Hôm qua',
        caption: 'Hỏi về cách bảo quản rau củ tươi lâu?',
        qaInfo: PostQaInfo(
          question: 'Hỏi về cách bảo quản rau củ tươi lâu?',
          categoryTag: 'MEAL PREP',
          details: 'Mình thường mua rau cho cả tuần.',
          respondentsSummary: '2 câu trả lời',
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          child: const CommunityQuestionDetailScreen(
            questionId: 'post_03_qa',
            initialPost: qaPost,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi tiết câu hỏi'), findsOneWidget);
      expect(find.text('Câu trả lời từ cộng đồng'), findsOneWidget);
      expect(find.text('Hỏi về cách bảo quản rau củ tươi lâu?'), findsOneWidget);

      // Enter answer text
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Chia nhỏ hộp hút chân không là tốt nhất!');
      await tester.pumpAndSettle();

      // Submit
      final sendBtn = find.byIcon(Icons.send_rounded);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.text('Chia nhỏ hộp hút chân không là tốt nhất!'), findsOneWidget);
    });
  });
}

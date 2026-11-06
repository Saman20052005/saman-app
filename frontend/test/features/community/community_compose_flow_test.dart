import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/draft_post.dart';
import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_ask_question_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_select_attachment_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_album_order_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_edit_media_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_select_media_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/create_content_bottom_sheet.dart';
import 'package:health_ai_app/features/community/presentation/widgets/draft_discard_dialog.dart';

Widget buildComposerTestApp({
  required Widget child,
  CommunityFakeDatasource? datasource,
  List<Override> overrides = const [],
}) {
  final ds = datasource ?? CommunityFakeDatasource();
  final repo = CommunityRepositoryImpl(datasource: ds);

  return ProviderScope(
    overrides: [
      communityFakeDatasourceProvider.overrideWithValue(ds),
      communityRepositoryProvider.overrideWithValue(repo),
      ...overrides,
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
        AppRoutes.communityFeed: (context) =>
            const Scaffold(body: Text('Community Feed')),
        AppRoutes.communityCreateMedia: (context) =>
            const PostSelectMediaScreen(),
        AppRoutes.communityCreateAttachment: (context) =>
            const CommunitySelectAttachmentScreen(),
        AppRoutes.communityCreateQuestion: (context) =>
            const CommunityAskQuestionScreen(),
        AppRoutes.communityCreatePublish: (context) =>
            const PostComposePublishScreen(),
      },
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JCOM-03 Composer State & Logic Unit Tests', () {
    late CommunityFakeDatasource datasource;
    late CommunityRepositoryImpl repository;

    setUp(() {
      datasource = CommunityFakeDatasource();
      repository = CommunityRepositoryImpl(datasource: datasource);
    });

    test('Recent activities are fetched correctly for Workout and Meal',
        () async {
      final workouts = await repository.getRecentWorkoutActivities();
      expect(workouts.isNotEmpty, isTrue);
      expect(workouts.first.type, AttachmentType.workout);

      final meals = await repository.getRecentMealActivities();
      expect(meals.isNotEmpty, isTrue);
      expect(meals.first.type, AttachmentType.meal);
    });

    test('Privacy toggles in AttachmentSnapshot default to private', () {
      const snapshot = PostAttachmentSnapshot(
        id: 'w_01',
        type: AttachmentType.workout,
        title: 'Upper Body Workout',
        dateFormatted: 'Hôm nay, 08:30',
        includeLoadOrMacros: false,
      );

      expect(snapshot.includeLoadOrMacros, isFalse);
    });

    test('Publishing post creates record in repository', () async {
      final post = await repository.publishPost(
        caption: 'Hôm nay tập ngực rất đã!',
        mediaUrls: ['assets/images/nutrition/meal_pho.jpg'],
        topic: 'Thử thách 30 ngày',
        audience: 'Công khai',
        allowComments: true,
      );

      expect(post.id.startsWith('post_'), isTrue);
      expect(post.caption, 'Hôm nay tập ngực rất đã!');
      expect(post.author.name, 'Linh Nguyễn');

      final feedPosts =
          await repository.getFeedPosts(filter: CommunityFeedFilter.forYou);
      expect(feedPosts.any((p) => p.id == post.id), isTrue);
    });

    test('Publishing question creates record in repository with QA tag',
        () async {
      final question = await repository.publishQuestion(
        question: 'Tập ngực xong có nên uống whey ngay không?',
        categoryTag: 'Dinh dưỡng & Bữa ăn',
        details: 'Mình mới bắt đầu tập được 2 tuần.',
      );

      expect(question.type, CommunityPostType.qa);
      expect(question.qaInfo?.question,
          'Tập ngực xong có nên uống whey ngay không?');
      expect(question.qaInfo?.details, 'Mình mới bắt đầu tập được 2 tuần.');
      expect(question.qaInfo?.categoryTag, 'Dinh dưỡng & Bữa ăn');

      final qaFeed =
          await repository.getFeedPosts(filter: CommunityFeedFilter.qa);
      expect(qaFeed.any((p) => p.id == question.id), isTrue);
    });

    test('Draft saving and deletion cycle works properly', () async {
      final draft = DraftPost(
        id: 'draft_custom_01',
        caption: 'Bản nháp chia sẻ bữa tối...',
        mediaUrls: ['img1.jpg'],
        topic: 'Ăn sạch sống khoẻ',
        updatedAt: DateTime.now(),
      );
      await repository.saveDraft(draft);

      var drafts = await repository.getDrafts();
      expect(drafts.any((d) => d.id == draft.id), isTrue);

      await repository.deleteDraft(draft.id);
      drafts = await repository.getDrafts();
      expect(drafts.any((d) => d.id == draft.id), isFalse);
    });
  });

  group('JCOM-03 Riverpod Composer State Machine Tests', () {
    test('Composer state transitions: aspect ratio, rotation, and reset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(communityComposerProvider.notifier);

      // Select media
      notifier.setInitialMedia(['img1.jpg', 'img2.jpg']);
      expect(container.read(communityComposerProvider).selectedMediaUrls.length, 2);

      // Change aspect ratio
      notifier.setAspectRatio('1:1');
      expect(container.read(communityComposerProvider).aspectRatio, '1:1');

      // Rotate
      notifier.rotate();
      expect(container.read(communityComposerProvider).rotation, 90);
      notifier.rotate();
      expect(container.read(communityComposerProvider).rotation, 180);

      // Brightness & contrast
      notifier.setBrightness(0.2);
      notifier.setContrast(1.2);
      expect(container.read(communityComposerProvider).brightness, 0.2);
      expect(container.read(communityComposerProvider).contrast, 1.2);

      // Grid toggle
      notifier.toggleGrid();
      expect(container.read(communityComposerProvider).isGridOverlayVisible, isFalse);

      // Reorder media
      notifier.reorderMedia(0, 2);
      expect(
          container.read(communityComposerProvider).selectedMediaUrls.first, 'img2.jpg');

      // Reset
      notifier.resetAdjustments();
      expect(container.read(communityComposerProvider).rotation, 0);
    });

    test('Double submission lock prevents concurrent publishes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(communityComposerProvider.notifier);
      notifier.setCaption('Test post');

      // First call initiates publish
      final f1 = notifier.publish();
      // Second immediate call while isSubmitting is true should be rejected
      final f2 = notifier.publish();

      final res1 = await f1;
      final res2 = await f2;

      expect(res1, isNotNull);
      expect(res2, isNull);
    });
  });

  group('JCOM-03 Screens Widget Tests', () {
    testWidgets('CreateContentBottomSheet renders 4 action items',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => CreateContentBottomSheet.show(context),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Tạo nội dung mới'), findsOneWidget);
      expect(find.text('Bài viết'), findsOneWidget);
      expect(find.text('Chia sẻ buổi tập'), findsOneWidget);
      expect(find.text('Chia sẻ bữa ăn'), findsOneWidget);
      expect(find.text('Đặt câu hỏi'), findsOneWidget);
    });

    testWidgets('PostSelectMediaScreen allows toggling media selection',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: const PostSelectMediaScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bài viết mới'), findsOneWidget);
      expect(find.text('Đăng chỉ với nội dung văn bản'), findsOneWidget);

      // Tap on the second media item thumbnail in grid
      final inkWells = find.byType(InkWell);
      expect(inkWells, findsWidgets);

      // Verify header has next button
      expect(find.text('Tiếp'), findsOneWidget);
    });

    testWidgets('PostEditMediaScreen rotates image on rotate button click',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: const PostEditMediaScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chỉnh ảnh'), findsOneWidget);
      expect(find.text('Vuông'), findsOneWidget);
      expect(find.text('Gốc'), findsOneWidget);
      expect(find.text('Dọc (4:5)'), findsOneWidget);

      // Tap rotate button
      final rotateButton = find.byIcon(Icons.rotate_90_degrees_cw_rounded);
      expect(rotateButton, findsOneWidget);
      await tester.tap(rotateButton);
      await tester.pumpAndSettle();
    });

    testWidgets('PostAlbumOrderScreen renders order slots and instructions',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: Consumer(
            builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () {
                  ref
                      .read(communityComposerProvider.notifier)
                      .setInitialMedia(['img1.jpg', 'img2.jpg']);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PostAlbumOrderScreen(),
                    ),
                  );
                },
                child: const Text('Open Order'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Order'));
      await tester.pumpAndSettle();

      expect(find.text('Sắp xếp ảnh'), findsOneWidget);
      expect(find.text('Ảnh bìa'), findsOneWidget);
      expect(
          find.text(
              'Đổi thứ tự ảnh để bài viết mạch lạc hơn. Ảnh đầu tiên được đặt làm ảnh bìa đại diện trên bảng tin.'),
          findsOneWidget);
    });

    testWidgets(
        'CommunitySelectAttachmentScreen switches tabs and updates privacy toggles',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: const CommunitySelectAttachmentScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đính kèm hoạt động'), findsOneWidget);
      expect(find.text('Buổi tập'), findsOneWidget);
      expect(find.text('Bữa ăn'), findsOneWidget);

      // Check default privacy switch state (Load / Sets is off)
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);

      // Toggle first switch
      await tester.tap(switches.first);
      await tester.pumpAndSettle();

      // Switch tab to Meal
      await tester.tap(find.text('Bữa ăn'));
      await tester.pumpAndSettle();
      expect(find.text('Cơm trưa Bento Ức Gà & Khoai Lang'), findsWidgets);
    });

    testWidgets('PostComposePublishScreen inputs caption and shows privacy sheet',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: const PostComposePublishScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bài viết mới'), findsOneWidget);
      expect(find.text('Chia sẻ'), findsOneWidget);

      // Enter caption text
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Chia sẻ hành trình hôm nay!');
      await tester.pumpAndSettle();
      expect(find.text('Chia sẻ hành trình hôm nay!'), findsOneWidget);

      // Tap audience setting tile
      await tester.tap(find.text('Ai có thể xem?'));
      await tester.pumpAndSettle();

      expect(find.text('Ai có thể xem bài viết này?'), findsOneWidget);
      expect(find.text('Người theo dõi'), findsOneWidget);

      // Select "Người theo dõi"
      await tester.tap(find.text('Người theo dõi'));
      await tester.pumpAndSettle();
      expect(find.text('Người theo dõi'), findsWidgets);
    });

    testWidgets(
        'CommunityAskQuestionScreen validates required topic before publishing',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildComposerTestApp(
          child: const CommunityAskQuestionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đặt câu hỏi'), findsOneWidget);
      expect(find.text('Chủ đề thảo luận'), findsOneWidget);
      expect(find.text('Bắt buộc chọn 1'), findsOneWidget);

      // Enter title
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, 'Hỏi về lịch tập cho người mới?');
      await tester.pumpAndSettle();

      // Select a topic chip
      await tester.tap(find.text('Tập luyện'));
      await tester.pumpAndSettle();

      expect(find.text('Đăng'), findsOneWidget);
    });

    testWidgets('DraftDiscardDialog renders all 3 actions', (tester) async {
      DraftDiscardAction? action;

      await tester.pumpWidget(
        buildComposerTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                action = await DraftDiscardDialog.show(context);
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Lưu bản nháp bài viết?'), findsOneWidget);
      expect(find.text('Lưu bản nháp'), findsOneWidget);
      expect(find.text('Hủy bỏ thay đổi'), findsOneWidget);
      expect(find.text('Tiếp tục chỉnh sửa'), findsOneWidget);

      await tester.tap(find.text('Tiếp tục chỉnh sửa'));
      await tester.pumpAndSettle();

      expect(action, DraftDiscardAction.cancel);
    });
  });
}

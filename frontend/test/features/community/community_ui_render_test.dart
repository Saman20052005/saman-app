import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_discover_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_post_detail_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_ask_question_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_select_attachment_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_album_order_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_edit_media_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_select_media_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/create_content_bottom_sheet.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_follow_list_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_edit_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/notifications/community_notifications_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/saved/community_saved_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/drafts/community_drafts_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/qa/community_question_detail_screen.dart';

const screenshotDir =
    r'D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840\docs\jcom02_community_feed\screenshots';
const jcom03ScreenshotDir =
    r'D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840\docs\jcom03_media_composer\screenshots';
const jcom04ScreenshotDir =
    r'D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840\docs\jcom04_profile_notifications\screenshots';
const captureBoundaryKey = ValueKey('community-screen-capture-boundary');

Future<void> captureScreenshot(
  WidgetTester tester,
  String filename, {
  String dir = screenshotDir,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureBoundaryKey),
  );
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    Directory(dir).createSync(recursive: true);
    File('$dir/$filename.png').writeAsBytesSync(bytes);
    img.dispose();
  });
}

Widget buildCaptureHarness({
  required Widget child,
  CommunityFakeDatasource? datasource,
  Locale locale = const Locale('vi'),
  double textScaleFactor = 1.0,
}) {
  final ds = datasource ?? CommunityFakeDatasource();
  final repo = CommunityRepositoryImpl(datasource: ds);

  return ProviderScope(
    overrides: [
      communityFakeDatasourceProvider.overrideWithValue(ds),
      communityRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(393, 852),
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: RepaintBoundary(
          key: captureBoundaryKey,
          child: child,
        ),
      ),
    ),
  );
}

class _AlbumOrderCaptureWrapper extends ConsumerStatefulWidget {
  const _AlbumOrderCaptureWrapper();
  @override
  ConsumerState<_AlbumOrderCaptureWrapper> createState() =>
      _AlbumOrderCaptureWrapperState();
}

class _AlbumOrderCaptureWrapperState
    extends ConsumerState<_AlbumOrderCaptureWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(communityComposerProvider.notifier).setInitialMedia([
        'assets/images/nutrition/meal_pho.jpg',
        'assets/images/nutrition/meal_salmon.jpg',
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const PostAlbumOrderScreen();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JCOM-02 — UI Render & Evidence Screenshot Generation', () {
    testWidgets('Capture 01 & 02: R03 Community Feed For You top and workout',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const CommunityFeedScreen()),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c01_r03_community_feed_for_you_top');

      // Scroll to Post 2 Kinetic workout
      await tester.drag(find.byType(ListView).first, const Offset(0, -320));
      await tester.pumpAndSettle();

      await captureScreenshot(
          tester, 'c02_r03_community_feed_for_you_workout');
    });

    testWidgets('Capture 03: R03 Community Feed Following tab',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const CommunityFeedScreen()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Đang theo dõi'));
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c03_r03_community_feed_following_tab');
    });

    testWidgets('Capture 04: R03 Community Feed QA tab and question card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const CommunityFeedScreen()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Hỏi đáp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hỏi đáp'));
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c04_r03_community_feed_qa_tab');
    });

    testWidgets('Capture 05: R03 Community Feed End State delight card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const CommunityFeedScreen()),
      );
      await tester.pumpAndSettle();

      // Scroll to bottom
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c05_r03_community_feed_end_state');
    });

    testWidgets('Capture 06, 07, 08: R04 Discover grid, trends, creators',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const CommunityDiscoverScreen()),
      );
      await tester.pumpAndSettle();

      // Top with 3x3 grid
      await captureScreenshot(tester, 'c06_r04_community_discover_top');

      // Scroll to Trending Topics
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -320));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'c07_r04_community_discover_trends');

      // Scroll to Recommended Creators
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -280));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'c08_r04_community_discover_creators');
    });

    testWidgets('Capture 09, 10, 11: R05 Post Detail top, tips, and comments',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityPostDetailScreen(postId: 'post_01_meal'),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c09_r05_community_post_detail_top');

      // Scroll to action bar & discussion header
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      await captureScreenshot(
          tester, 'c10_r05_community_post_detail_engagement');

      // Scroll to threaded comments & composer
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -280));
      await tester.pumpAndSettle();
      await captureScreenshot(
          tester, 'c11_r05_community_post_detail_comments');
    });

    testWidgets('Capture 12: R03 Narrow 360px viewport without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const CommunityFeedScreen()),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c12_r03_narrow_viewport_360px');
    });

    testWidgets('Capture 13: R03 Large Text Scaling 200% without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityFeedScreen(),
          textScaleFactor: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(tester, 'c13_r03_text_scale_200');
    });
  });

  group('JCOM-03 — Media Composer UI Render & Evidence Screenshot Generation', () {
    testWidgets('Capture 14: R06A Select Media Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const PostSelectMediaScreen()),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c14_r06a_select_media',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 15: R06B Edit Media Screen with controls',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(child: const PostEditMediaScreen()),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c15_r06b_edit_media',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 16: R06C Album Order Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const _AlbumOrderCaptureWrapper(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c16_r06c_album_order',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 17: R07 Select Attachment Screen - Workout Tab',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunitySelectAttachmentScreen(
            initialTab: AttachmentType.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c17_r07_select_attachment_workout',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 18: R07 Select Attachment Screen - Meal Tab',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunitySelectAttachmentScreen(
            initialTab: AttachmentType.meal,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c18_r07_select_attachment_meal',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 19: R06D Compose & Publish Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const PostComposePublishScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c19_r06d_compose_publish',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 20: R08 Ask Question Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityAskQuestionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c20_r08_ask_question',
        dir: jcom03ScreenshotDir,
      );
    });

    testWidgets('Capture 21: Create Content Bottom Sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const Scaffold(
            backgroundColor: Color(0xFF121314),
            body: CreateContentBottomSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c21_create_content_bottom_sheet',
        dir: jcom03ScreenshotDir,
      );
    });
  });

  group('JCOM-04 UI Render Screenshot Captures', () {
    testWidgets('Capture 22: R09 Community Profile Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c22_r09_community_profile',
        dir: jcom04ScreenshotDir,
      );
    });

    testWidgets('Capture 23: R10 Community Follow List Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityFollowListScreen(
            authorName: 'Huấn luyện viên Tuấn',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c23_r10_community_follow_list',
        dir: jcom04ScreenshotDir,
      );
    });

    testWidgets('Capture 24: R14 Community Edit Profile Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityEditProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c24_r14_community_edit_profile',
        dir: jcom04ScreenshotDir,
      );
    });

    testWidgets('Capture 25: R11 Community Notifications Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityNotificationsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c25_r11_community_notifications',
        dir: jcom04ScreenshotDir,
      );
    });

    testWidgets('Capture 26: R12 Community Saved Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunitySavedScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c26_r12_community_saved',
        dir: jcom04ScreenshotDir,
      );
    });

    testWidgets('Capture 27: R13 Community Drafts Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityDraftsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c27_r13_community_drafts',
        dir: jcom04ScreenshotDir,
      );
    });

    testWidgets('Capture 28: R15 Community Question Detail Screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: const CommunityQuestionDetailScreen(questionId: 'qa_01'),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(
        tester,
        'c28_r15_community_question_detail',
        dir: jcom04ScreenshotDir,
      );
    });
  });
}

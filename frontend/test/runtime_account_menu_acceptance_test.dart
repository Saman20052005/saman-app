import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/plan_detail_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_account_popup_menu.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_plans_comparison_screen.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

Future<void> _loadTestFonts() async {
  final packageConfigFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final flutterPackage = packages
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final flutterRoot = Directory.fromUri(
    packageConfigFile.uri.resolve(flutterPackage['rootUri'] as String),
  );
  final sdkRoot = flutterRoot.parent.parent;
  final fontDirectory = Directory.fromUri(
    sdkRoot.uri.resolve('bin/cache/artifacts/material_fonts/'),
  );

  Future<ByteData> readFont(String name) async {
    final file = File.fromUri(fontDirectory.uri.resolve(name));
    return ByteData.sublistView(await file.readAsBytes());
  }

  for (final family in ['Roboto', 'Inter']) {
    final fontLoader = FontLoader(family);
    for (final name in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Italic.ttf',
    ]) {
      fontLoader.addFont(readFont(name));
    }
    await fontLoader.load();
  }

  final iconFont = FontLoader('MaterialIcons')
    ..addFont(readFont('MaterialIcons-Regular.otf'));
  await iconFont.load();
}

Future<void> _captureScreenPng(WidgetTester tester, String outputPath) async {
  await tester.runAsync(() async {
    final boundary = tester.allRenderObjects
        .whereType<RenderRepaintBoundary>()
        .firstOrNull;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(buffer);

        // Also duplicate to brain artifact dir for immediate report embedding
        const artifactDir =
            'C:/Users/GL/.gemini/antigravity/brain/8c3bc196-eb01-4a85-9800-fccc4ce6d672/account_menu';
        final fileName = outputPath.split(RegExp(r'[/\\]')).last;
        final artifactFile = File('$artifactDir/$fileName');
        await artifactFile.parent.create(recursive: true);
        await artifactFile.writeAsBytes(buffer);
      }
    }
  });
}

class _AcceptanceProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _AcceptanceProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AcceptanceChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _AcceptanceChatNotifier({ChatState? initialState})
      : super(
          initialState ??
              ChatState(
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content:
                        'Chào bạn! Tôi là Saman Coach. Hôm nay bạn muốn lên thực đơn hay xem xu hướng?',
                  ),
                ],
                recentConversations: [
                  ChatConversationSummary(
                    id: 'active-thread',
                    title: 'Kế hoạch dinh dưỡng',
                    updatedAt: DateTime.now().toIso8601String(),
                  ),
                ],
                activeConversationId: 'active-thread',
              ),
        );

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadDailyBrief({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildAcceptanceApp({
  required Widget child,
  Size size = const Size(1024, 768),
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'sa***@gmail.com',
  );

  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(
        (ref) => _AcceptanceProfileNotifier(
          ProfileState(
            profile: profileEntity,
            snapshot: profileSnapshot,
            status: ProfileStatus.ready,
          ),
        ),
      ),
      chatControllerProvider.overrideWith(
        (ref) => _AcceptanceChatNotifier(),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0D0E),
      ),
      home: RepaintBoundary(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadTestFonts();
  });

  group('Runtime Acceptance — Saman Account Popup Menu & Plans Comparison', () {
    testWidgets(
      '1. Desktop: Mo menu tu banh rang & row tai khoan khi co ban nhap, dong bang click ngoai va Escape giu nguyen draft',
      (tester) async {
        const desktopSize = Size(1024, 768);
        tester.view.physicalSize = desktopSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildAcceptanceApp(
          child: const ChatScreen(),
          size: desktopSize,
        ));
        await tester.pumpAndSettle();

        // Type a draft into the composer
        final textField = find.byType(TextField);
        expect(textField, findsOneWidget);
        await tester.enterText(textField, 'Kế hoạch dinh dưỡng 2500 kcal');
        await tester.pumpAndSettle();

        // Verify draft text is in place
        expect(find.text('Kế hoạch dinh dưỡng 2500 kcal'), findsOneWidget);

        // 1a. Tap gear icon to open account menu
        final gearBtn = find.byTooltip('Tùy chọn Saman');
        expect(gearBtn, findsOneWidget);
        await tester.tap(gearBtn);
        await tester.pumpAndSettle();

        // Verify menu is visible and anchored
        expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

        // Capture Desktop Screenshot
        await _captureScreenPng(
          tester,
          'runtime_evidence/account_menu/account_menu_desktop.png',
        );

        // 1b. Close by outside tap barrier inside drawer bounds
        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();

        // Menu is closed, user remains on ChatScreen with exact draft intact
        expect(find.byType(SamanAccountPopupMenu), findsNothing);
        expect(find.text('Kế hoạch dinh dưỡng 2500 kcal'), findsOneWidget);

        // 1c. Open by account row
        final accountRow = find.text('Saman Athlete');
        expect(accountRow, findsOneWidget);
        await tester.tap(accountRow);
        await tester.pumpAndSettle();

        expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

        // 1d. Close by Escape key
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        // Menu is closed, user remains on ChatScreen with exact draft intact
        expect(find.byType(SamanAccountPopupMenu), findsNothing);
        expect(find.text('Kế hoạch dinh dưỡng 2500 kcal'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Mobile: Drawer mo menu tai khoan noi tren footer 390x844',
      (tester) async {
        const mobileSize = Size(390, 844);
        tester.view.physicalSize = mobileSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildAcceptanceApp(
          child: const ChatScreen(),
          size: mobileSize,
        ));
        await tester.pumpAndSettle();

        // Open drawer on mobile
        final menuBtn = find.byTooltip('Mở thanh điều hướng');
        if (menuBtn.evaluate().isNotEmpty) {
          await tester.tap(menuBtn);
        } else {
          final scaffoldFinder = find.byType(Scaffold);
          final scaffoldState =
              tester.state(scaffoldFinder) as ScaffoldState;
          scaffoldState.openDrawer();
        }
        await tester.pumpAndSettle();

        // In drawer, tap gear to open floating menu
        final gearBtn = find.byTooltip('Tùy chọn Saman');
        expect(gearBtn, findsOneWidget);
        await tester.tap(gearBtn);
        await tester.pumpAndSettle();

        expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

        // Capture Mobile Screenshot
        await _captureScreenPng(
          tester,
          'runtime_evidence/account_menu/account_menu_mobile.png',
        );

        // Dismiss menu
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();
        expect(find.byType(SamanAccountPopupMenu), findsNothing);
      },
    );

    testWidgets(
      '3. Plans Comparison Screen: Hien thi day du 4 goi, tag Ban xem truoc va badge Goi hien tai',
      (tester) async {
        const desktopSize = Size(1024, 768);
        tester.view.physicalSize = desktopSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildAcceptanceApp(
          child: const SamanPlansComparisonScreen(),
          size: desktopSize,
        ));
        await tester.pumpAndSettle();

        // Verify Title and "Bản xem trước" tag
        expect(find.text('Các gói Saman'), findsOneWidget);
        expect(find.text('Bản xem trước'), findsOneWidget);

        // Verify "Gói hiện tại" badge
        expect(find.text('Gói hiện tại'), findsOneWidget);

        // Capture Plans Comparison Screenshot
        await _captureScreenPng(
          tester,
          'runtime_evidence/account_menu/saman_plans_comparison.png',
        );

        // Verify CTA details
        expect(find.text('Đang sử dụng'), findsOneWidget); // For current free tier
        expect(find.text('Xem chi tiết gói'), findsWidgets); // For upgrade tiers
      },
    );

    testWidgets(
      '4. Trigger verification: Ca nhan hoa Coach, Quan ly goi, Giao dien, Nhac nho, Lich su, va notice chua kha dung',
      (tester) async {
        const desktopSize = Size(1024, 768);
        tester.view.physicalSize = desktopSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildAcceptanceApp(
          child: const ChatScreen(),
          size: desktopSize,
        ));
        await tester.pumpAndSettle();

        // Type a draft
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'Bản nháp 123');
        await tester.pumpAndSettle();

        // 4a. Ca nhan hoa Coach
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cá nhân hóa Coach'));
        await tester.pumpAndSettle();
        expect(find.text('Saman Preferences'), findsOneWidget);
        // Dismiss preferences
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp 123'), findsOneWidget);

        // 4b. Quan ly goi
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quản lý gói'));
        await tester.pumpAndSettle();
        expect(find.byType(ManageMembershipScreen), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp 123'), findsOneWidget);

        // 4c. Giao dien
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giao diện'));
        await tester.pumpAndSettle();
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('System'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp 123'), findsOneWidget);

        // 4d. Nhac nho
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cài đặt nhắc nhở'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Reminders and proactive notifications'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).hideCurrentSnackBar();
        await tester.pumpAndSettle();

        // 4e. Lich su tro chuyen
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lịch sử trò chuyện'));
        await tester.pumpAndSettle();
        expect(find.textContaining('conversation history will be available'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).hideCurrentSnackBar();
        await tester.pumpAndSettle();

        // 4f. Gioi han su dung
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giới hạn sử dụng'));
        await tester.pumpAndSettle();
        expect(
          find.text('Giới hạn sử dụng: Tính năng chưa khả dụng trong phiên bản thử nghiệm.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '5. Narrow viewport (420dp height) internal scrolling and PopScope / Android Back dismissal',
      (tester) async {
        const narrowSize = Size(390, 420);
        tester.view.physicalSize = narrowSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final drawer = SamanChatDrawer(
          isDesktop: false,
          onNewChat: () {},
          onPromptSelected: (_) {},
          onOpenPreferences: () {},
        );

        await tester.pumpWidget(_buildAcceptanceApp(
          child: Scaffold(body: drawer),
          size: narrowSize,
        ));
        await tester.pumpAndSettle();

        // Open menu
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

        // Scroll inside menu
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        expect(find.text('Trợ giúp'), findsOneWidget);

        // Trigger Pop / Android Back
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // Menu closed first, drawer stays open
        expect(find.byType(SamanAccountPopupMenu), findsNothing);
        expect(find.byType(SamanChatDrawer), findsOneWidget);
      },
    );

    testWidgets(
      '4. Trigger verification: Ca nhan hoa Coach, Quan ly goi, Giao dien, Nhac nho, Lich su, va notice chua kha dung',
      (tester) async {
        const desktopSize = Size(1024, 768);
        tester.view.physicalSize = desktopSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(_buildAcceptanceApp(
          child: const ChatScreen(),
          size: desktopSize,
        ));
        await tester.pumpAndSettle();

        // Type a draft
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'Bản nháp 123');
        await tester.pumpAndSettle();

        // 4a. Ca nhan hoa Coach
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cá nhân hóa Coach'));
        await tester.pumpAndSettle();
        expect(find.text('Saman Preferences'), findsOneWidget);
        // Dismiss preferences
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp 123'), findsOneWidget);

        // 4b. Quan ly goi
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quản lý gói'));
        await tester.pumpAndSettle();
        expect(find.byType(ManageMembershipScreen), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp 123'), findsOneWidget);

        // 4c. Giao dien
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giao diện'));
        await tester.pumpAndSettle();
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('System'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(find.text('Bản nháp 123'), findsOneWidget);

        // 4d. Nhac nho
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cài đặt nhắc nhở'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Reminders and proactive notifications'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).clearSnackBars();
        await tester.pumpAndSettle();

        // 4e. Lich su tro chuyen
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lịch sử trò chuyện'));
        await tester.pumpAndSettle();
        expect(find.textContaining('conversation history will be available'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).clearSnackBars();
        await tester.pumpAndSettle();

        // 4f. Gioi han su dung
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giới hạn sử dụng'));
        await tester.pumpAndSettle();
        expect(
          find.text('Giới hạn sử dụng: Tính năng chưa khả dụng trong phiên bản thử nghiệm.'),
          findsOneWidget,
        );
        ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).clearSnackBars();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '5. Narrow viewport (420dp height) internal scrolling and PopScope / Android Back dismissal',
      (tester) async {
        const narrowSize = Size(390, 420);
        tester.view.physicalSize = narrowSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final drawer = SamanChatDrawer(
          isDesktop: false,
          onNewChat: () {},
          onPromptSelected: (_) {},
          onOpenPreferences: () {},
        );

        await tester.pumpWidget(_buildAcceptanceApp(
          child: Scaffold(body: drawer),
          size: narrowSize,
        ));
        await tester.pumpAndSettle();

        // Open menu
        await tester.tap(find.byTooltip('Tùy chọn Saman'));
        await tester.pumpAndSettle();
        expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

        // Scroll inside menu
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        expect(find.text('Trợ giúp'), findsOneWidget);

        // Trigger Pop / Android Back
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // Menu closed first, drawer stays open
        expect(find.byType(SamanAccountPopupMenu), findsNothing);
        expect(find.byType(SamanChatDrawer), findsOneWidget);
      },
    );
  });
}

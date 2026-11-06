import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeVisualChatNotifier extends StateNotifier<ChatState> implements ChatController {
  _FakeVisualChatNotifier(super.initialState);

  @override
  Ref get ref => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> sendMessage(String text) async {}

  @override
  Future<void> retry() async {}

  @override
  void clearError() {}

  @override
  void clearChat() {
    state = state.copyWith(messages: []);
  }

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption, String? mode}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(activeConversationId: conversationId);
  }

  @override
  void newConversation() {
    clearChat();
  }
}

class _StaticProfileNotifier extends StateNotifier<ProfileState> implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _loadTestFonts() async {
  final packageConfig = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await packageConfig.readAsString()) as Map<String, dynamic>;
  final flutterPackage = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final flutterRoot = Directory.fromUri(
    packageConfig.uri.resolve(flutterPackage['rootUri'] as String),
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

Future<void> _captureRepaintPng(
    WidgetTester tester, GlobalKey repaintKey, String outputPath) async {
  await tester.runAsync(() async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final buffer = byteData.buffer.asUint8List();
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(buffer);
  });
}

void main() {
  setUpAll(_loadTestFonts);

  const evidenceDir = 'D:/SamanDev/runtime_evidence/saman-coach-series3/CP-02A/20261104T221500';

  final recentList = [
    ChatConversationSummary(
      id: 'c1',
      title: 'Buổi tập thân trên hôm nay (Ngực & Tay sau)',
      updatedAt: DateTime.now().toIso8601String(),
    ),
    ChatConversationSummary(
      id: 'c2',
      title: 'Kế hoạch dinh dưỡng TDEE & Macro 3 bữa',
      updatedAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    ),
    for (int i = 3; i <= 15; i++)
      ChatConversationSummary(
        id: 'c$i',
        title: 'Hội thoại #$i: Lên lịch tập & theo dõi phục hồi',
        updatedAt: DateTime.now().subtract(Duration(days: i)).toIso8601String(),
      ),
  ];

  final initialChatState = ChatState(
    messages: [
      ChatMessage(
        role: 'user',
        content: 'Chào Saman, hãy lên kế hoạch dinh dưỡng hôm nay theo TDEE của tôi.',
      ),
      ChatMessage(
        role: 'assistant',
        content:
            'Chào bạn! Dựa trên TDEE 2.150 kcal và mục tiêu tăng cơ giảm mỡ của bạn, tôi đề xuất thực đơn 3 bữa giàu đạm với tổng 140g Protein, 220g Carbs và 55g Fat.',
      ),
    ],
    recentConversations: recentList,
    activeConversationId: 'c1',
  );

  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'athlete@saman.app',
  );

  Widget buildApp(GlobalKey repaintKey) {
    return RepaintBoundary(
      key: repaintKey,
      child: ProviderScope(
        overrides: [
          chatControllerProvider
              .overrideWith((ref) => _FakeVisualChatNotifier(initialChatState)),
          profileProvider.overrideWith(
            (ref) => _StaticProfileNotifier(
              ProfileState(
                profile: profileEntity,
                snapshot: profileSnapshot,
                status: ProfileStatus.ready,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: SamanChatTokens.canvas,
            extensions: const [
              AppThemeExtension(
                aiAccent: SamanChatTokens.greenAccent,
                primaryPressed: Color(0xFF0B7249),
                warning: Color(0xFFD97706),
                inkMuted: Color(0xFF888888),
                inkSubtle: Color(0xFF555555),
                hairline: Color(0xFF2A2A2A),
                surfaceElevated: Color(0xFF222222),
                heroNumeric: TextStyle(fontSize: 44),
                labelCaps: TextStyle(fontSize: 11),
                statValue: TextStyle(fontSize: 17),
              ),
            ],
          ),
          home: const ChatScreen(),
        ),
      ),
    );
  }

  testWidgets('CP-02 Render: Desktop Expanded Sidebar (1024x768)', (tester) async {
    tester.view.physicalSize = const Size(1024 * 2.0, 768 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    await tester.pumpWidget(buildApp(repaintKey));
    await tester.pumpAndSettle();

    await _captureRepaintPng(
        tester, repaintKey, '$evidenceDir/desktop_sidebar_expanded.png');
  });

  testWidgets('CP-02 Render: Desktop Icon Rail (1024x768)', (tester) async {
    tester.view.physicalSize = const Size(1024 * 2.0, 768 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    await tester.pumpWidget(buildApp(repaintKey));
    await tester.pumpAndSettle();

    // Tap collapse button
    final collapseBtn = find.byTooltip('Thu gọn thanh bên');
    await tester.tap(collapseBtn);
    await tester.pumpAndSettle();

    await _captureRepaintPng(
        tester, repaintKey, '$evidenceDir/desktop_sidebar_rail.png');
  });

  testWidgets('CP-02 Render: Mobile Drawer Open (390x844)', (tester) async {
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    await tester.pumpWidget(buildApp(repaintKey));
    await tester.pumpAndSettle();

    // Open mobile drawer
    final menuBtn = find.byTooltip('Coach Menu');
    await tester.tap(menuBtn);
    await tester.pumpAndSettle();

    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/mobile_drawer.png');
  });

  testWidgets('CP-02 Render: Long History Scrolled with Pinned Account (1024x768)', (tester) async {
    tester.view.physicalSize = const Size(1024 * 2.0, 768 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    await tester.pumpWidget(buildApp(repaintKey));
    await tester.pumpAndSettle();

    // Drag the scrollable list downwards
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -350));
    await tester.pumpAndSettle();

    await _captureRepaintPng(tester, repaintKey,
        '$evidenceDir/desktop_history_scroll_account_pinned.png');
  });

  testWidgets('CP-02A Render: Sequence of interactions for video/GIF animation', (tester) async {
    tester.view.physicalSize = const Size(1024 * 2.0, 768 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    await tester.pumpWidget(buildApp(repaintKey));
    await tester.pumpAndSettle();

    // Frame 1: Expanded
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_01_expanded.png');

    // Frame 2: Collapse to rail
    await tester.tap(find.byTooltip('Thu gọn thanh bên'));
    await tester.pumpAndSettle();
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_02_rail.png');

    // Frame 3: Re-expand to full sidebar
    await tester.tap(find.byTooltip('Mở rộng thanh bên'));
    await tester.pumpAndSettle();
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_03_reexpanded.png');

    // Frame 4: Switch to Thread c2
    await tester.tap(find.text('Kế hoạch dinh dưỡng TDEE & Macro 3 bữa'));
    await tester.pumpAndSettle();
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_04_thread_switched.png');

    // Frame 5: Open tool - Phân tích lịch sử
    final historyTool = find.descendant(of: find.byType(SamanChatDrawer), matching: find.text('Phân tích lịch sử'));
    await tester.tap(historyTool);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_05_tool_analytics.png');

    // Close analytics sheet
    final sheetContext = tester.element(find.byType(HistoryAnalyticsSheet));
    Navigator.of(sheetContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Frame 6: Open Saman Preferences
    await tester.tap(find.byTooltip('Tùy chọn Saman'));
    await tester.pumpAndSettle();
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_06_preferences.png');

    // Close preferences dialog
    final prefContext = tester.element(find.text('Saman Preferences'));
    Navigator.of(prefContext).pop();
    await tester.pumpAndSettle();

    // Frame 7: Open tool - Phân tích ảnh món ăn (SamanAttachmentSheet)
    final photoTool = find.descendant(of: find.byType(SamanChatDrawer), matching: find.text('Phân tích ảnh món ăn'));
    await tester.tap(photoTool);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _captureRepaintPng(tester, repaintKey, '$evidenceDir/seq_07_food_attachment.png');
  });
}

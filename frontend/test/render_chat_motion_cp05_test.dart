import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _RenderMotionNotifier extends StateNotifier<ChatState> implements ChatController {
  _RenderMotionNotifier(super.initialState);

  @override
  Ref get ref => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> sendMessage(String text) async {}

  @override
  Future<void> retry() async {}

  @override
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void clearChat() {
    state = state.copyWith(messages: []);
  }

  @override
  void newConversation() {
    state = state.copyWith(messages: [], clearActiveConversation: true);
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(activeConversationId: conversationId);
  }
}

class _StaticProfileNotifier extends StateNotifier<ProfileState> implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

ThemeData _buildTestTheme() {
  return ThemeData.dark().copyWith(
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
  );
}

Widget _buildRenderApp({
  required ChatController chatNotifier,
  required GlobalKey repaintKey,
  bool disableAnimations = false,
  String? initialText,
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'saman@member.app',
  );

  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => chatNotifier),
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
      theme: _buildTestTheme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(disableAnimations: disableAnimations),
          child: child!,
        );
      },
      home: RepaintBoundary(
        key: repaintKey,
        child: ChatScreen(initialMessage: initialText),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadTestFonts);

  const evidenceDir = 'D:/SamanDev/runtime_evidence/saman-coach-series3/CP-05/20261105T121500';

  group('CP-05 · Visual Render Suite for Motion & Accessibility', () {
    testWidgets('1. Render desktop sidebar mid-transition at 100ms', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderMotionNotifier(
        ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'Gợi ý lịch tập ngực gym'),
            ChatMessage(role: 'assistant', content: 'Dưới đây là lịch tập 4 bài compound và isolation...'),
          ],
          isLoading: false,
          activeConversationId: 'c1',
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        initialText: 'Bản nháp câu hỏi tiếp theo được giữ nguyên...',
      ));
      await tester.pumpAndSettle();

      // Tap collapse
      await tester.tap(find.byTooltip('Thu gọn thanh bên'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // mid-transition

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/motion_01_sidebar_expand_rail_transition.png',
      );
    });

    testWidgets('2. Render Tools popover with morphing + to x and 6px slide', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderMotionNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: null,
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
      ));
      await tester.pumpAndSettle();

      // Open tools popover
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160)); // finish entry slide

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/motion_02_popover_open_and_morph.png',
      );
    });

    testWidgets('3. Render multiline composer expansion with comfortable touch targets', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderMotionNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: null,
        ),
      );

      const multilineText = 'Mình muốn tăng cơ giảm mỡ trong 12 tuần:\n'
          '- Chiều cao: 175cm, cân nặng 72kg\n'
          '- Tập 4 buổi/tuần (Upper/Lower)\n'
          'Saman tư vấn macro và calorie thâm hụt phù hợp nhé!';

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        initialText: multilineText,
      ));
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/motion_03_multiline_composer_with_keyboard.png',
      );
    });

    testWidgets('4. Render steady waiting indicator under reduced motion', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderMotionNotifier(
        ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'Phân tích chế độ ăn hôm nay'),
          ],
          isLoading: true,
          activeConversationId: 'c1',
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        disableAnimations: true, // Reduced motion
      ));
      await tester.pump(const Duration(milliseconds: 300));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/motion_04_waiting_indicator_steady_reduced_motion.png',
      );
    });

    testWidgets('5. Render reading position with floating Mới nhất pill button', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final manyMessages = List.generate(
        10,
        (i) => i.isEven
            ? ChatMessage(role: 'user', content: 'Câu hỏi số $i: Gợi ý bài tập ngực?')
            : ChatMessage(role: 'assistant', content: 'Trả lời số $i: Ưu tiên incline bench press và dips...'),
      );

      final notifier = _RenderMotionNotifier(
        ChatState(
          messages: manyMessages,
          isLoading: false,
          activeConversationId: 'c1',
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
      ));
      await tester.pumpAndSettle();

      // Scroll up into history
      final scrollableFinder = find
          .descendant(
            of: find.byType(SamanMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollableFinder, const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/motion_05_scroll_to_bottom_button_appearance.png',
      );
    });

    testWidgets('6. Render mode selector popover with high-contrast locked badges', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderMotionNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: null,
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
      ));
      await tester.pumpAndSettle();

      // Open mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160)); // finish slide

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/motion_06_locked_ai_mode_high_contrast.png',
      );
    });
  });
}

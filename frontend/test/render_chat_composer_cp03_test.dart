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
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';
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

void main() {
  setUpAll(_loadTestFonts);

  const evidenceDir = 'D:/SamanDev/runtime_evidence/saman-coach-series3/CP-03/20261104T231500';

  group('CP-03 · Render Suite for Saman Coach Composer & Popovers', () {
    testWidgets('1. Render closed composer single line', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 400 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540.0),
                    child: SamanChatComposer(
                      controller: controller,
                      onSend: () {},
                      isLoading: false,
                      activeMode: AIMode.core3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_closed.png');
      expect(File('$evidenceDir/composer_closed.png').existsSync(), isTrue);
    });

    testWidgets('2. Render multiline expanded composer with bottom-anchored controls', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 450 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController(
        text: 'Em muốn lên kế hoạch tập thân trên hôm nay:\n'
            '- Bài 1: Incline Barbell Bench Press 4 hiệp x 8-10 reps\n'
            '- Bài 2: Dumbbell Shoulder Press 3 hiệp x 10-12 reps\n'
            '- Dinh dưỡng trước tập: 1 chuối + 1 muỗng whey isolate.',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540.0),
                    child: SamanChatComposer(
                      controller: controller,
                      onSend: () {},
                      isLoading: false,
                      activeMode: AIMode.core3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_multiline.png');
      expect(File('$evidenceDir/composer_multiline.png').existsSync(), isTrue);
    });

    testWidgets('3. Render Tools popover (+) toggled to (×)', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 500 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540.0),
                    child: SamanChatComposer(
                      controller: controller,
                      onSend: () {},
                      isLoading: false,
                      activeMode: AIMode.core3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap + button to open popover
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pumpAndSettle();

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_tools_menu_open.png');
      expect(File('$evidenceDir/composer_tools_menu_open.png').existsSync(), isTrue);
    });

    testWidgets('4. Render Mode popover (Core 3 v) with rollout locked status', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 550 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540.0),
                    child: SamanChatComposer(
                      controller: controller,
                      onSend: () {},
                      isLoading: false,
                      activeMode: AIMode.core3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Core 3 button to open popover
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_mode_menu_open.png');
      expect(File('$evidenceDir/composer_mode_menu_open.png').existsSync(), isTrue);
    });

    testWidgets('5. Render empty chat suggestions filling draft into composer', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final chatNotifier = _FakeVisualChatNotifier(ChatState(
        messages: [],
        recentConversations: [
          ChatConversationSummary(
            id: 'c1',
            title: 'Buổi tập thân trên hôm nay',
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ],
        activeConversationId: 'c1',
      ));

      const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
      const profileSnapshot = ProfileSnapshot(
        profile: profileEntity,
        fullName: 'Nguyen Van Saman',
        email: 'saman.athlete@test.com',
      );

      await tester.pumpWidget(
        ProviderScope(
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
            home: RepaintBoundary(
              key: repaintKey,
              child: const ChatScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap suggestion "Plan next meal"
      await tester.tap(find.text('Plan next meal'));
      await tester.pumpAndSettle();

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/empty_chat_suggestions_draft.png');
      expect(File('$evidenceDir/empty_chat_suggestions_draft.png').existsSync(), isTrue);
    });
  });
}

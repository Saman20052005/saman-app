import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

class _FakeVisualChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeVisualChatNotifier(super.initialState);

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {}

  @override
  Future<void> retry() async {}

  @override
  void clearError() {}

  @override
  void clearChat() {
    state = ChatState(messages: []);
  }
}

Future<void> _capturePng(
    WidgetTester tester, GlobalKey key, String outputPath) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final buffer = byteData.buffer.asUint8List();
    final file = File(outputPath);
    await file.writeAsBytes(buffer);
  });
}

void main() {
  testWidgets('Capture visual render of State 05 Typing/Generating at 390x844',
      (tester) async {
    const mobileWidth = 390.0;
    const mobileHeight = 844.0;
    tester.view.physicalSize =
        const Size(mobileWidth * 2.0, mobileHeight * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    const outputPath =
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_05_typing_render.png';

    final fakeChat = _FakeVisualChatNotifier(
      ChatState(
        messages: [
          ChatMessage(
            role: 'user',
            content:
                "Should I reduce today's squat load? Lower back felt tight during morning warmup.",
          ),
        ],
        isLoading: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith((ref) => fakeChat),
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
          home: RepaintBoundary(
            key: repaintKey,
            child: Scaffold(
              backgroundColor: SamanChatTokens.canvas,
              body: const ChatScreen(),
              bottomNavigationBar: SamanBottomNavigationBar(
                currentIndex: 2,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _capturePng(tester, repaintKey, outputPath);
  });

  testWidgets('Capture visual render of State 07 Recoverable Error at 390x844',
      (tester) async {
    const mobileWidth = 390.0;
    const mobileHeight = 844.0;
    tester.view.physicalSize =
        const Size(mobileWidth * 2.0, mobileHeight * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();
    const outputPath =
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_07_error_render.png';

    final fakeChat = _FakeVisualChatNotifier(
      ChatState(
        messages: [
          ChatMessage(
            role: 'user',
            content: "Can you adjust today's workout?",
          ),
        ],
        isLoading: false,
        errorMessage: "I couldn't complete that response.",
        failedUserMessage: "Can you adjust today's workout?",
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith((ref) => fakeChat),
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
          home: RepaintBoundary(
            key: repaintKey,
            child: Scaffold(
              backgroundColor: SamanChatTokens.canvas,
              body: const ChatScreen(),
              bottomNavigationBar: SamanBottomNavigationBar(
                currentIndex: 2,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _capturePng(tester, repaintKey, outputPath);
  });
}

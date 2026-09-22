import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

class _FakeActiveChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeActiveChatNotifier()
      : super(
          ChatState(
            messages: [
              ChatMessage(
                role: 'user',
                content: 'Should I train heavy today?',
              ),
              ChatMessage(
                role: 'assistant',
                content:
                    "Your recovery is slightly below baseline today. I’d keep the session, but reduce the top-set intensity to around RPE 7–7.5.",
              ),
              ChatMessage(
                role: 'user',
                content: 'What should I eat after?',
              ),
              ChatMessage(
                role: 'assistant',
                content:
                    "You still have room in today’s nutrition target. A protein-focused meal with moderate carbs would fit well.",
              ),
            ],
            isLoading: false,
          ),
        );

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {}

  @override
  void clearChat() {
    state = ChatState(messages: []);
  }

  @override
  Future<void> retry() async {}

  @override
  void clearError() {
    state = state.copyWith(clearError: true, clearFailedUserMessage: true);
  }

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}
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
  testWidgets('Capture visual render of Saman Chat Active Conversation at 390x844',
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
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_active_conversation_render.png';

    final fakeChat = _FakeActiveChatNotifier();

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

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/models/saman_nudge.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

class _FakeVisualNudgeChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeVisualNudgeChatNotifier(super.initialState);

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
  testWidgets('Capture visual render of State 04 Reminder / Nudge at 390x844',
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
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_04_reminder_render.png';

    final fakeChat = _FakeVisualNudgeChatNotifier(
      ChatState(messages: []),
    );

    final nudge = SamanNudge(
      id: 'fixture_dinner_nudge',
      message:
          'You still have 620 kcal and 35g protein left today. A high-protein dinner would close most of the gap before tomorrow’s upper-body session.',
      supportingLine: '• 1,780 / 2,400 kcal · 35g protein remaining',
      timestamp: DateTime(2026, 9, 22, 18, 15),
      primaryLabel: 'Plan dinner',
      secondaryLabel: 'Later',
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
              body: ChatScreen(initialNudge: nudge),
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
    await tester.pumpAndSettle();

    await _capturePng(tester, repaintKey, outputPath);
    expect(File(outputPath).existsSync(), isTrue);
  });
}

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
import 'package:health_ai_app/screens/chat/widgets/saman_assistant_response.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_header.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

class _FakeVisualLongChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeVisualLongChatNotifier(super.initialState);

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

const String _fixtureState09Markdown = '''
Looking at your training log and nutrition intake today, here is your breakdown and recommended plan:

### Training

1. Keep the leg session scheduled for tomorrow.
2. Reduce top-set intensity slightly (target **RPE 8** instead of 9).
3. Add a 5-minute hip-mobility warm-up before squats.

### Nutrition

You finished close to your calorie goal but are still about 24g short on protein.

| Metric | Today | Target |
| --- | --- | --- |
| Calories | 2,180 | 2,400 |
| Protein | 142g | 160g |
| Workout | RPE 8.5 | RPE 7–8 |
| Recovery | Moderate | Good |

### Tomorrow

Start with a higher-protein breakfast and keep the session around **RPE 7–8** to compensate for today's systemic fatigue.
''';

void main() {
  testWidgets('Capture visual render of State 09 Long Response at 390x844',
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
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_09_long_response_render.png';

    final messages = [
      ChatMessage(
        role: 'user',
        content:
            'Can you review my workout and nutrition today and tell me what I should change tomorrow?',
      ),
      ChatMessage(
        role: 'assistant',
        content: _fixtureState09Markdown,
      ),
    ];

    final fakeChat = _FakeVisualLongChatNotifier(
      ChatState(messages: messages),
    );

    final actions = [
      const SamanAssistantAction(
        label: "Adjust tomorrow's workout",
        icon: Icons.edit_calendar_outlined,
        isPrimary: true,
      ),
      const SamanAssistantAction(
        label: 'Plan breakfast',
        icon: Icons.restaurant_menu_outlined,
        isPrimary: false,
      ),
    ];

    final scrollController = ScrollController();

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
              appBar: SamanChatHeader(
                onNewChat: () {},
                onMenuTap: () {},
              ),
              body: Column(
                children: [
                  Expanded(
                    child: SamanMessageList(
                      messages: messages,
                      scrollController: scrollController,
                      latestAssistantActions: actions,
                    ),
                  ),
                  Container(
                    color: SamanChatTokens.canvas,
                    padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
                    child: SamanChatComposer(
                      controller: TextEditingController(),
                      onSend: () {},
                      isLoading: false,
                    ),
                  ),
                ],
              ),
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

    // Scroll to display table, sections, and contextual action buttons
    scrollController.jumpTo(420.0);
    await tester.pump();
    await tester.pumpAndSettle();

    await _capturePng(tester, repaintKey, outputPath);
    expect(File(outputPath).existsSync(), isTrue);
  });
}

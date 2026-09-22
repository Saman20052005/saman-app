import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

class _FakeVisualFoodChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeVisualFoodChatNotifier(super.initialState);

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

Widget _buildWrapper({
  required GlobalKey repaintKey,
  required ChatState chatState,
}) {
  final fakeChat = _FakeVisualFoodChatNotifier(chatState);

  return ProviderScope(
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
  );
}

void main() {
  const testImagePath =
      '/Users/saman/Desktop/project-root/frontend/assets/images/nutrition.jpg';

  testWidgets('Capture visual render of State 06 Food Analysis Loading at 390x844',
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
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_06_analysis_render.png';

    final chatState = ChatState(
      foodAnalysisState: const ChatFoodAnalysisState(
        status: FoodAnalysisStatus.analyzing,
        imagePath: testImagePath,
        userCaption: 'Can I fit this into today?',
      ),
    );

    await tester.pumpWidget(
      _buildWrapper(repaintKey: repaintKey, chatState: chatState),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _capturePng(tester, repaintKey, outputPath);
    expect(File(outputPath).existsSync(), isTrue);
  });

  testWidgets('Capture visual render of State 03 Food Photo Result at 390x844',
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
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_03_result_render.png';

    const result = AIAnalysisResult(
      foodName: 'Grilled chicken, quinoa & steamed broccoli',
      foodLabel: 'grilled_chicken_bowl',
      confidence: 0.94,
      lowConfidence: false,
      grams: 420.0,
      calories: 620.0,
      protein: 48.0,
      carbs: 58.0,
      fat: 16.0,
      per100g: {'calories': 148, 'protein': 11, 'carbs': 14, 'fat': 4},
      nutritionSource: 'usda',
      top3: [],
    );

    final chatState = ChatState(
      foodAnalysisState: const ChatFoodAnalysisState(
        status: FoodAnalysisStatus.success,
        imagePath: testImagePath,
        userCaption: 'Can I fit this into today?',
        result: result,
      ),
    );

    await tester.pumpWidget(
      _buildWrapper(repaintKey: repaintKey, chatState: chatState),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _capturePng(tester, repaintKey, outputPath);
    expect(File(outputPath).existsSync(), isTrue);
  });

  testWidgets('Capture visual render of State 08 Food Photo Failure at 390x844',
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
        '/Users/saman/.gemini/antigravity-ide/brain/3f6beed2-836f-4f92-acf2-501da675c85b/saman_chat_state_08_failure_render.png';

    final chatState = ChatState(
      foodAnalysisState: const ChatFoodAnalysisState(
        status: FoodAnalysisStatus.failure,
        imagePath: testImagePath,
        userCaption: 'Can I fit this into today?',
        errorMessage:
            "I couldn't estimate this meal confidently from the photo.",
      ),
    );

    await tester.pumpWidget(
      _buildWrapper(repaintKey: repaintKey, chatState: chatState),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _capturePng(tester, repaintKey, outputPath);
    expect(File(outputPath).existsSync(), isTrue);
  });
}

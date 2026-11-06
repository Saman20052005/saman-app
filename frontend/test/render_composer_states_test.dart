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
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';

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

  const evidenceDir = 'D:/SamanDev/runtime_evidence/saman-coach-series3/composer_states';

  group('Gemini-Aligned Composer Visual Render Suite', () {
    testWidgets('1. Render Empty State Pill (matches Gemini Image 1)', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 300 * 2);
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
            backgroundColor: const Color(0xFF0B111E), // Dark canvas matching Gemini bg
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620.0),
                    child: SamanChatComposer(
                      controller: controller,
                      hintText: 'Hỏi Saman',
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

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_empty_pill.png');
      expect(File('$evidenceDir/composer_empty_pill.png').existsSync(), isTrue);
    });

    testWidgets('2. Render Focused Empty State Pill (retains 1-row pill)', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 300 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: const Color(0xFF0B111E),
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620.0),
                    child: SamanChatComposer(
                      controller: controller,
                      focusNode: focusNode,
                      hintText: 'Hỏi Saman',
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

      focusNode.requestFocus();
      await tester.pumpAndSettle();

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_focused_empty.png');
      expect(File('$evidenceDir/composer_focused_empty.png').existsSync(), isTrue);
    });

    testWidgets('3. Render Single-line Composing State (matches Gemini Image 2)', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 340 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController(text: 'khi user soạn câu hỏi');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: const Color(0xFF0B111E),
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620.0),
                    child: SamanChatComposer(
                      controller: controller,
                      hintText: 'Hỏi Saman',
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

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_composing_single_line.png');
      expect(File('$evidenceDir/composer_composing_single_line.png').existsSync(), isTrue);
    });

    testWidgets('4. Render Multiline Expanded Composing State (pins bottom row)', (tester) async {
      tester.view.physicalSize = const Size(800 * 2, 400 * 2);
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
            backgroundColor: const Color(0xFF0B111E),
            body: RepaintBoundary(
              key: repaintKey,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620.0),
                    child: SamanChatComposer(
                      controller: controller,
                      hintText: 'Hỏi Saman',
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

      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/composer_composing_multiline.png');
      expect(File('$evidenceDir/composer_composing_multiline.png').existsSync(), isTrue);
    });
  });
}

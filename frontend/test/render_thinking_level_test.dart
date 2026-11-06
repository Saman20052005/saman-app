import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  const evidenceDir = 'D:/SamanDev/runtime_evidence/saman-coach-series3/thinking_level';

  group('Thinking Level Render Evidence Suite', () {
    testWidgets('1. Render desktop dual-menu cascade: AI modes + Thinking Level submenu', (tester) async {
      tester.view.physicalSize = const Size(1280 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController(text: 'Kế hoạch dinh dưỡng tuần tới');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: RepaintBoundary(
              key: repaintKey,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0, left: 32.0, right: 32.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620.0),
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

      // Open AI Mode Menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Open Thinking Level Submenu
      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pumpAndSettle();

      // Capture desktop screenshot
      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/desktop_dual_menu_cascade.png');
      expect(File('$evidenceDir/desktop_dual_menu_cascade.png').existsSync(), isTrue);
    });

    testWidgets('2. Render mobile drilldown submenu: header with back navigation + options', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final controller = TextEditingController(text: 'Thực đơn tăng cơ');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTestTheme(),
          home: Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: RepaintBoundary(
              key: repaintKey,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360.0),
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

      // Open Mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Tap Thinking Level trigger row to enter mobile drilldown
      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pumpAndSettle();

      // Capture mobile drilldown screenshot
      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/mobile_drilldown_submenu.png');
      expect(File('$evidenceDir/mobile_drilldown_submenu.png').existsSync(), isTrue);
    });

    testWidgets('3. Render mobile main menu showing Thinking Level trigger row', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
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
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360.0),
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

      // Open Mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Capture mobile main menu screenshot
      await _captureRepaintPng(tester, repaintKey, '$evidenceDir/mobile_main_menu_trigger.png');
      expect(File('$evidenceDir/mobile_main_menu_trigger.png').existsSync(), isTrue);
    });
  });
}


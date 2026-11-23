import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/services/analytics_service.dart';

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

void main() {
  setUpAll(_loadTestFonts);

  const evidenceDir =
      'C:/Users/GL/.gemini/antigravity/brain/dd776699-076b-49c4-a273-0d162dbef616/trend_analysis_stitch';

  group('Trend Analysis Sheet Visual Render Suite', () {
    testWidgets('1. Render Frame 1: With Data (14 days, 38 meals, 14 workouts)',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 720 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final quote = AnalyticsQuote(
        quoteId: 'quote-frame1-render',
        rangeDays: 14,
        rawNutritionCount: 38,
        activeDays: 12,
        workoutSessions: 14,
        includedWorkouts: 14,
        workoutTruncated: false,
        estimatedTokens: 3840,
        quotaCost: 1,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF0F172A),
              body: RepaintBoundary(
                key: repaintKey,
                child: Container(
                  color: const Color(0xFF0F172A),
                  alignment: Alignment.bottomCenter,
                  child: HistoryAnalyticsSheet(
                    initialQuote: quote,
                    isDemo: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/trend_analysis_frame1_data.png',
      );
    });

    testWidgets('2. Render Frame 2: Empty State (7 days, 0 meals, 0 workouts)',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final quote = AnalyticsQuote(
        quoteId: 'quote-frame2-render',
        rangeDays: 7,
        rawNutritionCount: 0,
        activeDays: 0,
        workoutSessions: 0,
        includedWorkouts: 0,
        workoutTruncated: false,
        estimatedTokens: 0,
        quotaCost: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF0F172A),
              body: RepaintBoundary(
                key: repaintKey,
                child: Container(
                  color: const Color(0xFF0F172A),
                  alignment: Alignment.bottomCenter,
                  child: HistoryAnalyticsSheet(
                    initialQuote: quote,
                    isDemo: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/trend_analysis_frame2_empty.png',
      );
    });
  });
}


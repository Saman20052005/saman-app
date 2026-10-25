import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_meal_estimate_card.dart';

import 'fixtures/chat_render/render_resources.dart';

const _caution =
    'Calories and macros are AI estimates. Please review before logging.';
const _badges = {
  'usda': 'USDA data',
  'openfoodfacts': 'OpenFoodFacts',
  'fallback': 'Reference data',
  'gemini_estimate': 'Gemini estimate',
  'unknown': 'Source unavailable',
};

AIAnalysisResult _result(String? source) => AIAnalysisResult.fromJson({
      'food_name':
          'Grilled chicken, quinoa and steamed broccoli with vegetables',
      'food_label': 'chicken',
      'confidence': 0.94,
      'grams': 350,
      'nutrition': {'calories': 620, 'protein': 42, 'carbs': 68, 'fat': 18},
      if (source != null) 'nutrition_source': source,
    });

Future<GlobalKey> _pumpCard(
  WidgetTester tester,
  String? source, {
  bool logged = false,
  VoidCallback? onLogMeal,
  double width = 380,
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          backgroundColor: SamanChatTokens.canvas,
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: SamanMealEstimateCard(
                result: _result(source),
                isMealLogged: logged,
                onLogMeal: onLogMeal ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['SAMAN_CP18_EVIDENCE'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$output/renders/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  setUpAll(loadChatRenderFonts);

  for (final source in [
    ..._badges.keys,
    '',
    'USDA',
    'reference',
    null,
    'unrecognized_provider_with_a_very_long_name'
  ]) {
    testWidgets(
        'Raw source $source renders honest provenance and unchanged data',
        (tester) async {
      final result = _result(source);
      await _pumpCard(tester, source);
      expect(
          find.text(_badges[source] ?? 'Source unavailable'), findsOneWidget);
      expect(find.text(_caution),
          source == 'gemini_estimate' ? findsOneWidget : findsNothing);
      expect(find.text('Meal estimate'), findsOneWidget);
      expect(find.text('~620 kcal'), findsOneWidget);
      for (final grams in ['42g', '68g', '18g']) {
        expect(find.text(grams), findsOneWidget);
      }
      expect(result.grams, 350);
      expect(result.withGrams(200).nutritionSource, result.nutritionSource);
      expect(tester.takeException(), isNull);
    });
  }

  for (final source in _badges.keys) {
    testWidgets('$source keeps log callback and logged disabled state',
        (tester) async {
      var calls = 0;
      await _pumpCard(tester, source, onLogMeal: () => calls++);
      await tester.tap(find.text('Log meal'));
      expect(calls, 1);
      await _pumpCard(tester, source, logged: true, onLogMeal: () => calls++);
      expect(find.text('Log meal'), findsNothing);
      expect(find.text('✓ Meal logged'), findsOneWidget);
      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      await tester.tap(find.text('✓ Meal logged'));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final narrow in [false, true]) {
      for (final entry in _badges.entries) {
        testWidgets(
            '${brightness.name} ${narrow ? 'narrow scaled' : 'normal'} '
            '${entry.key} wraps and has readable provenance', (tester) async {
          final key = await _pumpCard(tester, entry.key,
              width: narrow ? 280 : 380,
              scale: narrow ? 2 : 1,
              brightness: brightness);
          final badge = find.text(entry.value);
          expect(badge, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(badge);
          expect(paragraph.didExceedMaxLines, isFalse);
          final text = tester.widget<Text>(badge);
          final container = tester.widget<Container>(
              find.ancestor(of: badge, matching: find.byType(Container)).first);
          final decoration = container.decoration! as BoxDecoration;
          final background =
              Color.alphaBlend(decoration.color!, SamanChatTokens.surface);
          expect(_contrast(text.style!.color!, background),
              greaterThanOrEqualTo(4.5));
          if (entry.key == 'gemini_estimate') {
            final caution = tester.widget<Text>(find.text(_caution));
            expect(_contrast(caution.style!.color!, SamanChatTokens.surface),
                greaterThanOrEqualTo(4.5));
            expect(
                tester
                    .renderObject<RenderParagraph>(find.text(_caution))
                    .didExceedMaxLines,
                isFalse);
          }
          expect(tester.takeException(), isNull);
          await _capture(tester, key,
              '${entry.key}_${brightness.name}_${narrow ? '280_scale2' : '380_scale1'}');
        });
      }
    }
  }
}

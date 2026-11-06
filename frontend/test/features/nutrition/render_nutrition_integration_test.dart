import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/presentation/widgets/nutrition_home_components.dart';

import 'nutrition_home_ui_test.dart' as existing;
import 'nutrition_ui_integration_test.dart';

const destination = String.fromEnvironment('EVIDENCE_DIR');
const captureKey = ValueKey('integrated-nutrition-capture');

Future<void> capture(WidgetTester tester, String filename) async {
  if (destination.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(destination).createSync(recursive: true);
    File('$destination/$filename.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // Use the SDK's bundled Roboto for deterministic Flutter test rendering.
    // Browser evidence separately runs the complete lib/main.dart app/theme.
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk != null) {
      final bytes =
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-regular.ttf')
              .readAsBytesSync();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  for (final scenario in [
    (name: 'production-screen-empty', empty: true, width: 390.0, scale: 1.0),
    (
      name: 'production-screen-populated',
      empty: false,
      width: 390.0,
      scale: 1.0
    ),
    (name: 'production-screen-narrow', empty: false, width: 320.0, scale: 1.0),
    (name: 'production-screen-200pct', empty: false, width: 320.0, scale: 2.0),
  ]) {
    testWidgets('render integrated ${scenario.name}', (tester) async {
      tester.view.physicalSize = Size(scenario.width, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      final notifier = IntegrationNutritionNotifier(
          scenario.empty ? emptyIntegratedPlan() : existing.createSamplePlan());
      await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: integratedNutritionTestApp(notifier, scale: scenario.scale)));
      await tester.runAsync(() => precacheImage(
          const AssetImage(NutritionFoodHero.foodAsset),
          tester.element(find.byType(NutritionFoodHero))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await capture(tester, scenario.name);
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await capture(tester, '${scenario.name}-scrolled');
    });
  }
}

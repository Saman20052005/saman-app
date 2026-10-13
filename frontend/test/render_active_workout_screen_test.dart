import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_review_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_complete_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture_boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(bytes, isNotNull);
    final file = File('test/workout_evidence/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the SDK's real Material font instead of the test-only Ahem glyphs.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final loader = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      loader.addFont(File('${artifacts.path}/material_fonts/roboto-$weight.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File('${artifacts.path}/material_fonts/materialicons-regular.otf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    await icons.load();
    if (Platform.isWindows) {
      final mono = FontLoader('monospace')
        ..addFont(
          File('${Platform.environment['WINDIR']}/Fonts/consola.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await mono.load();
    }
  });
  for (final size in [
    const Size(320, 600),
    const Size(375, 812),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('Active -> Review -> Complete -> History renders at ${size.width}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('capture_boundary'),
            child: child!,
          ),
          home: const ActiveWorkoutScreen(autoTick: false),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 390) await capture(tester, 'active');

      await tester
          .tap(find.byKey(const ValueKey('active_workout_log_set_button')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('active_workout_finish_button')));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutReviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (size.width == 390) {
        await capture(tester, 'review_top');
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        await capture(tester, 'review_bottom');
      }

      await tester.tap(find.byKey(const ValueKey('save_session_button')));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutCompleteScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (size.width == 390) {
        await capture(tester, 'complete_top');
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        await capture(tester, 'complete_bottom');
      }

      await tester.tap(find.text('View workout history'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
      expect(find.text('Upper Body Strength'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 390) await capture(tester, 'history');
      await tester.pumpWidget(const SizedBox());
    });
  }
}

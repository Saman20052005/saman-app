import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout/data/repositories/mock_exercise_repository.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/presentation/screens/session_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';

import 'workout_history_detail_redesign_test.dart' as fixtures;

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final root = Platform.environment['SAMAN_RENDER_EVIDENCE'] ??
        '${Directory.systemTemp.path}/saman_cp19';
    final file = File('$root/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final font = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      font.addFont(File('${artifacts.path}/material_fonts/roboto-$weight.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    }
    await font.load();
    // Explicit DefaultTextStyle in the existing detail uses the test fallback
    // family. Give it the same real SDK glyphs as the themed text.
    final fallback = FontLoader('Ahem')
      ..addFont(File('${artifacts.path}/material_fonts/roboto-regular.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await fallback.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
          File('${artifacts.path}/material_fonts/materialicons-regular.otf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
    await icons.load();
  });
  for (final width in [280.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('History and detail width $width scale $scale',
          (tester) async {
        FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-only'});
        await tester.binding.setSurfaceSize(Size(width, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = MockExerciseRepository(curatedExerciseLibrary);
        final saved = fixtures.session('render', '2026-10-24T16:59:59Z',
            title: 'Upper body strength with a very long saved workout title',
            minutes: 0,
            logs: [
              fixtures.log(id: 'db-bench-press'),
              fixtures.log(id: 'plank', seconds: 50, weight: 0),
              fixtures.log(id: 'unknown-exercise', reps: 10, weight: 0),
            ]);
        await repo.saveWorkoutSession(saved.copyWith(totalVolumeKg: 208));
        final container = ProviderContainer(overrides: [
          exerciseRepositoryProvider.overrideWithValue(repo),
          workoutSessionRepositoryProvider.overrideWithValue(repo),
        ]);
        addTearDown(container.dispose);
        Widget app(Widget home) => UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Roboto'),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                      key: const ValueKey('capture'), child: child!),
                ),
                home: home,
              ),
            );
        final prefix = '${width.toInt()}_scale${scale.toInt()}';
        await tester.pumpWidget(app(const WorkoutHistoryScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, '${prefix}_history');
        await tester.enterText(find.byType(TextField),
            'A very long search query without matching saved workouts');
        await tester.pumpAndSettle();
        expect(find.text('No workouts match your filters'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, '${prefix}_search');
        await tester.tap(find.byTooltip('Clear filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Calendar and period overview'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, '${prefix}_calendar');
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, '${prefix}_overview');
        await tester
            .pumpWidget(app(const SessionDetailScreen(sessionId: 'render')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, '${prefix}_detail');
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, '${prefix}_detail_bottom');
      });
    }
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/active_workout_state.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_review_screen.dart';
import 'package:health_ai_app/presentation/widgets/exercise_card.dart';
import 'package:health_ai_app/presentation/widgets/exercise_thumbnail.dart';

import 'workout_exercise_catalog_test.dart'
    show originalExerciseIds, expectedNewExercises;

const evidenceDirectory = String.fromEnvironment('WORKOUT_IMAGE_EVIDENCE');

const testWorkoutThemeExtension = AppThemeExtension(
  aiAccent: Color(0xFF10B981),
  primaryPressed: Color(0xFF0B7249),
  warning: Color(0xFFD97706),
  inkMuted: Color(0xFF888888),
  inkSubtle: Color(0xFF555555),
  hairline: Color(0xFF2A2A2A),
  surfaceElevated: Color(0xFF222222),
  heroNumeric: TextStyle(fontSize: 44),
  labelCaps: TextStyle(fontSize: 11),
  statValue: TextStyle(fontSize: 17),
);

Future<void> capture(WidgetTester tester, String name,
    {double pixelRatio = 2}) async {
  if (evidenceDirectory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('image_evidence_boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$evidenceDirectory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

List<String> sources(WidgetTester tester, Finder screen) => tester
    .widgetList<ExerciseThumbnail>(
      find.descendant(of: screen, matching: find.byType(ExerciseThumbnail)),
    )
    .map((image) => image.source)
    .toList();

Future<void> loadImages(WidgetTester tester, Iterable<String> paths) async {
  final context = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final path in paths.where((path) => path.startsWith('assets/'))) {
      await precacheImage(AssetImage(path), context);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> loadTestFonts() async {
  // Real SDK fonts also keep layout assertions independent of Ahem metrics.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final text = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    text.addFont(File('${artifacts.path}/material_fonts/roboto-$weight.ttf')
        .readAsBytes()
        .then(ByteData.sublistView));
  }
  await text.load();
  final monospace = FontLoader('monospace');
  final evidenceFont = File('C:/Windows/Fonts/consola.ttf');
  final monoFile = evidenceDirectory.isNotEmpty && evidenceFont.existsSync()
      ? evidenceFont
      : File('${artifacts.path}/material_fonts/roboto-regular.ttf');
  monospace.addFont(monoFile.readAsBytes().then(ByteData.sublistView));
  await monospace.load();
  await (FontLoader('MaterialIcons')
        ..addFont(
            File('${artifacts.path}/material_fonts/materialicons-regular.otf')
                .readAsBytes()
                .then(ByteData.sublistView)))
      .load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final cacheDirectory =
        await Directory.systemTemp.createTemp('saman-workout-image-cache-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => cacheDirectory.path,
    );
    await loadTestFonts();
  });

  testWidgets('Every approved variant loads and decodes from Flutter bundle',
      (tester) async {
    final thumbnails = {
      ...curatedExerciseLibrary.map((e) => e.thumbnailUrl),
      ...createDefaultUpperBodySession().exercises.map((e) => e.imageUrl),
    };
    expect(curatedExerciseLibrary, hasLength(27));
    expect(curatedExerciseLibrary.map((e) => e.id),
        [...originalExerciseIds, ...expectedNewExercises.keys]);
    expect(thumbnails, hasLength(27));
    expect(thumbnails, expectedNewExercises.keys.followedBy(
        curatedExerciseLibrary.take(17).map((e) => e.slug))
        .map((slug) => 'assets/images/exercises/$slug-thumb.jpg').toSet());
    for (final thumbnail in thumbnails) {
      final paths = [
        thumbnail,
        exercisePosterSource(thumbnail)
      ];
      expect(paths, everyElement(startsWith('assets/images/exercises/')));
      for (final path in paths.where((path) => path.isNotEmpty)) {
        final bytes = await rootBundle.load(path);
        final dimensions = await tester.runAsync(() async {
          final codec =
              await ui.instantiateImageCodec(bytes.buffer.asUint8List());
          final frame = await codec.getNextFrame();
          final result =
              Size(frame.image.width.toDouble(), frame.image.height.toDouble());
          frame.image.dispose();
          codec.dispose();
          return result;
        });
        expect(
            dimensions,
            path.endsWith('-thumb.jpg')
                ? const Size(512, 512)
                : const Size(1280, 720));
      }
    }
    expect(exercisePosterSource('assets/images/exercises/plank-thumb.jpg'),
        'assets/images/exercises/plank-poster.jpg');
  });

  testWidgets('Empty and missing asset sources have neutral fallback',
      (tester) async {
    for (final source in ['', 'assets/images/exercises/missing.jpg']) {
      await tester.pumpWidget(MaterialApp(
          home: ExerciseThumbnail(
        source: source,
        width: 80,
        height: 80,
        showUnavailableLabel: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Exercise image unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.fitness_center_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('HTTP(S) loading and error use the same neutral fallback',
      (tester) async {
    for (final scheme in ['http', 'https']) {
      await tester.pumpWidget(MaterialApp(
          home: ExerciseThumbnail(
        source: '$scheme://invalid.example/missing.jpg',
        width: 80,
        height: 80,
        showUnavailableLabel: true,
      )));
      final network =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final context = tester.element(find.byType(CachedNetworkImage));
      final loading = network.placeholder!(context, network.imageUrl);
      expect(loading, isNotNull);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // TestWidgetsFlutterBinding's HTTP client returns an error response.
      for (var attempt = 0;
          attempt < 20 &&
              find.text('Exercise image unavailable').evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.text('Exercise image unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // Flush the cache manager's scheduled cleanup in the fake test clock.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  for (final id in curatedExerciseLibrary.map((e) => e.id)) {
    testWidgets(
        '$id keeps image approval across Library -> Detail -> Active -> Review',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final exercise = curatedExerciseLibrary.firstWhere((e) => e.id == id);
      final poster = exercisePosterSource(exercise.thumbnailUrl);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (_, child) => RepaintBoundary(
            key: const ValueKey('image_evidence_boundary'),
            child: child!,
          ),
          home: const ExerciseLibraryScreen(initialCategory: 'All'),
        ),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField), exercise.name);
      await tester.pump();
      await loadImages(tester, [exercise.thumbnailUrl, poster]);
      expect(sources(tester, find.byType(ExerciseLibraryScreen)),
          [exercise.thumbnailUrl]);
      await capture(tester, '$id-library');

      await tester.tap(find.byKey(ValueKey('exercise_row_$id')));
      await tester.pumpAndSettle();
      expect(sources(tester, find.byType(ExerciseDetailScreen)), [poster]);
      expect(
          tester.widget<ExerciseThumbnail>(find.byType(ExerciseThumbnail)).fit,
          BoxFit.contain);
      if (poster.isEmpty)
        expect(find.text('Exercise image unavailable'), findsOneWidget);
      await capture(tester, '$id-detail');
      await tester
          .tap(find.byKey(const ValueKey('exercise_detail_start_button')));
      await tester.pumpAndSettle();
      final sessionId =
          container.read(activeWorkoutSessionProvider.notifier).sessionId;
      expect(
          container.read(activeWorkoutSessionProvider).exercises.single.id, id);
      expect(sources(tester, find.byType(ActiveWorkoutScreen)), [poster]);
      expect(
          tester.widget<ExerciseThumbnail>(find.byType(ExerciseThumbnail)).fit,
          BoxFit.contain);
      await capture(tester, '$id-active');

      final log = find.byKey(const ValueKey('active_workout_log_set_button'));
      final isBodyweight = id == 'reverse-lunge' || id == 'dead-bug';
      if (isBodyweight) {
        final minus = find.byKey(const ValueKey('active_workout_weight_minus'));
        await tester.ensureVisible(minus);
        for (var kg = 20; kg > 0; kg--) {
          await tester.tap(minus);
          await tester.pump();
        }
        expect(container.read(activeWorkoutSessionProvider)
            .currentExercise!.draftWeightKg, 0);
      }
      await tester.ensureVisible(log);
      await tester.tap(log);
      await tester.pumpAndSettle();
      final logged =
          container.read(activeWorkoutSessionProvider).exercises.single;
      if (id == 'plank') {
        expect(logged.sets.first.unit, SetUnit.seconds);
        expect(logged.sets.first.seconds, 45);
        expect(logged.sets.first.reps, 0);
        expect(logged.sets.first.weightKg, 0);
      } else {
        expect(logged.sets.first.reps,
            int.parse(exercise.defaultReps.split('-').first));
        expect(logged.sets.first.weightKg, isBodyweight ? 0 : 20);
      }
      await tester
          .tap(find.byKey(const ValueKey('active_workout_finish_button')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutReviewScreen), findsOneWidget);
      expect(sources(tester, find.byType(WorkoutReviewScreen)),
          [poster, exercise.thumbnailUrl]);
      expect(container.read(activeWorkoutSessionProvider.notifier).sessionId,
          sessionId);
      await capture(tester, '$id-review-top');
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -480));
      await tester.pumpAndSettle();
      await capture(tester, '$id-review');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('ExerciseCard and switched Active exercise use their own sources',
      (tester) async {
    final selected = curatedExerciseLibrary;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [
          testWorkoutThemeExtension,
        ]),
        home: ExerciseCard(exercise: selected[2], onTap: () {})));
    await loadImages(tester, [selected[2].thumbnailUrl]);
    expect(
        sources(tester, find.byType(ExerciseCard)), [selected[2].thumbnailUrl]);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: ActiveWorkoutScreen(exercises: selected, autoTick: false)),
    ));
    await loadImages(
        tester, selected.map((e) => exercisePosterSource(e.thumbnailUrl)));
    final notifier = container.read(activeWorkoutSessionProvider.notifier);
    final sessionId = notifier.sessionId;
    for (final exercise in selected) {
      expect(sources(tester, find.byType(ActiveWorkoutScreen)),
          [exercisePosterSource(exercise.thumbnailUrl)]);
      expect(container.read(activeWorkoutSessionProvider).currentExercise!.id,
          exercise.id);
      expect(notifier.sessionId, sessionId);
      notifier.nextExercise();
      await tester.pumpAndSettle();
    }
    final legacy = createDefaultUpperBodySession().exercises.first;
    expect(legacy.id, 'ex_1');
    expect(legacy.imageUrl, selected.first.thumbnailUrl);
    expect(legacy.draftWeightKg, 26);
    expect(legacy.sets.map((s) => s.targetReps), everyElement(8));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Default Active switches variants and preserves legacy session',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ActiveWorkoutScreen(autoTick: false),
      ),
    ));
    final notifier = container.read(activeWorkoutSessionProvider.notifier);
    final initial = container.read(activeWorkoutSessionProvider);
    final expected = <String, String>{
      'ex_1': 'dumbbell-bench-press',
      'ex_2': 'lat-pulldown',
      'ex_3': 'incline-dumbbell-flyes',
      'ex_4': 'overhead-triceps-extension',
      'ex_5': 'face-pulls',
    };
    expect(initial.exercises.map((e) => e.id), expected.keys);
    expect(initial.exercises.map((e) => e.draftWeightKg), [26, 45, 16, 20, 15]);
    expect(initial.exercises.map((e) => e.draftReps), [8, 10, 12, 12, 15]);
    expect(initial.exercises.map((e) => e.sets.length), [4, 4, 3, 3, 4]);
    final sessionId = notifier.sessionId;
    await loadImages(tester, expected.values.map(
        (slug) => 'assets/images/exercises/$slug-poster.jpg'));
    for (final entry in expected.entries) {
      final current = container.read(activeWorkoutSessionProvider).currentExercise!;
      expect(current.id, entry.key);
      expect(current.imageUrl,
          'assets/images/exercises/${entry.value}-thumb.jpg');
      expect(sources(tester, find.byType(ActiveWorkoutScreen)),
          ['assets/images/exercises/${entry.value}-poster.jpg']);
      expect(notifier.sessionId, sessionId);
      notifier.nextExercise();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Review mixed session banner never substitutes another exercise',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final selected = curatedExerciseLibrary
        .where((e) => e.id == 'db-bench-press' || e.id == 'plank').toList();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ActiveWorkoutScreen(exercises: selected, autoTick: false),
      ),
    ));
    final notifier = container.read(activeWorkoutSessionProvider.notifier);
    notifier.logActiveSet();
    notifier.nextExercise();
    notifier.logActiveSet();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WorkoutReviewScreen()),
    ));
    await loadImages(tester, selected.map((e) => e.thumbnailUrl));
    expect(sources(tester, find.byType(WorkoutReviewScreen)),
        ['', ...selected.map((e) => e.thumbnailUrl)]);
    expect(find.text('Exercise image unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_outlined), findsOneWidget);
    expect(exerciseReviewPosterSource(['']), isEmpty);
    expect(exerciseReviewPosterSource(['unresolved-plan-image']), isEmpty);
    expect(exerciseReviewPosterSource(const []), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Flutter contact sheets show 68/80 crops and landscape posters',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final groups = [
      curatedExerciseLibrary.take(9).map((e) => (e.name, e.thumbnailUrl)).toList(),
      curatedExerciseLibrary.skip(9).take(8).map((e) => (e.name, e.thumbnailUrl)).toList(),
      curatedExerciseLibrary.skip(20).map((e) => (e.name, e.thumbnailUrl)).toList(),
      createDefaultUpperBodySession().exercises
          .map((e) => (e.name, e.imageUrl)).toList(),
    ];
    for (var page = 0; page < groups.length; page++) {
      final exercises = groups[page];
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: RepaintBoundary(
          key: const ValueKey('image_evidence_boundary'),
          child: Scaffold(
            appBar: AppBar(title: Text(
                'Flutter test engine | ${page < 3 ? "Library ${page + 1}/3" : "Default Active"} | 68px / 80px + poster')),
            body: GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 400,
                mainAxisSpacing: 8,
                crossAxisSpacing: 16,
              ),
              itemCount: exercises.length,
              itemBuilder: (_, index) {
                final (name, thumbnail) = exercises[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 12),
                    Row(children: [
                      ExerciseThumbnail(source: thumbnail, width: 68, height: 68),
                      const SizedBox(width: 16),
                      ExerciseThumbnail(source: thumbnail, width: 80, height: 80),
                      const SizedBox(width: 16),
                      const Text('68 x 68\n80 x 80'),
                    ]),
                    const SizedBox(height: 12),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ExerciseThumbnail(
                        source: exercisePosterSource(thumbnail),
                        fit: BoxFit.contain,
                        showUnavailableLabel: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ));
      await loadImages(tester, exercises.expand((e) =>
          [e.$2, exercisePosterSource(e.$2)]));
      expect(find.byType(ExerciseThumbnail), findsNWidgets(exercises.length * 3));
      expect(find.byIcon(Icons.fitness_center_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester,
          page < 3 ? 'contact-library-${page + 1}' : 'contact-default-active',
          pixelRatio: 1);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

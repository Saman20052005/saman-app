import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
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
    show originalExerciseIds, allNewExercises, expectedRoundTwoExercises;

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

File? _findFontFile(List<String> paths) {
  for (final path in paths) {
    if (path.isEmpty) continue;
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

Future<void> loadTestFonts() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final devtoolsFonts =
      '$flutterRoot/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts';

  final text = FontLoader('Roboto');
  var robotoLoaded = false;
  for (final weight in ['regular', 'medium', 'bold']) {
    final cap = weight[0].toUpperCase() + weight.substring(1);
    final fontFile = _findFontFile([
      '${artifacts.path}/material_fonts/roboto-$weight.ttf',
      '$devtoolsFonts/Roboto/Roboto-$cap.ttf',
      '$devtoolsFonts/Roboto/Roboto-$weight.ttf',
    ]);
    if (fontFile != null) {
      text.addFont(fontFile.readAsBytes().then(ByteData.sublistView));
      robotoLoaded = true;
    }
  }
  if (robotoLoaded) {
    await text.load();
  }

  final monospace = FontLoader('monospace');
  final evidenceFont = File('C:/Windows/Fonts/consola.ttf');
  final monoFile = _findFontFile([
    if (evidenceDirectory.isNotEmpty && evidenceFont.existsSync())
      evidenceFont.path,
    '$devtoolsFonts/Roboto_Mono/RobotoMono-Regular.ttf',
    '${artifacts.path}/material_fonts/roboto-regular.ttf',
    '$devtoolsFonts/Roboto/Roboto-Regular.ttf',
  ]);
  if (monoFile != null) {
    monospace.addFont(monoFile.readAsBytes().then(ByteData.sublistView));
    await monospace.load();
  }

  final iconsFile = _findFontFile([
    '${artifacts.path}/material_fonts/materialicons-regular.otf',
    '$devtoolsFonts/MaterialIcons-Regular.otf',
  ]);
  if (iconsFile != null) {
    await (FontLoader('MaterialIcons')
          ..addFont(iconsFile.readAsBytes().then(ByteData.sublistView)))
        .load();
  }
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
    expect(curatedExerciseLibrary, hasLength(35));
    expect(curatedExerciseLibrary.map((e) => e.id),
        [...originalExerciseIds, ...allNewExercises.keys]);
    expect(thumbnails, hasLength(35));
    expect(thumbnails, allNewExercises.keys.followedBy(
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
    final variants = thumbnails.expand((source) => [source, exercisePosterSource(source)]).toSet();
    expect(variants, hasLength(70));
    final files = Directory('assets/images/exercises').listSync()
        .whereType<File>().where((file) => file.path.endsWith('.jpg'));
    expect(files, hasLength(70));
  });

  test('All 54 prior image bytes retain their pre-task SHA-256', () {
    const expectedHashes = <String, String>{
      'assets/images/exercises/ab-wheel-rollout-poster.jpg': 'a9703d3ae53457b1a8afc13fa65a2917987c74b2def361e303cde5383ed5b385',
      'assets/images/exercises/ab-wheel-rollout-thumb.jpg': 'fe969b15ca82e84408d4e3740053617de1f99d837941997f823e70314f55247a',
      'assets/images/exercises/barbell-back-squat-poster.jpg': 'c0e9e6412fa6e7150b98837c4d33a0e0ddf373747bb5bdc10466235aff8ff0ee',
      'assets/images/exercises/barbell-back-squat-thumb.jpg': '028731348e6586cfe5f12e7e45dfe3d3a8d70dddee0b6e771c03247d2536fbc6',
      'assets/images/exercises/barbell-hip-thrust-poster.jpg': '881c1af68dc583c2f3ef5db284720cb6e31cd3705a5a2c55687dedf140658503',
      'assets/images/exercises/barbell-hip-thrust-thumb.jpg': '5b386ee7ed3f8ae92286ead035adc73f98c86199fb930f4f94682fdf57f9ac97',
      'assets/images/exercises/cable-woodchopper-poster.jpg': '74307568e0388c51c1e4d0b9d2f8499ce64e88eb90d066fce524e7fa68358c0b',
      'assets/images/exercises/cable-woodchopper-thumb.jpg': '78d904a25730bc40fce2b40aa6799ed7d0ae2ed0e83917f0d8f17de2aa07ad93',
      'assets/images/exercises/dead-bug-poster.jpg': 'c544d2178b4f90126b60496e601947608d6e1b4573fbb33bd27b954dc21d96ba',
      'assets/images/exercises/dead-bug-thumb.jpg': 'b6ddecdf9d671e26e43e5b0c65fbe4650b62a9ac3e00504a2535d5792baa00c2',
      'assets/images/exercises/dumbbell-bench-press-poster.jpg': '9bd8b51397494d8ce939acb472714d12be8a9fafed84027f70704766e257e7d3',
      'assets/images/exercises/dumbbell-bench-press-thumb.jpg': '5e73e77c59250bdb9fc2d78ec49c474360eedd164e8e05b249f508f96f782a66',
      'assets/images/exercises/dumbbell-bicep-curl-poster.jpg': '4522637538339c03424fa880466f15ce64f5308493cb61c338dc52a55cd127cb',
      'assets/images/exercises/dumbbell-bicep-curl-thumb.jpg': '2fe06ea3cc689894eea46c1ddee93d54e55b1ebda24858b1bd1c03d7bf6bae8d',
      'assets/images/exercises/dumbbell-lateral-raise-poster.jpg': '5ee09b8fea8c717862da6b8a3da4d066a9391a3be17d734eae6179c9aacb67e2',
      'assets/images/exercises/dumbbell-lateral-raise-thumb.jpg': 'e4cf01fa06615ac44208e7b3e773eb25fa406f635747631206eb460031e97ddc',
      'assets/images/exercises/dumbbell-shoulder-press-poster.jpg': '6cffd4a5db20a3ab4150ca076e7d12669937f67bae00813d9ae0c9d04e343906',
      'assets/images/exercises/dumbbell-shoulder-press-thumb.jpg': 'd94e218e5f8d7c804ffb4049311d42df2ba9b04575c32d53eaad956408374996',
      'assets/images/exercises/face-pulls-poster.jpg': '0818c593ccbb2ad876573d49f1a84e2ee9bbd50b2af8a3b7ebcd1e5bce5fa2b6',
      'assets/images/exercises/face-pulls-thumb.jpg': 'a25634bdd8b64faedac67f47e34e1622ef90dc42f43f9ce6407800da10f39a85',
      'assets/images/exercises/goblet-squat-poster.jpg': '484b8402c31bc46a46178d4df89590d4599f4db11fa6c8f6065279daf90c8bb9',
      'assets/images/exercises/goblet-squat-thumb.jpg': '645df7b51afd82d82454ef0270fc001a04e5b867337364ec77e00bc9b6aad78e',
      'assets/images/exercises/hammer-curl-poster.jpg': '3f2cfbd2a46dc31049a5cd9cb11913da2aacb281509cb5cf098bb540dbb67dc7',
      'assets/images/exercises/hammer-curl-thumb.jpg': '5cf44dd6c80da694fb886df8131e54003f94971919c38ee13d14103184c6428d',
      'assets/images/exercises/hanging-leg-raise-poster.jpg': '926e687a3ccab86f66f5af80dfad587196fbdf5dac327a6762ee9f51812ff3f7',
      'assets/images/exercises/hanging-leg-raise-thumb.jpg': 'eb0ba1876cde2ff49b4209240213d8b5a9d8898c462c439df1a8b43d16bb5f24',
      'assets/images/exercises/incline-dumbbell-flyes-poster.jpg': '54a435ed56e18e3ec431d939f300beda88dfaf046a18bc0583c45b87c490fe12',
      'assets/images/exercises/incline-dumbbell-flyes-thumb.jpg': 'f357140d241a8e35068a04464976bef94db25507e9fa84f886903b2b3a8a74f3',
      'assets/images/exercises/incline-dumbbell-press-poster.jpg': '48a5932619ba7df33493f327da701975d594215ab1bfbea4bb0763dcab94ef4b',
      'assets/images/exercises/incline-dumbbell-press-thumb.jpg': '5db64a955501410fad4ff0ca57b4b4aea5a3212b0ce3b51c7e8831e6caa7efe4',
      'assets/images/exercises/lat-pulldown-poster.jpg': 'de5c55452542979c95719a5b2b02c9f25cb9f0524e8a2cf7b1eb4120f005bd8d',
      'assets/images/exercises/lat-pulldown-thumb.jpg': 'b3f27c76bfe5312d1745dca22c0ba39cb0dd55f6271d0a6621a5fa0a4bc926de',
      'assets/images/exercises/leg-press-poster.jpg': '032c1eb7177cb88fe201847e12dbdac9f13ade221228bfb002088444c69534a6',
      'assets/images/exercises/leg-press-thumb.jpg': 'bf4f50e62495384d216edac87240fe70dcdf1ca1a43ff58952a188b47d19600a',
      'assets/images/exercises/lying-leg-curl-poster.jpg': '73390198b564fa03e5d4fd0c764b5d545610b7ce97acb3e72a5b1f0663b52c40',
      'assets/images/exercises/lying-leg-curl-thumb.jpg': '630a43ee4c6d92a68b7c04a5de7a735c234b3cbcdf70b68378777319c36eab09',
      'assets/images/exercises/one-arm-dumbbell-row-poster.jpg': 'dfad75c491f60732948735c7c442e6ec73e3d7e1e4d5d62103d64abfbfb393f1',
      'assets/images/exercises/one-arm-dumbbell-row-thumb.jpg': '3697ae296cad474cdb25f19fdcd336e0063da8dfc4f3c73dc20f2fb5b67249a5',
      'assets/images/exercises/overhead-triceps-extension-poster.jpg': '4f0fb27d4e5699fff3381e8bd5738fec86efc5d3bb06c270c211b3e99c8f9bb3',
      'assets/images/exercises/overhead-triceps-extension-thumb.jpg': '5b236b58f1b4f1b39bea34244c2288fa05fc2512d41e16b2f808ae45a6b84a98',
      'assets/images/exercises/plank-poster.jpg': '828bcafe5eb078049194d8cfe316ff2ab65566b604daa9344224092dd15017a7',
      'assets/images/exercises/plank-thumb.jpg': 'de2ace93816d3ad2cd54a6074fda1e3fc6e10eb170518dda574b1ab0237237ca',
      'assets/images/exercises/push-up-poster.jpg': '8c158599090240cb9ff74d6dcfcf93f5e5227a099a54268ae6444dd94339265e',
      'assets/images/exercises/push-up-thumb.jpg': '0d946304254fb33f3908dd757625fa02b28c35a3abe08977de4392feb42a44f9',
      'assets/images/exercises/reverse-lunge-poster.jpg': 'fd81d4e88fffbde745a2d07ce69262165686ee338b30c6eaa489f8d8b7ae54f8',
      'assets/images/exercises/reverse-lunge-thumb.jpg': 'ee2a40cc4c11beb20f7a2f9c88bfca855e155b3a41caf50341664ce372c3e541',
      'assets/images/exercises/romanian-deadlift-poster.jpg': '665d1be7dfdaee5316b05aa63a02a83eb5b0eae718021ece2b8dbf3478b1bb43',
      'assets/images/exercises/romanian-deadlift-thumb.jpg': '79583adc211b3d6cb9c43278f34b3fe717989b4d287b273781f311f010a3bbf9',
      'assets/images/exercises/seated-cable-row-poster.jpg': '7281959ce9b9ce0651496f359c1b236ca5d0ee4d9357821f7b6a0925992a6c3f',
      'assets/images/exercises/seated-cable-row-thumb.jpg': 'c7bfb3f011ebeb1a1412a6057df66bc8244e3887dc65afa856bc6fe3725e994c',
      'assets/images/exercises/standing-calf-raise-poster.jpg': 'f7c87c1252621d68c93dc38f5ca2991f455f57658da8d41044c23c3baf42954f',
      'assets/images/exercises/standing-calf-raise-thumb.jpg': '5538122dd5077b5c94d7423ab47a6fea826dbee201cc8f77b2ad8120d8cb888b',
      'assets/images/exercises/triceps-rope-pushdown-poster.jpg': 'e8eb6d0cfb16928f7baac1a2e9d940548d40c5d674df494a38fdca0daf3ac509',
      'assets/images/exercises/triceps-rope-pushdown-thumb.jpg': '437e62a666e978fd82a01246f3a980549a0f83eab3f50ac899a1a4528aef5d9e',
    };
    expect(expectedHashes, hasLength(54));
    for (final entry in expectedHashes.entries) {
      expect(sha256.convert(File(entry.key).readAsBytesSync()).toString(),
          entry.value, reason: entry.key);
    }
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
          [exercise.thumbnailUrl,
            if (id == 'plank') 'assets/images/exercises/side-plank-thumb.jpg']);
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
      final isBodyweight = ['reverse-lunge', 'dead-bug', 'pull-up', 'reverse-crunch'].contains(id);
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
      if (exercise.repType == 'seconds') {
        expect(logged.sets.first.unit, SetUnit.seconds);
        expect(logged.sets.first.seconds,
            int.parse(exercise.defaultReps.split('-').first));
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
      // 35 decoded posters exceed the default image cache. Await real I/O
      // when switching to a poster that precacheImage may have evicted.
      await loadImages(tester, [exercisePosterSource(
          container.read(activeWorkoutSessionProvider).currentExercise!.imageUrl)]);
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

  testWidgets('Round two contact sheet places eight pairs beside three approved reference pairs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = [
      for (final id in ['db-shoulder-press', 'push-up', 'db-bicep-curl', ...expectedRoundTwoExercises.keys])
        curatedExerciseLibrary.singleWhere((e) => e.id == id),
    ];
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: RepaintBoundary(
        key: const ValueKey('image_evidence_boundary'),
        child: Scaffold(
          appBar: AppBar(title: const Text('3 approved reference pairs + 8 new pairs | 68px / 80px + poster | Developer review pending')),
          body: GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisExtent: 400,
              mainAxisSpacing: 8, crossAxisSpacing: 16,
            ),
            itemCount: selected.length,
            itemBuilder: (_, index) {
              final e = selected[index];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${index < 3 ? "REFERENCE" : "NEW"} | ${e.name}', style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 12),
                Row(children: [
                  ExerciseThumbnail(source: e.thumbnailUrl, width: 68, height: 68),
                  const SizedBox(width: 16),
                  ExerciseThumbnail(source: e.thumbnailUrl, width: 80, height: 80),
                  const SizedBox(width: 16),
                  const Text('68 x 68\n80 x 80'),
                ]),
                const SizedBox(height: 12),
                AspectRatio(aspectRatio: 16 / 9, child: ExerciseThumbnail(
                  source: exercisePosterSource(e.thumbnailUrl), fit: BoxFit.contain,
                )),
              ]);
            },
          ),
        ),
      ),
    ));
    await loadImages(tester, selected.expand((e) => [e.thumbnailUrl, exercisePosterSource(e.thumbnailUrl)]));
    expect(find.byType(ExerciseThumbnail), findsNWidgets(33));
    expect(find.byIcon(Icons.fitness_center_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await capture(tester, 'contact-round-two-with-references', pixelRatio: 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Flutter contact sheets show 68/80 crops and landscape posters',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final groups = [
      curatedExerciseLibrary.take(9).map((e) => (e.name, e.thumbnailUrl)).toList(),
      curatedExerciseLibrary.skip(9).take(8).map((e) => (e.name, e.thumbnailUrl)).toList(),
      curatedExerciseLibrary.skip(20).take(7).map((e) => (e.name, e.thumbnailUrl)).toList(),
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

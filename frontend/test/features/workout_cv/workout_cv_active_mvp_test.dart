import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_native_source.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;
import 'workout_cv_rep_replay_test.dart' show cycle, pose;

// Geometric landmarks are test input, never a camera/replay demo or accuracy proof.
Map<String, dynamic> cameraPose(int time, double angle, {int gen = 5}) => {
      ...pose(time, angle, gen: gen),
      'sourceMode': 'camera',
      'timestamp': time,
      // Conflicting replay metadata must not drive live analysis time.
      'videoPtsMs': 0,
      'previewPtsMs': 0,
    };

const latPulldown = Exercise(
  id: 'lat-pulldown',
  slug: 'lat-pulldown',
  name: 'Lat Pulldown',
  nameVi: 'Kéo xô',
  muscleGroup: 'Back',
  targetMuscles: ['Lats'],
  secondaryMuscles: ['Biceps'],
  equipment: ['Cable Machine'],
  difficulty: 'intermediate',
  thumbnailUrl: '',
  defaultSets: 3,
  defaultReps: '10-12',
  restSeconds: 90,
  repType: 'reps',
  cvSupported: false,
  cues: [],
  commonMistakes: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Active Lat pulldown live analysis', () {
    late MockWorkoutCvNativeSource source;
    late WorkoutCvNotifier controller;

    Future<void> send(Map<String, dynamic> event) async {
      source.emitEvent(event);
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> runCycle({int offset = 0, int gen = 5}) async {
      for (final (time, angle) in cycle) {
        await send(cameraPose(time + offset, angle, gen: gen));
      }
    }

    setUp(() async {
      source = MockWorkoutCvNativeSource();
      controller = WorkoutCvNotifier(source);
      await controller.initialize(
          exerciseId: 'lat-pulldown', exerciseSlug: 'lat-pulldown');
    });
    tearDown(() {
      controller.dispose();
      source.dispose();
    });

    test('live landmarks use capture time and existing baseline phases', () async {
      final phases = <LatPulldownPhase>{};
      for (final (time, angle) in cycle) {
        await send(cameraPose(time, angle));
        phases.add(controller.state.analysisPhase);
      }
      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.replayRepEvents.single.durationMs, 900);
      expect(controller.state.replayRepEvents.single.status, 'PROVISIONAL');
      await runCycle(); // Duplicate capture times cannot add a rep.
      expect(controller.state.completedReps, 1);
    });

    test('long invalid gap discards partial cycle and retains completed rep',
        () async {
      await runCycle();
      for (final (time, angle) in cycle.take(6)) {
        await send(cameraPose(time + 1300, angle));
      }
      await send({
        ...cameraPose(2500, 40),
        'status': 'lost',
        'numPoses': 0,
        'landmarks': [],
      });
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.completedReps, 1);
      for (final (time, angle) in cycle.skip(6)) {
        await send(cameraPose(time + 2600, angle));
      }
      expect(controller.state.completedReps, 1);
      await runCycle(offset: 3900);
      expect(controller.state.completedReps, 2);
    });

    test('dimensions, visibility and multiple-person gates reject invalid reps',
        () async {
      var generation = 5;
      for (final defect in ['dimensions', 'visibility', 'multiplePeople']) {
        await controller.initialize(
            exerciseId: 'lat-pulldown', exerciseSlug: 'lat-pulldown');
        for (final (time, angle) in cycle) {
          final event = cameraPose(time, angle, gen: generation);
          if (defect == 'dimensions') event.remove('inputImageWidth');
          if (defect == 'visibility') {
            (event['landmarks'] as List)[15]['visibility'] = 0.1;
          }
          if (defect == 'multiplePeople') event['numPoses'] = 2;
          await send(event);
        }
        expect(controller.state.completedReps, 0, reason: defect);
        expect(controller.state.replayAnalysisStatus,
            ReplayAnalysisStatus.insufficientData, reason: defect);
        generation++;
      }
    });

    test('source, exercise and native generation changes reset rep/phase state',
        () async {
      await runCycle();
      await controller.startVideoReplay();
      expect(controller.state.completedReps, 0);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      for (final (time, angle) in cycle) {
        await send(pose(time, angle, gen: 6));
      }
      expect(controller.state.completedReps, 1);
      await controller.switchToCamera();
      expect(controller.state.completedReps, 0);
      await runCycle(gen: 7);
      expect(controller.state.completedReps, 1);
      await send(cameraPose(20, 120, gen: 8));
      expect(controller.state.completedReps, 0);
      await runCycle(offset: 100, gen: 8);
      expect(controller.state.completedReps, 1);
      await controller.initialize(
          exerciseId: 'bench-press', exerciseSlug: 'bench-press');
      await runCycle(gen: 9);
      expect(controller.state.completedReps, 0);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
    });
  });

  testWidgets('production bridge makes no native calls outside Android',
      (tester) async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    const method = MethodChannel('com.example.health_ai_app/workout_cv/method');
    const events = MethodChannel('com.example.health_ai_app/workout_cv/events');
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    for (final platform in TargetPlatform.values) {
      if (!kIsWeb && platform == TargetPlatform.android) continue;
      debugDefaultTargetPlatformOverride = platform;
      final source = WorkoutCvNativeSource();
      expect(await source.checkPermission(), 'unsupported');
      expect(await source.requestPermission(), isFalse);
      expect(await source.startSession('lat-pulldown'), isFalse);
      expect(await source.startVideoReplay('unused.mp4'), isFalse);
      expect(await source.switchSource('camera'), isFalse);
      expect(await source.restartVideoReplay(), isFalse);
      expect(await source.acknowledgeReplayFrame(1, 20, 'pose'), isFalse);
      expect(await source.stopSession(), isFalse);
      expect(await source.eventStream.toList(), isEmpty);
    }
    expect(calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Lat pulldown platform entry leaves workout session intact',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final source = MockWorkoutCvNativeSource();
    final container = ProviderContainer(overrides: [
      workoutCvNativeSourceProvider.overrideWithValue(source),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ActiveWorkoutScreen(exercises: [latPulldown], autoTick: false),
      ),
    ));
    await tester.pumpAndSettle();
    final before = container.read(activeWorkoutSessionProvider);
    await tester.tap(
        find.byKey(const ValueKey('active_workout_form_check_badge')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Web/iOS chưa có replay'), findsOneWidget);
    expect(find.byType(WorkoutCvScreen), findsNothing);
    expect(source.startSessionCalled, isFalse);
    expect(source.startVideoReplayCalled, isFalse);
    expect(identical(before, container.read(activeWorkoutSessionProvider)), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    source.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('live CV reps render without mutating manual workout session',
      (tester) async {
    final source = MockWorkoutCvNativeSource();
    final container = ProviderContainer(overrides: [
      workoutCvNativeSourceProvider.overrideWithValue(source),
    ]);
    container.read(activeWorkoutSessionProvider.notifier).startSession([latPulldown]);
    final before = container.read(activeWorkoutSessionProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WorkoutCvScreen(
        exerciseId: 'lat-pulldown',
        exerciseSlug: 'lat-pulldown',
        exerciseName: 'Lat Pulldown',
      )),
    ));
    await tester.pumpAndSettle();
    // Drive the Dart integration with test landmarks; this does not run Android.
    await container.read(workoutCvControllerProvider.notifier).initialize(
        exerciseId: 'lat-pulldown', exerciseSlug: 'lat-pulldown');
    for (final (time, angle) in cycle) {
      source.emitEvent(cameraPose(time, angle));
      await tester.idle();
      await tester.pump();
    }
    expect(find.text('Số lần kéo: 1'), findsOneWidget);
    expect(find.textContaining('Pha: extended'), findsOneWidget);
    expect(find.textContaining('Baseline quy tắc'), findsOneWidget);
    expect(identical(before, container.read(activeWorkoutSessionProvider)), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    source.dispose();
  });
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

// A geometric cycle through the existing default bands, with no injected tracker.
const cycle = <(int, double)>[
  (20, 120),
  (120, 120),
  (220, 120),
  (320, 80),
  (420, 40),
  (520, 40),
  (620, 40),
  (720, 40),
  (820, 40),
  (920, 80),
  (1020, 120),
  (1120, 120),
  (1220, 120),
];

Map<String, dynamic> pose(int pts, double angle, {int gen = 5}) {
  final radians = angle * math.pi / 180;
  final landmarks = List.generate(
      33,
      (i) => <String, dynamic>{
            'index': i,
            'x': 0.5,
            'y': 0.7,
            'z': 0.0,
            'visibility': 0.95,
          });
  landmarks[11].addAll({'x': 0.5, 'y': 0.35});
  landmarks[12].addAll({'x': 0.65, 'y': 0.35});
  landmarks[13].addAll({'x': 0.5, 'y': 0.5});
  landmarks[15].addAll({
    'x': 0.5 + math.sin(radians) * 200 / 1080,
    'y': 0.5 - math.cos(radians) * 200 / 1920,
  });
  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'video_replay',
    'videoPtsMs': pts,
    'previewPtsMs': pts,
    'ptsSkewMs': 0,
    'timestamp': 9000000 + pts * 20,
    'latencyMs': 900,
    'isPtsVerified': true,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': 1080,
    'inputImageHeight': 1920,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockWorkoutCvNativeSource source;
  late WorkoutCvNotifier controller;

  Future<void> send(Map<String, dynamic> event) async {
    source.emitEvent(event);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> runCycle({int offset = 0, int gen = 5}) async {
    for (final (pts, angle) in cycle) {
      await send(pose(pts + offset, angle, gen: gen));
    }
  }

  setUp(() async {
    source = MockWorkoutCvNativeSource();
    controller = WorkoutCvNotifier(source);
    await controller.initialize(
        exerciseId: 'lat-pulldown', exerciseSlug: 'lat-pulldown');
    await controller.startVideoReplay();
  });
  tearDown(() {
    controller.dispose();
    source.dispose();
  });

  test('replay entry initializes exercise context without starting live camera',
      () async {
    final replaySource = MockWorkoutCvNativeSource();
    final replayController = WorkoutCvNotifier(replaySource);
    await replayController.initialize(
      exerciseId: 'lat-pulldown',
      exerciseSlug: 'lat-pulldown',
      videoReplay: true,
    );
    expect(replaySource.startSessionCalled, isFalse);
    expect(replaySource.startVideoReplayCalled, isTrue);
    expect(replayController.state.sourceMode, 'video_replay');
    expect(replayController.state.exerciseSlug, 'lat-pulldown');
    expect(replayController.state.completedReps, 0);
    replayController.dispose();
    replaySource.dispose();
  });

  test(
      'counts each generation/PTS once and uses video time, not inference delay',
      () async {
    for (final (pts, angle) in cycle) {
      await send(pose(pts, angle));
      await send(pose(pts, angle));
    }
    await runCycle(); // Reordered/duplicate delivery cannot start another cycle.
    expect(controller.state.completedReps, 1);
    final rep = controller.state.replayRepEvents.single;
    expect(rep.startTimestampMs, 320);
    expect(rep.endTimestampMs, 1220);
    expect(rep.durationMs, 900);
  });

  testWidgets('clear overlay and progress never invalidate a genuine cycle',
      (tester) async {
    for (final (pts, angle) in cycle) {
      source.emitEvent({
        'status': 'replayPreparing',
        'sessionGen': 5,
        'nextVideoPtsMs': pts
      });
      await tester.idle();
      expect(controller.state.landmarks, isEmpty);
      source.emitEvent(
          {'status': 'previewProgress', 'sessionGen': 5, 'videoPtsMs': pts});
      source.emitEvent(pose(pts, angle));
      await tester.pump();
    }
    expect(controller.state.completedReps, 1);
    expect(source.replayAcknowledgements.length, cycle.length);
  });

  test('real tracking loss aborts an incomplete cycle immediately', () async {
    for (final (pts, angle) in cycle) {
      await send(pts == 520
          ? {
              ...pose(pts, angle),
              'status': 'lost',
              'numPoses': 0,
              'landmarks': []
            }
          : pose(pts, angle));
    }
    expect(controller.state.completedReps, 0);
    await runCycle(offset: 1300);
    expect(controller.state.completedReps, 1);
  });

  test('valid samples separated by a video gap cannot form a rep', () async {
    for (final (pts, angle) in cycle) {
      if (pts >= 520 && pts <= 820) continue;
      await send(pose(pts >= 920 ? pts + 100 : pts, angle));
    }
    expect(controller.state.completedReps, 0);
  });

  test(
      'short invalid measurement interrupts return hold; long invalid gap aborts',
      () async {
    for (final (pts, angle) in cycle) {
      final event = pose(pts, angle);
      if (pts == 1120) (event['landmarks'] as List)[15]['visibility'] = 0.1;
      await send(event);
    }
    expect(controller.state.completedReps,
        0); // Cannot bridge the invalid hold sample.
    await send(pose(1320, 120));
    await send(pose(1420, 120));
    expect(controller.state.completedReps, 1);
    for (final (pts, angle) in cycle) {
      final event = pose(pts + 1500, angle);
      if (pts >= 520) (event['landmarks'] as List)[15]['visibility'] = 0.1;
      await send(event);
    }
    expect(controller.state.replayAnalysisStatus,
        ReplayAnalysisStatus.insufficientData);
    await send(pose(2820, 120));
    await send(pose(2920, 120));
    await send(pose(3020, 120));
    expect(controller.state.completedReps, 1);
  });

  test(
      'EOF retains completed reps, discards partial rep, and rejects late callbacks',
      () async {
    await runCycle();
    for (final (pts, angle) in cycle.take(6)) {
      await send(pose(pts + 1300, angle));
    }
    await send({'status': 'endOfStream', 'sessionGen': 5, 'videoPtsMs': 1820});
    final finished = controller.state;
    expect(finished.completedReps, 1);
    expect(finished.landmarks, isEmpty);
    expect(finished.replayAnalysisStatus, ReplayAnalysisStatus.finished);
    expect(finished.trackingStatus, isNot(TrackingStatus.detecting));
    await runCycle(offset: 2600);
    await send(
        {'status': 'replayPreparing', 'sessionGen': 5, 'nextVideoPtsMs': 5000});
    await send(pose(5100, 120, gen: 4));
    await send(pose(5200, 120));
    source.emitError(StateError('late stream error after EOF'));
    await Future<void>.delayed(Duration.zero);
    expect(identical(controller.state, finished), isTrue);
  });

  test('restart and clip change reset count without relying on frameCount',
      () async {
    await runCycle();
    await controller.restartVideoReplay();
    expect(controller.state.completedReps, 0);
    expect(controller.state.replayAnalysisStatus, ReplayAnalysisStatus.waiting);
    await send(pose(1320, 120)); // Old generation after restart.
    expect(controller.state.completedReps, 0);
    await runCycle(gen: 6);
    expect(controller.state.completedReps, 1);
    await controller.startVideoReplay(videoPath: '/test/another.mp4');
    expect(controller.state.completedReps, 0);
    await runCycle(gen: 7);
    expect(controller.state.completedReps, 1);
    await controller.restartVideoReplay();
    expect(source.lastVideoPath, '/test/another.mp4');
    expect(controller.state.completedReps, 0);
  });

  test('new generation resets features even when frameCount is nonzero',
      () async {
    await runCycle();
    final count = controller.state.frameCount;
    await send(pose(20, 40, gen: 6));
    expect(controller.state.frameCount, greaterThan(count));
    expect(controller.state.completedReps, 0);
    await runCycle(offset: 100, gen: 6);
    expect(controller.state.completedReps, 1);
  });

  test('missing dimensions and unverified pose report insufficient data',
      () async {
    await send(pose(20, 120)..remove('inputImageWidth'));
    expect(controller.state.replayAnalysisStatus,
        ReplayAnalysisStatus.insufficientData);
    await send({...pose(120, 120), 'isPtsVerified': false});
    expect(controller.state.completedReps, 0);
    expect(controller.state.replayAnalysisStatus,
        ReplayAnalysisStatus.insufficientData);
  });

  test('error and stop retain count and block subsequent results', () async {
    await runCycle();
    await send({
      'status': 'error',
      'sessionGen': 5,
      'videoPtsMs': 1320,
      'errorMessage': 'decode failed'
    });
    await runCycle(offset: 1400);
    expect(controller.state.completedReps, 1);
    expect(controller.state.replayAnalysisStatus, ReplayAnalysisStatus.error);
    expect(controller.state.landmarks, isEmpty);
    await controller.restartVideoReplay();
    await runCycle(gen: 6);
    await controller.stop();
    await runCycle(offset: 1300, gen: 6);
    expect(controller.state.completedReps, 1);
    expect(controller.state.landmarks, isEmpty);
  });

  testWidgets(
      'replay UI shows count, slow label, honest missing data, EOF and error',
      (tester) async {
    final container = ProviderContainer(overrides: [
      workoutCvNativeSourceProvider.overrideWithValue(source),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: WorkoutCvScreen(
        exerciseId: 'lat-pulldown',
        exerciseSlug: 'lat-pulldown',
        exerciseName: 'Lat Pulldown',
      )),
    ));
    await tester.pump();
    final uiController = container.read(workoutCvControllerProvider.notifier);
    await uiController.startVideoReplay();
    source.emitEvent(pose(20, 40));
    await tester.idle();
    await tester.pump();
    expect(find.text('Số lần kéo: 0'), findsOneWidget);
    expect(find.text('Replay thử nghiệm • phát chậm'), findsOneWidget);
    expect(find.text('Chưa đủ dữ liệu'), findsWidgets);
    for (final (pts, angle) in cycle) {
      source.emitEvent(pose(pts + 100, angle));
      await tester.idle();
      await tester.pump();
    }
    expect(find.text('Số lần kéo: 1'), findsOneWidget);
    source.emitEvent(
        {'status': 'endOfStream', 'sessionGen': 5, 'videoPtsMs': 1320});
    await tester.idle();
    await tester.pump();
    expect(find.text('Đã kết thúc'), findsWidgets);
    expect(find.text('TRACKING'), findsNothing);
    expect(find.text('Số lần kéo: 1'), findsOneWidget);
    await tester.tap(find.text('Chạy lại'));
    await tester.pump();
    expect(find.text('Số lần kéo: 0'), findsOneWidget);
    source.emitEvent({
      'status': 'error',
      'sessionGen': 6,
      'videoPtsMs': 0,
      'errorMessage': 'decode failed'
    });
    await tester.idle();
    await tester.pump();
    expect(find.text('Lỗi phân tích'), findsOneWidget);
    expect(find.text('decode failed'), findsOneWidget);
    expect(find.text('Số lần kéo: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

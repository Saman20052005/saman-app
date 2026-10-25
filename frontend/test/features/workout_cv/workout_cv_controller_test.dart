import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_native_source.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';

class MockWorkoutCvNativeSource implements WorkoutCvNativeSource {
  String permissionStatus = 'granted';
  bool requestPermissionResult = true;
  bool startSessionResult = true;
  bool startSessionCalled = false;
  bool startVideoReplayCalled = false;
  String? lastVideoPath;
  bool switchSourceCalled = false;
  String? lastSwitchMode;
  bool restartVideoReplayCalled = false;
  bool stopSessionCalled = false;
  final replayAcknowledgements = <List<Object>>[];
  bool replayAcknowledgementResult = true;

  @override
  Future<bool> acknowledgeReplayFrame(int sessionGen, int videoPtsMs, String phase) async {
    replayAcknowledgements.add([sessionGen, videoPtsMs, phase]);
    return replayAcknowledgementResult;
  }
  int stopSessionCallCount = 0;
  String? lastStartedSlug;
  Completer<bool>? pendingPermissionCompleter;
  Completer<bool>? pendingStartSessionCompleter;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<String> checkPermission() async => permissionStatus;

  @override
  Future<bool> requestPermission() async {
    if (pendingPermissionCompleter != null) {
      return pendingPermissionCompleter!.future;
    }
    return requestPermissionResult;
  }

  @override
  Future<bool> startSession(String exerciseSlug) async {
    startSessionCalled = true;
    lastStartedSlug = exerciseSlug;
    if (pendingStartSessionCompleter != null) {
      return pendingStartSessionCompleter!.future;
    }
    return startSessionResult;
  }

  @override
  Future<bool> startVideoReplay(String videoPath) async {
    startVideoReplayCalled = true;
    lastVideoPath = videoPath;
    return true;
  }

  @override
  Future<bool> switchSource(String mode, {String? videoPath}) async {
    switchSourceCalled = true;
    lastSwitchMode = mode;
    lastVideoPath = videoPath;
    return true;
  }

  @override
  Future<bool> restartVideoReplay() async {
    restartVideoReplayCalled = true;
    return true;
  }

  @override
  Future<bool> stopSession() async {
    stopSessionCalled = true;
    stopSessionCallCount++;
    return true;
  }

  @override
  Stream<Map<String, dynamic>> get eventStream => _controller.stream;

  void emitEvent(Map<String, dynamic> event) {
    _controller.add(event);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  testWidgets('paced replay clears before presentation and acknowledges poses after Flutter frame', (tester) async {
    final source = MockWorkoutCvNativeSource();
    final notifier = WorkoutCvNotifier(source);
    await notifier.startVideoReplay();
    source.emitEvent({'status': 'replayPreparing', 'sessionGen': 1, 'nextVideoPtsMs': 100});
    await tester.idle();
    expect(notifier.state.landmarks, isEmpty);
    expect(notifier.state.isSyncValid, isFalse);
    expect(source.replayAcknowledgements, isEmpty);
    await tester.pump();
    expect(source.replayAcknowledgements, [[1, 100, 'clear']]);

    source.emitEvent({
      'status': 'detecting', 'sessionGen': 1, 'sourceMode': 'video_replay',
      'videoPtsMs': 100, 'previewPtsMs': 100, 'ptsSkewMs': 0,
      'isPtsVerified': true, 'requiresReplayAck': true, 'latencyMs': 450,
      'numPoses': 1,
      'landmarks': List.generate(33, (i) => {'index': i, 'x': 0.5, 'y': 0.5, 'z': 0.0, 'visibility': 0.95}),
    });
    await tester.idle();
    expect(notifier.state.isSyncValid, isTrue);
    expect(notifier.state.latencyMs, 450); // Processing delay is not video PTS skew.
    expect(source.replayAcknowledgements.length, 1);
    await tester.pump();
    expect(source.replayAcknowledgements.last, [1, 100, 'pose']);

    source.emitEvent({'status': 'replayPreparing', 'sessionGen': 1, 'nextVideoPtsMs': 200});
    await tester.idle();
    expect(notifier.state.landmarks, isEmpty);
    expect(notifier.state.isSyncValid, isFalse);
    await notifier.restartVideoReplay();
    await tester.pump();
    expect(source.replayAcknowledgements.length, 2); // Old operation cannot unblock new decoder.
    notifier.dispose();
    source.dispose();
  });

  testWidgets('stopping replay rejects a pending frame acknowledgement', (tester) async {
    final source = MockWorkoutCvNativeSource();
    final notifier = WorkoutCvNotifier(source);
    await notifier.startVideoReplay();
    source.emitEvent({'status': 'replayPreparing', 'sessionGen': 3, 'nextVideoPtsMs': 100});
    await tester.idle();
    await notifier.stop();
    await tester.pump();
    expect(source.replayAcknowledgements, isEmpty);
    notifier.dispose();
    source.dispose();
  });

  testWidgets('failed replay acknowledgement exposes an error and hides pose', (tester) async {
    final source = MockWorkoutCvNativeSource()..replayAcknowledgementResult = false;
    final notifier = WorkoutCvNotifier(source);
    await notifier.startVideoReplay();
    source.emitEvent({'status': 'replayPreparing', 'sessionGen': 1, 'nextVideoPtsMs': 100});
    await tester.idle();
    await tester.pump();
    await tester.idle();
    expect(notifier.state.trackingStatus, TrackingStatus.error);
    expect(notifier.state.errorMessage, contains('acknowledgement failed'));
    expect(notifier.state.landmarks, isEmpty);
    notifier.dispose();
    source.dispose();
  });

  group('WorkoutCvNotifier Quality Gates and Telemetry Tests', () {
    late MockWorkoutCvNativeSource mockSource;
    late WorkoutCvNotifier controller;
    late bool controllerDisposed;

    setUp(() {
      mockSource = MockWorkoutCvNativeSource();
      controller = WorkoutCvNotifier(mockSource);
      controllerDisposed = false;
    });

    tearDown(() {
      if (!controllerDisposed) {
        controller.dispose();
      }
      mockSource.dispose();
    });

    test(
        '1. Initial state is uninitialized with empty landmarks and zero latency',
        () {
      expect(controller.state.trackingStatus, TrackingStatus.uninitialized);
      expect(controller.state.landmarks, isEmpty);
      expect(controller.state.latencyMs, 0);
      expect(controller.state.posesDetected, 0);
    });

    test(
        '2. Permission denied transitions to permissionDenied state without crashing',
        () async {
      mockSource.permissionStatus = 'denied';
      mockSource.requestPermissionResult = false;

      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      expect(controller.state.trackingStatus, TrackingStatus.permissionDenied);
      expect(controller.state.isCameraActive, isFalse);
      expect(mockSource.startSessionCalled, isFalse);
    });

    test('3. Permission granted starts session and listens to event stream',
        () async {
      mockSource.permissionStatus = 'granted';

      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      expect(mockSource.startSessionCalled, isTrue);
      expect(mockSource.lastStartedSlug, 'pull-up');
      expect(controller.state.isCameraActive, isTrue);
      expect(controller.state.trackingStatus, TrackingStatus.needsSetup);
    });

    test(
        '4. Multiple people event triggers multiplePeople gating and clears landmarks',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      mockSource.emitEvent({
        'status': 'multiplePeople',
        'timestamp': 1000,
        'latencyMs': 24,
        'numPoses': 2,
        'landmarks': [],
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.multiplePeople);
      expect(controller.state.posesDetected, 2);
      expect(controller.state.landmarks, isEmpty);
      expect(controller.state.guideMessage, contains('Multiple people'));
    });

    test('5. Target lost event triggers lost status and clears old landmarks',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      mockSource.emitEvent({
        'status': 'lost',
        'timestamp': 2000,
        'latencyMs': 18,
        'numPoses': 0,
        'landmarks': [],
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.lost);
      expect(controller.state.posesDetected, 0);
      expect(controller.state.landmarks, isEmpty);
      expect(controller.state.guideMessage, contains('No person detected'));
    });

    test(
        '6. Incomplete upper body joints (missing shoulders) triggers needsSetup',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      // 33 landmarks with low shoulder visibility (0.1)
      final dummyLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.1, // Not confident
        },
      );

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 3000,
        'latencyMs': 22,
        'numPoses': 1,
        'landmarks': dummyLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.needsSetup);
      expect(controller.state.guideMessage, contains('Align upper body'));
    });

    test(
        '7. Confident upper body landmarks trigger detecting with accurate telemetry',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      final confidentLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': 0.3,
          'z': 0.0,
          'visibility': 0.95, // Highly confident
        },
      );

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 4000,
        'latencyMs': 28,
        'numPoses': 1,
        'landmarks': confidentLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.detecting);
      expect(controller.state.posesDetected, 1);
      expect(controller.state.landmarks.length, 33);
      expect(controller.state.latencyMs, 28);
      expect(controller.state.guideMessage, contains('Tracking active'));
    });

    test('8. Latency history correctly calculates p50 and p95 medians',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      // Emit 10 latency measurements: 10, 20, 30, ... 100
      for (int i = 1; i <= 10; i++) {
        mockSource.emitEvent({
          'status': 'lost',
          'timestamp': 1000 + i * 50,
          'latencyMs': i * 10,
          'numPoses': 0,
          'landmarks': [],
        });
      }

      await pumpEventQueue();

      expect(controller.state.latencyHistoryMs.length, 10);
      expect(controller.state.p50LatencyMs, 60);
      expect(controller.state.p95LatencyMs, 100);
    });

    test('9. Stopping controller unsubscribes and calls native stopSession',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');
      await controller.stop();

      expect(mockSource.stopSessionCalled, isTrue);
      expect(controller.state.isCameraActive, isFalse);

      // Subsequent events after stop should be ignored
      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 5000,
        'latencyMs': 20,
        'numPoses': 1,
        'landmarks': [],
      });

      await pumpEventQueue();
      expect(controller.state.trackingStatus, TrackingStatus.uninitialized);
    });

    test(
        '10. Required joints outside image boundaries with high visibility trigger needsSetup',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      // 33 landmarks with high visibility (0.95), but both elbows and hips out of bounds
      final outOfBoundsLandmarks = List.generate(
        33,
        (i) {
          double x = 0.5;
          double y = 0.5;
          if (i == 13) x = 1.25; // Left elbow outside image (x > 1.0)
          if (i == 14) x = -0.15; // Right elbow outside image (x < 0.0)
          if (i == 23 || i == 24) y = 1.10; // Hips outside image (y > 1.0)
          return {
            'index': i,
            'x': x,
            'y': y,
            'z': 0.0,
            'visibility':
                0.95, // High confidence should NOT bypass boundary check
          };
        },
      );

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 6000,
        'latencyMs': 25,
        'numPoses': 1,
        'landmarks': outOfBoundsLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.needsSetup);
      expect(controller.state.guideMessage, contains('Align upper body'));
    });

    test(
        '11. Required joints with NaN or Infinity coordinates trigger needsSetup without crashing',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      // Case A: NaN in shoulder coordinate
      final nanLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': i == 11 ? double.nan : 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.95,
        },
      );

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 7000,
        'latencyMs': 22,
        'numPoses': 1,
        'landmarks': nanLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.needsSetup);
      expect(controller.state.guideMessage, contains('Align upper body'));

      // Case B: Infinity in elbow/hip coordinate
      final infLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': (i == 13 || i == 14 || i == 23 || i == 24)
              ? double.infinity
              : 0.5,
          'z': 0.0,
          'visibility': 0.95,
        },
      );

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 7050,
        'latencyMs': 22,
        'numPoses': 1,
        'landmarks': infLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.needsSetup);
    });

    test('12. Valid and fully in-bounds frame passes gate to detecting status',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      final validLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.90,
        },
      );

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 8000,
        'latencyMs': 20,
        'numPoses': 1,
        'landmarks': validLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.detecting);
      expect(controller.state.guideMessage, contains('Tracking active'));
      expect(controller.state.landmarks.length, 33);
    });

    test(
        '13. Channel or native startSession failure transitions to error state without faking active camera',
        () async {
      mockSource.permissionStatus = 'granted';
      mockSource.startSessionResult = false;

      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      expect(mockSource.startSessionCalled, isTrue);
      expect(controller.state.trackingStatus, TrackingStatus.error);
      expect(controller.state.isCameraActive, isFalse);
      expect(controller.state.errorMessage, isNotNull);
      expect(controller.state.guideMessage,
          contains('Unable to start camera session'));
    });

    test(
        '14. Native error event and stream onError transition to error state and clear landmarks',
        () async {
      await controller.initialize(
          exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      mockSource.emitEvent({
        'status': 'error',
        'timestamp': 8500,
        'latencyMs': 0,
        'numPoses': 0,
        'landmarks': [],
        'errorMessage': 'Camera device disconnected',
      });
      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.error);
      expect(controller.state.errorMessage, 'Camera device disconnected');
      expect(controller.state.landmarks, isEmpty);

      mockSource.emitError('EventChannel broken');
      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.error);
      expect(controller.state.errorMessage, contains('EventChannel broken'));
    });

    test(
        '15. Dispose and stop during pending async init ignore late completions and late events',
        () async {
      mockSource.permissionStatus = 'denied';
      mockSource.pendingPermissionCompleter = Completer<bool>();

      final initFuture =
          controller.initialize(exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      // Stop before permission dialog completes
      await controller.stop();
      mockSource.pendingPermissionCompleter!.complete(true);
      await initFuture;

      expect(mockSource.startSessionCalled, isFalse);
      expect(controller.state.isCameraActive, isFalse);

      // Now test dispose while startSession is in flight
      mockSource.permissionStatus = 'granted';
      mockSource.pendingStartSessionCompleter = Completer<bool>();

      final secondInitFuture =
          controller.initialize(exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      controller.dispose();
      controllerDisposed = true;

      mockSource.pendingStartSessionCompleter!.complete(true);
      await secondInitFuture;

      // Late event after dispose must not throw
      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 9000,
        'latencyMs': 15,
        'numPoses': 1,
        'landmarks': [],
      });
      await pumpEventQueue();

      expect(mockSource.stopSessionCallCount, greaterThanOrEqualTo(2));
    });

    test(
        '16. Sparse landmark list resolves required joints by explicit landmark index',
        () async {
      await controller.initialize(
          exerciseId: 'lat-pulldown', exerciseSlug: 'lat-pulldown');

      // Provide only key upper-body joints out of array order
      final sparseLandmarks = [
        {'index': 24, 'x': 0.55, 'y': 0.75, 'z': 0.0, 'visibility': 0.85},
        {'index': 12, 'x': 0.60, 'y': 0.35, 'z': 0.0, 'visibility': 0.90},
        {'index': 11, 'x': 0.40, 'y': 0.35, 'z': 0.0, 'visibility': 0.90},
        {'index': 13, 'x': 0.35, 'y': 0.50, 'z': 0.0, 'visibility': 0.80},
      ];

      mockSource.emitEvent({
        'status': 'detecting',
        'timestamp': 9500,
        'latencyMs': 19,
        'numPoses': 1,
        'landmarks': sparseLandmarks,
      });

      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.detecting);
      expect(controller.state.landmarks.length, 4);
    });
    test('13. startVideoReplay configures state and delegates to native source', () async {
      await controller.startVideoReplay(videoPath: '/data/user/0/test_videos/sample.mp4');

      expect(mockSource.startVideoReplayCalled, isTrue);
      expect(mockSource.lastVideoPath, '/data/user/0/test_videos/sample.mp4');
      expect(controller.state.sourceMode, 'video_replay');
      expect(controller.state.clipName, 'sample.mp4');
      expect(controller.state.isCameraActive, isTrue);
      expect(controller.state.isEndOfStream, isFalse);
    });

    test('14. End of stream event updates state without resetting metrics or crashing', () async {
      await controller.startVideoReplay(videoPath: 'sample.mp4');

      mockSource.emitEvent({
        'status': 'endOfStream',
        'isEndOfStream': true,
        'timestamp': 5500,
        'videoPtsMs': 5500,
        'previewPtsMs': 5520,
        'ptsSkewMs': 20,
        'sourceFps': 50.0,
      });

      await pumpEventQueue();

      expect(controller.state.isEndOfStream, isTrue);
      expect(controller.state.videoPtsMs, 5500);
      expect(controller.state.previewPtsMs, 5520);
      expect(controller.state.ptsSkewMs, 20);
      expect(controller.state.guideMessage, contains('Video replay finished'));
    });

    test('15. switchToCamera switches source mode and resets replay telemetry', () async {
      await controller.startVideoReplay(videoPath: 'sample.mp4');
      expect(controller.state.sourceMode, 'video_replay');

      await controller.switchToCamera();

      expect(mockSource.switchSourceCalled, isTrue);
      expect(mockSource.lastSwitchMode, 'camera');
      expect(controller.state.sourceMode, 'camera');
      expect(controller.state.clipName, isEmpty);
      expect(controller.state.isCameraActive, isTrue);
    });

    test('16. isSyncValid evaluates correctly based on sourceMode, isPtsVerified, and ptsSkewMs', () {
      // In camera mode, sync is always valid
      const cameraState = ExerciseCvState(sourceMode: 'camera', ptsSkewMs: 150, isPtsVerified: false);
      expect(cameraState.isSyncValid, isTrue);

      // In replay mode with verified PTS and skew <= 80ms, sync is valid
      const replayValid = ExerciseCvState(sourceMode: 'video_replay', ptsSkewMs: 60, isPtsVerified: true);
      expect(replayValid.isSyncValid, isTrue);

      // In replay mode with skew > 80ms, sync is invalid
      const replayInvalid = ExerciseCvState(sourceMode: 'video_replay', ptsSkewMs: 95, isPtsVerified: true);
      expect(replayInvalid.isSyncValid, isFalse);

      // In replay mode with unverified PTS, sync is invalid even if skew is 0ms
      const replayUnverified = ExerciseCvState(sourceMode: 'video_replay', ptsSkewMs: 0, isPtsVerified: false);
      expect(replayUnverified.isSyncValid, isFalse);
    });

    test('17. previewProgress continuously updates previewPtsMs and auto-hides skeleton when skew exceeds 80ms', () async {
      await controller.startVideoReplay(videoPath: 'sample.mp4');

      // Initially before first pose callback, isPtsVerified is false -> not synced
      expect(controller.state.isSyncValid, isFalse);

      final validLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.95,
        },
      );

      // Pose callback arrives for frame at 200ms while preview is at 260ms (skew = 60ms <= 80ms)
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 1,
        'timestamp': 200,
        'videoPtsMs': 200,
        'previewPtsMs': 260,
        'ptsSkewMs': 60,
        'isPtsVerified': true,
        'latencyMs': 72,
        'numPoses': 1,
        'landmarks': validLandmarks,
        'overlayVisiblePct': 30.0,
        'overlayHiddenSkewPct': 50.0,
        'overlayHiddenNoResultPct': 20.0,
        'overlayHiddenGatePct': 0.0,
      });
      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.detecting);
      expect(controller.state.videoPtsMs, 200);
      expect(controller.state.previewPtsMs, 260);
      expect(controller.state.ptsSkewMs, 60);
      expect(controller.state.isSyncValid, isTrue);
      expect(controller.state.frameCount, 1);

      // Video preview advances to 300ms while no new pose callback has arrived (skew = 100ms > 80ms)
      mockSource.emitEvent({
        'status': 'previewProgress',
        'sessionGen': 1,
        'timestamp': 200,
        'videoPtsMs': 200,
        'previewPtsMs': 300,
        'ptsSkewMs': 100,
        'isPtsVerified': true,
        'overlayVisiblePct': 25.0,
        'overlayHiddenSkewPct': 60.0,
        'overlayHiddenNoResultPct': 15.0,
        'overlayHiddenGatePct': 0.0,
      });
      await pumpEventQueue();

      // Skeleton must immediately auto-hide (isSyncValid == false) without incrementing pose frameCount
      expect(controller.state.previewPtsMs, 300);
      expect(controller.state.ptsSkewMs, 100);
      expect(controller.state.isSyncValid, isFalse);
      expect(controller.state.frameCount, 1);
      expect(controller.state.overlayHiddenSkewPct, 60.0);

      // Next pose callback arrives for 280ms while preview is at 340ms (skew = 60ms <= 80ms)
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 1,
        'timestamp': 280,
        'videoPtsMs': 280,
        'previewPtsMs': 340,
        'ptsSkewMs': 60,
        'isPtsVerified': true,
        'latencyMs': 75,
        'numPoses': 1,
        'landmarks': validLandmarks,
      });
      await pumpEventQueue();

      expect(controller.state.videoPtsMs, 280);
      expect(controller.state.previewPtsMs, 340);
      expect(controller.state.ptsSkewMs, 60);
      expect(controller.state.isSyncValid, isTrue);
      expect(controller.state.frameCount, 2);
    });

    test('18. Stale callbacks from an older sessionGen are rejected after restart or source switch', () async {
      await controller.startVideoReplay(videoPath: 'sample.mp4');

      final validLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.95,
        },
      );

      // Emit event in sessionGen = 2
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 2,
        'timestamp': 500,
        'videoPtsMs': 500,
        'previewPtsMs': 540,
        'ptsSkewMs': 40,
        'isPtsVerified': true,
        'latencyMs': 70,
        'numPoses': 1,
        'landmarks': validLandmarks,
      });
      await pumpEventQueue();
      expect(controller.state.sessionGen, 2);
      expect(controller.state.videoPtsMs, 500);
      expect(controller.state.frameCount, 1);

      // Restart replay -> starts a new session
      await controller.restartVideoReplay();
      expect(controller.state.frameCount, 0);
      expect(controller.state.landmarks, isEmpty);

      // Late callback from old sessionGen = 2 arrives -> MUST be ignored
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 2,
        'timestamp': 580,
        'videoPtsMs': 580,
        'previewPtsMs': 620,
        'ptsSkewMs': 40,
        'isPtsVerified': true,
        'latencyMs': 70,
        'numPoses': 1,
        'landmarks': validLandmarks,
      });
      await pumpEventQueue();

      expect(controller.state.frameCount, 0);
      expect(controller.state.landmarks, isEmpty);
      expect(controller.state.videoPtsMs, 0);

      // Callback from new sessionGen = 3 arrives -> accepted
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 3,
        'timestamp': 40,
        'videoPtsMs': 40,
        'previewPtsMs': 80,
        'ptsSkewMs': 40,
        'isPtsVerified': true,
        'latencyMs': 68,
        'numPoses': 1,
        'landmarks': validLandmarks,
      });
      await pumpEventQueue();

      expect(controller.state.sessionGen, 3);
      expect(controller.state.frameCount, 1);
      expect(controller.state.videoPtsMs, 40);
      expect(controller.state.isSyncValid, isTrue);
    });

    test('19. End of stream (EOS) preserves summary and rejects late callbacks from same generation', () async {
      await controller.startVideoReplay(videoPath: 'sample.mp4');

      final validLandmarks = List.generate(
        33,
        (i) => {
          'index': i,
          'x': 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.95,
        },
      );

      // Frame at 14000ms
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 1,
        'timestamp': 14000,
        'videoPtsMs': 14000,
        'previewPtsMs': 14000,
        'ptsSkewMs': 0,
        'isPtsVerified': true,
        'latencyMs': 60,
        'numPoses': 1,
        'landmarks': validLandmarks,
        'overlayVisiblePct': 75.0,
        'overlayHiddenSkewPct': 10.0,
        'overlayHiddenNoResultPct': 15.0,
        'overlayHiddenGatePct': 0.0,
      });
      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.detecting);
      expect(controller.state.isEndOfStream, isFalse);

      // EOS event arrives
      mockSource.emitEvent({
        'status': 'endOfStream',
        'sessionGen': 1,
        'timestamp': 16360,
        'videoPtsMs': 16360,
        'previewPtsMs': 16360,
        'ptsSkewMs': 0,
        'isPtsVerified': true,
        'isEndOfStream': true,
        'numPoses': 0,
        'landmarks': [],
        'overlayVisiblePct': 75.0,
        'overlayHiddenSkewPct': 10.0,
        'overlayHiddenNoResultPct': 15.0,
        'overlayHiddenGatePct': 0.0,
      });
      await pumpEventQueue();

      expect(controller.state.isEndOfStream, isTrue);
      expect(controller.state.guideMessage, contains('Video replay finished'));
      expect(controller.state.overlayVisiblePct, 75.0);

      // Late callback for old frame arrives after EOS has been reached
      mockSource.emitEvent({
        'status': 'detecting',
        'sessionGen': 1,
        'timestamp': 16340,
        'videoPtsMs': 16340,
        'previewPtsMs': 16360,
        'ptsSkewMs': 20,
        'isPtsVerified': true,
        'latencyMs': 65,
        'numPoses': 1,
        'landmarks': validLandmarks,
      });
      await pumpEventQueue();

      // EOS state and summary must be strictly preserved
      expect(controller.state.isEndOfStream, isTrue);
      expect(controller.state.guideMessage, contains('Video replay finished'));
      expect(controller.state.overlayVisiblePct, 75.0);
      expect(controller.state.landmarks, isEmpty);
      expect(controller.state.posesDetected, 0);
      expect(controller.state.isSyncValid, isFalse);
    });
  });
}

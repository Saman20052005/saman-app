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
  bool stopSessionCalled = false;
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
  });
}

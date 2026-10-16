import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/workout_cv_native_source.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/entities/pose_landmark.dart';

final workoutCvNativeSourceProvider = Provider<WorkoutCvNativeSource>((ref) {
  return WorkoutCvNativeSource();
});

final workoutCvControllerProvider =
    StateNotifierProvider.autoDispose<WorkoutCvNotifier, ExerciseCvState>((ref) {
  final source = ref.watch(workoutCvNativeSourceProvider);
  return WorkoutCvNotifier(source);
});

class WorkoutCvNotifier extends StateNotifier<ExerciseCvState> {
  final WorkoutCvNativeSource _nativeSource;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  int _lastFpsWindowCount = 0;
  DateTime _lastFpsWindowTime = DateTime.now();

  WorkoutCvNotifier(this._nativeSource) : super(const ExerciseCvState());

  Future<void> initialize({
    required String exerciseId,
    required String exerciseSlug,
  }) async {
    state = state.copyWith(
      exerciseId: exerciseId,
      exerciseSlug: exerciseSlug,
      guideMessage: 'Checking camera permission...',
      trackingStatus: TrackingStatus.uninitialized,
      landmarks: const [],
    );

    var perm = await _nativeSource.checkPermission();
    if (perm != 'granted') {
      final requested = await _nativeSource.requestPermission();
      if (!requested) {
        state = state.copyWith(
          trackingStatus: TrackingStatus.permissionDenied,
          guideMessage: 'Camera permission denied. Please grant permission in Settings.',
          isCameraActive: false,
        );
        return;
      }
    }

    // Permission granted -> Start session
    state = state.copyWith(
      isCameraActive: true,
      guideMessage: 'Starting camera stream...',
      trackingStatus: TrackingStatus.needsSetup,
    );

    await _nativeSource.startSession(exerciseSlug);
    _listenToEvents();
  }

  void _listenToEvents() {
    _subscription?.cancel();
    _lastFpsWindowTime = DateTime.now();
    _lastFpsWindowCount = 0;

    _subscription = _nativeSource.eventStream.listen(
      (event) {
        if (!mounted || !state.isCameraActive) return;
        _processEvent(event);
      },
      onError: (err) {
        if (!mounted) return;
        state = state.copyWith(
          trackingStatus: TrackingStatus.error,
          errorMessage: 'Stream error: $err',
          guideMessage: 'Error receiving camera stream.',
        );
      },
    );
  }

  void _processEvent(Map<String, dynamic> event) {
    final statusStr = event['status'] as String? ?? 'lost';
    final timestamp = (event['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final latency = (event['latencyMs'] as num?)?.toInt() ?? 0;
    final numPoses = (event['numPoses'] as num?)?.toInt() ?? 0;

    // Moving FPS calculation
    final now = DateTime.now();
    final newFrameCount = state.frameCount + 1;
    _lastFpsWindowCount++;
    double currentFps = state.fps;
    final elapsedSec = now.difference(_lastFpsWindowTime).inMilliseconds / 1000.0;
    if (elapsedSec >= 1.0) {
      currentFps = _lastFpsWindowCount / elapsedSec;
      _lastFpsWindowCount = 0;
      _lastFpsWindowTime = now;
    }

    // Maintain latency history capped at 500
    final updatedLatencyHistory = [...state.latencyHistoryMs, latency];
    if (updatedLatencyHistory.length > 500) {
      updatedLatencyHistory.removeAt(0);
    }

    // Quality Gate 1: Native reported error
    if (statusStr == 'error') {
      state = state.copyWith(
        trackingStatus: TrackingStatus.error,
        errorMessage: event['errorMessage'] as String? ?? 'Camera or inference error',
        guideMessage: 'Camera/Model encountered an error.',
        landmarks: const [],
        latencyMs: latency,
        timestamp: timestamp,
        frameCount: newFrameCount,
        fps: currentFps,
        latencyHistoryMs: updatedLatencyHistory,
      );
      return;
    }

    // Quality Gate 2: Multiple people detected
    if (statusStr == 'multiplePeople' || numPoses > 1) {
      state = state.copyWith(
        trackingStatus: TrackingStatus.multiplePeople,
        posesDetected: numPoses,
        landmarks: const [],
        guideMessage: 'Multiple people detected. Only one person should be in frame.',
        latencyMs: latency,
        timestamp: timestamp,
        frameCount: newFrameCount,
        fps: currentFps,
        latencyHistoryMs: updatedLatencyHistory,
      );
      return;
    }

    // Quality Gate 3: No poses or tracking lost
    if (statusStr == 'lost' || numPoses == 0) {
      state = state.copyWith(
        trackingStatus: TrackingStatus.lost,
        posesDetected: 0,
        landmarks: const [],
        guideMessage: 'No person detected. Step into the camera view.',
        latencyMs: latency,
        timestamp: timestamp,
        frameCount: newFrameCount,
        fps: currentFps,
        latencyHistoryMs: updatedLatencyHistory,
      );
      return;
    }

    // Quality Gate 4: Single person detected -> Verify Upper Body Landmarks
    final rawLandmarks = event['landmarks'] as List<dynamic>? ?? [];
    if (rawLandmarks.isEmpty) {
      state = state.copyWith(
        trackingStatus: TrackingStatus.lost,
        posesDetected: 0,
        landmarks: const [],
        guideMessage: 'No landmarks detected. Step into camera view.',
        latencyMs: latency,
        timestamp: timestamp,
        frameCount: newFrameCount,
        fps: currentFps,
        latencyHistoryMs: updatedLatencyHistory,
      );
      return;
    }

    final parsedLandmarks = rawLandmarks
        .whereType<Map>()
        .map((m) => PoseLandmark.fromMap(m))
        .toList();

    // Check critical upper body joints (shoulders: 11, 12, elbows: 13, 14, hips: 23, 24)
    bool hasShoulders = _isJointConfident(parsedLandmarks, PoseLandmark.leftShoulder) &&
        _isJointConfident(parsedLandmarks, PoseLandmark.rightShoulder);
    bool hasElbows = _isJointConfident(parsedLandmarks, PoseLandmark.leftElbow) ||
        _isJointConfident(parsedLandmarks, PoseLandmark.rightElbow);
    bool hasHips = _isJointConfident(parsedLandmarks, PoseLandmark.leftHip) ||
        _isJointConfident(parsedLandmarks, PoseLandmark.rightHip);

    if (!hasShoulders || (!hasElbows && !hasHips)) {
      // Incomplete upper body framing
      state = state.copyWith(
        trackingStatus: TrackingStatus.needsSetup,
        posesDetected: 1,
        landmarks: parsedLandmarks,
        guideMessage: 'Align upper body (shoulders, arms, hips) inside frame.',
        latencyMs: latency,
        timestamp: timestamp,
        frameCount: newFrameCount,
        fps: currentFps,
        latencyHistoryMs: updatedLatencyHistory,
      );
      return;
    }

    // All quality gates passed -> Detecting & Tracking Active
    state = state.copyWith(
      trackingStatus: TrackingStatus.detecting,
      posesDetected: 1,
      landmarks: parsedLandmarks,
      guideMessage: 'Pose detected. Tracking active.',
      latencyMs: latency,
      timestamp: timestamp,
      frameCount: newFrameCount,
      fps: currentFps,
      latencyHistoryMs: updatedLatencyHistory,
      clearErrorMessage: true,
    );
  }

  bool _isJointConfident(List<PoseLandmark> landmarks, int index) {
    if (index >= landmarks.length) return false;
    return landmarks[index].isVisible(threshold: 0.45);
  }

  Future<void> stop() async {
    _subscription?.cancel();
    _subscription = null;
    await _nativeSource.stopSession();
    if (mounted) {
      state = state.copyWith(
        isCameraActive: false,
        landmarks: const [],
        trackingStatus: TrackingStatus.uninitialized,
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _nativeSource.stopSession();
    super.dispose();
  }
}

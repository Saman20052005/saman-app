import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/workout_cv_native_source.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/entities/pose_landmark.dart';
import '../../domain/services/lat_pulldown_baseline.dart';
import '../../domain/services/workout_cv_motion_features.dart';

final workoutCvNativeSourceProvider = Provider<WorkoutCvNativeSource>((ref) {
  return WorkoutCvNativeSource();
});

final workoutCvControllerProvider =
    StateNotifierProvider.autoDispose<WorkoutCvNotifier, ExerciseCvState>(
        (ref) {
  final source = ref.watch(workoutCvNativeSourceProvider);
  return WorkoutCvNotifier(source);
});

class WorkoutCvNotifier extends StateNotifier<ExerciseCvState> {
  final WorkoutCvNativeSource _nativeSource;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  int _lastFpsWindowCount = 0;
  DateTime _lastFpsWindowTime = DateTime.now();
  int _latestSeenSessionGen = 0;
  int _minRejectedSessionGen = 0;
  int _initGeneration = 0;
  bool _isStopped = false;
  final LatPulldownBaseline _repTracker = LatPulldownBaseline();
  int? _repSessionGen;
  int? _lastRepPtsMs;
  bool _analysisClosed = false;
  String? _replayVideoPath;

  WorkoutCvNotifier(this._nativeSource) : super(const ExerciseCvState());

  Future<void> initialize({
    required String exerciseId,
    required String exerciseSlug,
    bool videoReplay = false,
  }) async {
    final opId = ++_initGeneration;
    _isStopped = false;
    _minRejectedSessionGen = _latestSeenSessionGen;
    _subscription?.cancel();
    _subscription = null;

    _resetRepAnalysis();

    state = state.copyWith(
      sourceMode: 'camera',
      isEndOfStream: false,
      isPtsVerified: true,
      exerciseId: exerciseId,
      exerciseSlug: exerciseSlug,
      guideMessage: 'Checking camera permission...',
      trackingStatus: TrackingStatus.uninitialized,
      isCameraActive: false,
      landmarks: const [],
      clearErrorMessage: true,
    );

    if (videoReplay) {
      await startVideoReplay();
      return;
    }

    final perm = await _nativeSource.checkPermission();
    if (!mounted || _isStopped || opId != _initGeneration) return;

    if (perm != 'granted') {
      final requested = await _nativeSource.requestPermission();
      if (!mounted || _isStopped || opId != _initGeneration) return;
      if (!requested) {
        state = state.copyWith(
          trackingStatus: TrackingStatus.permissionDenied,
          guideMessage:
              'Camera permission denied. Please grant permission in Settings.',
          isCameraActive: false,
        );
        return;
      }
    }

    final started = await _nativeSource.startSession(exerciseSlug);
    if (!mounted || _isStopped || opId != _initGeneration) {
      if (started) {
        await _nativeSource.stopSession();
      }
      return;
    }

    if (!started) {
      state = state.copyWith(
        trackingStatus: TrackingStatus.error,
        isCameraActive: false,
        errorMessage: 'Failed to start native camera session.',
        guideMessage: 'Unable to start camera session.',
        landmarks: const [],
      );
      return;
    }

    // Permission granted and native session started -> Listen to events
    state = state.copyWith(
      isCameraActive: true,
      guideMessage: 'Starting camera stream...',
      trackingStatus: TrackingStatus.needsSetup,
      clearErrorMessage: true,
    );

    _listenToEvents();
  }

  Future<void> startVideoReplay({String? videoPath}) async {
    final path = videoPath ?? '/data/data/com.example.health_ai_app/files/test_videos/15620300_1080_1920_50fps.mp4';
    final name = path.split('/').last;
    _replayVideoPath = path;

    final opId = ++_initGeneration;
    _isStopped = false;
    _subscription?.cancel();
    _subscription = null;
    _minRejectedSessionGen = _latestSeenSessionGen;
    _lastFpsWindowTime = DateTime.now();
    _lastFpsWindowCount = 0;

    _resetRepAnalysis();

    state = state.copyWith(
      sourceMode: 'video_replay',
      clipName: name,
      guideMessage: 'Starting video replay...',
      trackingStatus: TrackingStatus.needsSetup,
      isCameraActive: true,
      isEndOfStream: false,
      frameCount: 0,
      fps: 0.0,
      landmarks: const [],
      latencyHistoryMs: const [],
      videoPtsMs: 0,
      previewPtsMs: 0,
      ptsSkewMs: 0,
      isPtsVerified: false,
      sourceFps: 50.0,
      overlayVisiblePct: 0.0,
      overlayHiddenSkewPct: 0.0,
      overlayHiddenNoResultPct: 0.0,
      overlayHiddenGatePct: 0.0,
      clearErrorMessage: true,
    );

    // Subscribe before native starts its first bounded frame handshake.
    _listenToEvents();
    final started = await _nativeSource.startVideoReplay(path);
    if (!mounted || _isStopped || opId != _initGeneration) return;
    if (!started) {
      _closeRepAnalysis(failed: true);
      state = state.copyWith(
        trackingStatus: TrackingStatus.error,
        isCameraActive: false,
        landmarks: const [],
        errorMessage: 'Failed to start native CV source.',
        guideMessage: 'Unable to start requested source.',
      );
      return;
    }
  }

  Future<void> restartVideoReplay() async {
    await startVideoReplay(videoPath: _replayVideoPath);
  }

  Future<void> switchToCamera() async {
    final opId = ++_initGeneration;
    _isStopped = false;
    _subscription?.cancel();
    _subscription = null;
    _minRejectedSessionGen = _latestSeenSessionGen;
    _lastFpsWindowTime = DateTime.now();
    _lastFpsWindowCount = 0;

    _resetRepAnalysis();

    state = state.copyWith(
      sourceMode: 'camera',
      clipName: '',
      guideMessage: 'Switching to live camera...',
      trackingStatus: TrackingStatus.needsSetup,
      isCameraActive: true,
      isEndOfStream: false,
      frameCount: 0,
      fps: 0.0,
      landmarks: const [],
      latencyHistoryMs: const [],
      videoPtsMs: 0,
      previewPtsMs: 0,
      ptsSkewMs: 0,
      isPtsVerified: true,
      overlayVisiblePct: 0.0,
      overlayHiddenSkewPct: 0.0,
      overlayHiddenNoResultPct: 0.0,
      overlayHiddenGatePct: 0.0,
      clearErrorMessage: true,
    );

    final started = await _nativeSource.switchSource('camera');
    if (!mounted || _isStopped || opId != _initGeneration) return;
    if (!started) {
      state = state.copyWith(
        trackingStatus: TrackingStatus.error,
        isCameraActive: false,
        landmarks: const [],
        errorMessage: 'Failed to start native CV source.',
        guideMessage: 'Unable to start requested source.',
      );
      return;
    }
    _listenToEvents();
  }

  void _listenToEvents() {
    _subscription?.cancel();
    _lastFpsWindowTime = DateTime.now();
    _lastFpsWindowCount = 0;

    _subscription = _nativeSource.eventStream.listen(
      (event) {
        if (!mounted || _isStopped || !state.isCameraActive) return;
        final generation = (event['sessionGen'] as num?)?.toInt();
        if (generation != null && (generation <= _minRejectedSessionGen ||
            generation < _latestSeenSessionGen)) return;
        if (_analysisClosed) return;
        if (generation != null && generation != _repSessionGen) {
          _resetRepAnalysis();
          _repSessionGen = generation;
        }
        _processEvent(event);
        _processRepAnalysis(event);
        if (state.sourceMode == 'video_replay' && !state.isEndOfStream &&
            generation == state.sessionGen && state.trackingStatus != TrackingStatus.error) {
          if (event['status'] == 'replayPreparing') {
            _acknowledgeAfterFrame(generation!, (event['nextVideoPtsMs'] as num).toInt(), 'clear');
          } else if (event['requiresReplayAck'] == true &&
              state.videoPtsMs == (event['videoPtsMs'] as num?)?.toInt()) {
            _acknowledgeAfterFrame(generation!, state.videoPtsMs, 'pose');
          }
        }
      },
      onError: (err) {
        if (!mounted || _isStopped) return;
        if (state.sourceMode == 'video_replay' && _analysisClosed) return;
        _closeRepAnalysis(failed: true);
        state = state.copyWith(
          trackingStatus: TrackingStatus.error,
          landmarks: const [],
          errorMessage: 'Stream error: $err',
          guideMessage: 'Error receiving camera stream.',
        );
      },
    );
  }

  void _processEvent(Map<String, dynamic> event) {
    final eventSessionGen = (event['sessionGen'] as num?)?.toInt();
    if (eventSessionGen != null) {
      if (eventSessionGen <= _minRejectedSessionGen || eventSessionGen < _latestSeenSessionGen) {
        return;
      }
      _latestSeenSessionGen = eventSessionGen;
    }

    final statusStr = event['status'] as String? ?? 'lost';
    if (statusStr == 'replayPreparing') {
      if (state.isEndOfStream) return;
      state = state.copyWith(
        sessionGen: eventSessionGen,
        landmarks: const [],
        posesDetected: 0,
        isPtsVerified: false,
        guideMessage: 'Slow video replay: waiting for the next pose...',
      );
      return;
    }
    final timestamp = (event['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final latency = (event['latencyMs'] as num?)?.toInt() ?? 0;
    final numPoses = (event['numPoses'] as num?)?.toInt() ?? 0;

    final sourceMode = event['sourceMode'] as String? ?? state.sourceMode;
    final clipName = event['clipName'] as String? ?? state.clipName;
    final videoPtsMs = (event['videoPtsMs'] as num?)?.toInt() ?? timestamp;
    final previewPtsMs = (event['previewPtsMs'] as num?)?.toInt() ?? videoPtsMs;
    final ptsSkewMs = (event['ptsSkewMs'] as num?)?.toInt() ?? (previewPtsMs - videoPtsMs).abs();
    final isPtsVerified = event['isPtsVerified'] as bool? ?? (sourceMode == 'camera');
    final sourceFps = (event['sourceFps'] as num?)?.toDouble() ?? (sourceMode == 'video_replay' ? 50.0 : 30.0);
    final isEos = event['isEndOfStream'] == true || statusStr == 'endOfStream';
    final readbackLatency = (event['readbackMs'] as num?)?.toDouble() ?? state.readbackLatencyMs;

    final overlayVisiblePct = (event['overlayVisiblePct'] as num?)?.toDouble() ?? state.overlayVisiblePct;
    final overlayHiddenSkewPct = (event['overlayHiddenSkewPct'] as num?)?.toDouble() ?? state.overlayHiddenSkewPct;
    final overlayHiddenNoResultPct = (event['overlayHiddenNoResultPct'] as num?)?.toDouble() ?? state.overlayHiddenNoResultPct;
    final overlayHiddenGatePct = (event['overlayHiddenGatePct'] as num?)?.toDouble() ?? state.overlayHiddenGatePct;

    // Ignore late frame callbacks after EOS has been reached for this generation
    if (state.isEndOfStream && eventSessionGen == state.sessionGen && !isEos) {
      return;
    }

    // Continuous preview progress tick (updates previewPtsMs, skew & auto-hides stale skeleton if >80ms)
    if (statusStr == 'previewProgress') {
      state = state.copyWith(
        sessionGen: eventSessionGen ?? state.sessionGen,
        videoPtsMs: videoPtsMs,
        previewPtsMs: previewPtsMs,
        ptsSkewMs: ptsSkewMs,
        isPtsVerified: isPtsVerified,
        sourceMode: sourceMode,
        clipName: clipName,
        sourceFps: sourceFps,
        readbackLatencyMs: readbackLatency,
        overlayVisiblePct: overlayVisiblePct,
        overlayHiddenSkewPct: overlayHiddenSkewPct,
        overlayHiddenNoResultPct: overlayHiddenNoResultPct,
        overlayHiddenGatePct: overlayHiddenGatePct,
      );
      return;
    }

    // End of stream handling
    if (isEos) {
      _closeRepAnalysis();
      state = state.copyWith(
        sessionGen: eventSessionGen ?? state.sessionGen,
        isEndOfStream: true,
        trackingStatus: TrackingStatus.uninitialized,
        landmarks: const [],
        posesDetected: 0,
        guideMessage: 'Video replay finished. Tap Restart to replay.',
        videoPtsMs: videoPtsMs,
        previewPtsMs: previewPtsMs,
        ptsSkewMs: ptsSkewMs,
        isPtsVerified: false,
        sourceMode: sourceMode,
        clipName: clipName,
        sourceFps: sourceFps,
        readbackLatencyMs: readbackLatency,
        overlayVisiblePct: overlayVisiblePct,
        overlayHiddenSkewPct: overlayHiddenSkewPct,
        overlayHiddenNoResultPct: overlayHiddenNoResultPct,
        overlayHiddenGatePct: overlayHiddenGatePct,
      );
      return;
    }

    // Moving FPS calculation
    final now = DateTime.now();
    final newFrameCount = state.frameCount + 1;
    _lastFpsWindowCount++;
    double currentFps = state.fps;
    final elapsedSec =
        now.difference(_lastFpsWindowTime).inMilliseconds / 1000.0;
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

    state = state.copyWith(
        sourceMode: sourceMode,
        clipName: clipName,
        sessionGen: eventSessionGen ?? state.sessionGen,
        videoPtsMs: videoPtsMs,
        previewPtsMs: previewPtsMs,
        ptsSkewMs: ptsSkewMs,
        isPtsVerified: isPtsVerified,
        sourceFps: sourceFps,
        readbackLatencyMs: readbackLatency,
        overlayVisiblePct: overlayVisiblePct,
        overlayHiddenSkewPct: overlayHiddenSkewPct,
        overlayHiddenNoResultPct: overlayHiddenNoResultPct,
        overlayHiddenGatePct: overlayHiddenGatePct,
    );

    // Quality Gate 1: Native reported error
    if (statusStr == 'error') {
      state = state.copyWith(
        trackingStatus: TrackingStatus.error,
        errorMessage:
            event['errorMessage'] as String? ?? 'Camera or inference error',
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
        guideMessage:
            'Multiple people detected. Only one person should be in frame.',
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
    final hasShoulders =
        _isJointConfident(parsedLandmarks, PoseLandmark.leftShoulder) &&
            _isJointConfident(parsedLandmarks, PoseLandmark.rightShoulder);
    final hasElbows =
        _isJointConfident(parsedLandmarks, PoseLandmark.leftElbow) ||
            _isJointConfident(parsedLandmarks, PoseLandmark.rightElbow);
    final hasHips = _isJointConfident(parsedLandmarks, PoseLandmark.leftHip) ||
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

  void _resetRepAnalysis() {
    _repTracker.reset();
    _repSessionGen = null;
    _lastRepPtsMs = null;
    _analysisClosed = false;
    state = state.copyWith(
      replayRepEvents: const [],
      analysisPhase: LatPulldownPhase.notReady,
      replayAnalysisStatus: ReplayAnalysisStatus.waiting,
    );
  }

  void _closeRepAnalysis({bool failed = false}) {
    _analysisClosed = true;
    // Drop any incomplete cycle, preserving only completed events in UI state.
    _repTracker.reset();
    state = state.copyWith(
      analysisPhase: LatPulldownPhase.notReady,
      replayAnalysisStatus: failed
          ? ReplayAnalysisStatus.error
          : ReplayAnalysisStatus.finished,
    );
  }

  void _processRepAnalysis(Map<String, dynamic> event) {
    if (_analysisClosed) return;
    if (state.trackingStatus == TrackingStatus.error) {
      _closeRepAnalysis(failed: true);
      return;
    }
    // Display handshakes/progress are not pose samples or recognition failures.
    if (event['status'] == 'replayPreparing' ||
        event['status'] == 'previewProgress') return;
    if (state.exerciseSlug != 'lat-pulldown') return;

    final isReplay = state.sourceMode == 'video_replay';
    // Native camera timestamps are capture uptime, never inference arrival time.
    final ptsMs = (event[isReplay ? 'videoPtsMs' : 'timestamp'] as num?)?.toInt();
    if ((isReplay && (_repSessionGen == null ||
            event['sessionGen'] != _repSessionGen)) ||
        ptsMs == null || ptsMs < 0) {
      _closeRepAnalysis(failed: true);
      state = state.copyWith(
        trackingStatus: TrackingStatus.error,
        landmarks: const [],
        errorMessage: isReplay
            ? 'Replay pose is missing its generation or video PTS.'
            : 'Camera pose is missing its capture timestamp.',
      );
      return;
    }
    if (_lastRepPtsMs != null && ptsMs <= _lastRepPtsMs!) return;
    _lastRepPtsMs = ptsMs;

    final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
      frameIndex: state.frameCount - 1,
      timestampMs: ptsMs,
      landmarks: state.landmarks,
      imageWidth: (event['inputImageWidth'] as num?)?.toDouble() ?? 0,
      imageHeight: (event['inputImageHeight'] as num?)?.toDouble() ?? 0,
      isGateDetecting: state.trackingStatus == TrackingStatus.detecting &&
          state.isSyncValid,
    );
    // Invalid/lost samples must reach the baseline to interrupt holds/cycles.
    final result = _repTracker.processFrameFeatures(features);
    state = state.copyWith(
      replayRepEvents: _repTracker.repHistory,
      analysisPhase: result.phase,
      replayAnalysisStatus: result.isSampleValid &&
              result.phase != LatPulldownPhase.notReady
          ? ReplayAnalysisStatus.analyzing
          : ReplayAnalysisStatus.insufficientData,
    );
  }

  void _acknowledgeAfterFrame(int generation, int ptsMs, String phase) {
    final operation = _initGeneration;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isStopped || operation != _initGeneration ||
          state.sessionGen != generation || state.isEndOfStream ||
          state.sourceMode != 'video_replay') return;
      final accepted = await _nativeSource.acknowledgeReplayFrame(generation, ptsMs, phase);
      if (!accepted && mounted && !_isStopped && operation == _initGeneration &&
          state.sessionGen == generation && !state.isEndOfStream) {
        _closeRepAnalysis(failed: true);
        state = state.copyWith(
          trackingStatus: TrackingStatus.error,
          landmarks: const [],
          isPtsVerified: false,
          errorMessage: 'Replay frame acknowledgement failed.',
          guideMessage: 'Replay stopped. Restart to try again.',
        );
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool _isJointConfident(List<PoseLandmark> landmarks, int index) {
    PoseLandmark? lm;
    if (index < landmarks.length && landmarks[index].index == index) {
      lm = landmarks[index];
    } else {
      for (final l in landmarks) {
        if (l.index == index) {
          lm = l;
          break;
        }
      }
    }
    if (lm == null) return false;
    if (!lm.isVisible(threshold: 0.45)) return false;
    if (!lm.x.isFinite || !lm.y.isFinite) return false;
    if (lm.x < 0.0 || lm.x > 1.0 || lm.y < 0.0 || lm.y > 1.0) return false;
    return true;
  }

  Future<void> stop() async {
    ++_initGeneration;
    _isStopped = true;
    _repTracker.reset();
    _analysisClosed = true;
    _subscription?.cancel();
    _subscription = null;
    await _nativeSource.stopSession();
    if (mounted) {
      state = state.copyWith(
        isCameraActive: false,
        landmarks: const [],
        trackingStatus: TrackingStatus.uninitialized,
        analysisPhase: LatPulldownPhase.notReady,
      );
    }
  }

  @override
  void dispose() {
    ++_initGeneration;
    _isStopped = true;
    _subscription?.cancel();
    _subscription = null;
    _nativeSource.stopSession();
    super.dispose();
  }
}

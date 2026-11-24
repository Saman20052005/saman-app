import 'dart:math' as math;

import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Plank Hold isometric state machine.
enum PlankHoldPhase {
  /// Subject is setting up, misaligned, or lost tracking; not accumulating hold time.
  notReady,

  /// Body is aligned within plank tolerance (>= 165 deg) and accumulating valid hold time.
  holding,
}

/// A completed 1-second isometric Plank Hold segment emitted every 1000ms of aligned hold.
class PlankHoldRepEvent extends LatPulldownRepEvent {
  final bool isAligned;
  final int validHoldMs;

  const PlankHoldRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    required this.isAligned,
    required this.validHoldMs,
  });
}

/// Configuration parameters for [PlankHoldBaseline].
class PlankHoldBaselineConfig {
  final double minAlignedAngleDeg;
  final double minHorizontalTorsoLeanDeg;
  final int holdChunkMs;
  final int maxAllowedGapMs;

  const PlankHoldBaselineConfig({
    this.minAlignedAngleDeg = 165.0,
    this.minHorizontalTorsoLeanDeg = 45.0,
    this.holdChunkMs = 1000,
    this.maxAllowedGapMs = 600,
  });
}

/// Output record for a single processed Plank Hold frame.
class PlankHoldBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final PlankHoldPhase phase;
  final int completedReps;
  final PlankHoldRepEvent? newRepEvent;
  final double? bodyAlignmentDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const PlankHoldBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.bodyAlignmentDeg,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal state machine for isometric Plank and Side Plank holds.
///
/// Accumulates valid hold time only while body alignment (`Shoulder -> Hip -> Ankle`)
/// remains >= 165 degrees and emits one [PlankHoldRepEvent] per 1000ms held.
class PlankHoldBaseline {
  final PlankHoldBaselineConfig config;

  PlankHoldPhase _phase = PlankHoldPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastTimestampMs;
  int? _lastValidTimestampMs;
  int? _lastHoldFrameTimestampMs;
  int? _chunkStartTimestampMs;
  int _accumulatedValidMs = 0;
  double? _minAlignmentInCurrentChunk;
  int _droppedNonMonotonicFrames = 0;

  PlankHoldBaseline({PlankHoldBaselineConfig? config})
      : config = config ?? const PlankHoldBaselineConfig();

  PlankHoldPhase get phase => _phase;
  int get completedReps => _completedReps;
  int get validSeconds => _completedReps;
  int get accumulatedValidMs => _accumulatedValidMs;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = PlankHoldPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastTimestampMs = null;
    _lastValidTimestampMs = null;
    _lastHoldFrameTimestampMs = null;
    _chunkStartTimestampMs = null;
    _accumulatedValidMs = 0;
    _minAlignmentInCurrentChunk = null;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes a [PlankHoldFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  PlankHoldBaselineFrameResult processPlankHoldFeatures(
    PlankHoldFrameFeatures features,
  ) {
    final isAlignmentValid = features.bodyAlignmentDeg.isValid;
    final alignment =
        isAlignmentValid ? features.bodyAlignmentDeg.value : null;
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      bodyAlignmentDeg: alignment,
      torsoLeanDeg: torsoLean,
      isSampleValid: isAlignmentValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  PlankHoldBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? bodyAlignmentDeg,
    double? torsoLeanDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return PlankHoldBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        bodyAlignmentDeg: bodyAlignmentDeg,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      _resetHold();
      return PlankHoldBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        bodyAlignmentDeg: bodyAlignmentDeg,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    if (!isSampleValid ||
        bodyAlignmentDeg == null ||
        !bodyAlignmentDeg.isFinite) {
      _lastHoldFrameTimestampMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        _resetHold();
        return PlankHoldBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return PlankHoldBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isSampleValid: false,
      );
    }

    String? resetReason;
    if (_lastValidTimestampMs != null &&
        (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
      if (_phase == PlankHoldPhase.holding) {
        resetReason = 'dataLossGapBeforeValidSample';
      }
      _resetHold();
    }
    _lastValidTimestampMs = timestampMs;

    final isHorizontal = torsoLeanDeg == null ||
        !torsoLeanDeg.isFinite ||
        torsoLeanDeg >= config.minHorizontalTorsoLeanDeg;
    final isAligned =
        bodyAlignmentDeg >= config.minAlignedAngleDeg && isHorizontal;

    if (!isAligned) {
      final wasHolding = _phase == PlankHoldPhase.holding;
      _resetHold();
      final reason =
          bodyAlignmentDeg < config.minAlignedAngleDeg
              ? 'hipMisaligned'
              : 'notHorizontalPosture';
      return PlankHoldBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        bodyAlignmentDeg: bodyAlignmentDeg,
        isSampleValid: true,
        transitionReason: reason,
        resetReason: resetReason ?? (wasHolding ? reason : null),
      );
    }

    String? transitionReason;
    PlankHoldRepEvent? latestRepEvent;

    if (_phase == PlankHoldPhase.notReady) {
      _phase = PlankHoldPhase.holding;
      _accumulatedValidMs = 0;
      _chunkStartTimestampMs = timestampMs;
      _lastHoldFrameTimestampMs = timestampMs;
      _minAlignmentInCurrentChunk = bodyAlignmentDeg;
      transitionReason = 'holdStarted';
    } else {
      if (_lastHoldFrameTimestampMs != null) {
        final deltaMs = timestampMs - _lastHoldFrameTimestampMs!;
        if (deltaMs > 0 && deltaMs <= config.maxAllowedGapMs) {
          _accumulatedValidMs += deltaMs;
        }
      }
      _lastHoldFrameTimestampMs = timestampMs;
      _chunkStartTimestampMs ??= timestampMs;
      _minAlignmentInCurrentChunk = _minAlignmentInCurrentChunk == null
          ? bodyAlignmentDeg
          : math.min(_minAlignmentInCurrentChunk!, bodyAlignmentDeg);

      while (_accumulatedValidMs >= config.holdChunkMs) {
        _completedReps++;
        final chunkEnd = timestampMs - (_accumulatedValidMs - config.holdChunkMs);
        final chunkStart = _chunkStartTimestampMs ?? (chunkEnd - config.holdChunkMs);
        final chunkMid = (chunkStart + chunkEnd) ~/ 2;
        final minAngle = _minAlignmentInCurrentChunk ?? bodyAlignmentDeg;

        latestRepEvent = PlankHoldRepEvent(
          repNumber: _completedReps,
          startTimestampMs: chunkStart,
          bottomTimestampMs: chunkMid,
          endTimestampMs: chunkEnd,
          durationMs: config.holdChunkMs,
          minElbowAngleDeg: minAngle,
          status: 'PROVISIONAL',
          isAligned: true,
          validHoldMs: config.holdChunkMs,
        );
        _repHistory.add(latestRepEvent);
        transitionReason = 'validSecondCompleted';

        _accumulatedValidMs -= config.holdChunkMs;
        _chunkStartTimestampMs = chunkEnd;
        _minAlignmentInCurrentChunk = bodyAlignmentDeg;
      }
    }

    return PlankHoldBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: latestRepEvent,
      bodyAlignmentDeg: bodyAlignmentDeg,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: resetReason,
    );
  }

  void _resetHold() {
    _phase = PlankHoldPhase.notReady;
    _lastHoldFrameTimestampMs = null;
    _chunkStartTimestampMs = null;
    _accumulatedValidMs = 0;
    _minAlignmentInCurrentChunk = null;
  }
}

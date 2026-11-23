import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Bicep Curl exercise state machine.
enum BicepCurlPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Arms extended at bottom of curl (elbow angle >= 145 deg).
  extended,

  /// Concentric curling phase upward (elbow angle < 130 deg).
  curling,

  /// Peak flexion at top of curl (elbow angle <= 60 deg).
  flexed,

  /// Eccentric lowering phase back toward extension (elbow angle > 80 deg).
  lowering,
}

/// Configuration parameters for Bicep Curl rule-based state machine.
class BicepCurlBaselineConfig {
  final double extendedEnterDeg;
  final double curlingEnterDeg;
  final double flexedEnterDeg;
  final double loweringEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxAllowedGapMs;

  const BicepCurlBaselineConfig({
    this.extendedEnterDeg = 145.0,
    this.curlingEnterDeg = 130.0,
    this.flexedEnterDeg = 60.0,
    this.loweringEnterDeg = 80.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Bicep Curl frame.
class BicepCurlBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final BicepCurlPhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const BicepCurlBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.elbowAngleDeg,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal rule-based state machine for Bicep Curl repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Uses best-confidence elbow angle (Shoulder -> Elbow -> Wrist) in pixel space.
class BicepCurlBaseline {
  final BicepCurlBaselineConfig config;

  BicepCurlPhase _phase = BicepCurlPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakFlexedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  int _droppedNonMonotonicFrames = 0;

  BicepCurlBaseline({BicepCurlBaselineConfig? config})
      : config = config ?? const BicepCurlBaselineConfig();

  BicepCurlPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = BicepCurlPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _droppedNonMonotonicFrames = 0;
  }

  BicepCurlBaselineFrameResult processFrameFeatures(
      MultiExerciseAngleFeatures features) {
    final isAngleValid = features.bestElbowAngleDeg.isValid;
    final angle = isAngleValid ? features.bestElbowAngleDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  BicepCurlBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return BicepCurlBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      const resetReason = 'gateNotDetecting';
      _abortInProgressCycle();
      return BicepCurlBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        resetReason: resetReason,
      );
    }

    if (!isSampleValid || elbowAngleDeg == null || !elbowAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        const resetReason = 'dataLossGapExceeded';
        _abortInProgressCycle();
        return BicepCurlBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: resetReason,
        );
      }

      return BicepCurlBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isSampleValid: false,
      );
    }

    String? gapResetReason;
    if (_lastValidTimestampMs != null &&
        (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
      if (_phase != BicepCurlPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case BicepCurlPhase.notReady:
        if (elbowAngleDeg >= config.extendedEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = BicepCurlPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case BicepCurlPhase.extended:
        if (elbowAngleDeg < config.curlingEnterDeg) {
          _phase = BicepCurlPhase.curling;
          transitionReason = 'curlStarted';
          _repStartTimestampMs = timestampMs;
          _peakFlexedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        break;

      case BicepCurlPhase.curling:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = BicepCurlPhase.flexed;
          transitionReason = 'flexedReached';
          _peakFlexedTimestampMs = timestampMs;
        } else if (elbowAngleDeg >= config.curlingEnterDeg) {
          _phase = BicepCurlPhase.extended;
          transitionReason = 'incompleteCurlReturnedToExtended';
          _repStartTimestampMs = null;
        }
        break;

      case BicepCurlPhase.flexed:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          _peakFlexedTimestampMs = timestampMs;
        }

        if (elbowAngleDeg > config.loweringEnterDeg) {
          _phase = BicepCurlPhase.lowering;
          transitionReason = 'loweringStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case BicepCurlPhase.lowering:
        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = BicepCurlPhase.flexed;
          transitionReason = 'reFlexedDuringLowering';
          _extendedCandidateStartMs = null;
        } else if (elbowAngleDeg >= config.extendedEnterDeg) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs) {
              _completedReps++;
              newRepEvent = LatPulldownRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs: _peakFlexedTimestampMs ??
                    ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _minElbowAngleInCurrentRep,
                status: 'PROVISIONAL',
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else {
              transitionReason = 'repTooShortIgnored';
            }

            _phase = BicepCurlPhase.extended;
            _repStartTimestampMs = null;
            _peakFlexedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = 180.0;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return BicepCurlBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      elbowAngleDeg: elbowAngleDeg,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  void _abortInProgressCycle() {
    _phase = BicepCurlPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
  }
}

import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Push-up exercise state machine.
enum PushUpPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Plank lockout at top of push-up (elbow angle >= 150 deg).
  extended,

  /// Eccentric lowering phase (elbow angle < 135 deg toward floor).
  lowering,

  /// Bottom of push-up (elbow angle <= 95 deg).
  bottom,

  /// Concentric pushing phase (elbow angle > 110 deg back toward lockout).
  pushing,
}

/// Configuration parameters for Push-up rule-based state machine.
class PushUpBaselineConfig {
  final double extendedEnterDeg;
  final double loweringEnterDeg;
  final double bottomEnterDeg;
  final double pushingEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxAllowedGapMs;

  const PushUpBaselineConfig({
    this.extendedEnterDeg = 150.0,
    this.loweringEnterDeg = 135.0,
    this.bottomEnterDeg = 95.0,
    this.pushingEnterDeg = 110.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Push-up frame.
class PushUpBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final PushUpPhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const PushUpBaselineFrameResult({
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

/// Pure Dart causal rule-based state machine for Push-up repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Uses best-confidence elbow angle (Shoulder -> Elbow -> Wrist) in pixel space.
class PushUpBaseline {
  final PushUpBaselineConfig config;

  PushUpPhase _phase = PushUpPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _bottomReachedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  int _droppedNonMonotonicFrames = 0;

  PushUpBaseline({PushUpBaselineConfig? config})
      : config = config ?? const PushUpBaselineConfig();

  PushUpPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = PushUpPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _droppedNonMonotonicFrames = 0;
  }

  PushUpBaselineFrameResult processFrameFeatures(
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

  PushUpBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return PushUpBaselineFrameResult(
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
      return PushUpBaselineFrameResult(
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
        return PushUpBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: resetReason,
        );
      }

      return PushUpBaselineFrameResult(
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
      if (_phase != PushUpPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case PushUpPhase.notReady:
        if (elbowAngleDeg >= config.extendedEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = PushUpPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case PushUpPhase.extended:
        if (elbowAngleDeg < config.loweringEnterDeg) {
          _phase = PushUpPhase.lowering;
          transitionReason = 'loweringStarted';
          _repStartTimestampMs = timestampMs;
          _bottomReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        break;

      case PushUpPhase.lowering:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg <= config.bottomEnterDeg) {
          _phase = PushUpPhase.bottom;
          transitionReason = 'bottomReached';
          _bottomReachedTimestampMs = timestampMs;
        } else if (elbowAngleDeg >= config.loweringEnterDeg) {
          _phase = PushUpPhase.extended;
          transitionReason = 'incompleteDescentReturnedToExtended';
          _repStartTimestampMs = null;
        }
        break;

      case PushUpPhase.bottom:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          _bottomReachedTimestampMs = timestampMs;
        }

        if (elbowAngleDeg > config.pushingEnterDeg) {
          _phase = PushUpPhase.pushing;
          transitionReason = 'pushStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case PushUpPhase.pushing:
        if (elbowAngleDeg <= config.bottomEnterDeg) {
          _phase = PushUpPhase.bottom;
          transitionReason = 'reBottomedDuringPush';
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
                bottomTimestampMs: _bottomReachedTimestampMs ??
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

            _phase = PushUpPhase.extended;
            _repStartTimestampMs = null;
            _bottomReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = 180.0;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return PushUpBaselineFrameResult(
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
    _phase = PushUpPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
  }
}

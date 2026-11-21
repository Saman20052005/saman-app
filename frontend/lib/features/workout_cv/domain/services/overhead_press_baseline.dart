import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Overhead Press exercise state machine.
enum OverheadPressPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Starting rack position at shoulder height (elbow angle <= 95 deg).
  ready,

  /// Concentric pressing phase upward (elbow angle > 110 deg).
  pressing,

  /// Overhead lockout peak (elbow angle >= 150 deg and wrist above shoulder).
  lockout,

  /// Eccentric lowering phase back toward shoulder rack (elbow angle < 135 deg).
  lowering,
}

/// Configuration parameters for Overhead Press rule-based state machine.
class OverheadPressBaselineConfig {
  final double readyEnterDeg;
  final double pressingEnterDeg;
  final double lockoutEnterDeg;
  final double loweringEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxAllowedGapMs;

  const OverheadPressBaselineConfig({
    this.readyEnterDeg = 95.0,
    this.pressingEnterDeg = 110.0,
    this.lockoutEnterDeg = 150.0,
    this.loweringEnterDeg = 135.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Overhead Press frame.
class OverheadPressBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final OverheadPressPhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isWristAboveShoulder;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const OverheadPressBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.elbowAngleDeg,
    required this.isWristAboveShoulder,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal rule-based state machine for Overhead Press repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Transitions from shoulder rack (<= 95 deg) -> press (> 110 deg) ->
/// overhead lockout (>= 150 deg & wrist above shoulder) -> lower (< 135 deg) ->
/// return to shoulder rack (<= 95 deg).
class OverheadPressBaseline {
  final OverheadPressBaselineConfig config;

  OverheadPressPhase _phase = OverheadPressPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _lockoutReachedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  int _droppedNonMonotonicFrames = 0;

  OverheadPressBaseline({OverheadPressBaselineConfig? config})
      : config = config ?? const OverheadPressBaselineConfig();

  OverheadPressPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = OverheadPressPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _lockoutReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _droppedNonMonotonicFrames = 0;
  }

  OverheadPressBaselineFrameResult processFrameFeatures(
      MultiExerciseAngleFeatures features) {
    final isAngleValid = features.bestElbowAngleDeg.isValid;
    final angle = isAngleValid ? features.bestElbowAngleDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isWristAboveShoulder: features.isWristAboveShoulder,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  OverheadPressBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    required bool isWristAboveShoulder,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return OverheadPressBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isWristAboveShoulder: isWristAboveShoulder,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      const resetReason = 'gateNotDetecting';
      _abortInProgressCycle();
      return OverheadPressBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isWristAboveShoulder: false,
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
        return OverheadPressBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isWristAboveShoulder: false,
          isSampleValid: false,
          resetReason: resetReason,
        );
      }

      return OverheadPressBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isWristAboveShoulder: false,
        isSampleValid: false,
      );
    }

    String? gapResetReason;
    if (_lastValidTimestampMs != null &&
        (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
      if (_phase != OverheadPressPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case OverheadPressPhase.notReady:
        if (elbowAngleDeg <= config.readyEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = OverheadPressPhase.ready;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case OverheadPressPhase.ready:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        if (elbowAngleDeg > config.pressingEnterDeg) {
          _phase = OverheadPressPhase.pressing;
          transitionReason = 'pressStarted';
          _repStartTimestampMs = timestampMs;
          _lockoutReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
            _minElbowAngleInCurrentRep = elbowAngleDeg;
          }
        }
        break;

      case OverheadPressPhase.pressing:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg >= config.lockoutEnterDeg && isWristAboveShoulder) {
          _phase = OverheadPressPhase.lockout;
          transitionReason = 'lockoutReached';
          _lockoutReachedTimestampMs = timestampMs;
        } else if (elbowAngleDeg <= config.pressingEnterDeg) {
          _phase = OverheadPressPhase.ready;
          transitionReason = 'incompletePressReturnedToReady';
          _repStartTimestampMs = null;
        }
        break;

      case OverheadPressPhase.lockout:
        if (elbowAngleDeg < config.loweringEnterDeg) {
          _phase = OverheadPressPhase.lowering;
          transitionReason = 'loweringStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case OverheadPressPhase.lowering:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg >= config.lockoutEnterDeg && isWristAboveShoulder) {
          _phase = OverheadPressPhase.lockout;
          transitionReason = 'reLockedOutDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (elbowAngleDeg <= config.readyEnterDeg) {
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
                bottomTimestampMs: _lockoutReachedTimestampMs ??
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

            _phase = OverheadPressPhase.ready;
            _repStartTimestampMs = null;
            _lockoutReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = elbowAngleDeg;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return OverheadPressBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      elbowAngleDeg: elbowAngleDeg,
      isWristAboveShoulder: isWristAboveShoulder,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  void _abortInProgressCycle() {
    _phase = OverheadPressPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _lockoutReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
  }
}

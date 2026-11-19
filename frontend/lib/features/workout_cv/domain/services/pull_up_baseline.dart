import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Pull-up exercise state machine.
enum PullUpPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Arms extended overhead in the start/finish zone (elbow angle high).
  extended,

  /// Concentric pulling phase (elbow angle decreasing from extended toward flexed).
  pulling,

  /// Top of the pull (elbow angle low, arms flexed near torso).
  flexed,

  /// Eccentric returning phase (elbow angle increasing from flexed back toward extended).
  returning,
}

/// A completed rep event emitted when returning to the extended position.
class PullUpRepEvent extends LatPulldownRepEvent {
  const PullUpRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
  });
}

/// Configuration parameters for Pull-up rule-based state machine.
///
/// Uses explicit hysteresis bands and millisecond-based temporal guards (independent of FPS).
class PullUpBaselineConfig {
  /// Minimum 2D elbow angle (degrees) to enter extended zone.
  final double extendedEnterDeg;

  /// Elbow angle (degrees) below which pulling begins from extended position.
  final double pullingEnterDeg;

  /// Maximum 2D elbow angle (degrees) to enter flexed zone (top of pull-up).
  final double flexedEnterDeg;

  /// Elbow angle (degrees) above which eccentric return begins from flexed position.
  final double returningEnterDeg;

  /// Minimum time (ms) continuous in extension before transitioning from notReady to extended.
  final int minReadyHoldMs;

  /// Minimum time (ms) continuous in extension to confirm completed rep return.
  final int minExtendedHoldMs;

  /// Minimum duration (ms) from rep start to rep end (prevents noise spikes).
  final int minRepDurationMs;

  /// Maximum allowed duration (ms) of invalid samples or gap before in-progress cycle is aborted.
  final int maxAllowedGapMs;

  const PullUpBaselineConfig({
    this.extendedEnterDeg = 110.0,
    this.pullingEnterDeg = 100.0,
    this.flexedEnterDeg = 60.0,
    this.returningEnterDeg = 75.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed frame.
class PullUpBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final PullUpPhase phase;
  final int completedReps;
  final PullUpRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const PullUpBaselineFrameResult({
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

  @override
  String toString() =>
      'Frame $frameIndex @ ${timestampMs}ms: phase=${phase.name}, reps=$completedReps${newRepEvent != null ? " [NEW REP]" : ""}${transitionReason != null ? " ($transitionReason)" : ""}';
}

/// Pure Dart causal rule-based state machine for Pull-up repetition counting.
///
/// Operates strictly forward in time (no lookahead, no future frames, no offline smoothing).
/// Fixed to Model Left elbow angle (Model IDs 11-13-15).
class PullUpBaseline {
  final PullUpBaselineConfig config;

  PullUpPhase _phase = PullUpPhase.notReady;
  int _completedReps = 0;
  final List<PullUpRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;

  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _bottomReachedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  int _droppedNonMonotonicFrames = 0;

  PullUpBaseline({PullUpBaselineConfig? config})
      : config = config ?? const PullUpBaselineConfig();

  PullUpPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<PullUpRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  /// Resets state machine counters and history for a new replay or live session.
  void reset() {
    _phase = PullUpPhase.notReady;
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

  /// Processes a [LatPulldownFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  ///
  /// Uses Model Left elbow angle (IDs 11-13-15) as primary kinematic signal.
  PullUpBaselineFrameResult processFrameFeatures(
      LatPulldownFrameFeatures features) {
    final leftSide = features.leftSide;
    final isAngleValid = leftSide.elbowAngleDeg.isValid;
    final angle = isAngleValid ? leftSide.elbowAngleDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  /// Low-level causal processing step for a single kinematic sample.
  PullUpBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    // 1. Guard against non-monotonic timestamps (clock jitter or corrupted stream)
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return PullUpBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        newRepEvent: null,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    // 2. Gate failure / Data gap guard
    if (!isGateDetecting) {
      const resetReason = 'gateNotDetecting';
      _abortInProgressCycle(resetReason);
      return PullUpBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        newRepEvent: null,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        resetReason: resetReason,
      );
    }

    if (!isSampleValid || elbowAngleDeg == null || !elbowAngleDeg.isFinite) {
      // An invalid sample interrupts any continuous posture hold candidates
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      // Check gap duration since last valid sample
      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        const resetReason = 'dataLossGapExceeded';
        _abortInProgressCycle(resetReason);
        return PullUpBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          newRepEvent: null,
          elbowAngleDeg: null,
          isSampleValid: false,
          resetReason: resetReason,
        );
      }

      // Short invalid gap: do not advance phase, do not hold stale values to advance
      return PullUpBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        newRepEvent: null,
        elbowAngleDeg: null,
        isSampleValid: false,
      );
    }

    // Check gap since last valid sample even if this sample is valid
    if (_lastValidTimestampMs != null &&
        (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
      _abortInProgressCycle('dataLossGapBeforeValidSample');
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    PullUpRepEvent? newRepEvent;

    // 3. Causal FSM State Transitions
    switch (_phase) {
      case PullUpPhase.notReady:
        if (elbowAngleDeg >= config.extendedEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = PullUpPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case PullUpPhase.extended:
        if (elbowAngleDeg < config.pullingEnterDeg) {
          _phase = PullUpPhase.pulling;
          transitionReason = 'pullingStarted';
          _repStartTimestampMs = timestampMs;
          _bottomReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        break;

      case PullUpPhase.pulling:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = PullUpPhase.flexed;
          transitionReason = 'flexedReached';
          _bottomReachedTimestampMs = timestampMs;
        } else if (elbowAngleDeg >= config.pullingEnterDeg) {
          // Aborted pull before reaching flexed: return to extended without counting rep
          _phase = PullUpPhase.extended;
          transitionReason = 'incompletePullReturnedToExtended';
          _repStartTimestampMs = null;
        }
        break;

      case PullUpPhase.flexed:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          _bottomReachedTimestampMs = timestampMs;
        }

        if (elbowAngleDeg > config.returningEnterDeg) {
          _phase = PullUpPhase.returning;
          transitionReason = 'returnStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case PullUpPhase.returning:
        if (elbowAngleDeg <= config.flexedEnterDeg) {
          // Dip back into flexed zone
          _phase = PullUpPhase.flexed;
          transitionReason = 'reFlexedDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (elbowAngleDeg >= config.extendedEnterDeg) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs) {
              _completedReps++;
              newRepEvent = PullUpRepEvent(
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

            _phase = PullUpPhase.extended;
            _repStartTimestampMs = null;
            _bottomReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = 180.0;
          }
        } else {
          // Dropped below extendedEnterDeg while waiting for hold duration
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return PullUpBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      elbowAngleDeg: elbowAngleDeg,
      isSampleValid: true,
      transitionReason: transitionReason,
    );
  }

  void _abortInProgressCycle(String reason) {
    if (_phase != PullUpPhase.notReady) {
      _phase = PullUpPhase.notReady;
    }
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
  }
}

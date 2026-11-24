import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Squat exercise state machine.
enum SquatPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Standing upright at top of squat (knee angle >= 155 deg).
  standing,

  /// Eccentric lowering phase (knee angle < 140 deg toward bottom).
  descending,

  /// Bottom of the squat (knee angle <= 100 deg).
  bottom,

  /// Concentric rising phase (knee angle > 115 deg back toward standing).
  ascending,
}

/// A completed Squat rep event emitted when returning to the standing position.
class SquatRepEvent extends LatPulldownRepEvent {
  final double? maxTorsoLeanDeg;
  final double? minHipAngleDeg;
  final bool? isBackStraight;

  const SquatRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    this.maxTorsoLeanDeg,
    this.minHipAngleDeg,
    this.isBackStraight,
  });
}

/// Configuration parameters for Squat rule-based state machine.
///
/// Uses explicit hysteresis bands and millisecond-based temporal guards (independent of FPS).
class SquatBaselineConfig {
  final double standingEnterDeg;
  final double descendingEnterDeg;
  final double bottomEnterDeg;
  final double ascendingEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;
  final double maxStandingTorsoLeanDeg;
  final double minStandingHipAngleDeg;
  final double maxBottomHipAngleDeg;
  final double maxValidTorsoLeanDeg;
  final double maxPlausibleTorsoLeanDeg;

  const SquatBaselineConfig({
    this.standingEnterDeg = 155.0,
    this.descendingEnterDeg = 140.0,
    this.bottomEnterDeg = 100.0,
    this.ascendingEnterDeg = 115.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
    this.maxStandingTorsoLeanDeg = 35.0,
    this.minStandingHipAngleDeg = 140.0,
    this.maxBottomHipAngleDeg = 145.0,
    this.maxValidTorsoLeanDeg = 55.0,
    this.maxPlausibleTorsoLeanDeg = 75.0,
  });
}

/// Output record for a single processed Squat frame.
class SquatBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final SquatPhase phase;
  final int completedReps;
  final SquatRepEvent? newRepEvent;
  final double? kneeAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const SquatBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.kneeAngleDeg,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal rule-based state machine for Squat repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Uses best-confidence knee angle (Hip -> Knee -> Ankle), hip flexion angle,
/// and torso lean angle in pixel space.
class SquatBaseline {
  final SquatBaselineConfig config;

  SquatPhase _phase = SquatPhase.notReady;
  int _completedReps = 0;
  final List<SquatRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _bottomReachedTimestampMs;
  double _minKneeAngleInCurrentRep = 180.0;
  double? _maxTorsoLeanInCurrentRep;
  double? _minHipAngleInCurrentRep;
  int _droppedNonMonotonicFrames = 0;

  SquatBaseline({SquatBaselineConfig? config})
      : config = config ?? const SquatBaselineConfig();

  SquatPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<SquatRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = SquatPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minKneeAngleInCurrentRep = 180.0;
    _maxTorsoLeanInCurrentRep = null;
    _minHipAngleInCurrentRep = null;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes a [SquatFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  SquatBaselineFrameResult processSquatFeatures(SquatFrameFeatures features) {
    final isAngleValid = features.bestKneeAngleDeg.isValid;
    final angle = isAngleValid ? features.bestKneeAngleDeg.value : null;
    final hipAngle = features.bestHipAngleDeg.isValid
        ? features.bestHipAngleDeg.value
        : null;
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      kneeAngleDeg: angle,
      hipAngleDeg: hipAngle,
      torsoLeanDeg: torsoLean,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  SquatBaselineFrameResult processFrameFeatures(
      MultiExerciseAngleFeatures features) {
    final isAngleValid = features.bestKneeAngleDeg.isValid;
    final angle = isAngleValid ? features.bestKneeAngleDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      kneeAngleDeg: angle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  SquatBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? kneeAngleDeg,
    double? hipAngleDeg,
    double? torsoLeanDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return SquatBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        kneeAngleDeg: kneeAngleDeg,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      const resetReason = 'gateNotDetecting';
      _abortInProgressCycle();
      return SquatBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        kneeAngleDeg: kneeAngleDeg,
        isSampleValid: false,
        resetReason: resetReason,
      );
    }

    if (!isSampleValid || kneeAngleDeg == null || !kneeAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        const resetReason = 'dataLossGapExceeded';
        _abortInProgressCycle();
        return SquatBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: resetReason,
        );
      }

      return SquatBaselineFrameResult(
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
      if (_phase != SquatPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    SquatRepEvent? newRepEvent;

    final bool hipValidForBottom = hipAngleDeg == null ||
        !hipAngleDeg.isFinite ||
        hipAngleDeg <= config.maxBottomHipAngleDeg;
    final bool torsoValidForBottom = torsoLeanDeg == null ||
        !torsoLeanDeg.isFinite ||
        torsoLeanDeg <= config.maxPlausibleTorsoLeanDeg;

    switch (_phase) {
      case SquatPhase.notReady:
        if (kneeAngleDeg >= config.standingEnterDeg &&
            _isUprightForStanding(hipAngleDeg, torsoLeanDeg)) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = SquatPhase.standing;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
            _maxTorsoLeanInCurrentRep = null;
            _minHipAngleInCurrentRep = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case SquatPhase.standing:
        if (kneeAngleDeg < config.descendingEnterDeg) {
          _phase = SquatPhase.descending;
          transitionReason = 'descentStarted';
          _repStartTimestampMs = timestampMs;
          _bottomReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minKneeAngleInCurrentRep = kneeAngleDeg;
          _maxTorsoLeanInCurrentRep = null;
          _minHipAngleInCurrentRep = null;
          _updateCurrentRepUpperBodyMetrics(hipAngleDeg, torsoLeanDeg);
        }
        break;

      case SquatPhase.descending:
        if (kneeAngleDeg < _minKneeAngleInCurrentRep) {
          _minKneeAngleInCurrentRep = kneeAngleDeg;
        }
        _updateCurrentRepUpperBodyMetrics(hipAngleDeg, torsoLeanDeg);

        if (kneeAngleDeg <= config.bottomEnterDeg &&
            hipValidForBottom &&
            torsoValidForBottom) {
          _phase = SquatPhase.bottom;
          transitionReason = 'bottomReached';
          _bottomReachedTimestampMs = timestampMs;
        } else if (kneeAngleDeg >= config.descendingEnterDeg) {
          _phase = SquatPhase.standing;
          transitionReason = 'incompleteDescentReturnedToStanding';
          _repStartTimestampMs = null;
          _maxTorsoLeanInCurrentRep = null;
          _minHipAngleInCurrentRep = null;
        }
        break;

      case SquatPhase.bottom:
        if (kneeAngleDeg < _minKneeAngleInCurrentRep) {
          _minKneeAngleInCurrentRep = kneeAngleDeg;
          _bottomReachedTimestampMs = timestampMs;
        }
        _updateCurrentRepUpperBodyMetrics(hipAngleDeg, torsoLeanDeg);

        if (kneeAngleDeg > config.ascendingEnterDeg) {
          _phase = SquatPhase.ascending;
          transitionReason = 'ascentStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case SquatPhase.ascending:
        if (kneeAngleDeg < _minKneeAngleInCurrentRep) {
          _minKneeAngleInCurrentRep = kneeAngleDeg;
        }
        _updateCurrentRepUpperBodyMetrics(hipAngleDeg, torsoLeanDeg);

        if (kneeAngleDeg <= config.bottomEnterDeg &&
            hipValidForBottom &&
            torsoValidForBottom) {
          _phase = SquatPhase.bottom;
          transitionReason = 'reBottomedDuringAscent';
          _extendedCandidateStartMs = null;
        } else if (kneeAngleDeg >= config.standingEnterDeg) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs &&
                duration <= config.maxRepDurationMs) {
              _completedReps++;
              final isBackStraight = _maxTorsoLeanInCurrentRep != null
                  ? _maxTorsoLeanInCurrentRep! <= config.maxValidTorsoLeanDeg
                  : null;
              newRepEvent = SquatRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs: _bottomReachedTimestampMs ??
                    ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _minKneeAngleInCurrentRep,
                status: 'PROVISIONAL',
                maxTorsoLeanDeg: _maxTorsoLeanInCurrentRep,
                minHipAngleDeg: _minHipAngleInCurrentRep,
                isBackStraight: isBackStraight,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = SquatPhase.standing;
            _repStartTimestampMs = null;
            _bottomReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minKneeAngleInCurrentRep = 180.0;
            _maxTorsoLeanInCurrentRep = null;
            _minHipAngleInCurrentRep = null;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return SquatBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      kneeAngleDeg: kneeAngleDeg,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  bool _isUprightForStanding(double? hipAngleDeg, double? torsoLeanDeg) {
    if (torsoLeanDeg != null &&
        torsoLeanDeg.isFinite &&
        torsoLeanDeg > config.maxStandingTorsoLeanDeg) {
      return false;
    }
    if (hipAngleDeg != null &&
        hipAngleDeg.isFinite &&
        hipAngleDeg < config.minStandingHipAngleDeg) {
      return false;
    }
    return true;
  }

  void _updateCurrentRepUpperBodyMetrics(
    double? hipAngleDeg,
    double? torsoLeanDeg,
  ) {
    if (torsoLeanDeg != null && torsoLeanDeg.isFinite) {
      if (_maxTorsoLeanInCurrentRep == null ||
          torsoLeanDeg > _maxTorsoLeanInCurrentRep!) {
        _maxTorsoLeanInCurrentRep = torsoLeanDeg;
      }
    }
    if (hipAngleDeg != null && hipAngleDeg.isFinite) {
      if (_minHipAngleInCurrentRep == null ||
          hipAngleDeg < _minHipAngleInCurrentRep!) {
        _minHipAngleInCurrentRep = hipAngleDeg;
      }
    }
  }

  void _abortInProgressCycle() {
    _phase = SquatPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minKneeAngleInCurrentRep = 180.0;
    _maxTorsoLeanInCurrentRep = null;
    _minHipAngleInCurrentRep = null;
  }
}

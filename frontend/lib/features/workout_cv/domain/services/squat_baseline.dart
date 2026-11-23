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

  /// Bottom of the squat (knee angle <= 95 deg).
  bottom,

  /// Concentric rising phase (knee angle > 110 deg back toward standing).
  ascending,
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
  final int maxAllowedGapMs;

  const SquatBaselineConfig({
    this.standingEnterDeg = 155.0,
    this.descendingEnterDeg = 140.0,
    this.bottomEnterDeg = 95.0,
    this.ascendingEnterDeg = 110.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Squat frame.
class SquatBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final SquatPhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
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
/// Uses best-confidence knee angle (Hip -> Knee -> Ankle) in pixel space.
class SquatBaseline {
  final SquatBaselineConfig config;

  SquatPhase _phase = SquatPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _bottomReachedTimestampMs;
  double _minKneeAngleInCurrentRep = 180.0;
  int _droppedNonMonotonicFrames = 0;

  SquatBaseline({SquatBaselineConfig? config})
      : config = config ?? const SquatBaselineConfig();

  SquatPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
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
    _droppedNonMonotonicFrames = 0;
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
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case SquatPhase.notReady:
        if (kneeAngleDeg >= config.standingEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = SquatPhase.standing;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
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
        }
        break;

      case SquatPhase.descending:
        if (kneeAngleDeg < _minKneeAngleInCurrentRep) {
          _minKneeAngleInCurrentRep = kneeAngleDeg;
        }

        if (kneeAngleDeg <= config.bottomEnterDeg) {
          _phase = SquatPhase.bottom;
          transitionReason = 'bottomReached';
          _bottomReachedTimestampMs = timestampMs;
        } else if (kneeAngleDeg >= config.descendingEnterDeg) {
          _phase = SquatPhase.standing;
          transitionReason = 'incompleteDescentReturnedToStanding';
          _repStartTimestampMs = null;
        }
        break;

      case SquatPhase.bottom:
        if (kneeAngleDeg < _minKneeAngleInCurrentRep) {
          _minKneeAngleInCurrentRep = kneeAngleDeg;
          _bottomReachedTimestampMs = timestampMs;
        }

        if (kneeAngleDeg > config.ascendingEnterDeg) {
          _phase = SquatPhase.ascending;
          transitionReason = 'ascentStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case SquatPhase.ascending:
        if (kneeAngleDeg <= config.bottomEnterDeg) {
          _phase = SquatPhase.bottom;
          transitionReason = 'reBottomedDuringAscent';
          _extendedCandidateStartMs = null;
        } else if (kneeAngleDeg >= config.standingEnterDeg) {
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
                minElbowAngleDeg: _minKneeAngleInCurrentRep,
                status: 'PROVISIONAL',
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else {
              transitionReason = 'repTooShortIgnored';
            }

            _phase = SquatPhase.standing;
            _repStartTimestampMs = null;
            _bottomReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minKneeAngleInCurrentRep = 180.0;
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

  void _abortInProgressCycle() {
    _phase = SquatPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minKneeAngleInCurrentRep = 180.0;
  }
}

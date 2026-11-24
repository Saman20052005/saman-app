import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Face Pull exercise state machine.
enum FacePullPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Arms extended forward in start/finish zone (elbow angle >= 145 deg).
  extended,

  /// Concentric pulling phase toward face/ears (elbow angle < 130 deg).
  pulling,

  /// Peak contraction near face (elbow angle <= 85 deg).
  flexed,

  /// Eccentric returning phase back toward extension (elbow angle > 100 deg).
  returning,
}

/// A completed Face Pull rep event emitted when returning to extension.
class FacePullRepEvent extends LatPulldownRepEvent {
  final bool? isElbowHigh;

  const FacePullRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    this.isElbowHigh,
  });
}

/// Configuration parameters for [FacePullBaseline].
class FacePullBaselineConfig {
  final double extendedEnterDeg;
  final double pullingEnterDeg;
  final double flexedEnterDeg;
  final double returningEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;

  const FacePullBaselineConfig({
    this.extendedEnterDeg = 145.0,
    this.pullingEnterDeg = 130.0,
    this.flexedEnterDeg = 85.0,
    this.returningEnterDeg = 100.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Face Pull frame.
class FacePullBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final FacePullPhase phase;
  final int completedReps;
  final FacePullRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const FacePullBaselineFrameResult({
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

/// Pure Dart causal 5-phase FSM for Face Pull repetition counting.
///
/// Tracks elbow flexion (`Shoulder -> Elbow -> Wrist`) and verifies that
/// elbows stay raised at shoulder/face level during the pull (`isElbowHigh`).
class FacePullBaseline {
  final FacePullBaselineConfig config;

  FacePullPhase _phase = FacePullPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakFlexedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  bool _sawElbowHeightSample = false;
  bool _hadLowElbowInCurrentRep = false;
  int _droppedNonMonotonicFrames = 0;

  FacePullBaseline({FacePullBaselineConfig? config})
      : config = config ?? const FacePullBaselineConfig();

  FacePullPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = FacePullPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _sawElbowHeightSample = false;
    _hadLowElbowInCurrentRep = false;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes a [FacePullFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  FacePullBaselineFrameResult processFacePullFeatures(
    FacePullFrameFeatures features,
  ) {
    final isAngleValid = features.bestElbowAngleDeg.isValid;
    final angle = isAngleValid ? features.bestElbowAngleDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isElbowAtShoulderHeight: features.isElbowAtShoulderHeight,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  FacePullBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    bool? isElbowAtShoulderHeight,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return FacePullBaselineFrameResult(
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
      _abortInProgressCycle();
      return FacePullBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    if (!isSampleValid || elbowAngleDeg == null || !elbowAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        _abortInProgressCycle();
        return FacePullBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return FacePullBaselineFrameResult(
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
      if (_phase != FacePullPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    FacePullRepEvent? newRepEvent;

    switch (_phase) {
      case FacePullPhase.notReady:
        if (elbowAngleDeg >= config.extendedEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = FacePullPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case FacePullPhase.extended:
        if (elbowAngleDeg < config.pullingEnterDeg) {
          _phase = FacePullPhase.pulling;
          transitionReason = 'pullingStarted';
          _repStartTimestampMs = timestampMs;
          _peakFlexedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          _sawElbowHeightSample = false;
          _hadLowElbowInCurrentRep = false;
          _recordElbowHeight(isElbowAtShoulderHeight);
        }
        break;

      case FacePullPhase.pulling:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        _recordElbowHeight(isElbowAtShoulderHeight);

        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = FacePullPhase.flexed;
          transitionReason = 'flexedReached';
          _peakFlexedTimestampMs = timestampMs;
        } else if (elbowAngleDeg >= config.pullingEnterDeg) {
          _phase = FacePullPhase.extended;
          transitionReason = 'incompletePullReturnedToExtended';
          _clearCurrentRepMetrics();
        }
        break;

      case FacePullPhase.flexed:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          _peakFlexedTimestampMs = timestampMs;
        }
        _recordElbowHeight(isElbowAtShoulderHeight);

        if (elbowAngleDeg > config.returningEnterDeg) {
          _phase = FacePullPhase.returning;
          transitionReason = 'returningStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case FacePullPhase.returning:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = FacePullPhase.flexed;
          transitionReason = 'reFlexedDuringReturn';
          _extendedCandidateStartMs = null;
          _recordElbowHeight(isElbowAtShoulderHeight);
        } else if (elbowAngleDeg >= config.extendedEnterDeg) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs &&
                duration <= config.maxRepDurationMs) {
              _completedReps++;
              final bool? isElbowHigh = _sawElbowHeightSample
                  ? !_hadLowElbowInCurrentRep
                  : null;
              newRepEvent = FacePullRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs:
                    _peakFlexedTimestampMs ?? ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _minElbowAngleInCurrentRep,
                status: 'PROVISIONAL',
                isElbowHigh: isElbowHigh,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = FacePullPhase.extended;
            _clearCurrentRepMetrics();
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return FacePullBaselineFrameResult(
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

  void _recordElbowHeight(bool? isElbowAtShoulderHeight) {
    if (isElbowAtShoulderHeight == null) return;
    _sawElbowHeightSample = true;
    if (!isElbowAtShoulderHeight) {
      _hadLowElbowInCurrentRep = true;
    }
  }

  void _clearCurrentRepMetrics() {
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _extendedCandidateStartMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _sawElbowHeightSample = false;
    _hadLowElbowInCurrentRep = false;
  }

  void _abortInProgressCycle() {
    _phase = FacePullPhase.notReady;
    _readyCandidateStartMs = null;
    _clearCurrentRepMetrics();
  }
}

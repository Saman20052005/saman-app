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
  final bool? isChinCleared;

  const PullUpRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    super.viewAngle = CameraViewAngle.unknown,
    super.issueCode,
    this.isChinCleared,
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

  /// Whether wrists must be above shoulders to enter/stay in extended dead-hang state.
  final bool requireWristAboveShoulder;

  /// Whether reaching top/bar-clearance position is required to transition pulling -> flexed.
  final bool requireTopPositionForFlexed;

  /// Whether causal EMA smoothing is applied to incoming elbow angles.
  final bool enableAngleSmoothing;

  /// Smoothing factor for [AngleSmoother] when [enableAngleSmoothing] is true.
  final double smoothingAlpha;

  const PullUpBaselineConfig({
    this.extendedEnterDeg = 115.0,
    this.pullingEnterDeg = 100.0,
    this.flexedEnterDeg = 65.0,
    this.returningEnterDeg = 80.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 900,
    this.maxAllowedGapMs = 500,
    this.requireWristAboveShoulder = true,
    this.requireTopPositionForFlexed = true,
    this.enableAngleSmoothing = false,
    this.smoothingAlpha = 0.50,
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
/// Automatically selects the highest-visibility side's elbow angle.
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
  double _maxReturnElbowAngleInCurrentRep = 0.0;
  bool? _anyChinClearedInRep;
  bool _reachedFlexedAngleWithoutTop = false;
  int _droppedNonMonotonicFrames = 0;
  late final AngleSmoother _angleSmoother = AngleSmoother(
    alpha: config.smoothingAlpha,
    maxGapMs: config.maxAllowedGapMs,
  );

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
    _maxReturnElbowAngleInCurrentRep = 0.0;
    _anyChinClearedInRep = null;
    _reachedFlexedAngleWithoutTop = false;
    _droppedNonMonotonicFrames = 0;
    _angleSmoother.reset();
  }

  /// Processes a [PullUpFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  PullUpBaselineFrameResult processPullUpFeatures(
      PullUpFrameFeatures features) {
    final bestAngle = features.bestElbowAngleDeg;
    final isAngleValid = bestAngle.isValid;
    final angle = isAngleValid ? bestAngle.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
      isWristAboveShoulder: features.isWristAboveShoulder,
      isTopPositionReached: features.isTopPositionReached,
      isChinCleared: features.isChinCleared,
      viewAngle: features.viewAngle,
    );
  }

  /// Processes a [LatPulldownFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  ///
  /// Uses the highest-visibility side's elbow angle (`features.bestElbowAngleDeg`)
  /// as primary kinematic signal.
  PullUpBaselineFrameResult processFrameFeatures(
      LatPulldownFrameFeatures features) {
    final bestAngle = features.bestElbowAngleDeg;
    final isAngleValid = bestAngle.isValid;
    final angle = isAngleValid ? bestAngle.value : null;
    final wristRelY = features.bestSide.wristRelY;
    final wristAboveShoulder =
        wristRelY.isValid ? (wristRelY.value! < 0.0) : true;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
      isWristAboveShoulder: wristAboveShoulder,
      isTopPositionReached: true,
      viewAngle: features.viewAngle,
    );
  }

  /// Low-level causal processing step for a single kinematic sample.
  PullUpBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
    bool isWristAboveShoulder = true,
    bool isTopPositionReached = true,
    bool? isChinCleared,
    CameraViewAngle viewAngle = CameraViewAngle.unknown,
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
      if (config.enableAngleSmoothing) {
        _angleSmoother.smooth(timestampMs: timestampMs, rawAngleDeg: null);
      }

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
    String? gapResetReason;
    if (_lastValidTimestampMs != null &&
        (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
      if (_phase != PullUpPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle('dataLossGapBeforeValidSample');
    }
    _lastValidTimestampMs = timestampMs;

    final effectiveAngle = config.enableAngleSmoothing
        ? (_angleSmoother.smooth(
              timestampMs: timestampMs,
              rawAngleDeg: elbowAngleDeg,
            ) ??
            elbowAngleDeg)
        : elbowAngleDeg;
    final flexionOffset =
        ViewAngleProjectionHelper.elbowFlexionOffsetDeg(viewAngle);
    final extensionOffset =
        ViewAngleProjectionHelper.elbowExtensionOffsetDeg(viewAngle);
    final effectiveFlexedEnter = config.flexedEnterDeg + flexionOffset;
    final effectiveExtendedEnter = config.extendedEnterDeg + extensionOffset;

    String? transitionReason;
    PullUpRepEvent? newRepEvent;
    final bool wristReady =
        !config.requireWristAboveShoulder || isWristAboveShoulder;
    final bool topReady =
        !config.requireTopPositionForFlexed || isTopPositionReached;

    // 3. Causal FSM State Transitions
    switch (_phase) {
      case PullUpPhase.notReady:
        if (effectiveAngle >= effectiveExtendedEnter && wristReady) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = PullUpPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
            _anyChinClearedInRep = null;
            _reachedFlexedAngleWithoutTop = false;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case PullUpPhase.extended:
        if (config.requireWristAboveShoulder && !isWristAboveShoulder) {
          _phase = PullUpPhase.notReady;
          transitionReason = 'droppedFromBar';
          _readyCandidateStartMs = null;
          _extendedCandidateStartMs = null;
          _repStartTimestampMs = null;
          _anyChinClearedInRep = null;
          _reachedFlexedAngleWithoutTop = false;
        } else if (effectiveAngle < config.pullingEnterDeg) {
          _phase = PullUpPhase.pulling;
          transitionReason = 'pullingStarted';
          _repStartTimestampMs = timestampMs;
          _bottomReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = effectiveAngle;
          _maxReturnElbowAngleInCurrentRep = 0.0;
          _anyChinClearedInRep = null;
          _reachedFlexedAngleWithoutTop = false;
        }
        break;

      case PullUpPhase.pulling:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
        }
        if (isTopPositionReached || effectiveAngle <= effectiveFlexedEnter) {
          _updateChinCleared(isChinCleared);
        }

        if (effectiveAngle <= effectiveFlexedEnter && topReady) {
          _phase = PullUpPhase.flexed;
          transitionReason = 'flexedReached';
          _bottomReachedTimestampMs = timestampMs;
          _reachedFlexedAngleWithoutTop = false;
        } else {
          if (effectiveAngle <= effectiveFlexedEnter && !topReady) {
            _reachedFlexedAngleWithoutTop = true;
          }
          if (effectiveAngle >= config.pullingEnterDeg) {
            // Aborted pull before reaching flexed/top: return to extended without counting rep
            _phase = PullUpPhase.extended;
            transitionReason = _reachedFlexedAngleWithoutTop
                ? 'incompletePullChinNotCleared'
                : 'incompletePullReturnedToExtended';
            _repStartTimestampMs = null;
            _anyChinClearedInRep = null;
            _reachedFlexedAngleWithoutTop = false;
          }
        }
        break;

      case PullUpPhase.flexed:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
          _bottomReachedTimestampMs = timestampMs;
        }
        _updateChinCleared(isChinCleared);

        if (effectiveAngle > config.returningEnterDeg) {
          _phase = PullUpPhase.returning;
          transitionReason = 'returnStarted';
          _extendedCandidateStartMs = null;
          _maxReturnElbowAngleInCurrentRep = effectiveAngle;
        }
        break;

      case PullUpPhase.returning:
        if (effectiveAngle > _maxReturnElbowAngleInCurrentRep) {
          _maxReturnElbowAngleInCurrentRep = effectiveAngle;
        }
        if (effectiveAngle <= effectiveFlexedEnter && topReady) {
          // Dip back into flexed zone
          _phase = PullUpPhase.flexed;
          transitionReason = 'reFlexedDuringReturn';
          _extendedCandidateStartMs = null;
          _maxReturnElbowAngleInCurrentRep = 0.0;
          _updateChinCleared(isChinCleared);
        } else if (effectiveAngle >= effectiveExtendedEnter && wristReady) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs) {
              _completedReps++;
              final String? issueCode;
              if (_anyChinClearedInRep == false) {
                issueCode = 'chinNotCleared';
              } else if (duration < 1500) {
                issueCode = 'tooFast';
              } else if (_minElbowAngleInCurrentRep > 65.0 + flexionOffset) {
                issueCode = 'shallowDepth';
              } else if (viewAngle == CameraViewAngle.side90 &&
                  _maxReturnElbowAngleInCurrentRep < 130.0) {
                issueCode = 'incompleteLockout';
              } else {
                issueCode = null;
              }
              newRepEvent = PullUpRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs: _bottomReachedTimestampMs ??
                    ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _minElbowAngleInCurrentRep,
                status: 'PROVISIONAL',
                viewAngle: viewAngle,
                issueCode: issueCode,
                isChinCleared: _anyChinClearedInRep,
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
            _maxReturnElbowAngleInCurrentRep = 0.0;
            _anyChinClearedInRep = null;
            _reachedFlexedAngleWithoutTop = false;
          }
        } else {
          // Dropped below extendedEnterDeg or wrist dropped below shoulder while waiting for hold duration
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
      elbowAngleDeg: effectiveAngle,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  void _updateChinCleared(bool? isChinCleared) {
    if (isChinCleared == null) return;
    if (_anyChinClearedInRep == true) return;
    _anyChinClearedInRep = isChinCleared;
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
    _maxReturnElbowAngleInCurrentRep = 0.0;
    _anyChinClearedInRep = null;
    _reachedFlexedAngleWithoutTop = false;
    _angleSmoother.reset();
  }
}

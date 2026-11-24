import 'package:flutter/foundation.dart';

import 'workout_cv_motion_features.dart';

/// Operational phases for the Lat Pulldown exercise state machine.
enum LatPulldownPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Arms extended overhead in the start/finish zone (elbow angle high).
  extended,

  /// Concentric pulling phase (elbow angle decreasing from extended toward flexed).
  pulling,

  /// Bottom of the pull (elbow angle low, arms flexed near torso).
  flexed,

  /// Eccentric returning phase (elbow angle increasing from flexed back toward extended).
  returning,
}

/// A completed rep event emitted when returning to the extended position.
class LatPulldownRepEvent {
  final int repNumber;
  final int startTimestampMs;
  final int bottomTimestampMs;
  final int endTimestampMs;
  final int durationMs;
  final double minElbowAngleDeg;

  /// Candidate label designation. As required by protocol, machine proposals are PROVISIONAL
  /// until confirmed by human ground truth.
  final String status;

  /// Camera view angle under which this rep was recorded.
  final CameraViewAngle viewAngle;

  /// Optional machine-classified form/tempo issue code for RepRecord mapping.
  final String? issueCode;

  const LatPulldownRepEvent({
    required this.repNumber,
    required this.startTimestampMs,
    required this.bottomTimestampMs,
    required this.endTimestampMs,
    required this.durationMs,
    required this.minElbowAngleDeg,
    this.status = 'PROVISIONAL',
    this.viewAngle = CameraViewAngle.unknown,
    this.issueCode,
  });

  @override
  String toString() =>
      'Rep #$repNumber [$status]: ${startTimestampMs}ms -> bottom:${bottomTimestampMs}ms -> end:${endTimestampMs}ms (${durationMs}ms, minAngle:${minElbowAngleDeg.toStringAsFixed(1)} deg)';
}

/// Configuration parameters for Lat Pulldown rule-based state machine.
///
/// Uses explicit hysteresis bands and millisecond-based temporal guards (independent of FPS).
class LatPulldownBaselineConfig {
  /// Minimum 2D elbow angle (degrees) to enter extended zone.
  final double extendedEnterDeg;

  /// Elbow angle (degrees) below which pulling begins from extended position.
  final double pullingEnterDeg;

  /// Maximum 2D elbow angle (degrees) to enter flexed zone (bottom of pull).
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

  /// Whether causal EMA smoothing is applied to incoming elbow angles.
  final bool enableAngleSmoothing;

  /// Smoothing factor for [AngleSmoother] when [enableAngleSmoothing] is true.
  final double smoothingAlpha;

  /// Maximum valid torso lean angle (degrees) before flagging torsoLean.
  final double maxValidTorsoLeanDeg;

  const LatPulldownBaselineConfig({
    this.extendedEnterDeg = 105.0,
    this.pullingEnterDeg = 95.0,
    this.flexedEnterDeg = 55.0,
    this.returningEnterDeg = 68.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxAllowedGapMs = 500,
    this.enableAngleSmoothing = false,
    this.smoothingAlpha = 0.50,
    this.maxValidTorsoLeanDeg = 35.0,
  });
}

/// Output record for a single processed frame.
class LatPulldownBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final LatPulldownPhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const LatPulldownBaselineFrameResult({
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

/// Pure Dart causal rule-based state machine for Lat Pulldown repetition counting.
///
/// Operates strictly forward in time (no lookahead, no future frames, no offline smoothing).
/// Automatically selects the highest-visibility side's elbow angle.
class LatPulldownBaseline {
  final LatPulldownBaselineConfig config;

  LatPulldownPhase _phase = LatPulldownPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;

  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _bottomReachedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  double? _maxTorsoLeanInCurrentRep;
  String? _lockedSide;
  int _droppedNonMonotonicFrames = 0;
  late final AngleSmoother _angleSmoother = AngleSmoother(
    alpha: config.smoothingAlpha,
    maxGapMs: config.maxAllowedGapMs,
  );

  LatPulldownBaseline({LatPulldownBaselineConfig? config})
      : config = config ?? const LatPulldownBaselineConfig();

  LatPulldownPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  /// Resets state machine counters and history for a new replay or live session.
  void reset() {
    _phase = LatPulldownPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _maxTorsoLeanInCurrentRep = null;
    _lockedSide = null;
    _droppedNonMonotonicFrames = 0;
    _angleSmoother.reset();
  }

  /// Processes a [LatPulldownFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  ///
  /// Uses [ViewAngleProjectionHelper.selectBestLockedSide] to pick and stabilize
  /// the highest-visibility side for oblique/side viewpoints.
  LatPulldownBaselineFrameResult processFrameFeatures(
      LatPulldownFrameFeatures features) {
    final leftValid = features.leftSide.elbowAngleDeg.isValid &&
        features.leftSide.elbowAngleDeg.value != null &&
        features.leftSide.elbowAngleDeg.value!.isFinite;
    final rightValid = features.rightSide.elbowAngleDeg.isValid &&
        features.rightSide.elbowAngleDeg.value != null &&
        features.rightSide.elbowAngleDeg.value!.isFinite;
    final leftScore = leftValid
        ? (features.leftSide.elbowVisibilityScore > 0.0
            ? features.leftSide.elbowVisibilityScore
            : 1.0)
        : 0.0;
    final rightScore = rightValid
        ? (features.rightSide.elbowVisibilityScore > 0.0
            ? features.rightSide.elbowVisibilityScore
            : 1.0)
        : 0.0;

    final selectedSide = ViewAngleProjectionHelper.selectBestLockedSide(
      leftScore: leftScore,
      rightScore: rightScore,
      lockedSide: _lockedSide,
      viewAngle: features.viewAngle,
    );
    if (selectedSide != 'none') {
      _lockedSide = selectedSide;
    }

    final LatPulldownSideFeatures activeSide;
    if (selectedSide == 'right') {
      activeSide = features.rightSide;
    } else if (selectedSide == 'left') {
      activeSide = features.leftSide;
    } else {
      activeSide = features.bestSide;
    }

    final bestAngle = activeSide.elbowAngleDeg;
    final isAngleValid = bestAngle.isValid;
    final angle = isAngleValid ? bestAngle.value : null;
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      torsoLeanDeg: torsoLean,
      viewAngle: features.viewAngle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  /// Low-level causal processing step for a single kinematic sample.
  LatPulldownBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    double? torsoLeanDeg,
    CameraViewAngle viewAngle = CameraViewAngle.unknown,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    // 1. Guard against non-monotonic timestamps (clock jitter or corrupted stream)
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return LatPulldownBaselineFrameResult(
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
      return LatPulldownBaselineFrameResult(
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
        return LatPulldownBaselineFrameResult(
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
      return LatPulldownBaselineFrameResult(
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
    LatPulldownRepEvent? newRepEvent;

    // 3. Causal FSM State Transitions
    switch (_phase) {
      case LatPulldownPhase.notReady:
        if (effectiveAngle >= effectiveExtendedEnter) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = LatPulldownPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
            _maxTorsoLeanInCurrentRep = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case LatPulldownPhase.extended:
        if (effectiveAngle < config.pullingEnterDeg) {
          _phase = LatPulldownPhase.pulling;
          transitionReason = 'pullingStarted';
          _repStartTimestampMs = timestampMs;
          _bottomReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = effectiveAngle;
          _maxTorsoLeanInCurrentRep = null;
          _updateTorsoLean(torsoLeanDeg);
        }
        break;

      case LatPulldownPhase.pulling:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
        }
        _updateTorsoLean(torsoLeanDeg);

        if (effectiveAngle <= effectiveFlexedEnter) {
          _phase = LatPulldownPhase.flexed;
          transitionReason = 'flexedReached';
          _bottomReachedTimestampMs = timestampMs;
        } else if (effectiveAngle >= config.pullingEnterDeg) {
          // Aborted pull before reaching flexed: return to extended without counting rep
          _phase = LatPulldownPhase.extended;
          transitionReason = 'incompletePullReturnedToExtended';
          _repStartTimestampMs = null;
          _maxTorsoLeanInCurrentRep = null;
        }
        break;

      case LatPulldownPhase.flexed:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
          _bottomReachedTimestampMs = timestampMs;
        }
        _updateTorsoLean(torsoLeanDeg);

        if (effectiveAngle > config.returningEnterDeg) {
          _phase = LatPulldownPhase.returning;
          transitionReason = 'returnStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case LatPulldownPhase.returning:
        _updateTorsoLean(torsoLeanDeg);
        if (effectiveAngle <= effectiveFlexedEnter) {
          // Dip back into flexed zone
          _phase = LatPulldownPhase.flexed;
          transitionReason = 'reFlexedDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (effectiveAngle >= effectiveExtendedEnter) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs) {
              _completedReps++;
              final repCount = _completedReps;
              final startMs = repStart;
              final bottomMs = _bottomReachedTimestampMs ??
                  ((repStart + timestampMs) ~/ 2);
              final endMs = timestampMs;
              final durationMs = endMs - startMs;
              final minElbowDeg = _minElbowAngleInCurrentRep;

              final String? issueCode;
              if (_maxTorsoLeanInCurrentRep != null &&
                  _maxTorsoLeanInCurrentRep! > config.maxValidTorsoLeanDeg) {
                issueCode = 'torsoLean';
              } else if (durationMs < 2000) {
                issueCode = 'tooFast';
              } else if (minElbowDeg >= 45.0 + flexionOffset) {
                issueCode = 'shallowDepth';
              } else {
                issueCode = null;
              }

              debugPrint(
                  'CSV_QA: LAT_PULLDOWN, $repCount, $startMs, $bottomMs, $endMs, $durationMs, $minElbowDeg');

              newRepEvent = LatPulldownRepEvent(
                repNumber: repCount,
                startTimestampMs: startMs,
                bottomTimestampMs: bottomMs,
                endTimestampMs: endMs,
                durationMs: durationMs,
                minElbowAngleDeg: minElbowDeg,
                status: 'PROVISIONAL',
                viewAngle: viewAngle,
                issueCode: issueCode,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else {
              transitionReason = 'repTooShortIgnored';
            }

            _phase = LatPulldownPhase.extended;
            _repStartTimestampMs = null;
            _bottomReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = 180.0;
            _maxTorsoLeanInCurrentRep = null;
          }
        } else {
          // Dropped below extendedEnterDeg while waiting for hold duration
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return LatPulldownBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      elbowAngleDeg: effectiveAngle,
      isSampleValid: true,
      transitionReason: transitionReason,
    );
  }

  void _updateTorsoLean(double? torsoLeanDeg) {
    if (torsoLeanDeg != null && torsoLeanDeg.isFinite) {
      if (_maxTorsoLeanInCurrentRep == null ||
          torsoLeanDeg > _maxTorsoLeanInCurrentRep!) {
        _maxTorsoLeanInCurrentRep = torsoLeanDeg;
      }
    }
  }

  void _abortInProgressCycle(String reason) {
    if (_phase != LatPulldownPhase.notReady) {
      _phase = LatPulldownPhase.notReady;
    }
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _maxTorsoLeanInCurrentRep = null;
    _lockedSide = null;
    _angleSmoother.reset();
  }
}

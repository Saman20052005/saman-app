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

  /// Bottom of push-up (elbow angle <= 100 deg).
  bottom,

  /// Concentric pushing phase (elbow angle > 115 deg back toward lockout).
  pushing,
}

/// A completed Push-up rep event emitted when returning to the extended plank position.
class PushUpRepEvent extends LatPulldownRepEvent {
  final double? minBodyAlignmentDeg;
  final bool? isPlankAligned;

  const PushUpRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    super.viewAngle = CameraViewAngle.unknown,
    super.issueCode,
    this.minBodyAlignmentDeg,
    this.isPlankAligned,
  });
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
  final int maxRepDurationMs;
  final int maxAllowedGapMs;
  final double minHorizontalTorsoLeanDeg;
  final double minValidBodyAlignmentDeg;
  final double minPlausibleBodyAlignmentDeg;
  final bool enableAngleSmoothing;
  final double smoothingAlpha;

  const PushUpBaselineConfig({
    this.extendedEnterDeg = 150.0,
    this.loweringEnterDeg = 135.0,
    this.bottomEnterDeg = 100.0,
    this.pushingEnterDeg = 115.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 10000,
    this.maxAllowedGapMs = 500,
    this.minHorizontalTorsoLeanDeg = 45.0,
    this.minValidBodyAlignmentDeg = 155.0,
    this.minPlausibleBodyAlignmentDeg = 120.0,
    this.enableAngleSmoothing = false,
    this.smoothingAlpha = 0.50,
  });
}

/// Output record for a single processed Push-up frame.
class PushUpBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final PushUpPhase phase;
  final int completedReps;
  final PushUpRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isSampleValid;
  final bool isFrontalAngleWarning;
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
    this.isFrontalAngleWarning = false,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal rule-based state machine for Push-up repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Uses best-confidence elbow angle (Shoulder -> Elbow -> Wrist), torso lean,
/// and Shoulder -> Hip -> Ankle alignment in pixel space.
class PushUpBaseline {
  final PushUpBaselineConfig config;

  PushUpPhase _phase = PushUpPhase.notReady;
  int _completedReps = 0;
  final List<PushUpRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _bottomReachedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  double? _minBodyAlignmentInCurrentRep;
  int _droppedNonMonotonicFrames = 0;
  late final AngleSmoother _angleSmoother = AngleSmoother(
    alpha: config.smoothingAlpha,
    maxGapMs: config.maxAllowedGapMs,
  );

  PushUpBaseline({PushUpBaselineConfig? config})
      : config = config ?? const PushUpBaselineConfig();

  PushUpPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<PushUpRepEvent> get repHistory => List.unmodifiable(_repHistory);
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
    _minBodyAlignmentInCurrentRep = null;
    _droppedNonMonotonicFrames = 0;
    _angleSmoother.reset();
  }

  /// Processes a [PushUpFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  PushUpBaselineFrameResult processPushUpFeatures(PushUpFrameFeatures features) {
    final isAngleValid = features.bestElbowAngleDeg.isValid;
    final angle = isAngleValid ? features.bestElbowAngleDeg.value : null;
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;
    final bodyAlignment = features.bodyAlignmentDeg.isValid
        ? features.bodyAlignmentDeg.value
        : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      torsoLeanDeg: torsoLean,
      bodyAlignmentDeg: bodyAlignment,
      viewAngle: features.viewAngle,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
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
    double? torsoLeanDeg,
    double? bodyAlignmentDeg,
    CameraViewAngle viewAngle = CameraViewAngle.unknown,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    final isFrontalWarning = viewAngle == CameraViewAngle.frontal;

    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return PushUpBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        isFrontalAngleWarning: isFrontalWarning,
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
        isFrontalAngleWarning: isFrontalWarning,
        resetReason: resetReason,
      );
    }

    if (!isSampleValid || elbowAngleDeg == null || !elbowAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;
      if (config.enableAngleSmoothing) {
        _angleSmoother.smooth(timestampMs: timestampMs, rawAngleDeg: null);
      }

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
          isFrontalAngleWarning: isFrontalWarning,
          resetReason: resetReason,
        );
      }

      return PushUpBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isSampleValid: false,
        isFrontalAngleWarning: isFrontalWarning,
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
    final effectiveBottomEnter = config.bottomEnterDeg + flexionOffset;
    final effectivePushingEnter = config.pushingEnterDeg + flexionOffset;
    final effectiveExtendedEnter = config.extendedEnterDeg + extensionOffset;

    String? transitionReason;
    PushUpRepEvent? newRepEvent;

    switch (_phase) {
      case PushUpPhase.notReady:
        if (effectiveAngle >= effectiveExtendedEnter &&
            _isPlankPosture(torsoLeanDeg, bodyAlignmentDeg)) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = PushUpPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
            _minBodyAlignmentInCurrentRep = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case PushUpPhase.extended:
        if (!_isPlankPosture(torsoLeanDeg, bodyAlignmentDeg)) {
          _phase = PushUpPhase.notReady;
          transitionReason = 'leftPlankPosture';
          _readyCandidateStartMs = null;
          _extendedCandidateStartMs = null;
          _repStartTimestampMs = null;
          _minBodyAlignmentInCurrentRep = null;
        } else if (effectiveAngle < config.loweringEnterDeg) {
          _phase = PushUpPhase.lowering;
          transitionReason = 'loweringStarted';
          _repStartTimestampMs = timestampMs;
          _bottomReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = effectiveAngle;
          _minBodyAlignmentInCurrentRep = null;
          _updateCurrentRepBodyAlignment(bodyAlignmentDeg);
        }
        break;

      case PushUpPhase.lowering:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
        }
        _updateCurrentRepBodyAlignment(bodyAlignmentDeg);

        if (effectiveAngle <= effectiveBottomEnter) {
          _phase = PushUpPhase.bottom;
          transitionReason = 'bottomReached';
          _bottomReachedTimestampMs = timestampMs;
        } else if (effectiveAngle >= config.loweringEnterDeg) {
          _phase = PushUpPhase.extended;
          transitionReason = 'incompleteDescentReturnedToExtended';
          _repStartTimestampMs = null;
          _minBodyAlignmentInCurrentRep = null;
        }
        break;

      case PushUpPhase.bottom:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
          _bottomReachedTimestampMs = timestampMs;
        }
        _updateCurrentRepBodyAlignment(bodyAlignmentDeg);

        if (effectiveAngle > effectivePushingEnter) {
          _phase = PushUpPhase.pushing;
          transitionReason = 'pushStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case PushUpPhase.pushing:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
        }
        _updateCurrentRepBodyAlignment(bodyAlignmentDeg);

        if (effectiveAngle <= effectiveBottomEnter) {
          _phase = PushUpPhase.bottom;
          transitionReason = 'reBottomedDuringPush';
          _extendedCandidateStartMs = null;
        } else if (effectiveAngle >= effectiveExtendedEnter) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;
            final isPlankNow = _isPlankPosture(torsoLeanDeg, bodyAlignmentDeg);

            if (duration >= config.minRepDurationMs &&
                duration <= config.maxRepDurationMs &&
                isPlankNow) {
              _completedReps++;
              final isPlankAligned = _minBodyAlignmentInCurrentRep != null
                  ? _minBodyAlignmentInCurrentRep! >=
                      config.minValidBodyAlignmentDeg
                  : null;
              final String? issueCode;
              if (isFrontalWarning) {
                issueCode = 'frontalAngleWarning';
              } else if (isPlankAligned == false) {
                issueCode = 'hipSag';
              } else if (duration < 1200) {
                issueCode = 'tooFast';
              } else if (_minElbowAngleInCurrentRep > 95.0 + flexionOffset) {
                issueCode = 'shallowDepth';
              } else {
                issueCode = null;
              }
              newRepEvent = PushUpRepEvent(
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
                minBodyAlignmentDeg: _minBodyAlignmentInCurrentRep,
                isPlankAligned: isPlankAligned,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else if (duration > config.maxRepDurationMs) {
              transitionReason = 'repTooLongIgnored';
            } else {
              transitionReason = 'leftPlankPosture';
            }

            _phase = isPlankNow ? PushUpPhase.extended : PushUpPhase.notReady;
            _repStartTimestampMs = null;
            _bottomReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = 180.0;
            _minBodyAlignmentInCurrentRep = null;
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
      elbowAngleDeg: effectiveAngle,
      isSampleValid: true,
      isFrontalAngleWarning: isFrontalWarning,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  bool _isPlankPosture(double? torsoLeanDeg, double? bodyAlignmentDeg) {
    if (torsoLeanDeg != null &&
        torsoLeanDeg.isFinite &&
        torsoLeanDeg < config.minHorizontalTorsoLeanDeg) {
      return false;
    }
    if (bodyAlignmentDeg != null &&
        bodyAlignmentDeg.isFinite &&
        bodyAlignmentDeg < config.minPlausibleBodyAlignmentDeg) {
      return false;
    }
    return true;
  }

  void _updateCurrentRepBodyAlignment(double? bodyAlignmentDeg) {
    if (bodyAlignmentDeg != null && bodyAlignmentDeg.isFinite) {
      if (_minBodyAlignmentInCurrentRep == null ||
          bodyAlignmentDeg < _minBodyAlignmentInCurrentRep!) {
        _minBodyAlignmentInCurrentRep = bodyAlignmentDeg;
      }
    }
  }

  void _abortInProgressCycle() {
    _phase = PushUpPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _bottomReachedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _minBodyAlignmentInCurrentRep = null;
    _angleSmoother.reset();
  }
}

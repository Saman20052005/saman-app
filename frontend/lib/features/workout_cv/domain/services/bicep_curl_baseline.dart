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

/// A completed Bicep Curl rep event emitted when returning to extension.
class BicepCurlRepEvent extends LatPulldownRepEvent {
  final String? activeSide;
  final double? maxUpperArmSwingDeg;
  final double? maxTorsoLeanDeg;
  final bool? isElbowPinned;
  final bool? isTorsoStable;

  const BicepCurlRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    super.viewAngle = CameraViewAngle.unknown,
    super.issueCode,
    this.activeSide,
    this.maxUpperArmSwingDeg,
    this.maxTorsoLeanDeg,
    this.isElbowPinned,
    this.isTorsoStable,
  });
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
  final int maxRepDurationMs;
  final int maxAllowedGapMs;
  final double maxValidUpperArmSwingDeg;
  final double maxValidTorsoLeanDeg;
  final bool enableAngleSmoothing;
  final double smoothingAlpha;

  const BicepCurlBaselineConfig({
    this.extendedEnterDeg = 145.0,
    this.curlingEnterDeg = 130.0,
    this.flexedEnterDeg = 60.0,
    this.loweringEnterDeg = 80.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 10000,
    this.maxAllowedGapMs = 500,
    this.maxValidUpperArmSwingDeg = 35.0,
    this.maxValidTorsoLeanDeg = 25.0,
    this.enableAngleSmoothing = false,
    this.smoothingAlpha = 0.50,
  });
}

/// Output record for a single processed Bicep Curl frame.
class BicepCurlBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final BicepCurlPhase phase;
  final int completedReps;
  final BicepCurlRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final String? activeSide;
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
    this.activeSide,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal rule-based state machine for Bicep Curl repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Uses side-locking during each rep to prevent left/right jumping on
/// alternating curls, and tracks upper-arm swing (`Hip -> Shoulder -> Elbow`)
/// and torso stability.
class BicepCurlBaseline {
  final BicepCurlBaselineConfig config;

  BicepCurlPhase _phase = BicepCurlPhase.notReady;
  int _completedReps = 0;
  final List<BicepCurlRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakFlexedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  double? _maxUpperArmSwingInCurrentRep;
  double? _maxTorsoLeanInCurrentRep;
  String? _lockedSide;
  String? _preferredSide;
  String? _lastSmoothedSide;
  int _droppedNonMonotonicFrames = 0;
  late final AngleSmoother _angleSmoother = AngleSmoother(
    alpha: config.smoothingAlpha,
    maxGapMs: config.maxAllowedGapMs,
  );

  BicepCurlBaseline({
    BicepCurlBaselineConfig? config,
    double? maxValidUpperArmSwingDeg,
  }) : config = _resolveConfig(config, maxValidUpperArmSwingDeg);

  static BicepCurlBaselineConfig _resolveConfig(
    BicepCurlBaselineConfig? config,
    double? maxValidUpperArmSwingDeg,
  ) {
    final base = config ?? const BicepCurlBaselineConfig();
    if (maxValidUpperArmSwingDeg == null) return base;
    return BicepCurlBaselineConfig(
      extendedEnterDeg: base.extendedEnterDeg,
      curlingEnterDeg: base.curlingEnterDeg,
      flexedEnterDeg: base.flexedEnterDeg,
      loweringEnterDeg: base.loweringEnterDeg,
      minReadyHoldMs: base.minReadyHoldMs,
      minExtendedHoldMs: base.minExtendedHoldMs,
      minRepDurationMs: base.minRepDurationMs,
      maxRepDurationMs: base.maxRepDurationMs,
      maxAllowedGapMs: base.maxAllowedGapMs,
      maxValidUpperArmSwingDeg: maxValidUpperArmSwingDeg,
      maxValidTorsoLeanDeg: base.maxValidTorsoLeanDeg,
      enableAngleSmoothing: base.enableAngleSmoothing,
      smoothingAlpha: base.smoothingAlpha,
    );
  }

  BicepCurlPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<BicepCurlRepEvent> get repHistory => List.unmodifiable(_repHistory);
  String? get lockedSide => _lockedSide;
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
    _maxUpperArmSwingInCurrentRep = null;
    _maxTorsoLeanInCurrentRep = null;
    _lockedSide = null;
    _preferredSide = null;
    _lastSmoothedSide = null;
    _droppedNonMonotonicFrames = 0;
    _angleSmoother.reset();
  }

  /// Processes a [BicepCurlFrameFeatures] container with per-rep side-locking.
  BicepCurlBaselineFrameResult processBicepCurlFeatures(
      BicepCurlFrameFeatures features) {
    if (_lastTimestampMs != null && features.timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return BicepCurlBaselineFrameResult(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        activeSide: _lockedSide,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = features.timestampMs;

    if (!features.isGateDetecting) {
      const resetReason = 'gateNotDetecting';
      _abortInProgressCycle();
      return BicepCurlBaselineFrameResult(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isSampleValid: false,
        resetReason: resetReason,
      );
    }

    final leftValid = features.leftElbowAngleDeg.isValid &&
        features.leftElbowAngleDeg.value != null &&
        features.leftElbowAngleDeg.value!.isFinite;
    final rightValid = features.rightElbowAngleDeg.isValid &&
        features.rightElbowAngleDeg.value != null &&
        features.rightElbowAngleDeg.value!.isFinite;

    final leftAngle = leftValid ? features.leftElbowAngleDeg.value! : null;
    final rightAngle = rightValid ? features.rightElbowAngleDeg.value! : null;
    final leftSwing = features.leftUpperArmSwingDeg.isValid
        ? features.leftUpperArmSwingDeg.value
        : null;
    final rightSwing = features.rightUpperArmSwingDeg.isValid
        ? features.rightUpperArmSwingDeg.value
        : null;
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;

    if (_lockedSide != null) {
      final lockedAngle = _lockedSide == 'left' ? leftAngle : rightAngle;
      final lockedSwing = _lockedSide == 'left' ? leftSwing : rightSwing;
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        elbowAngleDeg: lockedAngle,
        upperArmSwingDeg: lockedSwing,
        torsoLeanDeg: torsoLean,
        activeSide: _lockedSide,
        viewAngle: features.viewAngle,
        isSampleValid: lockedAngle != null,
      );
    }

    // No side locked yet (notReady or extended).
    if (!leftValid && !rightValid) {
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        elbowAngleDeg: null,
        viewAngle: features.viewAngle,
        isSampleValid: false,
      );
    }

    // Check data gap before evaluating side-lock so stale state cannot lock a side.
    String? preLockGapResetReason;
    if (_lastValidTimestampMs != null &&
        (features.timestampMs - _lastValidTimestampMs!) >
            config.maxAllowedGapMs) {
      if (_phase != BicepCurlPhase.notReady) {
        preLockGapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }

    final leftScore = leftValid
        ? (features.leftElbowVisibilityScore > 0.0
            ? features.leftElbowVisibilityScore
            : 1.0)
        : 0.0;
    final rightScore = rightValid
        ? (features.rightElbowVisibilityScore > 0.0
            ? features.rightElbowVisibilityScore
            : 1.0)
        : 0.0;

    String? selectedSide;
    double? selectedAngle;
    double? selectedSwing;

    if (_phase == BicepCurlPhase.extended) {
      final leftCurling = leftAngle != null && leftAngle < config.curlingEnterDeg;
      final rightCurling =
          rightAngle != null && rightAngle < config.curlingEnterDeg;
      if (leftCurling && rightCurling) {
        final locked = ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: leftScore,
          rightScore: rightScore,
          lockedSide: _preferredSide,
          viewAngle: features.viewAngle,
        );
        if (locked != 'none') {
          selectedSide = locked;
        }
      } else if (leftCurling) {
        selectedSide = 'left';
      } else if (rightCurling) {
        selectedSide = 'right';
      }

      if (selectedSide != null) {
        _lockedSide = selectedSide;
        _preferredSide = selectedSide;
        selectedAngle = selectedSide == 'left' ? leftAngle : rightAngle;
        selectedSwing = selectedSide == 'left' ? leftSwing : rightSwing;
      }
    }

    if (selectedAngle == null) {
      final locked = ViewAngleProjectionHelper.selectBestLockedSide(
        leftScore: leftScore,
        rightScore: rightScore,
        lockedSide: _preferredSide,
        viewAngle: features.viewAngle,
      );
      if (locked != 'none') {
        _preferredSide = locked;
      }
      final useLeft = locked == 'left' || (locked == 'none' && leftValid);
      selectedSide = useLeft ? 'left' : 'right';
      selectedAngle = useLeft ? leftAngle : rightAngle;
      selectedSwing = useLeft ? leftSwing : rightSwing;
    }

    return _processValidatedSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: selectedAngle,
      upperArmSwingDeg: selectedSwing,
      torsoLeanDeg: torsoLean,
      activeSide: _lockedSide ?? selectedSide,
      viewAngle: features.viewAngle,
      isSampleValid: true,
      precheckedGapResetReason: preLockGapResetReason,
      skipGapCheck: true,
    );
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
    double? upperArmSwingDeg,
    double? torsoLeanDeg,
    String? activeSide,
    CameraViewAngle viewAngle = CameraViewAngle.unknown,
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
        activeSide: _lockedSide ?? activeSide,
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

    return _processValidatedSample(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      elbowAngleDeg: elbowAngleDeg,
      upperArmSwingDeg: upperArmSwingDeg,
      torsoLeanDeg: torsoLeanDeg,
      activeSide: activeSide,
      viewAngle: viewAngle,
      isSampleValid: isSampleValid,
    );
  }

  BicepCurlBaselineFrameResult _processValidatedSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    double? upperArmSwingDeg,
    double? torsoLeanDeg,
    String? activeSide,
    CameraViewAngle viewAngle = CameraViewAngle.unknown,
    required bool isSampleValid,
    String? precheckedGapResetReason,
    bool skipGapCheck = false,
  }) {
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
        activeSide: _lockedSide ?? activeSide,
        isSampleValid: false,
      );
    }

    String? gapResetReason = precheckedGapResetReason;
    if (!skipGapCheck) {
      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        if (_phase != BicepCurlPhase.notReady) {
          gapResetReason = 'dataLossGapBeforeValidSample';
        }
        _abortInProgressCycle();
      }
    }
    _lastValidTimestampMs = timestampMs;

    final effectiveSide = _lockedSide ?? activeSide;
    if (config.enableAngleSmoothing &&
        effectiveSide != null &&
        _lastSmoothedSide != null &&
        effectiveSide != _lastSmoothedSide) {
      _angleSmoother.reset();
    }
    if (effectiveSide != null) {
      _lastSmoothedSide = effectiveSide;
    }

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
    BicepCurlRepEvent? newRepEvent;

    switch (_phase) {
      case BicepCurlPhase.notReady:
        if (effectiveAngle >= effectiveExtendedEnter) {
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
        if (effectiveAngle < config.curlingEnterDeg) {
          _phase = BicepCurlPhase.curling;
          transitionReason = 'curlStarted';
          _repStartTimestampMs = timestampMs;
          _peakFlexedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = effectiveAngle;
          _maxUpperArmSwingInCurrentRep = null;
          _maxTorsoLeanInCurrentRep = null;
          if (_lockedSide == null && activeSide != null) {
            _lockedSide = activeSide;
          }
          _updateFormMetrics(upperArmSwingDeg, torsoLeanDeg);
        }
        break;

      case BicepCurlPhase.curling:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
        }
        _updateFormMetrics(upperArmSwingDeg, torsoLeanDeg);

        if (effectiveAngle <= effectiveFlexedEnter) {
          _phase = BicepCurlPhase.flexed;
          transitionReason = 'flexedReached';
          _peakFlexedTimestampMs = timestampMs;
        } else if (effectiveAngle >= config.curlingEnterDeg) {
          _phase = BicepCurlPhase.extended;
          transitionReason = 'incompleteCurlReturnedToExtended';
          _repStartTimestampMs = null;
          _maxUpperArmSwingInCurrentRep = null;
          _maxTorsoLeanInCurrentRep = null;
          _lockedSide = null;
        }
        break;

      case BicepCurlPhase.flexed:
        if (effectiveAngle < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = effectiveAngle;
          _peakFlexedTimestampMs = timestampMs;
        }
        _updateFormMetrics(upperArmSwingDeg, torsoLeanDeg);

        if (effectiveAngle > config.loweringEnterDeg) {
          _phase = BicepCurlPhase.lowering;
          transitionReason = 'loweringStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case BicepCurlPhase.lowering:
        _updateFormMetrics(upperArmSwingDeg, torsoLeanDeg);

        if (effectiveAngle <= effectiveFlexedEnter) {
          _phase = BicepCurlPhase.flexed;
          transitionReason = 'reFlexedDuringLowering';
          _extendedCandidateStartMs = null;
        } else if (effectiveAngle >= effectiveExtendedEnter) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs &&
                duration <= config.maxRepDurationMs) {
              _completedReps++;
              final isElbowPinned = _maxUpperArmSwingInCurrentRep != null
                  ? _maxUpperArmSwingInCurrentRep! <=
                      config.maxValidUpperArmSwingDeg
                  : null;
              final isTorsoStable = _maxTorsoLeanInCurrentRep != null
                  ? _maxTorsoLeanInCurrentRep! <= config.maxValidTorsoLeanDeg
                  : null;
              final String? issueCode;
              if (isElbowPinned == false) {
                issueCode = 'elbowSwing';
              } else if (isTorsoStable == false) {
                issueCode = 'torsoLean';
              } else if (duration < 1500) {
                issueCode = 'tooFast';
              } else if (_minElbowAngleInCurrentRep > 60.0 + flexionOffset) {
                issueCode = 'shallowDepth';
              } else {
                issueCode = null;
              }
              newRepEvent = BicepCurlRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs: _peakFlexedTimestampMs ??
                    ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _minElbowAngleInCurrentRep,
                status: 'PROVISIONAL',
                viewAngle: viewAngle,
                issueCode: issueCode,
                activeSide: _lockedSide ?? activeSide,
                maxUpperArmSwingDeg: _maxUpperArmSwingInCurrentRep,
                maxTorsoLeanDeg: _maxTorsoLeanInCurrentRep,
                isElbowPinned: isElbowPinned,
                isTorsoStable: isTorsoStable,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = BicepCurlPhase.extended;
            _repStartTimestampMs = null;
            _peakFlexedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minElbowAngleInCurrentRep = 180.0;
            _maxUpperArmSwingInCurrentRep = null;
            _maxTorsoLeanInCurrentRep = null;
            _lockedSide = null;
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
      elbowAngleDeg: effectiveAngle,
      activeSide: _lockedSide ?? activeSide,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  void _updateFormMetrics(double? upperArmSwingDeg, double? torsoLeanDeg) {
    if (upperArmSwingDeg != null && upperArmSwingDeg.isFinite) {
      if (_maxUpperArmSwingInCurrentRep == null ||
          upperArmSwingDeg > _maxUpperArmSwingInCurrentRep!) {
        _maxUpperArmSwingInCurrentRep = upperArmSwingDeg;
      }
    }
    if (torsoLeanDeg != null && torsoLeanDeg.isFinite) {
      if (_maxTorsoLeanInCurrentRep == null ||
          torsoLeanDeg > _maxTorsoLeanInCurrentRep!) {
        _maxTorsoLeanInCurrentRep = torsoLeanDeg;
      }
    }
  }

  void _abortInProgressCycle() {
    _phase = BicepCurlPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _maxUpperArmSwingInCurrentRep = null;
    _maxTorsoLeanInCurrentRep = null;
    _lockedSide = null;
    _preferredSide = null;
    _lastSmoothedSide = null;
    _angleSmoother.reset();
  }
}

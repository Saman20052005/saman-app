import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Lateral Raise exercise state machine.
enum LateralRaisePhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Arms resting at sides (shoulder angle <= 35 deg).
  ready,

  /// Concentric abduction raising arms laterally (shoulder angle > 48 deg).
  raising,

  /// Peak lateral abduction (shoulder angle >= 75 deg).
  peak,

  /// Eccentric lowering phase back to sides (shoulder angle < 55 deg).
  lowering,
}

/// Configuration parameters for [LateralRaiseBaseline].
class LateralRaiseBaselineConfig {
  final double readyEnterDeg;
  final double raisingEnterDeg;
  final double peakEnterDeg;
  final double loweringEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;

  const LateralRaiseBaselineConfig({
    this.readyEnterDeg = 35.0,
    this.raisingEnterDeg = 48.0,
    this.peakEnterDeg = 75.0,
    this.loweringEnterDeg = 55.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Lateral Raise frame.
class LateralRaiseBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final LateralRaisePhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? shoulderAngleDeg;
  final String? activeSide;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const LateralRaiseBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.shoulderAngleDeg,
    this.activeSide,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal 5-phase FSM with per-rep side-locking for Lateral Raises.
///
/// Tracks `Hip -> Shoulder -> Elbow` angle and stores `maxShoulderAngleInRep`
/// into [LatPulldownRepEvent.minElbowAngleDeg].
class LateralRaiseBaseline {
  final LateralRaiseBaselineConfig config;

  LateralRaisePhase _phase = LateralRaisePhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakTimestampMs;
  double _maxShoulderAngleInCurrentRep = 0.0;
  String? _lockedSide;
  int _droppedNonMonotonicFrames = 0;

  LateralRaiseBaseline({LateralRaiseBaselineConfig? config})
      : config = config ?? const LateralRaiseBaselineConfig();

  LateralRaisePhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  String? get lockedSide => _lockedSide;
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = LateralRaisePhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakTimestampMs = null;
    _maxShoulderAngleInCurrentRep = 0.0;
    _lockedSide = null;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes an [ExtendedLibraryFrameFeatures] container with per-rep side-locking.
  LateralRaiseBaselineFrameResult processExtendedFeatures(
    ExtendedLibraryFrameFeatures features,
  ) {
    if (_lastTimestampMs != null && features.timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return LateralRaiseBaselineFrameResult(
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
      _abortInProgressCycle();
      return LateralRaiseBaselineFrameResult(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    final leftValid = features.leftShoulderAngleDeg.isValid &&
        features.leftShoulderAngleDeg.value != null &&
        features.leftShoulderAngleDeg.value!.isFinite;
    final rightValid = features.rightShoulderAngleDeg.isValid &&
        features.rightShoulderAngleDeg.value != null &&
        features.rightShoulderAngleDeg.value!.isFinite;

    final leftAngle = leftValid ? features.leftShoulderAngleDeg.value! : null;
    final rightAngle =
        rightValid ? features.rightShoulderAngleDeg.value! : null;

    if (_lockedSide != null) {
      final lockedAngle = _lockedSide == 'left' ? leftAngle : rightAngle;
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        shoulderAngleDeg: lockedAngle,
        activeSide: _lockedSide,
        isSampleValid: lockedAngle != null,
      );
    }

    if (!leftValid && !rightValid) {
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        shoulderAngleDeg: null,
        isSampleValid: false,
      );
    }

    String? preLockGapResetReason;
    if (_lastValidTimestampMs != null &&
        (features.timestampMs - _lastValidTimestampMs!) >
            config.maxAllowedGapMs) {
      if (_phase != LateralRaisePhase.notReady) {
        preLockGapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }

    String? selectedSide;
    double? selectedAngle;

    if (_phase == LateralRaisePhase.ready) {
      final leftRaising =
          leftAngle != null && leftAngle > config.raisingEnterDeg;
      final rightRaising =
          rightAngle != null && rightAngle > config.raisingEnterDeg;
      if (leftRaising && rightRaising) {
        selectedSide = features.leftShoulderVisibilityScore >=
                features.rightShoulderVisibilityScore
            ? 'left'
            : 'right';
      } else if (leftRaising) {
        selectedSide = 'left';
      } else if (rightRaising) {
        selectedSide = 'right';
      }

      if (selectedSide != null) {
        _lockedSide = selectedSide;
        selectedAngle = selectedSide == 'left' ? leftAngle : rightAngle;
      }
    }

    if (selectedAngle == null) {
      final useLeft = leftValid &&
          (!rightValid ||
              features.leftShoulderVisibilityScore >=
                  features.rightShoulderVisibilityScore);
      selectedSide = useLeft ? 'left' : 'right';
      selectedAngle = useLeft ? leftAngle : rightAngle;
    }

    return _processValidatedSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      shoulderAngleDeg: selectedAngle,
      activeSide: _lockedSide ?? selectedSide,
      isSampleValid: true,
      precheckedGapResetReason: preLockGapResetReason,
      skipGapCheck: true,
    );
  }

  LateralRaiseBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? shoulderAngleDeg,
    String? activeSide,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return LateralRaiseBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        shoulderAngleDeg: shoulderAngleDeg,
        activeSide: _lockedSide ?? activeSide,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      _abortInProgressCycle();
      return LateralRaiseBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        shoulderAngleDeg: shoulderAngleDeg,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    return _processValidatedSample(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      shoulderAngleDeg: shoulderAngleDeg,
      activeSide: activeSide,
      isSampleValid: isSampleValid,
    );
  }

  LateralRaiseBaselineFrameResult _processValidatedSample({
    required int frameIndex,
    required int timestampMs,
    double? shoulderAngleDeg,
    String? activeSide,
    required bool isSampleValid,
    String? precheckedGapResetReason,
    bool skipGapCheck = false,
  }) {
    if (!isSampleValid ||
        shoulderAngleDeg == null ||
        !shoulderAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        _abortInProgressCycle();
        return LateralRaiseBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return LateralRaiseBaselineFrameResult(
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
        if (_phase != LateralRaisePhase.notReady) {
          gapResetReason = 'dataLossGapBeforeValidSample';
        }
        _abortInProgressCycle();
      }
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case LateralRaisePhase.notReady:
        if (shoulderAngleDeg <= config.readyEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = LateralRaisePhase.ready;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case LateralRaisePhase.ready:
        if (shoulderAngleDeg > config.raisingEnterDeg) {
          _phase = LateralRaisePhase.raising;
          transitionReason = 'raisingStarted';
          _repStartTimestampMs = timestampMs;
          _peakTimestampMs = null;
          _extendedCandidateStartMs = null;
          _maxShoulderAngleInCurrentRep = shoulderAngleDeg;
          if (_lockedSide == null && activeSide != null) {
            _lockedSide = activeSide;
          }
        }
        break;

      case LateralRaisePhase.raising:
        if (shoulderAngleDeg > _maxShoulderAngleInCurrentRep) {
          _maxShoulderAngleInCurrentRep = shoulderAngleDeg;
        }

        if (shoulderAngleDeg >= config.peakEnterDeg) {
          _phase = LateralRaisePhase.peak;
          transitionReason = 'peakReached';
          _peakTimestampMs = timestampMs;
        } else if (shoulderAngleDeg <= config.raisingEnterDeg) {
          _phase = LateralRaisePhase.ready;
          transitionReason = 'incompleteRaiseReturnedToReady';
          _repStartTimestampMs = null;
          _lockedSide = null;
        }
        break;

      case LateralRaisePhase.peak:
        if (shoulderAngleDeg > _maxShoulderAngleInCurrentRep) {
          _maxShoulderAngleInCurrentRep = shoulderAngleDeg;
          _peakTimestampMs = timestampMs;
        }

        if (shoulderAngleDeg < config.loweringEnterDeg) {
          _phase = LateralRaisePhase.lowering;
          transitionReason = 'loweringStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case LateralRaisePhase.lowering:
        if (shoulderAngleDeg > _maxShoulderAngleInCurrentRep) {
          _maxShoulderAngleInCurrentRep = shoulderAngleDeg;
        }

        if (shoulderAngleDeg >= config.peakEnterDeg) {
          _phase = LateralRaisePhase.peak;
          transitionReason = 'rePeakedDuringLowering';
          _extendedCandidateStartMs = null;
        } else if (shoulderAngleDeg <= config.readyEnterDeg) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs &&
                duration <= config.maxRepDurationMs) {
              _completedReps++;
              newRepEvent = LatPulldownRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs:
                    _peakTimestampMs ?? ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _maxShoulderAngleInCurrentRep,
                status: 'PROVISIONAL',
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = LateralRaisePhase.ready;
            _repStartTimestampMs = null;
            _peakTimestampMs = null;
            _extendedCandidateStartMs = null;
            _maxShoulderAngleInCurrentRep = 0.0;
            _lockedSide = null;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return LateralRaiseBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      shoulderAngleDeg: shoulderAngleDeg,
      activeSide: _lockedSide ?? activeSide,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  void _abortInProgressCycle() {
    _phase = LateralRaisePhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakTimestampMs = null;
    _maxShoulderAngleInCurrentRep = 0.0;
    _lockedSide = null;
  }
}

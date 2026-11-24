import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Tricep Extension exercise state machine.
enum TricepExtensionPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Starting flexed elbow position (elbow angle <= 95 deg).
  ready,

  /// Concentric extension phase toward lockout (elbow angle > 110 deg).
  extending,

  /// Peak lockout extension (elbow angle >= 155 deg).
  lockout,

  /// Eccentric returning phase back toward flexed start (elbow angle < 135 deg).
  returning,
}

/// Configuration parameters for [TricepExtensionBaseline].
class TricepExtensionBaselineConfig {
  final double readyEnterDeg;
  final double extendingEnterDeg;
  final double lockoutEnterDeg;
  final double returningEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;

  const TricepExtensionBaselineConfig({
    this.readyEnterDeg = 95.0,
    this.extendingEnterDeg = 110.0,
    this.lockoutEnterDeg = 155.0,
    this.returningEnterDeg = 135.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Tricep Extension frame.
class TricepExtensionBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final TricepExtensionPhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final String? activeSide;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const TricepExtensionBaselineFrameResult({
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

/// Pure Dart causal 5-phase FSM with per-rep side-locking for Tricep Extensions.
///
/// Stores peak extension angle (`maxElbowAngleInRep`) in [LatPulldownRepEvent.minElbowAngleDeg].
class TricepExtensionBaseline {
  final TricepExtensionBaselineConfig config;

  TricepExtensionPhase _phase = TricepExtensionPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _lockoutTimestampMs;
  double _maxElbowAngleInCurrentRep = 0.0;
  String? _lockedSide;
  int _droppedNonMonotonicFrames = 0;

  TricepExtensionBaseline({TricepExtensionBaselineConfig? config})
      : config = config ?? const TricepExtensionBaselineConfig();

  TricepExtensionPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  String? get lockedSide => _lockedSide;
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = TricepExtensionPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _lockoutTimestampMs = null;
    _maxElbowAngleInCurrentRep = 0.0;
    _lockedSide = null;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes an [ExtendedLibraryFrameFeatures] container with per-rep side-locking.
  TricepExtensionBaselineFrameResult processExtendedFeatures(
    ExtendedLibraryFrameFeatures features,
  ) {
    if (_lastTimestampMs != null && features.timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return TricepExtensionBaselineFrameResult(
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
      return TricepExtensionBaselineFrameResult(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
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

    if (_lockedSide != null) {
      final lockedAngle = _lockedSide == 'left' ? leftAngle : rightAngle;
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        elbowAngleDeg: lockedAngle,
        activeSide: _lockedSide,
        isSampleValid: lockedAngle != null,
      );
    }

    if (!leftValid && !rightValid) {
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        elbowAngleDeg: null,
        isSampleValid: false,
      );
    }

    String? preLockGapResetReason;
    if (_lastValidTimestampMs != null &&
        (features.timestampMs - _lastValidTimestampMs!) >
            config.maxAllowedGapMs) {
      if (_phase != TricepExtensionPhase.notReady) {
        preLockGapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }

    String? selectedSide;
    double? selectedAngle;

    if (_phase == TricepExtensionPhase.ready) {
      final leftExtending =
          leftAngle != null && leftAngle > config.extendingEnterDeg;
      final rightExtending =
          rightAngle != null && rightAngle > config.extendingEnterDeg;
      if (leftExtending && rightExtending) {
        selectedSide = features.leftElbowVisibilityScore >=
                features.rightElbowVisibilityScore
            ? 'left'
            : 'right';
      } else if (leftExtending) {
        selectedSide = 'left';
      } else if (rightExtending) {
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
              features.leftElbowVisibilityScore >=
                  features.rightElbowVisibilityScore);
      selectedSide = useLeft ? 'left' : 'right';
      selectedAngle = useLeft ? leftAngle : rightAngle;
    }

    return _processValidatedSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: selectedAngle,
      activeSide: _lockedSide ?? selectedSide,
      isSampleValid: true,
      precheckedGapResetReason: preLockGapResetReason,
      skipGapCheck: true,
    );
  }

  TricepExtensionBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    String? activeSide,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return TricepExtensionBaselineFrameResult(
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
      _abortInProgressCycle();
      return TricepExtensionBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    return _processValidatedSample(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      elbowAngleDeg: elbowAngleDeg,
      activeSide: activeSide,
      isSampleValid: isSampleValid,
    );
  }

  TricepExtensionBaselineFrameResult _processValidatedSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    String? activeSide,
    required bool isSampleValid,
    String? precheckedGapResetReason,
    bool skipGapCheck = false,
  }) {
    if (!isSampleValid || elbowAngleDeg == null || !elbowAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        _abortInProgressCycle();
        return TricepExtensionBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return TricepExtensionBaselineFrameResult(
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
        if (_phase != TricepExtensionPhase.notReady) {
          gapResetReason = 'dataLossGapBeforeValidSample';
        }
        _abortInProgressCycle();
      }
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case TricepExtensionPhase.notReady:
        if (elbowAngleDeg <= config.readyEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = TricepExtensionPhase.ready;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case TricepExtensionPhase.ready:
        if (elbowAngleDeg > config.extendingEnterDeg) {
          _phase = TricepExtensionPhase.extending;
          transitionReason = 'extensionStarted';
          _repStartTimestampMs = timestampMs;
          _lockoutTimestampMs = null;
          _extendedCandidateStartMs = null;
          _maxElbowAngleInCurrentRep = elbowAngleDeg;
          if (_lockedSide == null && activeSide != null) {
            _lockedSide = activeSide;
          }
        }
        break;

      case TricepExtensionPhase.extending:
        if (elbowAngleDeg > _maxElbowAngleInCurrentRep) {
          _maxElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg >= config.lockoutEnterDeg) {
          _phase = TricepExtensionPhase.lockout;
          transitionReason = 'lockoutReached';
          _lockoutTimestampMs = timestampMs;
        } else if (elbowAngleDeg <= config.extendingEnterDeg) {
          _phase = TricepExtensionPhase.ready;
          transitionReason = 'incompleteExtensionReturnedToReady';
          _repStartTimestampMs = null;
          _lockedSide = null;
        }
        break;

      case TricepExtensionPhase.lockout:
        if (elbowAngleDeg > _maxElbowAngleInCurrentRep) {
          _maxElbowAngleInCurrentRep = elbowAngleDeg;
          _lockoutTimestampMs = timestampMs;
        }

        if (elbowAngleDeg < config.returningEnterDeg) {
          _phase = TricepExtensionPhase.returning;
          transitionReason = 'returningStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case TricepExtensionPhase.returning:
        if (elbowAngleDeg > _maxElbowAngleInCurrentRep) {
          _maxElbowAngleInCurrentRep = elbowAngleDeg;
        }

        if (elbowAngleDeg >= config.lockoutEnterDeg) {
          _phase = TricepExtensionPhase.lockout;
          transitionReason = 'reLockedOutDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (elbowAngleDeg <= config.readyEnterDeg) {
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
                    _lockoutTimestampMs ?? ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _maxElbowAngleInCurrentRep,
                status: 'PROVISIONAL',
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = TricepExtensionPhase.ready;
            _repStartTimestampMs = null;
            _lockoutTimestampMs = null;
            _extendedCandidateStartMs = null;
            _maxElbowAngleInCurrentRep = 0.0;
            _lockedSide = null;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return TricepExtensionBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      elbowAngleDeg: elbowAngleDeg,
      activeSide: _lockedSide ?? activeSide,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  void _abortInProgressCycle() {
    _phase = TricepExtensionPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _lockoutTimestampMs = null;
    _maxElbowAngleInCurrentRep = 0.0;
    _lockedSide = null;
  }
}

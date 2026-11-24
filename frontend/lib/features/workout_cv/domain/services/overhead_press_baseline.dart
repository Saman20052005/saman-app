import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Overhead Press exercise state machine.
enum OverheadPressPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Starting rack position at shoulder height (elbow angle <= 100 deg).
  ready,

  /// Concentric pressing phase upward (elbow angle > 112 deg).
  pressing,

  /// Overhead lockout peak (elbow angle >= 150 deg and wrist above shoulder).
  lockout,

  /// Eccentric lowering phase back toward shoulder rack (elbow angle < 135 deg).
  lowering,
}

/// A completed Overhead Press rep event emitted when returning to the rack position.
///
/// Passes [peakLockoutAngleDeg] into [super.minElbowAngleDeg] so downstream
/// summary calculators and UI report the peak overhead lockout extension angle.
class OverheadPressRepEvent extends LatPulldownRepEvent {
  final double? minRackElbowAngleDeg;
  final double? maxTorsoLeanDeg;
  final bool? isBackVertical;

  const OverheadPressRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    this.minRackElbowAngleDeg,
    this.maxTorsoLeanDeg,
    this.isBackVertical,
  });

  double get peakLockoutAngleDeg => minElbowAngleDeg;
}

/// Configuration parameters for Overhead Press rule-based state machine.
class OverheadPressBaselineConfig {
  final double readyEnterDeg;
  final double pressingEnterDeg;
  final double lockoutEnterDeg;
  final double loweringEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;
  final double maxValidTorsoLeanDeg;
  final double maxPlausibleTorsoLeanDeg;

  const OverheadPressBaselineConfig({
    this.readyEnterDeg = 100.0,
    this.pressingEnterDeg = 112.0,
    this.lockoutEnterDeg = 150.0,
    this.loweringEnterDeg = 135.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 10000,
    this.maxAllowedGapMs = 500,
    this.maxValidTorsoLeanDeg = 25.0,
    this.maxPlausibleTorsoLeanDeg = 50.0,
  });
}

/// Output record for a single processed Overhead Press frame.
class OverheadPressBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final OverheadPressPhase phase;
  final int completedReps;
  final OverheadPressRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final bool isWristAboveShoulder;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const OverheadPressBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.elbowAngleDeg,
    required this.isWristAboveShoulder,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal rule-based state machine for Overhead Press repetition counting.
///
/// Operates strictly forward in time (no lookahead, no offline smoothing).
/// Transitions from shoulder rack (<= 100 deg) -> press (> 112 deg) ->
/// overhead lockout (>= 150 deg & wrist above shoulder) -> lower (< 135 deg) ->
/// return to shoulder rack (<= 100 deg).
class OverheadPressBaseline {
  final OverheadPressBaselineConfig config;

  OverheadPressPhase _phase = OverheadPressPhase.notReady;
  int _completedReps = 0;
  final List<OverheadPressRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _lockoutReachedTimestampMs;
  double _minRackElbowAngleInCurrentRep = 180.0;
  double _peakLockoutAngleInCurrentRep = 0.0;
  double? _maxTorsoLeanInCurrentRep;
  int _droppedNonMonotonicFrames = 0;

  OverheadPressBaseline({OverheadPressBaselineConfig? config})
      : config = config ?? const OverheadPressBaselineConfig();

  OverheadPressPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<OverheadPressRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = OverheadPressPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _lockoutReachedTimestampMs = null;
    _minRackElbowAngleInCurrentRep = 180.0;
    _peakLockoutAngleInCurrentRep = 0.0;
    _maxTorsoLeanInCurrentRep = null;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes an [OverheadPressFrameFeatures] container extracted by [WorkoutCvMotionFeatures].
  OverheadPressBaselineFrameResult processOverheadPressFeatures(
      OverheadPressFrameFeatures features) {
    final isAngleValid = features.bestElbowAngleDeg.isValid;
    final angle = isAngleValid ? features.bestElbowAngleDeg.value : null;
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isWristAboveShoulder: features.isWristAboveShoulder,
      torsoLeanDeg: torsoLean,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  OverheadPressBaselineFrameResult processFrameFeatures(
      MultiExerciseAngleFeatures features) {
    final isAngleValid = features.bestElbowAngleDeg.isValid;
    final angle = isAngleValid ? features.bestElbowAngleDeg.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      elbowAngleDeg: angle,
      isWristAboveShoulder: features.isWristAboveShoulder,
      isSampleValid: isAngleValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  OverheadPressBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    required bool isWristAboveShoulder,
    double? torsoLeanDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return OverheadPressBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isWristAboveShoulder: isWristAboveShoulder,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      const resetReason = 'gateNotDetecting';
      _abortInProgressCycle();
      return OverheadPressBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        elbowAngleDeg: elbowAngleDeg,
        isWristAboveShoulder: false,
        isSampleValid: false,
        resetReason: resetReason,
      );
    }

    if (!isSampleValid || elbowAngleDeg == null || !elbowAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        const resetReason = 'dataLossGapExceeded';
        _abortInProgressCycle();
        return OverheadPressBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isWristAboveShoulder: false,
          isSampleValid: false,
          resetReason: resetReason,
        );
      }

      return OverheadPressBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        isWristAboveShoulder: false,
        isSampleValid: false,
      );
    }

    String? gapResetReason;
    if (_lastValidTimestampMs != null &&
        (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
      if (_phase != OverheadPressPhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    OverheadPressRepEvent? newRepEvent;
    final isPlausibleTorso = _isTorsoPlausible(torsoLeanDeg);

    switch (_phase) {
      case OverheadPressPhase.notReady:
        if (elbowAngleDeg <= config.readyEnterDeg && isPlausibleTorso) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = OverheadPressPhase.ready;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
            _minRackElbowAngleInCurrentRep = elbowAngleDeg;
            _peakLockoutAngleInCurrentRep = 0.0;
            _maxTorsoLeanInCurrentRep = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case OverheadPressPhase.ready:
        if (!isPlausibleTorso) {
          _abortInProgressCycle();
          transitionReason = 'torsoNotVerticalPlausible';
          break;
        }
        if (elbowAngleDeg < _minRackElbowAngleInCurrentRep) {
          _minRackElbowAngleInCurrentRep = elbowAngleDeg;
        }
        if (elbowAngleDeg > config.pressingEnterDeg) {
          _phase = OverheadPressPhase.pressing;
          transitionReason = 'pressStarted';
          _repStartTimestampMs = timestampMs;
          _lockoutReachedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _peakLockoutAngleInCurrentRep = elbowAngleDeg;
          _maxTorsoLeanInCurrentRep = null;
          _updateMaxTorsoLean(torsoLeanDeg);
        }
        break;

      case OverheadPressPhase.pressing:
        if (elbowAngleDeg < _minRackElbowAngleInCurrentRep) {
          _minRackElbowAngleInCurrentRep = elbowAngleDeg;
        }
        if (elbowAngleDeg > _peakLockoutAngleInCurrentRep) {
          _peakLockoutAngleInCurrentRep = elbowAngleDeg;
        }
        _updateMaxTorsoLean(torsoLeanDeg);

        if (elbowAngleDeg >= config.lockoutEnterDeg &&
            isWristAboveShoulder &&
            isPlausibleTorso) {
          _phase = OverheadPressPhase.lockout;
          transitionReason = 'lockoutReached';
          _lockoutReachedTimestampMs = timestampMs;
        } else if (elbowAngleDeg <= config.pressingEnterDeg) {
          _phase = OverheadPressPhase.ready;
          transitionReason = 'incompletePressReturnedToReady';
          _repStartTimestampMs = null;
          _peakLockoutAngleInCurrentRep = 0.0;
          _maxTorsoLeanInCurrentRep = null;
        }
        break;

      case OverheadPressPhase.lockout:
        if (elbowAngleDeg > _peakLockoutAngleInCurrentRep) {
          _peakLockoutAngleInCurrentRep = elbowAngleDeg;
          _lockoutReachedTimestampMs = timestampMs;
        }
        _updateMaxTorsoLean(torsoLeanDeg);

        if (elbowAngleDeg < config.loweringEnterDeg) {
          _phase = OverheadPressPhase.lowering;
          transitionReason = 'loweringStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case OverheadPressPhase.lowering:
        if (elbowAngleDeg < _minRackElbowAngleInCurrentRep) {
          _minRackElbowAngleInCurrentRep = elbowAngleDeg;
        }
        if (elbowAngleDeg > _peakLockoutAngleInCurrentRep) {
          _peakLockoutAngleInCurrentRep = elbowAngleDeg;
        }
        _updateMaxTorsoLean(torsoLeanDeg);

        if (elbowAngleDeg >= config.lockoutEnterDeg &&
            isWristAboveShoulder &&
            isPlausibleTorso) {
          _phase = OverheadPressPhase.lockout;
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
              final isBackVertical = _maxTorsoLeanInCurrentRep != null
                  ? _maxTorsoLeanInCurrentRep! <= config.maxValidTorsoLeanDeg
                  : null;
              newRepEvent = OverheadPressRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs: _lockoutReachedTimestampMs ??
                    ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _peakLockoutAngleInCurrentRep,
                status: 'PROVISIONAL',
                minRackElbowAngleDeg: _minRackElbowAngleInCurrentRep,
                maxTorsoLeanDeg: _maxTorsoLeanInCurrentRep,
                isBackVertical: isBackVertical,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = isPlausibleTorso
                ? OverheadPressPhase.ready
                : OverheadPressPhase.notReady;
            _repStartTimestampMs = null;
            _lockoutReachedTimestampMs = null;
            _extendedCandidateStartMs = null;
            _minRackElbowAngleInCurrentRep = elbowAngleDeg;
            _peakLockoutAngleInCurrentRep = 0.0;
            _maxTorsoLeanInCurrentRep = null;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return OverheadPressBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      elbowAngleDeg: elbowAngleDeg,
      isWristAboveShoulder: isWristAboveShoulder,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  bool _isTorsoPlausible(double? torsoLeanDeg) {
    if (torsoLeanDeg != null &&
        torsoLeanDeg.isFinite &&
        torsoLeanDeg > config.maxPlausibleTorsoLeanDeg) {
      return false;
    }
    return true;
  }

  void _updateMaxTorsoLean(double? torsoLeanDeg) {
    if (torsoLeanDeg != null && torsoLeanDeg.isFinite) {
      if (_maxTorsoLeanInCurrentRep == null ||
          torsoLeanDeg > _maxTorsoLeanInCurrentRep!) {
        _maxTorsoLeanInCurrentRep = torsoLeanDeg;
      }
    }
  }

  void _abortInProgressCycle() {
    _phase = OverheadPressPhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _lockoutReachedTimestampMs = null;
    _minRackElbowAngleInCurrentRep = 180.0;
    _peakLockoutAngleInCurrentRep = 0.0;
    _maxTorsoLeanInCurrentRep = null;
  }
}

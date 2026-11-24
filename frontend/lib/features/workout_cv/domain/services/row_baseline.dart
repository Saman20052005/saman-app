import 'dart:math' as math;

import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for the Row exercise state machine.
enum RowPhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Arms extended in start/finish zone (elbow angle >= 145 deg).
  extended,

  /// Concentric pulling phase (elbow angle < 130 deg toward torso).
  pulling,

  /// Peak contraction at top of row (elbow angle <= 75-80 deg).
  flexed,

  /// Eccentric returning phase back toward extension (elbow angle > 95 deg).
  returning,
}

/// A completed Row rep event emitted when returning to arm extension.
class RowRepEvent extends LatPulldownRepEvent {
  final String? activeSide;
  final double? baselineTorsoLeanDeg;
  final double? maxTorsoSwingDeg;
  final bool? isBackStable;

  const RowRepEvent({
    required super.repNumber,
    required super.startTimestampMs,
    required super.bottomTimestampMs,
    required super.endTimestampMs,
    required super.durationMs,
    required super.minElbowAngleDeg,
    super.status = 'PROVISIONAL',
    this.activeSide,
    this.baselineTorsoLeanDeg,
    this.maxTorsoSwingDeg,
    this.isBackStable,
  });
}

/// Configuration parameters for [RowBaseline].
class RowBaselineConfig {
  final double extendedEnterDeg;
  final double pullingEnterDeg;
  final double flexedEnterDeg;
  final double returningEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;
  final double maxValidTorsoSwingDeg;

  const RowBaselineConfig({
    this.extendedEnterDeg = 145.0,
    this.pullingEnterDeg = 130.0,
    this.flexedEnterDeg = 80.0,
    this.returningEnterDeg = 95.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
    this.maxValidTorsoSwingDeg = 25.0,
  });
}

/// Output record for a single processed Row frame.
class RowBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final RowPhase phase;
  final int completedReps;
  final RowRepEvent? newRepEvent;
  final double? elbowAngleDeg;
  final String? activeSide;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const RowBaselineFrameResult({
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

/// Pure Dart causal 5-phase FSM for Barbell, Seated Cable, and One-Arm Dumbbell Rows.
///
/// Tracks per-rep side-locking when both arms are visible and monitors torso
/// angle stability relative to the rep's starting torso lean (`<= 25 deg` swing).
class RowBaseline {
  final RowBaselineConfig config;

  RowPhase _phase = RowPhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakFlexedTimestampMs;
  double _minElbowAngleInCurrentRep = 180.0;
  double? _baselineTorsoLeanDeg;
  double? _maxTorsoSwingInCurrentRep;
  String? _lockedSide;
  int _droppedNonMonotonicFrames = 0;

  RowBaseline({RowBaselineConfig? config})
      : config = config ?? const RowBaselineConfig();

  /// Creates a configured baseline matching [slug].
  factory RowBaseline.forSlug(String slug) {
    switch (slug.toLowerCase().trim()) {
      case 'bent-over-barbell-row':
      case 'one-arm-dumbbell-row':
        return RowBaseline(
          config: const RowBaselineConfig(
            flexedEnterDeg: 75.0,
            returningEnterDeg: 95.0,
          ),
        );
      case 'seated-cable-row':
      default:
        return RowBaseline(
          config: const RowBaselineConfig(
            flexedEnterDeg: 80.0,
            returningEnterDeg: 95.0,
          ),
        );
    }
  }

  RowPhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  String? get lockedSide => _lockedSide;
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = RowPhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _baselineTorsoLeanDeg = null;
    _maxTorsoSwingInCurrentRep = null;
    _lockedSide = null;
    _droppedNonMonotonicFrames = 0;
  }

  /// Processes a [RowFrameFeatures] container with per-rep side-locking.
  RowBaselineFrameResult processRowFeatures(RowFrameFeatures features) {
    if (_lastTimestampMs != null && features.timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return RowBaselineFrameResult(
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
      return RowBaselineFrameResult(
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
    final torsoLean =
        features.torsoLeanDeg.isValid ? features.torsoLeanDeg.value : null;

    if (_lockedSide != null) {
      final lockedAngle = _lockedSide == 'left' ? leftAngle : rightAngle;
      return _processValidatedSample(
        frameIndex: features.frameIndex,
        timestampMs: features.timestampMs,
        elbowAngleDeg: lockedAngle,
        torsoLeanDeg: torsoLean,
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
      if (_phase != RowPhase.notReady) {
        preLockGapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }

    String? selectedSide;
    double? selectedAngle;

    if (_phase == RowPhase.extended) {
      final leftPulling =
          leftAngle != null && leftAngle < config.pullingEnterDeg;
      final rightPulling =
          rightAngle != null && rightAngle < config.pullingEnterDeg;
      if (leftPulling && rightPulling) {
        selectedSide = features.leftElbowVisibilityScore >=
                features.rightElbowVisibilityScore
            ? 'left'
            : 'right';
      } else if (leftPulling) {
        selectedSide = 'left';
      } else if (rightPulling) {
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
      torsoLeanDeg: torsoLean,
      activeSide: _lockedSide ?? selectedSide,
      isSampleValid: true,
      precheckedGapResetReason: preLockGapResetReason,
      skipGapCheck: true,
    );
  }

  RowBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    double? torsoLeanDeg,
    String? activeSide,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return RowBaselineFrameResult(
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
      return RowBaselineFrameResult(
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
      torsoLeanDeg: torsoLeanDeg,
      activeSide: activeSide,
      isSampleValid: isSampleValid,
    );
  }

  RowBaselineFrameResult _processValidatedSample({
    required int frameIndex,
    required int timestampMs,
    double? elbowAngleDeg,
    double? torsoLeanDeg,
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
        return RowBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return RowBaselineFrameResult(
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
        if (_phase != RowPhase.notReady) {
          gapResetReason = 'dataLossGapBeforeValidSample';
        }
        _abortInProgressCycle();
      }
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    RowRepEvent? newRepEvent;

    switch (_phase) {
      case RowPhase.notReady:
        if (elbowAngleDeg >= config.extendedEnterDeg) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = RowPhase.extended;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case RowPhase.extended:
        if (elbowAngleDeg < config.pullingEnterDeg) {
          _phase = RowPhase.pulling;
          transitionReason = 'pullingStarted';
          _repStartTimestampMs = timestampMs;
          _peakFlexedTimestampMs = null;
          _extendedCandidateStartMs = null;
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          if (torsoLeanDeg != null && torsoLeanDeg.isFinite) {
            _baselineTorsoLeanDeg = torsoLeanDeg;
            _maxTorsoSwingInCurrentRep = 0.0;
          } else {
            _baselineTorsoLeanDeg = null;
            _maxTorsoSwingInCurrentRep = null;
          }
          if (_lockedSide == null && activeSide != null) {
            _lockedSide = activeSide;
          }
        }
        break;

      case RowPhase.pulling:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        _updateTorsoStability(torsoLeanDeg);

        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = RowPhase.flexed;
          transitionReason = 'flexedReached';
          _peakFlexedTimestampMs = timestampMs;
        } else if (elbowAngleDeg >= config.pullingEnterDeg) {
          _phase = RowPhase.extended;
          transitionReason = 'incompletePullReturnedToExtended';
          _clearCurrentRepMetrics();
        }
        break;

      case RowPhase.flexed:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
          _peakFlexedTimestampMs = timestampMs;
        }
        _updateTorsoStability(torsoLeanDeg);

        if (elbowAngleDeg > config.returningEnterDeg) {
          _phase = RowPhase.returning;
          transitionReason = 'returningStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case RowPhase.returning:
        if (elbowAngleDeg < _minElbowAngleInCurrentRep) {
          _minElbowAngleInCurrentRep = elbowAngleDeg;
        }
        _updateTorsoStability(torsoLeanDeg);

        if (elbowAngleDeg <= config.flexedEnterDeg) {
          _phase = RowPhase.flexed;
          transitionReason = 'reFlexedDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (elbowAngleDeg >= config.extendedEnterDeg) {
          _extendedCandidateStartMs ??= timestampMs;
          if ((timestampMs - _extendedCandidateStartMs!) >=
              config.minExtendedHoldMs) {
            final repStart = _repStartTimestampMs ?? timestampMs;
            final duration = timestampMs - repStart;

            if (duration >= config.minRepDurationMs &&
                duration <= config.maxRepDurationMs) {
              _completedReps++;
              final isBackStable = _maxTorsoSwingInCurrentRep != null
                  ? _maxTorsoSwingInCurrentRep! <= config.maxValidTorsoSwingDeg
                  : null;
              newRepEvent = RowRepEvent(
                repNumber: _completedReps,
                startTimestampMs: repStart,
                bottomTimestampMs:
                    _peakFlexedTimestampMs ?? ((repStart + timestampMs) ~/ 2),
                endTimestampMs: timestampMs,
                durationMs: duration,
                minElbowAngleDeg: _minElbowAngleInCurrentRep,
                status: 'PROVISIONAL',
                activeSide: _lockedSide ?? activeSide,
                baselineTorsoLeanDeg: _baselineTorsoLeanDeg,
                maxTorsoSwingDeg: _maxTorsoSwingInCurrentRep,
                isBackStable: isBackStable,
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = RowPhase.extended;
            _clearCurrentRepMetrics();
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return RowBaselineFrameResult(
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

  void _updateTorsoStability(double? torsoLeanDeg) {
    if (torsoLeanDeg == null || !torsoLeanDeg.isFinite) return;
    if (_baselineTorsoLeanDeg == null) {
      _baselineTorsoLeanDeg = torsoLeanDeg;
      _maxTorsoSwingInCurrentRep ??= 0.0;
      return;
    }
    final swing = (torsoLeanDeg - _baselineTorsoLeanDeg!).abs();
    _maxTorsoSwingInCurrentRep = math.max(
      _maxTorsoSwingInCurrentRep ?? 0.0,
      swing,
    );
  }

  void _clearCurrentRepMetrics() {
    _repStartTimestampMs = null;
    _peakFlexedTimestampMs = null;
    _extendedCandidateStartMs = null;
    _minElbowAngleInCurrentRep = 180.0;
    _baselineTorsoLeanDeg = null;
    _maxTorsoSwingInCurrentRep = null;
    _lockedSide = null;
  }

  void _abortInProgressCycle() {
    _phase = RowPhase.notReady;
    _readyCandidateStartMs = null;
    _clearCurrentRepMetrics();
  }
}

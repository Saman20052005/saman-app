import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for lower-body machine and unilateral lunge state machines.
enum LegMachinePhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Starting posture (flexed for pressOrExtend, extended for curl/lunge).
  ready,

  /// Active concentric/eccentric movement toward peak.
  active,

  /// Peak position reached (full extension for pressOrExtend, peak flexion for curl/lunge).
  peak,

  /// Returning phase back toward starting posture.
  returning,
}

/// Direction and knee-selection mode for [LegMachineBaseline].
enum LegMachineMode {
  /// Starts flexed (<= 105 deg), extends to peak (>= 150 deg), returns flexed.
  pressOrExtend,

  /// Starts extended (>= 150 deg), curls to peak flexion (<= 85 deg), returns extended.
  curl,

  /// Starts standing (>= 150 deg), lunges to peak flexion (<= 105 deg) using minValidKneeAngleDeg, returns standing.
  lunge,
}

/// Configuration parameters for [LegMachineBaseline].
class LegMachineBaselineConfig {
  final LegMachineMode mode;
  final double readyEnterDeg;
  final double activeEnterDeg;
  final double peakEnterDeg;
  final double returnEnterDeg;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;

  const LegMachineBaselineConfig({
    this.mode = LegMachineMode.pressOrExtend,
    this.readyEnterDeg = 105.0,
    this.activeEnterDeg = 120.0,
    this.peakEnterDeg = 150.0,
    this.returnEnterDeg = 130.0,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Leg Machine / Lunge frame.
class LegMachineBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final LegMachinePhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? kneeAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const LegMachineBaselineFrameResult({
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

/// Pure Dart causal 5-phase FSM for Leg Press, Leg Extension, Lying Leg Curl,
/// Reverse Lunge, and Bulgarian Split Squat.
class LegMachineBaseline {
  final LegMachineBaselineConfig config;

  LegMachinePhase _phase = LegMachinePhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakTimestampMs;
  double _extremumKneeAngleInCurrentRep = 0.0;
  int _droppedNonMonotonicFrames = 0;

  LegMachineBaseline({LegMachineBaselineConfig? config})
      : config = config ?? const LegMachineBaselineConfig() {
    _extremumKneeAngleInCurrentRep =
        this.config.mode == LegMachineMode.pressOrExtend ? 0.0 : 180.0;
  }

  /// Creates a configured baseline matching [slug] in `curatedExerciseLibrary`.
  factory LegMachineBaseline.forSlug(String slug) {
    switch (slug.toLowerCase().trim()) {
      case 'lying-leg-curl':
        return LegMachineBaseline(
          config: const LegMachineBaselineConfig(
            mode: LegMachineMode.curl,
            readyEnterDeg: 150.0,
            activeEnterDeg: 135.0,
            peakEnterDeg: 85.0,
            returnEnterDeg: 105.0,
          ),
        );
      case 'reverse-lunge':
      case 'bulgarian-split-squat':
        return LegMachineBaseline(
          config: const LegMachineBaselineConfig(
            mode: LegMachineMode.lunge,
            readyEnterDeg: 150.0,
            activeEnterDeg: 135.0,
            peakEnterDeg: 105.0,
            returnEnterDeg: 120.0,
          ),
        );
      case 'leg-press':
      case 'leg-extension':
      default:
        return LegMachineBaseline(
          config: const LegMachineBaselineConfig(
            mode: LegMachineMode.pressOrExtend,
            readyEnterDeg: 105.0,
            activeEnterDeg: 120.0,
            peakEnterDeg: 150.0,
            returnEnterDeg: 130.0,
          ),
        );
    }
  }

  LegMachinePhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = LegMachinePhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakTimestampMs = null;
    _extremumKneeAngleInCurrentRep =
        config.mode == LegMachineMode.pressOrExtend ? 0.0 : 180.0;
    _droppedNonMonotonicFrames = 0;
  }

  LegMachineBaselineFrameResult processExtendedFeatures(
    ExtendedLibraryFrameFeatures features,
  ) {
    final measurement = config.mode == LegMachineMode.lunge
        ? features.minValidKneeAngleDeg
        : features.bestKneeAngleDeg;
    final isKneeValid = measurement.isValid;
    final kneeAngle = isKneeValid ? measurement.value : null;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      kneeAngleDeg: kneeAngle,
      isSampleValid: isKneeValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  LegMachineBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? kneeAngleDeg,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return LegMachineBaselineFrameResult(
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
      _abortInProgressCycle();
      return LegMachineBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        kneeAngleDeg: kneeAngleDeg,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    if (!isSampleValid || kneeAngleDeg == null || !kneeAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        _abortInProgressCycle();
        return LegMachineBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return LegMachineBaselineFrameResult(
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
      if (_phase != LegMachinePhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;

    switch (_phase) {
      case LegMachinePhase.notReady:
        if (_isReadyAngle(kneeAngleDeg)) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = LegMachinePhase.ready;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case LegMachinePhase.ready:
        if (_isActiveStarted(kneeAngleDeg)) {
          _phase = LegMachinePhase.active;
          transitionReason = 'activePhaseStarted';
          _repStartTimestampMs = timestampMs;
          _peakTimestampMs = null;
          _extendedCandidateStartMs = null;
          _extremumKneeAngleInCurrentRep = kneeAngleDeg;
        }
        break;

      case LegMachinePhase.active:
        _updateExtremum(kneeAngleDeg);

        if (_isPeakReached(kneeAngleDeg)) {
          _phase = LegMachinePhase.peak;
          transitionReason = 'peakReached';
          _peakTimestampMs = timestampMs;
        } else if (_isReturnedBeforePeak(kneeAngleDeg)) {
          _phase = LegMachinePhase.ready;
          transitionReason = 'incompleteCycleReturnedToReady';
          _repStartTimestampMs = null;
        }
        break;

      case LegMachinePhase.peak:
        if (_isBetterExtremum(kneeAngleDeg)) {
          _extremumKneeAngleInCurrentRep = kneeAngleDeg;
          _peakTimestampMs = timestampMs;
        }

        if (_isReturningStarted(kneeAngleDeg)) {
          _phase = LegMachinePhase.returning;
          transitionReason = 'returningStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case LegMachinePhase.returning:
        _updateExtremum(kneeAngleDeg);

        if (_isPeakReached(kneeAngleDeg)) {
          _phase = LegMachinePhase.peak;
          transitionReason = 'rePeakedDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (_isReadyAngle(kneeAngleDeg)) {
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
                minElbowAngleDeg: _extremumKneeAngleInCurrentRep,
                status: 'PROVISIONAL',
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = LegMachinePhase.ready;
            _repStartTimestampMs = null;
            _peakTimestampMs = null;
            _extendedCandidateStartMs = null;
            _extremumKneeAngleInCurrentRep =
                config.mode == LegMachineMode.pressOrExtend ? 0.0 : 180.0;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return LegMachineBaselineFrameResult(
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

  bool get _isExtendPeak => config.mode == LegMachineMode.pressOrExtend;

  bool _isReadyAngle(double angle) =>
      _isExtendPeak ? angle <= config.readyEnterDeg : angle >= config.readyEnterDeg;

  bool _isActiveStarted(double angle) =>
      _isExtendPeak ? angle > config.activeEnterDeg : angle < config.activeEnterDeg;

  bool _isPeakReached(double angle) =>
      _isExtendPeak ? angle >= config.peakEnterDeg : angle <= config.peakEnterDeg;

  bool _isReturnedBeforePeak(double angle) =>
      _isExtendPeak ? angle <= config.activeEnterDeg : angle >= config.activeEnterDeg;

  bool _isReturningStarted(double angle) =>
      _isExtendPeak ? angle < config.returnEnterDeg : angle > config.returnEnterDeg;

  bool _isBetterExtremum(double angle) => _isExtendPeak
      ? angle > _extremumKneeAngleInCurrentRep
      : angle < _extremumKneeAngleInCurrentRep;

  void _updateExtremum(double angle) {
    if (_isBetterExtremum(angle)) {
      _extremumKneeAngleInCurrentRep = angle;
    }
  }

  void _abortInProgressCycle() {
    _phase = LegMachinePhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakTimestampMs = null;
    _extremumKneeAngleInCurrentRep = _isExtendPeak ? 0.0 : 180.0;
  }
}

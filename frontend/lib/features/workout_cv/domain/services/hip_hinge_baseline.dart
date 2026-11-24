import 'lat_pulldown_baseline.dart';
import 'workout_cv_motion_features.dart';

/// Operational phases for Hip Hinge and Hip Thrust state machines.
enum HipHingePhase {
  /// Subject is setting up or has lost required tracking; not yet ready to record reps.
  notReady,

  /// Starting posture (standing for hingeDown, bottom flexed hip for thrustUp).
  ready,

  /// Active movement phase toward peak (hinging down or thrusting up).
  hinging,

  /// Peak position reached (bottom hinge flexion or top hip lockout).
  peak,

  /// Returning phase back toward starting posture.
  returning,
}

/// Direction mode for [HipHingeBaseline].
enum HipHingeMode {
  /// Starts extended (high hip angle), hinges down to low hip angle, returns extended.
  hingeDown,

  /// Starts flexed (low hip angle), thrusts up to high hip lockout angle, returns flexed.
  thrustUp,
}

/// Configuration parameters for [HipHingeBaseline].
class HipHingeBaselineConfig {
  final HipHingeMode mode;
  final double readyEnterDeg;
  final double activeEnterDeg;
  final double peakEnterDeg;
  final double returnEnterDeg;
  final double? minKneeAngleForHingeDeg;
  final bool requireWristAboveShoulder;
  final int minReadyHoldMs;
  final int minExtendedHoldMs;
  final int minRepDurationMs;
  final int maxRepDurationMs;
  final int maxAllowedGapMs;

  const HipHingeBaselineConfig({
    this.mode = HipHingeMode.hingeDown,
    this.readyEnterDeg = 155.0,
    this.activeEnterDeg = 140.0,
    this.peakEnterDeg = 105.0,
    this.returnEnterDeg = 120.0,
    this.minKneeAngleForHingeDeg = 130.0,
    this.requireWristAboveShoulder = false,
    this.minReadyHoldMs = 200,
    this.minExtendedHoldMs = 150,
    this.minRepDurationMs = 800,
    this.maxRepDurationMs = 12000,
    this.maxAllowedGapMs = 500,
  });
}

/// Output record for a single processed Hip Hinge / Hip Thrust frame.
class HipHingeBaselineFrameResult {
  final int frameIndex;
  final int timestampMs;
  final HipHingePhase phase;
  final int completedReps;
  final LatPulldownRepEvent? newRepEvent;
  final double? hipAngleDeg;
  final double? kneeAngleDeg;
  final bool isSampleValid;
  final String? transitionReason;
  final String? resetReason;

  const HipHingeBaselineFrameResult({
    required this.frameIndex,
    required this.timestampMs,
    required this.phase,
    required this.completedReps,
    this.newRepEvent,
    this.hipAngleDeg,
    this.kneeAngleDeg,
    required this.isSampleValid,
    this.transitionReason,
    this.resetReason,
  });

  bool get hasNewRep => newRepEvent != null;
}

/// Pure Dart causal 5-phase FSM for Hip Hinge, Hanging Leg Raise, and Hip Thrust.
class HipHingeBaseline {
  final HipHingeBaselineConfig config;

  HipHingePhase _phase = HipHingePhase.notReady;
  int _completedReps = 0;
  final List<LatPulldownRepEvent> _repHistory = [];

  int? _lastValidTimestampMs;
  int? _lastTimestampMs;
  int? _readyCandidateStartMs;
  int? _extendedCandidateStartMs;
  int? _repStartTimestampMs;
  int? _peakTimestampMs;
  double _extremumHipAngleInCurrentRep = 180.0;
  int _droppedNonMonotonicFrames = 0;

  HipHingeBaseline({HipHingeBaselineConfig? config})
      : config = config ?? const HipHingeBaselineConfig();

  /// Creates a configured baseline matching [slug] in `curatedExerciseLibrary`.
  factory HipHingeBaseline.forSlug(String slug) {
    switch (slug.toLowerCase().trim()) {
      case 'hanging-leg-raise':
        return HipHingeBaseline(
          config: const HipHingeBaselineConfig(
            mode: HipHingeMode.hingeDown,
            readyEnterDeg: 145.0,
            activeEnterDeg: 130.0,
            peakEnterDeg: 95.0,
            returnEnterDeg: 110.0,
            minKneeAngleForHingeDeg: null,
            requireWristAboveShoulder: true,
          ),
        );
      case 'barbell-hip-thrust':
      case 'glute-bridge':
        return HipHingeBaseline(
          config: const HipHingeBaselineConfig(
            mode: HipHingeMode.thrustUp,
            readyEnterDeg: 130.0,
            activeEnterDeg: 140.0,
            peakEnterDeg: 160.0,
            returnEnterDeg: 145.0,
            minKneeAngleForHingeDeg: null,
            requireWristAboveShoulder: false,
          ),
        );
      case 'romanian-deadlift':
      default:
        return HipHingeBaseline(
          config: const HipHingeBaselineConfig(
            mode: HipHingeMode.hingeDown,
            readyEnterDeg: 155.0,
            activeEnterDeg: 140.0,
            peakEnterDeg: 105.0,
            returnEnterDeg: 120.0,
            minKneeAngleForHingeDeg: 130.0,
            requireWristAboveShoulder: false,
          ),
        );
    }
  }

  HipHingePhase get phase => _phase;
  int get completedReps => _completedReps;
  List<LatPulldownRepEvent> get repHistory => List.unmodifiable(_repHistory);
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  void reset() {
    _phase = HipHingePhase.notReady;
    _completedReps = 0;
    _repHistory.clear();
    _lastValidTimestampMs = null;
    _lastTimestampMs = null;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakTimestampMs = null;
    _extremumHipAngleInCurrentRep =
        config.mode == HipHingeMode.hingeDown ? 180.0 : 0.0;
    _droppedNonMonotonicFrames = 0;
  }

  HipHingeBaselineFrameResult processExtendedFeatures(
    ExtendedLibraryFrameFeatures features,
  ) {
    final isHipValid = features.bestHipAngleDeg.isValid;
    final hipAngle = isHipValid ? features.bestHipAngleDeg.value : null;
    final kneeAngle = features.bestKneeAngleDeg.isValid
        ? features.bestKneeAngleDeg.value
        : null;
    final wristOk = !features.hasWristSignal || features.isWristAboveShoulder;

    return processSample(
      frameIndex: features.frameIndex,
      timestampMs: features.timestampMs,
      hipAngleDeg: hipAngle,
      kneeAngleDeg: kneeAngle,
      isWristAboveShoulder: wristOk,
      isSampleValid: isHipValid && features.isGateDetecting,
      isGateDetecting: features.isGateDetecting,
    );
  }

  HipHingeBaselineFrameResult processSample({
    required int frameIndex,
    required int timestampMs,
    double? hipAngleDeg,
    double? kneeAngleDeg,
    bool isWristAboveShoulder = true,
    required bool isSampleValid,
    bool isGateDetecting = true,
  }) {
    if (_lastTimestampMs != null && timestampMs <= _lastTimestampMs!) {
      _droppedNonMonotonicFrames++;
      return HipHingeBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        hipAngleDeg: hipAngleDeg,
        kneeAngleDeg: kneeAngleDeg,
        isSampleValid: false,
        resetReason: 'droppedNonMonotonicTimestamp',
      );
    }
    _lastTimestampMs = timestampMs;

    if (!isGateDetecting) {
      _abortInProgressCycle();
      return HipHingeBaselineFrameResult(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        phase: _phase,
        completedReps: _completedReps,
        hipAngleDeg: hipAngleDeg,
        kneeAngleDeg: kneeAngleDeg,
        isSampleValid: false,
        resetReason: 'gateNotDetecting',
      );
    }

    if (!isSampleValid || hipAngleDeg == null || !hipAngleDeg.isFinite) {
      _readyCandidateStartMs = null;
      _extendedCandidateStartMs = null;

      if (_lastValidTimestampMs != null &&
          (timestampMs - _lastValidTimestampMs!) > config.maxAllowedGapMs) {
        _abortInProgressCycle();
        return HipHingeBaselineFrameResult(
          frameIndex: frameIndex,
          timestampMs: timestampMs,
          phase: _phase,
          completedReps: _completedReps,
          isSampleValid: false,
          resetReason: 'dataLossGapExceeded',
        );
      }

      return HipHingeBaselineFrameResult(
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
      if (_phase != HipHingePhase.notReady) {
        gapResetReason = 'dataLossGapBeforeValidSample';
      }
      _abortInProgressCycle();
    }
    _lastValidTimestampMs = timestampMs;

    String? transitionReason;
    LatPulldownRepEvent? newRepEvent;
    final bool wristReady =
        !config.requireWristAboveShoulder || isWristAboveShoulder;
    final bool kneeReadyForPeak = config.minKneeAngleForHingeDeg == null ||
        kneeAngleDeg == null ||
        !kneeAngleDeg.isFinite ||
        kneeAngleDeg >= config.minKneeAngleForHingeDeg!;

    switch (_phase) {
      case HipHingePhase.notReady:
        if (_isReadyAngle(hipAngleDeg) && wristReady) {
          _readyCandidateStartMs ??= timestampMs;
          if ((timestampMs - _readyCandidateStartMs!) >=
              config.minReadyHoldMs) {
            _phase = HipHingePhase.ready;
            transitionReason = 'readyHoldSatisfied';
            _readyCandidateStartMs = null;
            _repStartTimestampMs = null;
          }
        } else {
          _readyCandidateStartMs = null;
        }
        break;

      case HipHingePhase.ready:
        if (!wristReady) {
          _abortInProgressCycle();
          transitionReason = 'wristNotAboveShoulder';
          break;
        }
        if (_isActiveStarted(hipAngleDeg)) {
          _phase = HipHingePhase.hinging;
          transitionReason = 'activePhaseStarted';
          _repStartTimestampMs = timestampMs;
          _peakTimestampMs = null;
          _extendedCandidateStartMs = null;
          _extremumHipAngleInCurrentRep = hipAngleDeg;
        }
        break;

      case HipHingePhase.hinging:
        _updateExtremum(hipAngleDeg);

        if (_isPeakReached(hipAngleDeg) && kneeReadyForPeak && wristReady) {
          _phase = HipHingePhase.peak;
          transitionReason = 'peakReached';
          _peakTimestampMs = timestampMs;
        } else if (_isReturnedBeforePeak(hipAngleDeg)) {
          _phase = HipHingePhase.ready;
          transitionReason = 'incompleteCycleReturnedToReady';
          _repStartTimestampMs = null;
        }
        break;

      case HipHingePhase.peak:
        if (_isBetterExtremum(hipAngleDeg)) {
          _extremumHipAngleInCurrentRep = hipAngleDeg;
          _peakTimestampMs = timestampMs;
        }

        if (_isReturningStarted(hipAngleDeg)) {
          _phase = HipHingePhase.returning;
          transitionReason = 'returningStarted';
          _extendedCandidateStartMs = null;
        }
        break;

      case HipHingePhase.returning:
        _updateExtremum(hipAngleDeg);

        if (_isPeakReached(hipAngleDeg) && kneeReadyForPeak && wristReady) {
          _phase = HipHingePhase.peak;
          transitionReason = 'rePeakedDuringReturn';
          _extendedCandidateStartMs = null;
        } else if (_isReadyAngle(hipAngleDeg)) {
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
                minElbowAngleDeg: _extremumHipAngleInCurrentRep,
                status: 'PROVISIONAL',
              );
              _repHistory.add(newRepEvent);
              transitionReason = 'repCompleted';
            } else if (duration < config.minRepDurationMs) {
              transitionReason = 'repTooShortIgnored';
            } else {
              transitionReason = 'repTooLongIgnored';
            }

            _phase = wristReady ? HipHingePhase.ready : HipHingePhase.notReady;
            _repStartTimestampMs = null;
            _peakTimestampMs = null;
            _extendedCandidateStartMs = null;
            _extremumHipAngleInCurrentRep =
                config.mode == HipHingeMode.hingeDown ? 180.0 : 0.0;
          }
        } else {
          _extendedCandidateStartMs = null;
        }
        break;
    }

    return HipHingeBaselineFrameResult(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      phase: _phase,
      completedReps: _completedReps,
      newRepEvent: newRepEvent,
      hipAngleDeg: hipAngleDeg,
      kneeAngleDeg: kneeAngleDeg,
      isSampleValid: true,
      transitionReason: transitionReason,
      resetReason: gapResetReason,
    );
  }

  bool _isReadyAngle(double angle) => config.mode == HipHingeMode.hingeDown
      ? angle >= config.readyEnterDeg
      : angle <= config.readyEnterDeg;

  bool _isActiveStarted(double angle) => config.mode == HipHingeMode.hingeDown
      ? angle < config.activeEnterDeg
      : angle > config.activeEnterDeg;

  bool _isPeakReached(double angle) => config.mode == HipHingeMode.hingeDown
      ? angle <= config.peakEnterDeg
      : angle >= config.peakEnterDeg;

  bool _isReturnedBeforePeak(double angle) =>
      config.mode == HipHingeMode.hingeDown
          ? angle >= config.activeEnterDeg
          : angle <= config.activeEnterDeg;

  bool _isReturningStarted(double angle) =>
      config.mode == HipHingeMode.hingeDown
          ? angle > config.returnEnterDeg
          : angle < config.returnEnterDeg;

  bool _isBetterExtremum(double angle) => config.mode == HipHingeMode.hingeDown
      ? angle < _extremumHipAngleInCurrentRep
      : angle > _extremumHipAngleInCurrentRep;

  void _updateExtremum(double angle) {
    if (_isBetterExtremum(angle)) {
      _extremumHipAngleInCurrentRep = angle;
    }
  }

  void _abortInProgressCycle() {
    _phase = HipHingePhase.notReady;
    _readyCandidateStartMs = null;
    _extendedCandidateStartMs = null;
    _repStartTimestampMs = null;
    _peakTimestampMs = null;
    _extremumHipAngleInCurrentRep =
        config.mode == HipHingeMode.hingeDown ? 180.0 : 0.0;
  }
}

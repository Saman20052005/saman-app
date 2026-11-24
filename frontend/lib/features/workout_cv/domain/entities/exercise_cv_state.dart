import 'pose_landmark.dart';
import '../services/cv_form_summary_calculator.dart';
import '../services/lat_pulldown_baseline.dart';
import '../services/workout_cv_exercise_registry.dart';

enum ReplayAnalysisStatus { waiting, analyzing, insufficientData, finished, error }

enum TrackingStatus {
  uninitialized,
  permissionDenied,
  needsSetup,
  detecting,
  lost,
  multiplePeople,
  error,
}

class ExerciseCvState {
  final TrackingStatus trackingStatus;
  final List<PoseLandmark> landmarks;
  final int timestamp;
  final int latencyMs;
  final int posesDetected;
  final String guideMessage;
  final String? errorMessage;
  final String exerciseId;
  final String exerciseSlug;
  final bool isCameraActive;
  final int frameCount;
  final double fps;
  final List<int> latencyHistoryMs;

  // Replay fields
  final String sourceMode; // 'camera' or 'video_replay'
  final String clipName;
  final int sessionGen;
  final int videoPtsMs;
  final int previewPtsMs;
  final int ptsSkewMs;
  final bool isPtsVerified;
  final double sourceFps;
  final bool isEndOfStream;
  final double readbackLatencyMs;
  final double overlayVisiblePct;
  final double overlayHiddenSkewPct;
  final double overlayHiddenNoResultPct;
  final double overlayHiddenGatePct;
  final ReplayAnalysisStatus replayAnalysisStatus;
  // Shared camera/replay analysis. Session-only; never written to workout sets.
  final LatPulldownPhase analysisPhase;
  final List<LatPulldownRepEvent> replayRepEvents;
  final int abortCount;

  const ExerciseCvState({
    this.trackingStatus = TrackingStatus.uninitialized,
    this.landmarks = const [],
    this.timestamp = 0,
    this.latencyMs = 0,
    this.posesDetected = 0,
    this.guideMessage = 'Initializing Camera...',
    this.errorMessage,
    this.exerciseId = '',
    this.exerciseSlug = '',
    this.isCameraActive = false,
    this.frameCount = 0,
    this.fps = 0.0,
    this.latencyHistoryMs = const [],
    this.sourceMode = 'camera',
    this.clipName = '',
    this.sessionGen = 0,
    this.videoPtsMs = 0,
    this.previewPtsMs = 0,
    this.ptsSkewMs = 0,
    this.isPtsVerified = true,
    this.sourceFps = 0.0,
    this.isEndOfStream = false,
    this.readbackLatencyMs = 0.0,
    this.overlayVisiblePct = 0.0,
    this.overlayHiddenSkewPct = 0.0,
    this.overlayHiddenNoResultPct = 0.0,
    this.overlayHiddenGatePct = 0.0,
    this.replayAnalysisStatus = ReplayAnalysisStatus.waiting,
    this.replayRepEvents = const [],
    this.analysisPhase = LatPulldownPhase.notReady,
    this.abortCount = 0,
  });

  int get completedReps => replayRepEvents.length;
  String get repCountLabel => localizedRepCountLabel(isVietnamese: true);

  String localizedRepCountLabel({required bool isVietnamese}) {
    final module = WorkoutCvExerciseRegistry.resolveModule(
      id: exerciseId,
      slug: exerciseSlug,
    );
    if (module == CvExerciseModule.plankHold) {
      return isVietnamese
          ? 'Giữ chuẩn: ${completedReps}s'
          : 'Valid hold: ${completedReps}s';
    }
    if (module == CvExerciseModule.latPulldown ||
        module == CvExerciseModule.pullUp ||
        module == null) {
      return isVietnamese
          ? 'Số lần kéo: $completedReps'
          : 'Pulls: $completedReps';
    }
    return isVietnamese ? 'Số rep: $completedReps' : 'Reps: $completedReps';
  }

  CvFormSummary get formSummary {
    final module = WorkoutCvExerciseRegistry.resolveModule(
      id: exerciseId,
      slug: exerciseSlug,
    );
    return CvFormSummaryCalculator.compute(
      reps: replayRepEvents,
      abortCount: abortCount,
      module: module,
    );
  }

  String get replayAnalysisLabel =>
      localizedReplayAnalysisLabel(isVietnamese: true);

  String localizedReplayAnalysisLabel({required bool isVietnamese}) {
    switch (replayAnalysisStatus) {
      case ReplayAnalysisStatus.waiting:
      case ReplayAnalysisStatus.analyzing:
        return isVietnamese ? 'Đang phân tích' : 'Analyzing';
      case ReplayAnalysisStatus.insufficientData:
        return isVietnamese ? 'Chưa đủ dữ liệu' : 'Insufficient data';
      case ReplayAnalysisStatus.finished:
        return isVietnamese ? 'Đã kết thúc' : 'Finished';
      case ReplayAnalysisStatus.error:
        return isVietnamese ? 'Lỗi phân tích' : 'Analysis error';
    }
  }

  String localizedPhaseLabel({required bool isVietnamese}) {
    switch (analysisPhase) {
      case LatPulldownPhase.notReady:
        return isVietnamese ? 'Đang chuẩn bị' : 'Getting ready';
      case LatPulldownPhase.extended:
        return isVietnamese ? 'Tư thế nghỉ' : 'Ready';
      case LatPulldownPhase.pulling:
        return isVietnamese ? 'Đang thực hiện' : 'Active';
      case LatPulldownPhase.flexed:
        return isVietnamese ? 'Đạt đỉnh' : 'Peak';
      case LatPulldownPhase.returning:
        return isVietnamese ? 'Trở về' : 'Returning';
    }
  }

  /// Display convention: in video_replay mode, hide skeleton if PTS provenance
  /// is not verified or if preview PTS is ahead of pose PTS by >80ms.
  /// Note: <=80ms is a visual display convention, not a rep-counting accuracy guarantee.
  bool get isSyncValid =>
      sourceMode == 'camera' ||
      (isPtsVerified && ptsSkewMs >= 0 && ptsSkewMs <= 80);

  ExerciseCvState copyWith({
    TrackingStatus? trackingStatus,
    List<PoseLandmark>? landmarks,
    int? timestamp,
    int? latencyMs,
    int? posesDetected,
    String? guideMessage,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? exerciseId,
    String? exerciseSlug,
    bool? isCameraActive,
    int? frameCount,
    double? fps,
    List<int>? latencyHistoryMs,
    String? sourceMode,
    String? clipName,
    int? sessionGen,
    int? videoPtsMs,
    int? previewPtsMs,
    int? ptsSkewMs,
    bool? isPtsVerified,
    double? sourceFps,
    bool? isEndOfStream,
    double? readbackLatencyMs,
    double? overlayVisiblePct,
    double? overlayHiddenSkewPct,
    double? overlayHiddenNoResultPct,
    double? overlayHiddenGatePct,
    ReplayAnalysisStatus? replayAnalysisStatus,
    List<LatPulldownRepEvent>? replayRepEvents,
    LatPulldownPhase? analysisPhase,
    int? abortCount,
  }) {
    return ExerciseCvState(
      trackingStatus: trackingStatus ?? this.trackingStatus,
      landmarks: landmarks ?? this.landmarks,
      timestamp: timestamp ?? this.timestamp,
      latencyMs: latencyMs ?? this.latencyMs,
      posesDetected: posesDetected ?? this.posesDetected,
      guideMessage: guideMessage ?? this.guideMessage,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseSlug: exerciseSlug ?? this.exerciseSlug,
      isCameraActive: isCameraActive ?? this.isCameraActive,
      frameCount: frameCount ?? this.frameCount,
      fps: fps ?? this.fps,
      latencyHistoryMs: latencyHistoryMs ?? this.latencyHistoryMs,
      sourceMode: sourceMode ?? this.sourceMode,
      clipName: clipName ?? this.clipName,
      sessionGen: sessionGen ?? this.sessionGen,
      videoPtsMs: videoPtsMs ?? this.videoPtsMs,
      previewPtsMs: previewPtsMs ?? this.previewPtsMs,
      ptsSkewMs: ptsSkewMs ?? this.ptsSkewMs,
      isPtsVerified: isPtsVerified ?? this.isPtsVerified,
      sourceFps: sourceFps ?? this.sourceFps,
      isEndOfStream: isEndOfStream ?? this.isEndOfStream,
      readbackLatencyMs: readbackLatencyMs ?? this.readbackLatencyMs,
      overlayVisiblePct: overlayVisiblePct ?? this.overlayVisiblePct,
      overlayHiddenSkewPct: overlayHiddenSkewPct ?? this.overlayHiddenSkewPct,
      overlayHiddenNoResultPct: overlayHiddenNoResultPct ?? this.overlayHiddenNoResultPct,
      overlayHiddenGatePct: overlayHiddenGatePct ?? this.overlayHiddenGatePct,
      replayAnalysisStatus: replayAnalysisStatus ?? this.replayAnalysisStatus,
      replayRepEvents: replayRepEvents ?? this.replayRepEvents,
      analysisPhase: analysisPhase ?? this.analysisPhase,
      abortCount: abortCount ?? this.abortCount,
    );
  }

  /// Calculates p50 and p95 latency from history
  int get p50LatencyMs {
    if (latencyHistoryMs.isEmpty) return 0;
    final sorted = [...latencyHistoryMs]..sort();
    final idx = (sorted.length * 0.50).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  int get p95LatencyMs {
    if (latencyHistoryMs.isEmpty) return 0;
    final sorted = [...latencyHistoryMs]..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

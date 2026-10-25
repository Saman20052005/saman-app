import 'pose_landmark.dart';
import '../services/lat_pulldown_baseline.dart';

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
  // Session-only results; never written to workout history or set completion.
  final List<LatPulldownRepEvent> replayRepEvents;

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
  });

  int get completedReps => replayRepEvents.length;
  String get repCountLabel => 'Số lần kéo: $completedReps';
  String get replayAnalysisLabel {
    switch (replayAnalysisStatus) {
      case ReplayAnalysisStatus.waiting:
        return 'Đang phân tích';
      case ReplayAnalysisStatus.analyzing:
        return 'Đang phân tích';
      case ReplayAnalysisStatus.insufficientData:
        return 'Chưa đủ dữ liệu';
      case ReplayAnalysisStatus.finished:
        return 'Đã kết thúc';
      case ReplayAnalysisStatus.error:
        return 'Lỗi phân tích';
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

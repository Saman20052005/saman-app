import 'pose_landmark.dart';

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
  });

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

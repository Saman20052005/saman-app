import 'dart:async';
import 'workout_cv_native_source.dart';

/// Playback speed mode for Workout CV replay.
enum ReplayPlaybackSpeed {
  /// Emits all frames synchronously / as fast as possible (for tests & batch evaluations).
  instant,

  /// Emits frames respecting their inter-frame timestamp deltas (simulating real-time video).
  realtime,
}

/// A data source that streams pre-extracted pose landmark frames from a video recording.
///
/// Implements [WorkoutCvDataSource] to share the identical downstream quality gate,
/// pose tracking, and state notifier logic used by the live camera source.
class WorkoutCvReplaySource extends WorkoutCvNativeSource {
  final List<Map<String, dynamic>> _frames;
  final ReplayPlaybackSpeed speed;
  final bool loop;
  final Map<String, dynamic>? metadata;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  /// Generation/Session token to cancel in-flight async callbacks on reset/seek/stop.
  int _sessionToken = 0;

  /// Tracks the last emitted timestamp to block non-monotonic timestamps.
  int _lastEmittedTimestamp = -1;

  /// Count of frames blocked due to non-increasing timestamps.
  int _droppedNonMonotonicFrames = 0;

  WorkoutCvReplaySource({
    required List<Map<String, dynamic>> frames,
    this.speed = ReplayPlaybackSpeed.instant,
    this.loop = false,
    this.metadata,
  }) : _frames = List.unmodifiable(frames);

  /// Constructs a replay source from a parsed JSON document produced by `extract_pose.py`.
  factory WorkoutCvReplaySource.fromJsonDoc(
    Map<String, dynamic> doc, {
    ReplayPlaybackSpeed speed = ReplayPlaybackSpeed.instant,
    bool loop = false,
  }) {
    final rawFrames = doc['frames'] as List<dynamic>? ?? [];
    final frames =
        rawFrames.map((f) => Map<String, dynamic>.from(f as Map)).toList();
    final metadata = doc['metadata'] != null
        ? Map<String, dynamic>.from(doc['metadata'] as Map)
        : null;

    return WorkoutCvReplaySource(
      frames: frames,
      speed: speed,
      loop: loop,
      metadata: metadata,
    );
  }

  int get totalFrames => _frames.length;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  int get lastEmittedTimestamp => _lastEmittedTimestamp;
  int get droppedNonMonotonicFrames => _droppedNonMonotonicFrames;

  @override
  Future<String> checkPermission() async => 'granted';

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> startSession(String exerciseSlug) async {
    _sessionToken++;
    _isPlaying = true;
    final token = _sessionToken;
    Timer.run(() {
      if (_sessionToken == token && _isPlaying) {
        _scheduleNext();
      }
    });
    return true;
  }

  @override
  Future<bool> stopSession() async {
    _sessionToken++;
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    return true;
  }

  Future<bool> startVideoReplay(String videoPath) async => false;

  Future<bool> switchSource(String mode, {String? videoPath}) async => false;

  Future<bool> restartVideoReplay() async => false;

  @override
  Stream<Map<String, dynamic>> get eventStream => _controller.stream;

  /// Resets replay progress back to frame 0 and emits a reset event to notify downstream controllers.
  ///
  /// Increments the session token so in-flight realtime timers from the previous session are cancelled.
  void reset() {
    _sessionToken++;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _currentIndex = 0;
    _lastEmittedTimestamp = -1;
    _droppedNonMonotonicFrames = 0;

    _safeEmit({
      'status': 'reset',
      'isReset': true,
      'timestamp': 0,
      'latencyMs': 0,
      'numPoses': 0,
      'landmarks': <Map<String, dynamic>>[],
      'guideMessage': 'Replay reset to beginning.',
    });

    if (_isPlaying) {
      _scheduleNext();
    }
  }

  /// Seeks to the frame closest to [timestampMs] and emits a reset event.
  ///
  /// Increments the session token so in-flight realtime timers cannot leak frames from the pre-seek state.
  void seekTo(int timestampMs) {
    _sessionToken++;
    _playbackTimer?.cancel();
    _playbackTimer = null;

    var targetIdx = 0;
    for (var i = 0; i < _frames.length; i++) {
      final ts =
          _parseInt(_frames[i]['timestamp_ms'] ?? _frames[i]['timestamp']);
      if (ts >= timestampMs) {
        targetIdx = i;
        break;
      }
    }
    _currentIndex = targetIdx;
    _lastEmittedTimestamp = targetIdx > 0
        ? _parseInt(
            _frames[targetIdx - 1]['timestamp_ms'] ??
                _frames[targetIdx - 1]['timestamp'],
            timestampMs - 1)
        : -1;

    _safeEmit({
      'status': 'reset',
      'isReset': true,
      'timestamp': timestampMs,
      'latencyMs': 0,
      'numPoses': 0,
      'landmarks': <Map<String, dynamic>>[],
      'guideMessage': 'Seeked to ${timestampMs}ms.',
    });

    if (_isPlaying) {
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    if (!_isPlaying || _controller.isClosed) return;

    if (_currentIndex >= _frames.length) {
      if (loop && _frames.isNotEmpty) {
        reset();
      } else {
        _isPlaying = false;
      }
      return;
    }

    final currentToken = _sessionToken;

    if (speed == ReplayPlaybackSpeed.instant) {
      while (_isPlaying &&
          _currentIndex < _frames.length &&
          _sessionToken == currentToken) {
        final frame = _frames[_currentIndex++];
        _emitFrame(frame);
      }
      if (loop &&
          _frames.isNotEmpty &&
          _isPlaying &&
          _sessionToken == currentToken) {
        reset();
      } else if (_currentIndex >= _frames.length) {
        _isPlaying = false;
      }
    } else {
      final frame = _frames[_currentIndex];
      final currentTs = _parseInt(frame['timestamp_ms'] ?? frame['timestamp']);

      var delayMs = 33; // Default fallback ~30fps
      if (_currentIndex + 1 < _frames.length) {
        final nextFrame = _frames[_currentIndex + 1];
        final nextTs = _parseInt(
            nextFrame['timestamp_ms'] ?? nextFrame['timestamp'], currentTs);
        delayMs = (nextTs - currentTs).clamp(1, 2000);
      }

      _emitFrame(frame);
      _currentIndex++;

      _playbackTimer = Timer(Duration(milliseconds: delayMs), () {
        if (_sessionToken == currentToken &&
            _isPlaying &&
            !_controller.isClosed) {
          _scheduleNext();
        }
      });
    }
  }

  void _emitFrame(Map<String, dynamic> rawFrame) {
    if (_controller.isClosed) return;

    final status = rawFrame['status'] as String? ?? 'lost';
    final timestamp =
        _parseInt(rawFrame['timestamp_ms'] ?? rawFrame['timestamp']);
    final latency = _parseInt(rawFrame['latency_ms'] ?? rawFrame['latencyMs']);
    final numPoses = _parseInt(rawFrame['num_poses'] ?? rawFrame['numPoses']);
    final rawLandmarks = rawFrame['landmarks'] as List<dynamic>? ?? [];

    // Strict Monotonicity Guard (matching Android CameraX / MediaPipe live stream behavior):
    // If a frame timestamp is non-increasing (timestamp <= _lastEmittedTimestamp),
    // drop the frame to prevent backwards temporal distortion in downstream controllers.
    if (_lastEmittedTimestamp >= 0 && timestamp <= _lastEmittedTimestamp) {
      _droppedNonMonotonicFrames++;
      return;
    }
    _lastEmittedTimestamp = timestamp;

    final landmarkList = rawLandmarks.map((lm) {
      if (lm is Map) {
        return Map<String, dynamic>.from(lm);
      }
      return <String, dynamic>{};
    }).toList();

    _safeEmit({
      'status': status,
      'timestamp': timestamp,
      'latencyMs': latency,
      'numPoses': numPoses,
      'landmarks': landmarkList,
      if (rawFrame['errorMessage'] != null)
        'errorMessage': rawFrame['errorMessage'],
    });
  }

  void _safeEmit(Map<String, dynamic> event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  static int _parseInt(dynamic val, [int fallback = 0]) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? fallback;
    return fallback;
  }

  void dispose() {
    _sessionToken++;
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

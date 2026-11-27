import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/cv_telemetry_service.dart';

/// Feature-flag execution mode for on-device Workout CV ML inference.
enum MlMode {
  /// Default 100% Rule-based mode (0 ML overhead).
  ruleBased,

  /// Runs ML inference in parallel for telemetry/logging without altering outputs.
  mlShadow,

  /// Uses high-confidence ML predictions to stabilize view angle with safe Rule-based fallback.
  mlAssisted;

  String get wireName {
    switch (this) {
      case MlMode.ruleBased:
        return 'ruleBased';
      case MlMode.mlShadow:
        return 'mlShadow';
      case MlMode.mlAssisted:
        return 'mlAssisted';
    }
  }

  static MlMode fromWireName(String? raw) {
    switch (raw?.trim()) {
      case 'mlShadow':
        return MlMode.mlShadow;
      case 'mlAssisted':
        return MlMode.mlAssisted;
      case 'ruleBased':
      default:
        return MlMode.ruleBased;
    }
  }
}

/// Persists and exposes the active [MlMode] via [SharedPreferences].
class MlModeNotifier extends StateNotifier<MlMode> {
  static const String prefKey = 'workout_cv_ml_mode';

  final SharedPreferences? _injectedPrefs;

  MlModeNotifier({
    SharedPreferences? prefs,
    MlMode initialMode = MlMode.ruleBased,
  })  : _injectedPrefs = prefs,
        super(initialMode) {
    _loadInitial();
  }

  Future<SharedPreferences> _getPrefs() async {
    return _injectedPrefs ?? await SharedPreferences.getInstance();
  }

  Future<void> _loadInitial() async {
    try {
      final prefs = await _getPrefs();
      final saved = prefs.getString(prefKey);
      if (saved != null && mounted) {
        state = MlMode.fromWireName(saved);
      }
    } catch (_) {
      // Fail-silent: keep safe default MlMode.ruleBased.
    }
  }

  Future<void> setMode(MlMode mode) async {
    state = mode;
    try {
      final prefs = await _getPrefs();
      await prefs.setString(prefKey, mode.wireName);
    } catch (_) {
      // Ignore storage errors to keep UI responsive.
    }
  }
}

final mlModeProvider = StateNotifierProvider<MlModeNotifier, MlMode>((ref) {
  return MlModeNotifier();
});

/// Snapshot of anonymous skeleton frames captured during a CV session
/// awaiting set log / edit confirmation in ActiveWorkoutScreen.
@immutable
class PendingCvTelemetrySnapshot {
  final String exerciseId;
  final String exerciseSlug;
  final String viewAngle;
  final double fps;
  final List<SkeletonFrameSample> frames;
  final int cvReps;
  final String mlMode;
  final DateTime capturedAt;

  const PendingCvTelemetrySnapshot({
    required this.exerciseId,
    required this.exerciseSlug,
    required this.viewAngle,
    required this.fps,
    required this.frames,
    required this.cvReps,
    required this.mlMode,
    required this.capturedAt,
  });
}

final pendingCvTelemetryProvider =
    StateProvider<PendingCvTelemetrySnapshot?>((ref) => null);

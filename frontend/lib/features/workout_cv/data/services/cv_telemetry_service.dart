import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/api_config.dart';
import '../../domain/entities/pose_landmark.dart';

/// Compact timestamped skeleton frame sample for anonymous CV telemetry.
class SkeletonFrameSample {
  final int timestampMs;
  final List<PoseLandmark> landmarks;

  const SkeletonFrameSample({
    required this.timestampMs,
    required this.landmarks,
  });
}

/// Encodes skeleton frame sequences into quantized, gzip-compressed JSON
/// without any PII, raw images, or video bytes.
class CvTelemetryEncoder {
  static const String schemaVersion = 'saman_skel_v1';
  static const int quantizationScale = 1000;
  static const int maxPayloadBytes = 256 * 1024;

  /// Evenly downsamples [frames] to at most [maxFrames] samples.
  static List<SkeletonFrameSample> downsampleFrames(
    List<SkeletonFrameSample> frames, {
    int maxFrames = 600,
  }) {
    if (maxFrames <= 0 || frames.isEmpty) {
      return const <SkeletonFrameSample>[];
    }
    if (frames.length <= maxFrames) {
      return frames;
    }
    if (maxFrames == 1) {
      return <SkeletonFrameSample>[frames.first];
    }

    final result = <SkeletonFrameSample>[];
    final lastIndex = frames.length - 1;
    for (var i = 0; i < maxFrames; i++) {
      final sourceIndex = (i * lastIndex) ~/ (maxFrames - 1);
      result.add(frames[sourceIndex]);
    }
    return result;
  }

  /// Quantizes 33-point landmarks (scaled by 1000) and compresses with gzip.
  static Uint8List encodeFramesGzipBytes(
    List<SkeletonFrameSample> frames, {
    int maxFrames = 600,
  }) {
    final sampled = downsampleFrames(frames, maxFrames: maxFrames);
    final payload = <String, dynamic>{
      'schema': schemaVersion,
      'scale': quantizationScale,
      'frames': sampled.map((frame) {
        return <String, dynamic>{
          't': frame.timestampMs,
          'lm': frame.landmarks.map((lm) {
            return <int>[
              (lm.x * quantizationScale).round(),
              (lm.y * quantizationScale).round(),
              (lm.z * quantizationScale).round(),
              (lm.visibility * quantizationScale).round(),
            ];
          }).toList(growable: false),
        };
      }).toList(growable: false),
    };

    final jsonBytes = utf8.encode(jsonEncode(payload));
    return Uint8List.fromList(gzip.encode(jsonBytes));
  }

  /// Encodes quantized skeleton frames as base64-encoded gzip JSON.
  static String encodeFramesGzipBase64(
    List<SkeletonFrameSample> frames, {
    int maxFrames = 600,
  }) {
    return base64Encode(encodeFramesGzipBytes(frames, maxFrames: maxFrames));
  }
}

/// Result of a fire-and-forget anonymous CV telemetry upload attempt.
class CvTelemetryUploadResult {
  final bool sent;
  final String? skippedReason;
  final int? statusCode;
  final int? payloadBytes;

  const CvTelemetryUploadResult({
    required this.sent,
    this.skippedReason,
    this.statusCode,
    this.payloadBytes,
  });
}

/// Manages opt-in state and anonymous skeleton telemetry upload for CV workouts.
class CvTelemetryService {
  static const String optInPrefKey = 'cv_telemetry_opt_in';

  final Dio _dio;
  final Future<String?> Function() _tokenProvider;
  final SharedPreferences? _injectedPrefs;

  CvTelemetryService({
    Dio? dio,
    Future<String?> Function()? tokenProvider,
    SharedPreferences? prefs,
  })  : _dio = dio ?? _createDefaultDio(),
        _tokenProvider = tokenProvider ?? _defaultTokenProvider,
        _injectedPrefs = prefs;

  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
  }

  static Future<String?> _defaultTokenProvider() async {
    try {
      const storage = FlutterSecureStorage();
      return await storage.read(key: 'auth_token') ??
          await storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    return _injectedPrefs ?? await SharedPreferences.getInstance();
  }

  Future<Map<String, String>> _buildAuthHeaders() async {
    String? token;
    try {
      token = await _tokenProvider();
    } catch (_) {
      token = null;
    }
    return <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns whether the user has explicitly opted in (default: false).
  Future<bool> isOptedIn() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getBool(optInPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Persists opt-in preference locally and best-effort syncs to user profile.
  Future<bool> setOptIn(bool enabled) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(optInPrefKey, enabled);
    } catch (_) {
      // Ignore local storage errors to keep UI responsive.
    }

    try {
      final headers = await _buildAuthHeaders();
      await _dio.put<dynamic>(
        ApiConfig.getProfileEndpoint,
        data: <String, dynamic>{
          'preferences': <String, dynamic>{
            optInPrefKey: enabled,
          },
        },
        options: Options(headers: headers),
      );
    } catch (_) {
      // Best-effort profile sync; local preference remains source of truth.
    }

    return enabled;
  }

  /// Fire-and-forget upload of quantized anonymous skeleton coordinates.
  /// Never performs network I/O when opt-in is disabled.
  Future<CvTelemetryUploadResult> uploadAnonymousSession({
    required String exerciseSlug,
    required String viewAngle,
    required double fps,
    required List<SkeletonFrameSample> frames,
    required int cvReps,
    int? finalLoggedReps,
    String mlMode = 'ruleBased',
    bool? overrideOptIn,
  }) async {
    final optedIn = overrideOptIn ?? await isOptedIn();
    if (!optedIn) {
      return const CvTelemetryUploadResult(
        sent: false,
        skippedReason: 'opt_in_disabled',
      );
    }

    if (frames.isEmpty) {
      return const CvTelemetryUploadResult(
        sent: false,
        skippedReason: 'empty_frames',
      );
    }

    try {
      final sampledFrames = CvTelemetryEncoder.downsampleFrames(frames);
      final gzipBytes = CvTelemetryEncoder.encodeFramesGzipBytes(sampledFrames);
      if (gzipBytes.length > CvTelemetryEncoder.maxPayloadBytes) {
        return CvTelemetryUploadResult(
          sent: false,
          skippedReason: 'payload_too_large',
          payloadBytes: gzipBytes.length,
        );
      }

      final payloadB64 = base64Encode(gzipBytes);
      final headers = await _buildAuthHeaders();
      final body = <String, dynamic>{
        'exercise_slug': exerciseSlug,
        'view_angle': viewAngle,
        'fps': fps,
        'frame_count': sampledFrames.length,
        'cv_reps': cvReps,
        'final_logged_reps': finalLoggedReps,
        'user_adjusted_reps':
            finalLoggedReps != null && finalLoggedReps != cvReps,
        'ml_mode': mlMode,
        'payload_encoding': 'gzip_json_b64',
        'compressed_payload_b64': payloadB64,
      };

      final response = await _dio.post<dynamic>(
        ApiConfig.workoutCvTelemetryEndpoint,
        data: body,
        options: Options(headers: headers),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return CvTelemetryUploadResult(
          sent: true,
          statusCode: statusCode,
          payloadBytes: gzipBytes.length,
        );
      }

      return CvTelemetryUploadResult(
        sent: false,
        skippedReason: 'http_$statusCode',
        statusCode: statusCode,
        payloadBytes: gzipBytes.length,
      );
    } catch (_) {
      return const CvTelemetryUploadResult(
        sent: false,
        skippedReason: 'network_error',
      );
    }
  }
}

final cvTelemetryServiceProvider = Provider<CvTelemetryService>((ref) {
  return CvTelemetryService();
});

class CvTelemetryOptInNotifier extends StateNotifier<bool> {
  final CvTelemetryService _service;

  CvTelemetryOptInNotifier(this._service) : super(false) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final enabled = await _service.isOptedIn();
    if (mounted) {
      state = enabled;
    }
  }

  Future<void> setOptIn(bool enabled) async {
    state = enabled;
    await _service.setOptIn(enabled);
  }
}

final cvTelemetryOptInProvider =
    StateNotifierProvider<CvTelemetryOptInNotifier, bool>((ref) {
  final service = ref.watch(cvTelemetryServiceProvider);
  return CvTelemetryOptInNotifier(service);
});

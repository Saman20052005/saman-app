import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../config/api_config.dart';

class VideoCompressionOutput {
  final String outputPath;
  final int sizeBytes;
  final double durationSec;
  final int width;
  final int height;
  final int rotationDegrees;
  final bool usedFastPath;

  const VideoCompressionOutput({
    required this.outputPath,
    required this.sizeBytes,
    required this.durationSec,
    required this.width,
    required this.height,
    this.rotationDegrees = 0,
    this.usedFastPath = false,
  });

  factory VideoCompressionOutput.fromMap(Map<dynamic, dynamic> map) {
    return VideoCompressionOutput(
      outputPath: (map['outputPath'] as String?) ?? '',
      sizeBytes: _toInt(map['sizeBytes']) ?? 0,
      durationSec: _toDouble(map['durationSec']) ?? 0.0,
      width: _toInt(map['width']) ?? 720,
      height: _toInt(map['height']) ?? 1280,
      rotationDegrees: _toInt(map['rotationDegrees']) ?? 0,
      usedFastPath: map['usedFastPath'] == true,
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

typedef VideoCompressorFn = Future<VideoCompressionOutput> Function(
  String inputPath, {
  int maxBytes,
  int timeoutMs,
});

class VideoStoryUploadResult {
  final bool success;
  final String? videoStoryId;
  final String? videoUrl;
  final String? storageKey;
  final int? sizeBytes;
  final int? usedBytes;
  final int? limitMb;
  final String? retentionExpiresAt;
  final bool isUpgradeRequired;
  final bool isStorageQuotaExceeded;
  final bool isFileTooLarge;
  final String? errorMessage;

  const VideoStoryUploadResult({
    required this.success,
    this.videoStoryId,
    this.videoUrl,
    this.storageKey,
    this.sizeBytes,
    this.usedBytes,
    this.limitMb,
    this.retentionExpiresAt,
    this.isUpgradeRequired = false,
    this.isStorageQuotaExceeded = false,
    this.isFileTooLarge = false,
    this.errorMessage,
  });
}

class VideoStoryUploadService {
  static const String methodChannelName =
      'com.example.health_ai_app/workout_cv/method';
  static const String compressMethodName = 'compressVideoForStory';
  static const int maxUploadBytes = 15 * 1024 * 1024;
  static const int defaultTimeoutMs = 45000;

  static const MethodChannel _channel = MethodChannel(methodChannelName);

  final Dio _backendDio;
  final Dio _uploadDio;
  final Future<String?> Function() _tokenProvider;
  final VideoCompressorFn _compressor;
  final int _maxBytes;

  VideoStoryUploadService({
    Dio? backendDio,
    Dio? uploadDio,
    Future<String?> Function()? tokenProvider,
    VideoCompressorFn? compressor,
    int maxBytes = maxUploadBytes,
  })  : _backendDio = backendDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
              ),
            ),
        _uploadDio = uploadDio ?? _createCleanUploadDio(),
        _tokenProvider = tokenProvider ?? _defaultTokenProvider,
        _compressor = compressor ?? defaultVideoCompressor,
        _maxBytes = maxBytes;

  static Dio _createCleanUploadDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 90),
        headers: <String, dynamic>{},
      ),
    );
    dio.interceptors.clear();
    return dio;
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

  static Future<VideoCompressionOutput> defaultVideoCompressor(
    String inputPath, {
    int maxBytes = maxUploadBytes,
    int timeoutMs = defaultTimeoutMs,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      final dynamic raw = await _channel.invokeMethod<dynamic>(
        compressMethodName,
        <String, dynamic>{
          'inputPath': inputPath,
          'maxBytes': maxBytes,
          'timeoutMs': timeoutMs,
        },
      );
      if (raw is Map) {
        return VideoCompressionOutput.fromMap(raw);
      }
      throw PlatformException(
        code: 'COMPRESSION_FAILED',
        message: 'Unexpected compression result from native plugin',
      );
    }

    // Fallback when running outside Android (e.g., desktop/unit test fallback)
    final file = File(inputPath);
    if (!await file.exists()) {
      throw PlatformException(
        code: 'COMPRESSION_FAILED',
        message: 'Input video file not found: $inputPath',
      );
    }
    final length = await file.length();
    return VideoCompressionOutput(
      outputPath: file.path,
      sizeBytes: length,
      durationSec: 10.0,
      width: 720,
      height: 1280,
      rotationDegrees: 0,
      usedFastPath: length <= maxBytes,
    );
  }

  Future<VideoStoryUploadResult> uploadVideoStory({
    required String videoPath,
    required String exerciseSlug,
    String? workoutSessionId,
    Map<String, dynamic>? cvFormSummary,
    List<Map<String, dynamic>>? repTimeline,
    void Function(double progress, String stageLabel)? onProgress,
  }) async {
    onProgress?.call(0.0, 'compressing');

    // Step 1: Compress video (fast-path if <= 15 MB)
    VideoCompressionOutput compressed;
    try {
      compressed = await _compressor(
        videoPath,
        maxBytes: _maxBytes,
        timeoutMs: defaultTimeoutMs,
      );
    } on PlatformException catch (e) {
      final isTooLarge = e.code == 'FILE_TOO_LARGE_AFTER_COMPRESS';
      return VideoStoryUploadResult(
        success: false,
        isFileTooLarge: isTooLarge,
        errorMessage: e.message ?? 'Không thể nén video (${e.code}).',
      );
    } catch (e) {
      return VideoStoryUploadResult(
        success: false,
        errorMessage: 'Lỗi nén video: $e',
      );
    }

    final outputFile = File(compressed.outputPath);
    if (!await outputFile.exists()) {
      return const VideoStoryUploadResult(
        success: false,
        errorMessage: 'Không tìm thấy file video sau khi nén.',
      );
    }

    final actualFileSize = await outputFile.length();
    final effectiveSizeBytes =
        actualFileSize > 0 ? actualFileSize : compressed.sizeBytes;

    if (effectiveSizeBytes <= 0) {
      return const VideoStoryUploadResult(
        success: false,
        errorMessage: 'File video rỗng (0 bytes).',
      );
    }

    if (effectiveSizeBytes > _maxBytes) {
      return VideoStoryUploadResult(
        success: false,
        sizeBytes: effectiveSizeBytes,
        isFileTooLarge: true,
        errorMessage:
            'Dung lượng video sau nén vượt quá giới hạn ${_maxBytes ~/ (1024 * 1024)} MB.',
      );
    }

    onProgress?.call(0.25, 'presigning');

    // Step 2: Request presigned upload URL from Backend
    final token = await _tokenProvider();
    final backendHeaders = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    Map<String, dynamic> presignData;
    try {
      final presignResponse = await _backendDio.post<dynamic>(
        ApiConfig.workoutVideoStoryPresignEndpoint,
        data: <String, dynamic>{
          'exercise_slug': exerciseSlug,
          'size_bytes': effectiveSizeBytes,
          'content_type': 'video/mp4',
          'duration_sec': compressed.durationSec,
          'width': compressed.width,
          'height': compressed.height,
          if (workoutSessionId != null) 'workout_session_id': workoutSessionId,
        },
        options: Options(headers: backendHeaders),
      );
      presignData = _asMap(presignResponse.data);
    } on DioException catch (e) {
      return _mapDioFailure(e, fallbackMessage: 'Không thể khởi tạo tải lên.');
    } catch (e) {
      return VideoStoryUploadResult(
        success: false,
        errorMessage: 'Lỗi kết nối khi xin quyền tải video: $e',
      );
    }

    final uploadUrl = (presignData['upload_url'] as String?) ??
        (presignData['uploadUrl'] as String?) ??
        '';
    final storageKey = (presignData['storage_key'] as String?) ??
        (presignData['storageKey'] as String?) ??
        '';
    final rawPresignHeaders = presignData['headers'];

    if (uploadUrl.isEmpty || storageKey.isEmpty) {
      return const VideoStoryUploadResult(
        success: false,
        errorMessage: 'Phản hồi presign thiếu upload_url hoặc storage_key.',
      );
    }

    // Step 3: Direct PUT to Cloudflare R2 / S3 using clean Dio WITHOUT Authorization header
    final cleanPutHeaders = <String, dynamic>{};
    if (rawPresignHeaders is Map) {
      rawPresignHeaders.forEach((dynamic key, dynamic value) {
        final keyStr = key?.toString() ?? '';
        if (keyStr.isNotEmpty &&
            keyStr.toLowerCase() != 'authorization' &&
            value != null) {
          cleanPutHeaders[keyStr] = value.toString();
        }
      });
    }
    cleanPutHeaders.removeWhere(
      (key, _) => key.toLowerCase() == 'authorization',
    );
    cleanPutHeaders[Headers.contentLengthHeader] = effectiveSizeBytes;

    final contentType = (cleanPutHeaders['Content-Type'] as String?) ??
        (cleanPutHeaders['content-type'] as String?) ??
        'video/mp4';

    // Ensure _uploadDio base options also have no Authorization header
    _uploadDio.options.headers.removeWhere(
      (key, _) => key.toLowerCase() == 'authorization',
    );

    onProgress?.call(0.25, 'uploading');

    try {
      await _uploadDio.put<dynamic>(
        uploadUrl,
        data: outputFile.openRead(),
        options: Options(
          headers: cleanPutHeaders,
          contentType: contentType,
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 60),
        ),
        onSendProgress: (int sent, int total) {
          final denominator = total > 0 ? total : effectiveSizeBytes;
          if (denominator > 0) {
            final ratio = (sent / denominator).clamp(0.0, 1.0);
            final mappedProgress = 0.25 + (ratio * 0.65);
            onProgress?.call(mappedProgress, 'uploading');
          }
        },
      );
    } on DioException catch (e) {
      return _mapDioFailure(
        e,
        fallbackMessage: 'Không thể tải video lên đám mây (R2).',
      );
    } catch (e) {
      return VideoStoryUploadResult(
        success: false,
        errorMessage: 'Lỗi truyền dữ liệu video lên R2: $e',
      );
    }

    onProgress?.call(0.90, 'completing');

    // Step 4: Confirm upload completion with Backend
    Map<String, dynamic> completeData;
    try {
      final completeResponse = await _backendDio.post<dynamic>(
        ApiConfig.workoutVideoStoryCompleteEndpoint,
        data: <String, dynamic>{
          'storage_key': storageKey,
          'exercise_slug': exerciseSlug,
          'size_bytes': effectiveSizeBytes,
          'duration_sec': compressed.durationSec,
          'width': compressed.width,
          'height': compressed.height,
          if (workoutSessionId != null) 'workout_session_id': workoutSessionId,
          if (cvFormSummary != null) 'cv_form_summary': cvFormSummary,
          if (repTimeline != null) 'rep_timeline': repTimeline,
        },
        options: Options(headers: backendHeaders),
      );
      completeData = _asMap(completeResponse.data);
    } on DioException catch (e) {
      return _mapDioFailure(
        e,
        fallbackMessage: 'Không thể xác nhận hoàn tất lưu Video Story.',
      );
    } catch (e) {
      return VideoStoryUploadResult(
        success: false,
        errorMessage: 'Lỗi hoàn tất lưu Video Story: $e',
      );
    }

    onProgress?.call(1.0, 'completed');

    final storyMap = completeData['video_story'] is Map
        ? _asMap(completeData['video_story'])
        : completeData;

    final videoStoryId = (storyMap['id']?.toString()) ??
        (completeData['video_story_id']?.toString()) ??
        (completeData['id']?.toString());
    final videoUrl = (storyMap['video_url'] as String?) ??
        (storyMap['playback_url'] as String?) ??
        (completeData['video_url'] as String?) ??
        (completeData['playback_url'] as String?);
    final finalStorageKey =
        (storyMap['storage_key'] as String?) ?? storageKey;
    final usedBytes = _toInt(completeData['used_bytes']) ??
        _toInt(storyMap['used_bytes']) ??
        _toInt(presignData['used_bytes']);
    final limitMb = _toInt(completeData['limit_mb']) ??
        _toInt(storyMap['limit_mb']) ??
        _toInt(presignData['limit_mb']);
    final retentionExpiresAt =
        (storyMap['retention_expires_at'] as String?) ??
            (completeData['retention_expires_at'] as String?) ??
            (presignData['retention_expires_at'] as String?);

    return VideoStoryUploadResult(
      success: true,
      videoStoryId: videoStoryId,
      videoUrl: videoUrl,
      storageKey: finalStorageKey,
      sizeBytes: effectiveSizeBytes,
      usedBytes: usedBytes,
      limitMb: limitMb,
      retentionExpiresAt: retentionExpiresAt,
    );
  }

  VideoStoryUploadResult _mapDioFailure(
    DioException error, {
    required String fallbackMessage,
  }) {
    final statusCode = error.response?.statusCode;
    final bodyMap = _asMap(error.response?.data);
    final detailMap = bodyMap['detail'] is Map
        ? _asMap(bodyMap['detail'])
        : bodyMap;

    final serverMessage = (detailMap['message'] as String?) ??
        (bodyMap['detail'] is String ? bodyMap['detail'] as String : null) ??
        (bodyMap['message'] as String?) ??
        fallbackMessage;

    final usedBytes = _toInt(detailMap['used_bytes']);
    final limitMb = _toInt(detailMap['limit_mb']);

    if (statusCode == 403) {
      return VideoStoryUploadResult(
        success: false,
        isUpgradeRequired: true,
        usedBytes: usedBytes,
        limitMb: limitMb,
        errorMessage: serverMessage,
      );
    }

    if (statusCode == 429) {
      return VideoStoryUploadResult(
        success: false,
        isStorageQuotaExceeded: true,
        usedBytes: usedBytes,
        limitMb: limitMb,
        errorMessage: serverMessage,
      );
    }

    if (statusCode == 413) {
      return VideoStoryUploadResult(
        success: false,
        isFileTooLarge: true,
        usedBytes: usedBytes,
        limitMb: limitMb,
        errorMessage: serverMessage,
      );
    }

    return VideoStoryUploadResult(
      success: false,
      usedBytes: usedBytes,
      limitMb: limitMb,
      errorMessage: serverMessage,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

final videoStoryUploadServiceProvider = Provider<VideoStoryUploadService>((ref) {
  return VideoStoryUploadService();
});

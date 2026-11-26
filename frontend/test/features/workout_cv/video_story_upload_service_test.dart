import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/workout_cv/data/services/video_story_upload_service.dart';

class _RecordedRequest {
  final RequestOptions options;
  final List<int> bodyBytes;

  const _RecordedRequest({
    required this.options,
    required this.bodyBytes,
  });
}

typedef _AdapterHandler = Future<ResponseBody> Function(
  RequestOptions options,
  List<int> bodyBytes,
);

class _MockHttpClientAdapter implements HttpClientAdapter {
  final _AdapterHandler handler;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  _MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final collected = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        collected.addAll(chunk);
      }
    }
    requests.add(
      _RecordedRequest(
        options: options,
        bodyBytes: collected,
      ),
    );
    return handler(options, collected);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(
  Map<String, dynamic> payload, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

void main() {
  late Directory tempDir;
  late File sampleVideoFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_story_upload_test_');
    sampleVideoFile = File('${tempDir.path}/sample_workout.mp4');
    // Write 64 KB dummy MP4 payload
    final bytes = Uint8List.fromList(List<int>.generate(65536, (i) => i % 251));
    await sampleVideoFile.writeAsBytes(bytes, flush: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'Happy path: compress -> presign (with Bearer) -> R2 PUT (NO Authorization header) -> complete',
    () async {
      const presignedR2Url =
          'https://r2.cloudflarestorage.com/saman-stories/user_42/story_123.mp4?X-Amz-Signature=abc';
      const storageKey = 'user_42/story_123.mp4';

      final backendAdapter = _MockHttpClientAdapter((options, bodyBytes) async {
        final decodedBody = bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>
            : <String, dynamic>{};

        if (options.uri.toString() ==
            ApiConfig.workoutVideoStoryPresignEndpoint) {
          expect(options.method, 'POST');
          expect(options.headers['Authorization'], 'Bearer test-jwt-token');
          expect(decodedBody['exercise_slug'], 'squat');
          expect(decodedBody['size_bytes'], 65536);

          return _jsonResponse(<String, dynamic>{
            'story_id': 'vs_999',
            'upload_url': presignedR2Url,
            'storage_key': storageKey,
            'public_url': 'https://cdn.saman.app/stories/user_42/story_123.mp4',
            'headers': <String, String>{
              'Content-Type': 'video/mp4',
              'x-amz-meta-exercise': 'squat',
            },
            'used_bytes': 10485760,
            'limit_mb': 200,
          });
        }

        if (options.uri.toString() ==
            ApiConfig.workoutVideoStoryCompleteEndpoint) {
          expect(options.method, 'POST');
          expect(options.headers['Authorization'], 'Bearer test-jwt-token');
          expect(decodedBody['story_id'], 'vs_999');
          expect(decodedBody['storage_key'], storageKey);
          expect(
            decodedBody['video_url'],
            'https://cdn.saman.app/stories/user_42/story_123.mp4',
          );
          expect(decodedBody['exercise_slug'], 'squat');
          expect(decodedBody['cv_form_summary'], isA<Map<String, dynamic>>());
          expect(
            (decodedBody['cv_form_summary'] as Map)['avg_form_score'],
            88.5,
          );
          expect(decodedBody['rep_timeline'], isA<List<dynamic>>());
          expect((decodedBody['rep_timeline'] as List).length, 2);

          return _jsonResponse(<String, dynamic>{
            'video_story_id': 'vs_999',
            'video_url': 'https://cdn.saman.app/stories/user_42/story_123.mp4',
            'storage_key': storageKey,
            'used_bytes': 10551296,
            'limit_mb': 200,
            'retention_expires_at': '2026-12-26T00:00:00Z',
          });
        }

        return _jsonResponse(
          <String, dynamic>{'detail': 'Not found'},
          statusCode: 404,
        );
      });

      final uploadAdapter = _MockHttpClientAdapter((options, bodyBytes) async {
        expect(options.method, 'PUT');
        expect(options.uri.toString(), presignedR2Url);

        // Critical invariant: NO Authorization / authorization header sent to R2
        final hasAuthHeader = options.headers.keys.any(
          (k) => k.toLowerCase() == 'authorization',
        );
        expect(
          hasAuthHeader,
          isFalse,
          reason:
              'R2 presigned PUT must NEVER include Authorization: Bearer header',
        );
        expect(options.headers['Content-Type'], 'video/mp4');
        expect(options.headers['x-amz-meta-exercise'], 'squat');
        expect(
          options.headers[Headers.contentLengthHeader]?.toString(),
          '65536',
        );
        expect(bodyBytes.length, 65536);

        return ResponseBody.fromString('', 200);
      });

      final backendDio = Dio()..httpClientAdapter = backendAdapter;
      // Intentionally pollute uploadDio default headers with Authorization to verify service strips it
      final uploadDio = Dio(
        BaseOptions(
          headers: <String, dynamic>{
            'Authorization': 'Bearer should-be-stripped',
          },
        ),
      )..httpClientAdapter = uploadAdapter;

      final progressStages = <String>[];
      final progressValues = <double>[];

      final service = VideoStoryUploadService(
        backendDio: backendDio,
        uploadDio: uploadDio,
        tokenProvider: () async => 'test-jwt-token',
        compressor: (
          String inputPath, {
          int maxBytes = VideoStoryUploadService.maxUploadBytes,
          int timeoutMs = VideoStoryUploadService.defaultTimeoutMs,
        }) async {
          return VideoCompressionOutput(
            outputPath: inputPath,
            sizeBytes: 65536,
            durationSec: 12.4,
            width: 720,
            height: 1280,
            rotationDegrees: 90,
            usedFastPath: true,
          );
        },
      );

      final result = await service.uploadVideoStory(
        videoPath: sampleVideoFile.path,
        exerciseSlug: 'squat',
        workoutSessionId: 'ws_101',
        cvFormSummary: <String, dynamic>{
          'avg_form_score': 88.5,
          'valid_reps': 10,
        },
        repTimeline: <Map<String, dynamic>>[
          <String, dynamic>{'rep': 1, 'score': 90},
          <String, dynamic>{'rep': 2, 'score': 87},
        ],
        onProgress: (double progress, String stage) {
          progressValues.add(progress);
          progressStages.add(stage);
        },
      );

      expect(result.success, isTrue);
      expect(result.videoStoryId, 'vs_999');
      expect(
        result.videoUrl,
        'https://cdn.saman.app/stories/user_42/story_123.mp4',
      );
      expect(result.storageKey, storageKey);
      expect(result.sizeBytes, 65536);
      expect(result.usedBytes, 10551296);
      expect(result.limitMb, 200);
      expect(result.isUpgradeRequired, isFalse);
      expect(result.isStorageQuotaExceeded, isFalse);
      expect(result.isFileTooLarge, isFalse);

      expect(backendAdapter.requests.length, 2);
      expect(uploadAdapter.requests.length, 1);

      final r2PutHeaders = uploadAdapter.requests.single.options.headers;
      expect(
        r2PutHeaders.keys.any((k) => k.toLowerCase() == 'authorization'),
        isFalse,
      );

      expect(progressStages, containsAll(<String>['compressing', 'uploading', 'completing', 'completed']));
      expect(progressValues.first, 0.0);
      expect(progressValues.last, 1.0);
    },
  );

  test(
    'Free tier 403 on /presign returns isUpgradeRequired=true and skips R2 PUT & /complete',
    () async {
      final backendAdapter = _MockHttpClientAdapter((options, _) async {
        return _jsonResponse(
          <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'UPGRADE_REQUIRED',
              'message': 'Tính năng Video Story chỉ dành cho gói Pro và Ultra.',
            },
          },
          statusCode: 403,
        );
      });
      final uploadAdapter = _MockHttpClientAdapter((_, __) async {
        fail('R2 PUT must not be called when /presign returns 403');
      });

      final service = VideoStoryUploadService(
        backendDio: Dio()..httpClientAdapter = backendAdapter,
        uploadDio: Dio()..httpClientAdapter = uploadAdapter,
        tokenProvider: () async => 'free-user-token',
        compressor: (inputPath, {maxBytes = 15728640, timeoutMs = 45000}) async {
          return VideoCompressionOutput(
            outputPath: inputPath,
            sizeBytes: 65536,
            durationSec: 8.0,
            width: 720,
            height: 1280,
            usedFastPath: true,
          );
        },
      );

      final result = await service.uploadVideoStory(
        videoPath: sampleVideoFile.path,
        exerciseSlug: 'pushup',
      );

      expect(result.success, isFalse);
      expect(result.isUpgradeRequired, isTrue);
      expect(result.isStorageQuotaExceeded, isFalse);
      expect(result.isFileTooLarge, isFalse);
      expect(result.errorMessage, contains('Pro và Ultra'));
      expect(backendAdapter.requests.length, 1);
      expect(uploadAdapter.requests, isEmpty);
    },
  );

  test(
    'Storage quota exhausted 429 on /presign returns isStorageQuotaExceeded=true and skips R2 PUT & /complete',
    () async {
      final backendAdapter = _MockHttpClientAdapter((options, _) async {
        return _jsonResponse(
          <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'STORAGE_QUOTA_EXCEEDED',
              'message': 'Bạn đã dùng hết 200 MB dung lượng Video Story.',
              'used_bytes': 209715200,
              'limit_mb': 200,
            },
          },
          statusCode: 429,
        );
      });
      final uploadAdapter = _MockHttpClientAdapter((_, __) async {
        fail('R2 PUT must not be called when /presign returns 429');
      });

      final service = VideoStoryUploadService(
        backendDio: Dio()..httpClientAdapter = backendAdapter,
        uploadDio: Dio()..httpClientAdapter = uploadAdapter,
        tokenProvider: () async => 'pro-user-token',
        compressor: (inputPath, {maxBytes = 15728640, timeoutMs = 45000}) async {
          return VideoCompressionOutput(
            outputPath: inputPath,
            sizeBytes: 65536,
            durationSec: 10.0,
            width: 720,
            height: 1280,
            usedFastPath: true,
          );
        },
      );

      final result = await service.uploadVideoStory(
        videoPath: sampleVideoFile.path,
        exerciseSlug: 'plank',
      );

      expect(result.success, isFalse);
      expect(result.isStorageQuotaExceeded, isTrue);
      expect(result.isUpgradeRequired, isFalse);
      expect(result.usedBytes, 209715200);
      expect(result.limitMb, 200);
      expect(backendAdapter.requests.length, 1);
      expect(uploadAdapter.requests, isEmpty);
    },
  );

  test(
    'File still > 15 MB after compression is blocked on client with isFileTooLarge=true without calling /presign',
    () async {
      final oversizedFile = File('${tempDir.path}/oversized.mp4');
      // Create a 1024-byte file but configure maxBytes = 512 to test client size guard deterministically
      await oversizedFile.writeAsBytes(Uint8List(1024), flush: true);

      final backendAdapter = _MockHttpClientAdapter((_, __) async {
        fail('/presign must not be called when compressed file exceeds maxBytes');
      });
      final uploadAdapter = _MockHttpClientAdapter((_, __) async {
        fail('R2 PUT must not be called when compressed file exceeds maxBytes');
      });

      final service = VideoStoryUploadService(
        backendDio: Dio()..httpClientAdapter = backendAdapter,
        uploadDio: Dio()..httpClientAdapter = uploadAdapter,
        tokenProvider: () async => 'ultra-token',
        maxBytes: 512,
        compressor: (inputPath, {maxBytes = 512, timeoutMs = 45000}) async {
          return VideoCompressionOutput(
            outputPath: inputPath,
            sizeBytes: 1024,
            durationSec: 25.0,
            width: 720,
            height: 1280,
            usedFastPath: false,
          );
        },
      );

      final result = await service.uploadVideoStory(
        videoPath: oversizedFile.path,
        exerciseSlug: 'deadlift',
      );

      expect(result.success, isFalse);
      expect(result.isFileTooLarge, isTrue);
      expect(result.isUpgradeRequired, isFalse);
      expect(result.isStorageQuotaExceeded, isFalse);
      expect(backendAdapter.requests, isEmpty);
      expect(uploadAdapter.requests, isEmpty);
    },
  );

  test(
    'Compression failure / timeout returns success=false with clear errorMessage and does not crash',
    () async {
      final backendAdapter = _MockHttpClientAdapter((_, __) async {
        fail('/presign must not be called when compressor throws');
      });

      final service = VideoStoryUploadService(
        backendDio: Dio()..httpClientAdapter = backendAdapter,
        uploadDio: Dio(),
        tokenProvider: () async => 'ultra-token',
        compressor: (inputPath, {maxBytes = 15728640, timeoutMs = 45000}) async {
          throw PlatformException(
            code: 'COMPRESSION_TIMEOUT',
            message: 'Video compression timed out after 45000ms on device',
          );
        },
      );

      final result = await service.uploadVideoStory(
        videoPath: sampleVideoFile.path,
        exerciseSlug: 'lunge',
      );

      expect(result.success, isFalse);
      expect(result.isFileTooLarge, isFalse);
      expect(result.errorMessage, contains('timed out'));
      expect(backendAdapter.requests, isEmpty);
    },
  );
}

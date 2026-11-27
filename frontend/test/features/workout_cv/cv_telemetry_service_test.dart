import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/workout_cv/data/services/cv_telemetry_service.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';

class _RecordedRequest {
  final String method;
  final String uri;
  final Map<String, dynamic> headers;
  final dynamic data;

  _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.data,
  });
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  int statusCode = 200;
  String responseBody = '{"status":"ok"}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _RecordedRequest(
        method: options.method,
        uri: options.uri.toString(),
        headers: Map<String, dynamic>.from(options.headers),
        data: options.data,
      ),
    );
    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

List<SkeletonFrameSample> _buildSampleFrames(int frameCount) {
  return List<SkeletonFrameSample>.generate(frameCount, (f) {
    final landmarks = List<PoseLandmark>.generate(33, (j) {
      return PoseLandmark(
        index: j,
        x: ((f * 7 + j * 13) % 1000) / 1000.0,
        y: ((f * 11 + j * 17) % 1000) / 1000.0,
        z: (((f * 5 + j * 19) % 1000) - 500) / 1000.0,
        visibility: 0.85 + ((j % 15) * 0.01),
      );
    });
    return SkeletonFrameSample(
      timestampMs: f * 33,
      landmarks: landmarks,
    );
  });
}

void main() {
  group('CvTelemetryEncoder', () {
    test('compresses 150 frames x 33 landmarks under 60 KB without PII', () {
      final frames = _buildSampleFrames(150);

      final gzipBytes = CvTelemetryEncoder.encodeFramesGzipBytes(frames);
      final encodedB64 = CvTelemetryEncoder.encodeFramesGzipBase64(frames);

      // ignore: avoid_print
      print('GZIP_150_FRAMES_BYTES=${gzipBytes.length}');

      expect(gzipBytes.length, lessThanOrEqualTo(60 * 1024));
      expect(base64Decode(encodedB64), equals(gzipBytes));

      final decompressedJson = utf8.decode(gzip.decode(base64Decode(encodedB64)));
      expect(decompressedJson.contains('email'), isFalse);
      expect(decompressedJson.contains('video'), isFalse);
      expect(decompressedJson.contains('image'), isFalse);

      final decoded = jsonDecode(decompressedJson) as Map<String, dynamic>;
      expect(decoded['schema'], equals('saman_skel_v1'));
      expect(decoded['scale'], equals(1000));

      final decodedFrames = decoded['frames'] as List<dynamic>;
      expect(decodedFrames.length, equals(150));

      final firstFrame = decodedFrames.first as Map<String, dynamic>;
      expect(firstFrame['t'], equals(0));
      final firstLandmarks = firstFrame['lm'] as List<dynamic>;
      expect(firstLandmarks.length, equals(33));
      expect((firstLandmarks.first as List<dynamic>).length, equals(4));
    });
  });

  group('CvTelemetryService', () {
    late _FakeHttpClientAdapter adapter;
    late Dio dio;
    late SharedPreferences prefs;
    late CvTelemetryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      adapter = _FakeHttpClientAdapter();
      dio = Dio()..httpClientAdapter = adapter;
      service = CvTelemetryService(
        dio: dio,
        tokenProvider: () async => 'test-jwt-token',
        prefs: prefs,
      );
    });

    test('optIn == false (default) sends ZERO HTTP requests', () async {
      expect(await service.isOptedIn(), isFalse);

      final result = await service.uploadAnonymousSession(
        exerciseSlug: 'squat',
        viewAngle: 'side',
        fps: 30.0,
        frames: _buildSampleFrames(30),
        cvReps: 10,
        finalLoggedReps: 10,
      );

      expect(result.sent, isFalse);
      expect(result.skippedReason, equals('opt_in_disabled'));
      expect(adapter.requests, isEmpty);
    });

    test('optIn == true uploads quantized payload with user_adjusted_reps', () async {
      await prefs.setBool(CvTelemetryService.optInPrefKey, true);
      final frames = _buildSampleFrames(60);

      final result = await service.uploadAnonymousSession(
        exerciseSlug: 'squat',
        viewAngle: 'front',
        fps: 30.0,
        frames: frames,
        cvReps: 10,
        finalLoggedReps: 8,
        mlMode: 'hybrid',
      );

      expect(result.sent, isTrue);
      expect(result.statusCode, equals(200));
      expect(adapter.requests.length, equals(1));

      final req = adapter.requests.single;
      expect(req.method, equals('POST'));
      expect(req.uri, equals(ApiConfig.workoutCvTelemetryEndpoint));
      expect(req.headers['Authorization'], equals('Bearer test-jwt-token'));

      final payload = req.data as Map<String, dynamic>;
      expect(payload['exercise_slug'], equals('squat'));
      expect(payload['view_angle'], equals('front'));
      expect(payload['fps'], equals(30.0));
      expect(payload['frame_count'], equals(60));
      expect(payload['cv_reps'], equals(10));
      expect(payload['final_logged_reps'], equals(8));
      expect(payload['user_adjusted_reps'], isTrue);
      expect(payload['ml_mode'], equals('hybrid'));
      expect(payload['payload_encoding'], equals('gzip_json_b64'));
      expect(payload['compressed_payload_b64'], isA<String>());
      expect((payload['compressed_payload_b64'] as String).isNotEmpty, isTrue);
    });

    test('setOptIn(true) persists SharedPreferences and syncs PUT /api/user/profile', () async {
      final result = await service.setOptIn(true);

      expect(result, isTrue);
      expect(prefs.getBool(CvTelemetryService.optInPrefKey), isTrue);
      expect(await service.isOptedIn(), isTrue);

      expect(adapter.requests.length, equals(1));
      final req = adapter.requests.single;
      expect(req.method, equals('PUT'));
      expect(req.uri, equals(ApiConfig.getProfileEndpoint));
      expect(req.headers['Authorization'], equals('Bearer test-jwt-token'));
      expect(req.data, equals(<String, dynamic>{
        'preferences': <String, dynamic>{
          'cv_telemetry_opt_in': true,
        },
      }));
    });
  });
}

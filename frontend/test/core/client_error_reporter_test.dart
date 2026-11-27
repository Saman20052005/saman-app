import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/core/services/client_error_reporter.dart';
import 'package:health_ai_app/screens/login/login_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  group('scrubSensitiveText', () {
    test('redacts JWT, Bearer token, email, Gemini API key, and kv secrets',
        () {
      const raw =
          'Auth failed for user@example.com with Bearer abc.def_123== '
          'jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTYifQ.sig_xyz '
          'apiKey=AIzaSyDummyKey1234567890 password=mySecret123';

      final scrubbed = scrubSensitiveText(raw);

      expect(scrubbed, isNot(contains('user@example.com')));
      expect(scrubbed, isNot(contains('abc.def_123==')));
      expect(scrubbed, isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')));
      expect(scrubbed, isNot(contains('AIzaSyDummyKey1234567890')));
      expect(scrubbed, isNot(contains('mySecret123')));
      expect(scrubbed, contains('[REDACTED_EMAIL]'));
      expect(scrubbed, contains('Bearer [REDACTED]'));
      expect(scrubbed, contains('[REDACTED_JWT]'));
      expect(scrubbed, contains('[REDACTED_API_KEY]'));
      expect(scrubbed, contains('password=[REDACTED]'));
    });

    test('caps output length to 2000 characters by default', () {
      final longStack = List<String>.filled(2500, 'x').join();

      final scrubbed = scrubSensitiveText(longStack);

      expect(scrubbed.length, 2000);
    });
  });

  group('ClientErrorReporter', () {
    late _MockDio mockDio;

    setUp(() {
      mockDio = _MockDio();
    });

    test('posts scrubbed JSON payload to client-error telemetry endpoint',
        () async {
      when(
        () => mockDio.post<dynamic>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(
            path: ApiConfig.clientErrorTelemetryEndpoint,
          ),
          statusCode: 200,
        ),
      );

      final reporter = ClientErrorReporter(dio: mockDio);
      final longStack = StackTrace.fromString(
        '${List<String>.filled(2100, 'a').join()}\nuser@secret.dev',
      );

      final sent = await reporter.reportError(
        StateError('Failed with Bearer tok_999 for alice@saman.ai'),
        longStack,
        screen: 'LoginScreen',
        isFatal: true,
        appVersion: '1.0.0+1',
      );

      expect(sent, isTrue);

      final captured = verify(
        () => mockDio.post<dynamic>(
          ApiConfig.clientErrorTelemetryEndpoint,
          data: captureAny(named: 'data'),
        ),
      ).captured;

      expect(captured, hasLength(1));
      final payload = captured.single as Map<String, dynamic>;
      expect(payload['error_type'], 'StateError');
      expect(payload['message'], isNot(contains('tok_999')));
      expect(payload['message'], isNot(contains('alice@saman.ai')));
      expect((payload['stack_preview'] as String).length, lessThanOrEqualTo(2000));
      expect(payload['app_version'], '1.0.0+1');
      expect(payload['platform'], isNotEmpty);
      expect(payload['screen'], 'LoginScreen');
      expect(payload['is_fatal'], isTrue);
    });

    test('swallows network errors silently and returns false', () async {
      when(
        () => mockDio.post<dynamic>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: ApiConfig.clientErrorTelemetryEndpoint,
          ),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final reporter = ClientErrorReporter(dio: mockDio);
      final sent = await reporter.reportError(
        Exception('Network down'),
        StackTrace.current,
      );

      expect(sent, isFalse);
    });

    test('enforces rate limit of max 5 reports per minute', () async {
      var now = DateTime(2026, 11, 27, 12, 0, 0);
      when(
        () => mockDio.post<dynamic>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(
            path: ApiConfig.clientErrorTelemetryEndpoint,
          ),
          statusCode: 200,
        ),
      );

      final reporter = ClientErrorReporter(
        dio: mockDio,
        nowProvider: () => now,
      );

      for (var i = 0; i < 5; i++) {
        final ok = await reporter.reportError(Exception('err $i'), null);
        expect(ok, isTrue);
      }

      // 6th call within the same 60s window is dropped.
      final sixth = await reporter.reportError(Exception('err 5'), null);
      expect(sixth, isFalse);

      // Advance past 60s window -> allowed again.
      now = now.add(const Duration(seconds: 61));
      final seventh = await reporter.reportError(Exception('err 6'), null);
      expect(seventh, isTrue);

      verify(
        () => mockDio.post<dynamic>(
          ApiConfig.clientErrorTelemetryEndpoint,
          data: any(named: 'data'),
        ),
      ).called(6);
    });

    test('anti-recursion guard drops re-entrant reportError calls', () async {
      final completer = Completer<Response<dynamic>>();
      when(
        () => mockDio.post<dynamic>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) => completer.future);

      final reporter = ClientErrorReporter(dio: mockDio);
      final firstFuture = reporter.reportError(Exception('first'), null);
      final secondResult = await reporter.reportError(Exception('nested'), null);

      expect(secondResult, isFalse);

      completer.complete(
        Response<dynamic>(
          requestOptions: RequestOptions(
            path: ApiConfig.clientErrorTelemetryEndpoint,
          ),
          statusCode: 200,
        ),
      );
      expect(await firstFuture, isTrue);

      verify(
        () => mockDio.post<dynamic>(
          ApiConfig.clientErrorTelemetryEndpoint,
          data: any(named: 'data'),
        ),
      ).called(1);
    });
  });

  group('Release Guest Mode lock', () {
    test('isGuestModeAllowed returns false when debugOverride is false', () {
      expect(isGuestModeAllowed(debugOverride: false), isFalse);
    });

    test('isGuestModeAllowed returns true when debugOverride is true', () {
      expect(isGuestModeAllowed(debugOverride: true), isTrue);
    });
  });
}

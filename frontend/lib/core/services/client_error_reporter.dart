import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:health_ai_app/config/api_config.dart';

/// Scrubs PII and credentials (JWT, Bearer tokens, emails, API keys, secrets)
/// and caps the output length at [maxLength].
String scrubSensitiveText(String input, {int maxLength = 2000}) {
  if (maxLength <= 0 || input.isEmpty) {
    return '';
  }

  var sanitized = input;

  // JWT tokens (header.payload.signature)
  sanitized = sanitized.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*'),
    '[REDACTED_JWT]',
  );

  // Bearer authorization headers/tokens
  sanitized = sanitized.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
    'Bearer [REDACTED]',
  );

  // Google / Gemini API keys
  sanitized = sanitized.replaceAll(
    RegExp(r'AIza[0-9A-Za-z\-_]{10,}'),
    '[REDACTED_API_KEY]',
  );

  // Email addresses
  sanitized = sanitized.replaceAll(
    RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
    '[REDACTED_EMAIL]',
  );

  // Query/header/body key-value secrets (key=, token=, password=, secret=)
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'''((?:api_?key|key|token|password|passwd|secret)\s*[:=]\s*)(?!\[REDACTED)([^\s,;'"&}]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );

  if (sanitized.length > maxLength) {
    return sanitized.substring(0, maxLength);
  }
  return sanitized;
}

/// Global non-blocking client crash & error reporter with PII scrubbing,
/// anti-recursion guard, and 5-reports/minute rate limiting.
class ClientErrorReporter {
  ClientErrorReporter({
    Dio? dio,
    DateTime Function()? nowProvider,
    int maxReportsPerMinute = 5,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                headers: const {'Content-Type': 'application/json'},
              ),
            ),
        _nowProvider = nowProvider ?? DateTime.now,
        _maxReportsPerMinute = maxReportsPerMinute;

  final Dio _dio;
  final DateTime Function() _nowProvider;
  final int _maxReportsPerMinute;

  bool _isReporting = false;
  final List<DateTime> _recentReportTimestamps = <DateTime>[];

  static String scrubText(String input, {int maxLength = 2000}) =>
      scrubSensitiveText(input, maxLength: maxLength);

  Future<bool> reportError(
    Object error,
    StackTrace? stackTrace, {
    String? screen,
    bool isFatal = false,
    String? appVersion,
  }) async {
    if (_isReporting) {
      return false;
    }

    final now = _nowProvider();
    final windowStart = now.subtract(const Duration(seconds: 60));
    _recentReportTimestamps.removeWhere((ts) => ts.isBefore(windowStart));
    if (_recentReportTimestamps.length >= _maxReportsPerMinute) {
      return false;
    }

    _isReporting = true;
    _recentReportTimestamps.add(now);

    try {
      final errorType = scrubSensitiveText(
        error.runtimeType.toString(),
        maxLength: 120,
      );
      final message = scrubSensitiveText(
        error.toString(),
        maxLength: 500,
      );
      final stackPreview = stackTrace == null
          ? ''
          : scrubSensitiveText(stackTrace.toString(), maxLength: 2000);
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;

      final payload = <String, dynamic>{
        'error_type': errorType,
        'message': message,
        'stack_preview': stackPreview,
        'app_version': appVersion ?? '1.0.0',
        'platform': platform,
        if (screen != null && screen.isNotEmpty)
          'screen': scrubSensitiveText(screen, maxLength: 120),
        'is_fatal': isFatal,
      };

      await _dio.post<dynamic>(
        ApiConfig.clientErrorTelemetryEndpoint,
        data: payload,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      _isReporting = false;
    }
  }

  static void installGlobalHandlers({ClientErrorReporter? reporter}) {
    final activeReporter = reporter ?? ClientErrorReporter();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      unawaited(
        activeReporter.reportError(
          details.exception,
          details.stack,
          screen: details.context?.toDescription(),
          isFatal: false,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(
        activeReporter.reportError(
          error,
          stack,
          isFatal: true,
        ),
      );
      return !kDebugMode;
    };
  }
}

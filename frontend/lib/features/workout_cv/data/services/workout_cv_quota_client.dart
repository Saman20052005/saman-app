import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../../config/api_config.dart';

class WorkoutCvAuthorizeResult {
  final bool allowed;
  final bool paywallEnforced;
  final bool isQuotaExhausted;
  final bool isUpgradeRequired;
  final bool isServiceUnavailable;
  final String? tier;
  final int? limitUnits;
  final int? remainingUnits;
  final String? operationId;
  final String? message;

  const WorkoutCvAuthorizeResult({
    required this.allowed,
    this.paywallEnforced = false,
    this.isQuotaExhausted = false,
    this.isUpgradeRequired = false,
    this.isServiceUnavailable = false,
    this.tier,
    this.limitUnits,
    this.remainingUnits,
    this.operationId,
    this.message,
  });
}

class WorkoutCvQuotaClient {
  final http.Client _client;
  final Future<String?> Function() _tokenGetter;
  final bool _bypassCheck;
  final Duration _timeout;

  WorkoutCvQuotaClient({
    http.Client? client,
    Future<String?> Function()? tokenGetter,
    bool? bypassCheck,
    Duration timeout = const Duration(seconds: 10),
  })  : _client = client ?? http.Client(),
        _tokenGetter = tokenGetter ?? _defaultTokenGetter,
        _bypassCheck = bypassCheck ??
            const bool.fromEnvironment('BYPASS_CV_CHECK', defaultValue: false),
        _timeout = timeout;

  static Future<String?> _defaultTokenGetter() async {
    try {
      const storage = FlutterSecureStorage();
      return await storage.read(key: 'auth_token') ??
          await storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  static String _generateIdempotencyKey() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 20);
    return 'cv_${micros}_$rand';
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _extractDetailMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'];
      if (detail is Map<String, dynamic>) {
        return detail;
      }
      if (detail is Map) {
        return Map<String, dynamic>.from(detail);
      }
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const <String, dynamic>{};
  }

  Future<WorkoutCvAuthorizeResult> authorize({
    String? exerciseSlug,
    String sourceMode = 'realtime',
    String? idempotencyKey,
  }) async {
    if (_bypassCheck) {
      return const WorkoutCvAuthorizeResult(
        allowed: true,
        paywallEnforced: false,
      );
    }

    try {
      final token = await _tokenGetter();
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final body = jsonEncode(<String, dynamic>{
        'exercise_slug': exerciseSlug,
        'source_mode': sourceMode,
        'idempotency_key': idempotencyKey ?? _generateIdempotencyKey(),
      });

      final response = await _client
          .post(
            Uri.parse(ApiConfig.workoutCvAuthorizeEndpoint),
            headers: headers,
            body: body,
          )
          .timeout(_timeout);

      Map<String, dynamic> decoded = const <String, dynamic>{};
      if (response.body.isNotEmpty) {
        try {
          final raw = jsonDecode(response.body);
          if (raw is Map<String, dynamic>) {
            decoded = raw;
          } else if (raw is Map) {
            decoded = Map<String, dynamic>.from(raw);
          }
        } catch (_) {
          decoded = const <String, dynamic>{};
        }
      }

      if (response.statusCode == 200) {
        return WorkoutCvAuthorizeResult(
          allowed: decoded['allowed'] == true,
          paywallEnforced: decoded['paywall_enforced'] == true,
          tier: decoded['tier'] as String?,
          limitUnits: _toInt(decoded['limit_units']),
          remainingUnits: _toInt(decoded['remaining_units']),
          operationId: decoded['operation_id'] as String?,
          message: decoded['message'] as String?,
        );
      }

      final detail = _extractDetailMap(decoded);

      if (response.statusCode == 429) {
        return WorkoutCvAuthorizeResult(
          allowed: false,
          paywallEnforced: true,
          isQuotaExhausted: true,
          tier: detail['tier'] as String?,
          limitUnits: _toInt(detail['limit_units']),
          remainingUnits: _toInt(detail['remaining_units']),
          message: detail['message'] as String?,
        );
      }

      if (response.statusCode == 403) {
        return WorkoutCvAuthorizeResult(
          allowed: false,
          paywallEnforced: true,
          isUpgradeRequired: true,
          tier: detail['tier'] as String?,
          limitUnits: _toInt(detail['limit_units']),
          remainingUnits: _toInt(detail['remaining_units']),
          message: detail['message'] as String?,
        );
      }

      return WorkoutCvAuthorizeResult(
        allowed: false,
        paywallEnforced: false,
        isServiceUnavailable: true,
        message: detail['message'] as String?,
      );
    } on TimeoutException {
      return const WorkoutCvAuthorizeResult(
        allowed: false,
        paywallEnforced: false,
        isServiceUnavailable: true,
      );
    } catch (_) {
      return const WorkoutCvAuthorizeResult(
        allowed: false,
        paywallEnforced: false,
        isServiceUnavailable: true,
      );
    }
  }
}

bool _isFlutterTestEnvironment() {
  if (kIsWeb) return false;
  try {
    return Platform.environment['FLUTTER_TEST'] == 'true';
  } catch (_) {
    return false;
  }
}

final workoutCvQuotaClientProvider = Provider<WorkoutCvQuotaClient>((ref) {
  return WorkoutCvQuotaClient(
    bypassCheck:
        const bool.fromEnvironment('BYPASS_CV_CHECK', defaultValue: false) ||
            _isFlutterTestEnvironment(),
  );
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

/// Current legal consent status returned by `/api/user/consent`.
class ConsentStatus {
  const ConsentStatus({
    required this.hasConsented,
    required this.requiredVersion,
    this.consentVersion,
    this.acceptedAt,
    this.acceptedHealthData = false,
    this.acceptedAiProcessing = false,
    this.acknowledgedMedicalDisclaimer = false,
  });

  final bool hasConsented;
  final String requiredVersion;
  final String? consentVersion;
  final String? acceptedAt;
  final bool acceptedHealthData;
  final bool acceptedAiProcessing;
  final bool acknowledgedMedicalDisclaimer;

  factory ConsentStatus.fromJson(Map<String, dynamic> json) {
    return ConsentStatus(
      hasConsented: json['has_consented'] == true,
      requiredVersion: (json['required_version'] as String?) ??
          PrivacyService.requiredConsentVersion,
      consentVersion: json['consent_version'] as String?,
      acceptedAt: json['accepted_at'] as String?,
      acceptedHealthData: json['accepted_health_data'] == true,
      acceptedAiProcessing: json['accepted_ai_processing'] == true,
      acknowledgedMedicalDisclaimer:
          json['acknowledged_medical_disclaimer'] == true,
    );
  }
}

/// Summary returned by `DELETE /api/user/account`.
class DeleteAccountResult {
  const DeleteAccountResult({
    required this.deleted,
    required this.collectionsCleaned,
    required this.totalDocumentsDeleted,
    required this.r2ObjectsDeleted,
    required this.r2ObjectsFailed,
  });

  final bool deleted;
  final int collectionsCleaned;
  final int totalDocumentsDeleted;
  final int r2ObjectsDeleted;
  final int r2ObjectsFailed;

  factory DeleteAccountResult.fromJson(Map<String, dynamic> json) {
    return DeleteAccountResult(
      deleted: json['deleted'] == true,
      collectionsCleaned: (json['collections_cleaned'] as num?)?.toInt() ?? 0,
      totalDocumentsDeleted:
          (json['total_documents_deleted'] as num?)?.toInt() ?? 0,
      r2ObjectsDeleted: (json['r2_objects_deleted'] as num?)?.toInt() ?? 0,
      r2ObjectsFailed: (json['r2_objects_failed'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Client service for VN 2026 health-data consent, personal data export,
/// and permanent account deletion.
class PrivacyService {
  PrivacyService({
    Dio? dio,
    Future<String?> Function()? tokenProvider,
    Future<SharedPreferences> Function()? prefsProvider,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {'Content-Type': 'application/json'},
              ),
            ),
        _tokenProvider = tokenProvider ?? AuthHelper.getToken,
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static const String requiredConsentVersion = 'v1.0-vn-2026';

  final Dio _dio;
  final Future<String?> Function() _tokenProvider;
  final Future<SharedPreferences> Function() _prefsProvider;

  /// Cache key in SharedPreferences for per-user consent status.
  String cacheKeyForUser(String userId) =>
      'consent_${requiredConsentVersion}_$userId';

  Future<Options> _authOptions() async {
    final token = await _tokenProvider();
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return Options(headers: headers);
  }

  /// Fast-path check for locally cached consent for [userId].
  Future<bool> hasCachedConsent(String userId) async {
    if (userId.isEmpty) return false;
    final prefs = await _prefsProvider();
    return prefs.getBool(cacheKeyForUser(userId)) ?? false;
  }

  /// Clears locally cached consent for [userId].
  Future<void> clearCachedConsent(String userId) async {
    if (userId.isEmpty) return;
    final prefs = await _prefsProvider();
    await prefs.remove(cacheKeyForUser(userId));
  }

  Future<void> _writeCachedConsent(String userId, bool hasConsented) async {
    if (userId.isEmpty) return;
    final prefs = await _prefsProvider();
    if (hasConsented) {
      await prefs.setBool(cacheKeyForUser(userId), true);
    } else {
      await prefs.remove(cacheKeyForUser(userId));
    }
  }

  /// Fetches consent status from `GET /api/user/consent` and updates cache.
  Future<ConsentStatus> fetchConsentStatus({String? userId}) async {
    final options = await _authOptions();
    final response = await _dio.get<dynamic>(
      ApiConfig.userConsentEndpoint,
      options: options,
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final status = ConsentStatus.fromJson(data);
    if (userId != null && userId.isNotEmpty) {
      await _writeCachedConsent(userId, status.hasConsented);
    }
    return status;
  }

  /// Submits explicit 3-flag consent to `POST /api/user/consent` and caches it.
  Future<ConsentStatus> submitConsent({
    required String userId,
    required bool acceptedHealthData,
    required bool acceptedAiProcessing,
    required bool acknowledgedMedicalDisclaimer,
    String locale = 'vi',
  }) async {
    final options = await _authOptions();
    final response = await _dio.post<dynamic>(
      ApiConfig.userConsentEndpoint,
      data: <String, dynamic>{
        'consent_version': requiredConsentVersion,
        'accepted_health_data': acceptedHealthData,
        'accepted_ai_processing': acceptedAiProcessing,
        'acknowledged_medical_disclaimer': acknowledgedMedicalDisclaimer,
        'locale': locale,
      },
      options: options,
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final status = ConsentStatus.fromJson(data);
    if (userId.isNotEmpty) {
      await _writeCachedConsent(userId, status.hasConsented);
    }
    return status;
  }

  /// Exports all personal data from `GET /api/user/export`.
  Future<Map<String, dynamic>> exportUserData() async {
    final options = await _authOptions();
    final response = await _dio.get<dynamic>(
      ApiConfig.userExportEndpoint,
      options: options,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Permanently deletes the user's account via `DELETE /api/user/account`.
  Future<DeleteAccountResult> deleteAccount({
    required String confirmText,
    String? userId,
  }) async {
    final options = await _authOptions();
    final response = await _dio.delete<dynamic>(
      ApiConfig.userDeleteAccountEndpoint,
      data: <String, dynamic>{
        'confirm_text': confirmText,
      },
      options: options,
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final result = DeleteAccountResult.fromJson(data);
    if (result.deleted && userId != null && userId.isNotEmpty) {
      await clearCachedConsent(userId);
    }
    return result;
  }
}

final privacyServiceProvider = Provider<PrivacyService>((ref) {
  return PrivacyService();
});

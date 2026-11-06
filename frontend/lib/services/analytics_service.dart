import 'package:dio/dio.dart';

import 'api_client.dart';

class AnalyticsQuote {
  const AnalyticsQuote({
    required this.quoteId,
    required this.rangeDays,
    required this.rawNutritionCount,
    required this.activeDays,
    required this.workoutSessions,
    required this.includedWorkouts,
    required this.workoutTruncated,
    required this.estimatedTokens,
    required this.quotaCost,
  });

  final String quoteId;
  final int rangeDays;
  final int rawNutritionCount;
  final int activeDays;
  final int workoutSessions;
  final int includedWorkouts;
  final bool workoutTruncated;
  final int estimatedTokens;
  final int quotaCost;

  factory AnalyticsQuote.fromJson(Map<String, dynamic> json) {
    return AnalyticsQuote(
      quoteId: json['quote_id'].toString(),
      rangeDays: (json['range_days'] as num).toInt(),
      rawNutritionCount: (json['raw_nutrition_count'] as num).toInt(),
      activeDays: (json['active_days'] as num).toInt(),
      workoutSessions: (json['matched_workout_sessions'] as num).toInt(),
      includedWorkouts: (json['included_workout_sessions'] as num).toInt(),
      workoutTruncated: json['workout_truncated'] == true,
      estimatedTokens: (json['estimated_tokens'] as num).toInt(),
      quotaCost: (json['quota_cost'] as num).toInt(),
    );
  }
}

class QuoteExpiredException implements Exception {
  const QuoteExpiredException();
}

class AnalyticsService {
  AnalyticsService({Dio? dio}) : _dio = dio ?? ApiClient.dio;

  final Dio _dio;

  Future<AnalyticsQuote> getPreflightQuote(int rangeDays) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/coach/analytics/preflight',
      data: {'range_days': rangeDays},
    );
    return AnalyticsQuote.fromJson(response.data!);
  }

  Future<Map<String, dynamic>> executeAnalytics({
    required String quoteId,
    required int rangeDays,
    required bool confirm,
    required String operationId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/coach/analytics/execute',
        data: {
          'quote_id': quoteId,
          'range_days': rangeDays,
          'confirm': confirm,
          'operation_id': operationId,
        },
      );
      return response.data!;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 409) {
        throw const QuoteExpiredException();
      }
      rethrow;
    }
  }
}

import 'package:dio/dio.dart';
import '../../../../config/api_config.dart';
import '../../../../services/api_client.dart';
import '../../domain/models/journey_models.dart';

class WalletBalanceData {
  final int balance;
  final int aiCredits;

  const WalletBalanceData({
    required this.balance,
    required this.aiCredits,
  });
}

abstract class JourneyRepository {
  Future<SamanJourney?> getActiveJourney();
  Future<SamanJourney> createJourney({
    required JourneyFocus focus,
    required int totalDays,
    String? reminderTime,
  });
  Future<SamanJourney> completeTask({
    required String journeyId,
    required String taskId,
    String? activityId,
  });
  Future<SamanJourney> claimDailyReward({
    required String journeyId,
    String? date,
  });
  Future<WalletBalanceData> getPointBalance();
  Future<List<PointTransaction>> getPointHistory();
  Future<List<RewardItem>> getRewardsCatalog();
  Future<bool> redeemReward({required String rewardId});
}

class JourneyRepositoryImpl implements JourneyRepository {
  final Dio _dio;

  JourneyRepositoryImpl([Dio? dio]) : _dio = dio ?? ApiClient.dio;

  @override
  Future<SamanJourney?> getActiveJourney() async {
    try {
      final response = await _dio.get('${ApiConfig.baseUrl}/api/journey/active');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['journey'] != null) {
          return SamanJourney.fromJson(data['journey'] as Map<String, dynamic>);
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<SamanJourney> createJourney({
    required JourneyFocus focus,
    required int totalDays,
    String? reminderTime,
  }) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/journey/create',
      data: {
        'focus': focus.name,
        'total_days': totalDays,
        'reminder_time': reminderTime,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return SamanJourney.fromJson(data['journey'] as Map<String, dynamic>);
  }

  @override
  Future<SamanJourney> completeTask({
    required String journeyId,
    required String taskId,
    String? activityId,
  }) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/journey/complete-task',
      data: {
        'journey_id': journeyId,
        'task_id': taskId,
        'activity_id': activityId,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return SamanJourney.fromJson(data['journey'] as Map<String, dynamic>);
  }

  @override
  Future<SamanJourney> claimDailyReward({
    required String journeyId,
    String? date,
  }) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/journey/claim-daily-reward',
      data: {
        'journey_id': journeyId,
        'date': date,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return SamanJourney.fromJson(data['journey'] as Map<String, dynamic>);
  }

  @override
  Future<WalletBalanceData> getPointBalance() async {
    final response = await _dio.get('${ApiConfig.baseUrl}/api/wallet/balance');
    final data = response.data as Map<String, dynamic>;
    return WalletBalanceData(
      balance: (data['balance'] as num?)?.toInt() ?? 0,
      aiCredits: (data['ai_credits'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<PointTransaction>> getPointHistory() async {
    final response = await _dio.get('${ApiConfig.baseUrl}/api/wallet/history');
    final data = response.data as Map<String, dynamic>;
    final rawList = data['transactions'] as List<dynamic>? ?? [];
    return rawList.map((t) => PointTransaction.fromJson(t as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<RewardItem>> getRewardsCatalog() async {
    final response = await _dio.get('${ApiConfig.baseUrl}/api/wallet/rewards');
    final data = response.data as Map<String, dynamic>;
    final rawList = data['rewards'] as List<dynamic>? ?? [];
    return rawList.map((r) => RewardItem.fromJson(r as Map<String, dynamic>)).toList();
  }

  @override
  Future<bool> redeemReward({required String rewardId}) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/wallet/redeem',
      data: {'reward_id': rewardId},
    );
    return response.statusCode == 200;
  }
}

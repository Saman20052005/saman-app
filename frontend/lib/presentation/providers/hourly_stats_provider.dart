import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/report/domain/entities/hourly_calorie_stats.dart';
import '../../services/api_client.dart';

// Toggle demo mode when backend endpoint is not available
const bool kHourlyStatsDemoMode = false;

class HourlyStatsController
    extends AutoDisposeAsyncNotifier<List<HourlyCalorieStats>> {
  @override
  Future<List<HourlyCalorieStats>> build() async {
    if (kHourlyStatsDemoMode) return _generateMock(points: 12);
    return await fetch();
  }

  Future<List<HourlyCalorieStats>> fetch() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/api/v1/stats/daily-hourly');
      final raw = resp.data;

      List<dynamic> list;
      if (raw is Map && raw['data'] is List) {
        list = raw['data'];
      } else if (raw is List) {
        list = raw;
      } else if (raw is Map && raw['stats'] is List) {
        list = raw['stats'];
      } else {
        throw Exception('Unexpected response for hourly stats');
      }

      return list.map((e) {
        if (e is Map<String, dynamic>) {
          return HourlyCalorieStats.fromJson(e);
        }
        return HourlyCalorieStats.fromJson(Map<String, dynamic>.from(e as Map));
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => fetch());
  }

  List<HourlyCalorieStats> _generateMock({int points = 12}) {
    final rnd = Random();
    return List.generate(
        points,
        (i) => HourlyCalorieStats(
            hour: i,
            intake: 40 + rnd.nextDouble() * 120,
            burn: 30 + rnd.nextDouble() * 80));
  }
}

final hourlyStatsProvider = AsyncNotifierProvider.autoDispose<
    HourlyStatsController, List<HourlyCalorieStats>>(HourlyStatsController.new);

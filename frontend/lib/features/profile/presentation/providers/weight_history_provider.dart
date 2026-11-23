import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/api_config.dart';
import '../../../../presentation/providers/workout_history_providers.dart';
import '../../../../providers/profile_provider.dart';
import '../../../../services/api_client.dart';
import '../../../../utils/auth_helper.dart';

/// Single weight log entry in user history.
class WeightHistoryEntry {
  final String date;
  final double weightKg;
  final String source;

  const WeightHistoryEntry({
    required this.date,
    required this.weightKg,
    required this.source,
  });

  factory WeightHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WeightHistoryEntry(
      date: json['date'] as String? ?? '',
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0.0,
      source: json['source'] as String? ?? '',
    );
  }
}

/// Aggregated weight trend data payload.
class WeightHistoryData {
  final int days;
  final List<WeightHistoryEntry> entries;
  final double? latestWeightKg;
  final double? deltaKg;

  const WeightHistoryData({
    required this.days,
    required this.entries,
    this.latestWeightKg,
    this.deltaKg,
  });

  factory WeightHistoryData.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? const [];
    final entries = rawEntries.map((e) {
      if (e is Map<String, dynamic>) {
        return WeightHistoryEntry.fromJson(e);
      } else if (e is Map) {
        return WeightHistoryEntry.fromJson(Map<String, dynamic>.from(e));
      }
      return const WeightHistoryEntry(date: '', weightKg: 0.0, source: '');
    }).toList();

    return WeightHistoryData(
      days: (json['days'] as num?)?.toInt() ?? 30,
      entries: entries,
      latestWeightKg: (json['latest_weight_kg'] as num?)?.toDouble(),
      deltaKg: (json['delta_kg'] as num?)?.toDouble(),
    );
  }
}

/// Filter days for weight trend (7, 30, 90). Defaults to 30.
final weightHistoryDaysProvider = StateProvider<int>((ref) => 30);

/// Weight history future provider scoped by authentication and filter days.
final weightHistoryProvider =
    FutureProvider.autoDispose<WeightHistoryData>((ref) async {
  ref.watch(workoutAuthScopeProvider);
  final days = ref.watch(weightHistoryDaysProvider);
  if (ref.read(authLoggingOutProvider)) {
    return WeightHistoryData(days: days, entries: const []);
  }
  final dio = ref.watch(dioProvider);

  final response = await dio.get<Map<String, dynamic>>(
    '${ApiConfig.baseUrl}/api/user/weight-history',
    queryParameters: {'days': days},
  );

  final data = response.data;
  if (data == null) {
    return WeightHistoryData(days: days, entries: const []);
  }
  return WeightHistoryData.fromJson(data);
});

/// Logs a manual weight entry and synchronizes profile + weight history.
Future<void> logManualWeight(
  dynamic ref, {
  required double weightKg,
  String? date,
}) async {
  final Dio dio;
  if (ref is WidgetRef) {
    dio = ref.read(dioProvider);
  } else if (ref is Ref) {
    dio = ref.read(dioProvider);
  } else {
    dio = (ref.read(dioProvider) as Dio);
  }

  await dio.post(
    '${ApiConfig.baseUrl}/api/user/weight-history',
    data: {
      'weight_kg': weightKg,
      if (date != null) 'date': date,
    },
  );

  if (ref is WidgetRef) {
    ref.invalidate(weightHistoryProvider);
    await ref.read(profileProvider.notifier).loadProfile();
  } else if (ref is Ref) {
    ref.invalidate(weightHistoryProvider);
    await ref.read(profileProvider.notifier).loadProfile();
  } else {
    ref.invalidate(weightHistoryProvider);
    await (ref.read(profileProvider.notifier) as ProfileNotifier).loadProfile();
  }
}

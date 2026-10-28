import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

abstract class ReportRepository {
  Future<WeeklyReportEntity> getWeeklyReport(DateTime date);
}

class ReportRepositoryImpl implements ReportRepository {
  @override
  Future<WeeklyReportEntity> getWeeklyReport(DateTime date) async {
    final token = await AuthHelper.getToken();
    if (token == null) throw Exception("Unauthorized");

    // Align to Monday as start of week
    final monday = date.subtract(Duration(days: date.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final startDateStr = DateFormat('yyyy-MM-dd').format(weekStart);

    const nutritionUrl = '${ApiConfig.baseUrl}/api/nutrition/report/weekly';
    const workoutUrl = '${ApiConfig.baseUrl}/api/workouts/report/weekly';

    try {
      final responses = await Future.wait([
        ApiClient.dio.get(
          nutritionUrl,
          queryParameters: {'start_date': startDateStr},
        ),
        ApiClient.dio.get(
          workoutUrl,
          queryParameters: {'start_date': startDateStr},
        ),
      ]);

      final nutritionResponse = responses[0];
      final workoutResponse = responses[1];

      if (kDebugMode) {
        debugPrint(
          '[REPORT] Responses: nutrition=${nutritionResponse.statusCode} '
          'workout=${workoutResponse.statusCode}',
        );
      }

      // 1. Process Nutrition Data
      Map<String, dynamic> nutritionMap = {};
      Map<String, dynamic> macroTargets = {};
      int targetCalories = 0;
      int targetProtein = 0;
      int targetCarbs = 0;
      int targetFat = 0;

      if (nutritionResponse.statusCode == 200 &&
          nutritionResponse.data != null) {
        final data = nutritionResponse.data is String
            ? jsonDecode(nutritionResponse.data as String)
            : nutritionResponse.data;

        if (data is Map) {
          if (data['macro_targets'] is Map) {
            macroTargets = data['macro_targets'] as Map<String, dynamic>;
            targetCalories = (macroTargets['calories'] as num?)?.toInt() ?? 0;
            targetProtein = (macroTargets['protein'] as num?)?.toInt() ?? 0;
            targetCarbs = (macroTargets['carbs'] as num?)?.toInt() ?? 0;
            targetFat = (macroTargets['fat'] as num?)?.toInt() ?? 0;
          }

          final list = data['daily'] as List? ?? data['items'] as List? ?? [];
          for (var item in list) {
            if (item is Map && item['date'] != null) {
              nutritionMap[item['date'].toString()] = item;
            }
          }
        }
      }

      // 2. Process Workout Data
      Map<String, List<Map<String, dynamic>>> workoutMap = {};
      int targetBurned = 400; // Standard goal

      if (workoutResponse.statusCode == 200 && workoutResponse.data != null) {
        final decoded = workoutResponse.data is String
            ? jsonDecode(workoutResponse.data as String)
            : workoutResponse.data;

        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map) {
          if (decoded.containsKey('daily_data')) {
            list = decoded['daily_data'] as List? ?? [];
          } else if (decoded.containsKey('items')) {
            list = decoded['items'] as List? ?? [];
          }
        }

        for (var item in list) {
          if (item is Map) {
            String? itemDate;
            if (item['date'] != null) {
              itemDate = item['date'].toString().split('T')[0];
            } else if (item['started_at'] != null) {
              itemDate = item['started_at'].toString().split('T')[0];
            } else if (item['created_at'] != null) {
              itemDate = item['created_at'].toString().split('T')[0];
            }

            if (itemDate != null) {
              workoutMap.putIfAbsent(itemDate, () => []).add(item as Map<String, dynamic>);
            }
          }
        }
      }

      // 3. Construct 7 Days (Monday to Sunday)
      List<DailyStats> stats = [];
      List<WorkoutSessionItem> workoutSessions = [];
      double totalCalIn = 0;
      double totalCalOut = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;

      for (int i = 0; i < 7; i++) {
        final d = weekStart.add(Duration(days: i));
        final dStr = DateFormat('yyyy-MM-dd').format(d);
        final dayName = DateFormat('EEEE').format(d);

        // Nutrition day mapping
        final nItem = nutritionMap[dStr];
        final int logCount = (nItem != null && nItem['log_count'] != null)
            ? (nItem['log_count'] as num).toInt()
            : (nItem != null ? 1 : 0);

        final bool isRecorded = logCount > 0;
        final double calIn = (nItem != null)
            ? (nItem['calories'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        final double protein = (nItem != null)
            ? (nItem['protein'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        final double carbs = (nItem != null)
            ? (nItem['carbs'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        final double fat = (nItem != null)
            ? (nItem['fat'] as num?)?.toDouble() ?? 0.0
            : 0.0;

        // Workout day mapping
        final dayWorkouts = workoutMap[dStr] ?? [];
        double calOut = 0;
        int durationMin = 0;
        String? workoutTitle;
        double? rpe;
        bool isRestDay = false;

        for (var w in dayWorkouts) {
          final c = (w['calories_burned'] ?? w['calories'] ?? w['kcal']);
          final numVal = (c is num) ? c.toDouble() : 0.0;
          calOut += numVal;

          final dur = (w['total_duration_minutes'] ?? w['duration_minutes'] ?? w['duration'] ?? 0);
          if (dur is num) durationMin += dur.toInt();

          if (workoutTitle == null && (w['plan_name'] != null || w['name'] != null || w['title'] != null)) {
            workoutTitle = (w['plan_name'] ?? w['name'] ?? w['title'])?.toString();
          }

          if (w['rpe'] is num) {
            rpe = (w['rpe'] as num).toDouble();
          }

          if (w['is_rest_day'] == true || (w['status'] == 'rest')) {
            isRestDay = true;
          }

          workoutSessions.add(WorkoutSessionItem(
            title: workoutTitle ?? 'Workout Session',
            dayName: dayName,
            date: d,
            durationMinutes: durationMin > 0 ? durationMin : 30,
            caloriesBurned: numVal.round(),
            rpe: rpe,
          ));
        }

        final bool hasWorkout = dayWorkouts.isNotEmpty;

        stats.add(DailyStats(
          date: d,
          caloriesIn: calIn,
          caloriesBurned: calOut,
          protein: protein,
          carbs: carbs,
          fat: fat,
          logCount: logCount,
          isRecorded: isRecorded,
          hasWorkout: hasWorkout,
          isRestDay: isRestDay,
          workoutDurationMinutes: durationMin,
          workoutTitle: workoutTitle,
          rpe: rpe,
        ));

        if (isRecorded) {
          totalCalIn += calIn;
          totalProtein += protein;
          totalCarbs += carbs;
          totalFat += fat;
        }
        totalCalOut += calOut;
      }

      // 4. Transparent Calculations
      final loggedDays = stats.where((d) => d.isRecorded && !d.isFuture).toList();
      final activeDays = stats.where((d) => d.hasWorkout && d.caloriesBurned > 0).toList();

      final avgCalIn = loggedDays.isNotEmpty ? (totalCalIn / loggedDays.length) : 0.0;
      final avgProtein = loggedDays.isNotEmpty ? (totalProtein / loggedDays.length) : 0.0;
      final avgCarbs = loggedDays.isNotEmpty ? (totalCarbs / loggedDays.length) : 0.0;
      final avgFat = loggedDays.isNotEmpty ? (totalFat / loggedDays.length) : 0.0;
      final avgCalOut = activeDays.isNotEmpty ? (totalCalOut / activeDays.length) : 0.0;

      // 5. Data-driven Factual Takeaway
      String takeaway;
      if (loggedDays.isEmpty && activeDays.isEmpty) {
        takeaway = 'No nutrition or workout logs recorded this week yet. Track daily to view your weekly performance.';
      } else if (loggedDays.isNotEmpty && activeDays.isNotEmpty) {
        final pct = targetCalories > 0 ? ((avgCalIn - targetCalories).abs() / targetCalories * 100).round() : 0;
        final deltaText = targetCalories > 0 ? 'stayed within $pct% of target' : 'averaged ${avgCalIn.round()} kcal/day';
        takeaway = 'Caloric intake $deltaText while completing ${activeDays.length} training sessions this week.';
      } else if (loggedDays.isNotEmpty) {
        takeaway = 'Caloric intake averaged ${avgCalIn.round()} kcal/day across ${loggedDays.length} logged days.';
      } else {
        takeaway = 'Completed ${activeDays.length} workout sessions with ${totalCalOut.round()} kcal burned. Log meals to complete energy telemetry.';
      }

      return WeeklyReportEntity(
        days: stats,
        avgCaloriesIn: avgCalIn,
        avgCaloriesBurned: avgCalOut,
        avgProtein: avgProtein,
        avgCarbs: avgCarbs,
        avgFat: avgFat,
        targetCalories: targetCalories,
        targetProtein: targetProtein,
        targetCarbs: targetCarbs,
        targetFat: targetFat,
        targetBurned: targetBurned,
        daysLogged: loggedDays.length,
        activeDays: activeDays.length,
        totalCaloriesBurned: totalCalOut,
        workoutSessions: workoutSessions,
        takeaway: takeaway,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[REPORT] Request failed: ${e.runtimeType}');
        debugPrintStack(stackTrace: stack);
      }
      return WeeklyReportEntity(
        days: List.generate(7, (i) {
          final d = weekStart.add(Duration(days: i));
          return DailyStats(
            date: d,
            caloriesIn: 0,
            caloriesBurned: 0,
            protein: 0,
            isRecorded: false,
          );
        }),
        avgCaloriesIn: 0,
        avgCaloriesBurned: 0,
        avgProtein: 0,
      );
    }
  }
}

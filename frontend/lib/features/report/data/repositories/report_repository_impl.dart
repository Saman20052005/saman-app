import 'dart:convert';
import 'dart:developer';
import 'package:intl/intl.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

abstract class ReportRepository {
  Future<WeeklyReportEntity> getWeeklyReport(DateTime endDate);
}

class ReportRepositoryImpl implements ReportRepository {
  @override
  Future<WeeklyReportEntity> getWeeklyReport(DateTime endDate) async {
    print("🔥🔥🔥 STARTING REPORT REPO IMPL - LOGIC MOI 🔥🔥🔥");
    final token = await AuthHelper.getToken();
    if (token == null) throw Exception("Unauthorized");

    final dateStr = DateFormat('yyyy-MM-dd').format(endDate);

    // 1. CHUẨN BỊ URI
    final nutritionUrl = '${ApiConfig.baseUrl}/api/nutrition/report/weekly';
    final workoutUrl = '${ApiConfig.baseUrl}/api/workouts/report/weekly';

    try {
      print("🔥🔥🔥 CALLING API... 🔥🔥🔥");

      // 2. GỌI API SONG SONG (Đã sửa lỗi cú pháp tại đây)
      final responses = await Future.wait([
        ApiClient.dio
            .get(nutritionUrl, queryParameters: {'start_date': dateStr}),
        ApiClient.dio.get(workoutUrl, queryParameters: {'date': dateStr}),
      ]);

      final nutritionResponse = responses[0];
      final workoutResponse = responses[1];

      print("🔥🔥🔥 API DONE. STATUS: ${responses[1].statusCode} 🔥🔥🔥");
      print("🔥🔥🔥 WORKOUT BODY: ${responses[1].data} 🔥🔥🔥");

      // 3. XỬ LÝ DỮ LIỆU NUTRITION
      Map<String, dynamic> nutritionMap = {};
      if (nutritionResponse.statusCode == 200 &&
          nutritionResponse.data != null) {
        final data = nutritionResponse.data is String
            ? jsonDecode(nutritionResponse.data as String)
            : nutritionResponse.data;
        final list = data['items'] as List? ?? [];
        for (var item in list) {
          if (item['date'] != null) nutritionMap[item['date']] = item;
        }
      }

      // 4. XỬ LÝ DỮ LIỆU WORKOUT
      Map<String, double> workoutMap = {};

      if (workoutResponse.statusCode == 200 && workoutResponse.data != null) {
        final decoded = workoutResponse.data is String
            ? jsonDecode(workoutResponse.data as String)
            : workoutResponse.data;
        List<dynamic> list = [];

        // Logic mới: Bắt cả trường hợp List hoặc Map
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded.containsKey('items')) {
          list = decoded['items'] as List? ?? [];
        }

        print("🔍 WORKOUT DATA LIST: $list"); // Log kiểm tra data sau khi parse

        for (var item in list) {
          if (item is Map && item['date'] != null) {
            final val = item['calories'];
            // Parse an toàn cho cả int và double
            workoutMap[item['date']] = (val is num) ? val.toDouble() : 0.0;
          }
        }
      } else {
        print(
            "❌ Workout API Failed: ${workoutResponse.statusCode} - ${workoutResponse.data}");
      }

      // 5. MERGE DỮ LIỆU VÀO ENTITY
      List<DailyStats> stats = [];
      double totalCalIn = 0;
      double totalCalOut = 0;
      double totalProtein = 0;

      for (int i = 6; i >= 0; i--) {
        final d = endDate.subtract(Duration(days: i));
        final dStr = DateFormat('yyyy-MM-dd').format(d);

        // Lấy từ Nutrition Map
        final nItem = nutritionMap[dStr];
        double calIn = (nItem != null)
            ? (nItem['calories'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        double protein = (nItem != null)
            ? (nItem['protein'] as num?)?.toDouble() ?? 0.0
            : 0.0;

        // Lấy từ Workout Map
        double calOut = workoutMap[dStr] ?? 0.0;

        stats.add(DailyStats(
          date: d,
          caloriesIn: calIn,
          caloriesBurned: calOut,
          protein: protein,
        ));

        totalCalIn += calIn;
        totalCalOut += calOut;
        totalProtein += protein;
      }

      return WeeklyReportEntity(
        days: stats,
        avgCaloriesIn: totalCalIn / 7,
        avgCaloriesBurned: totalCalOut / 7,
        avgProtein: totalProtein / 7,
      );
    } catch (e, stack) {
      log("Error fetching report: $e", stackTrace: stack);
      return WeeklyReportEntity(
          days: [], avgCaloriesIn: 0, avgCaloriesBurned: 0, avgProtein: 0);
    }
  }
}

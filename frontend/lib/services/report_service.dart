// [File: lib/services/report_service.dart]
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../models/report_model.dart';
import '../services/api_client.dart';

class ReportService {
  Future<WeeklyReport?> fetchWeeklyReport(DateTime endDate) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(endDate);

      // Gọi đúng Endpoint đã khai báo trong main.py
      final response = await ApiClient.dio.get(
        '${ApiConfig.baseUrl}/api/nutrition/report/weekly',
        queryParameters: {'date': dateStr},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return WeeklyReport.fromJson(data);
      }
      return null;
    } catch (e) {
      print("❌ Report Fetch Error: $e");
      return null;
    }
  }
}

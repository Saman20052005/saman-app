import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
// Đảm bảo import đúng file Impl (không phải v2)
import 'package:health_ai_app/features/report/data/repositories/report_repository_impl.dart';

final weeklyReportProvider =
    FutureProvider.family<WeeklyReportEntity, DateTime>((ref, date) async {
  // Gọi class ReportRepositoryImpl mới nhất
  final repository = ReportRepositoryImpl();
  return repository.getWeeklyReport(date);
});

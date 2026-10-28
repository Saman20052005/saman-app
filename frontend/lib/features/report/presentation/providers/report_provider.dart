import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import 'package:health_ai_app/features/report/data/repositories/report_repository_impl.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepositoryImpl();
});

final weeklyReportProvider =
    FutureProvider.family<WeeklyReportEntity, DateTime>((ref, date) async {
  // Normalize date to Monday so all days of the same week share the exact same key
  final monday = date.subtract(Duration(days: date.weekday - 1));
  final normalized = DateTime(monday.year, monday.month, monday.day);
  final repository = ref.watch(reportRepositoryProvider);
  return repository.getWeeklyReport(normalized);
});

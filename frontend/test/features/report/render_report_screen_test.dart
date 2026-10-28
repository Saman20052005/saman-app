import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/screens/report_screen.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import 'package:health_ai_app/features/report/data/repositories/report_repository_impl.dart';
import 'package:health_ai_app/features/report/presentation/providers/report_provider.dart';
import 'package:health_ai_app/features/report/presentation/widgets/daily_breakdown_sheet.dart';

class _RenderFakeReportRepository implements ReportRepository {
  final WeeklyReportEntity Function(DateTime date) reportBuilder;

  _RenderFakeReportRepository({required this.reportBuilder});

  @override
  Future<WeeklyReportEntity> getWeeklyReport(DateTime date) async {
    return reportBuilder(date);
  }
}

WeeklyReportEntity _buildSampleData(DateTime monday) {
  final days = List.generate(7, (i) {
    final d = monday.add(Duration(days: i));
    if (i == 1) {
      // Tuesday: unlogged
      return DailyStats(
        date: d,
        caloriesIn: 0,
        caloriesBurned: 0,
        protein: 0,
        isRecorded: false,
        hasWorkout: false,
        isRestDay: false,
        logCount: 0,
      );
    }
    if (i == 4) {
      // Friday: logged rest day (0 kcal burn recorded)
      return DailyStats(
        date: d,
        caloriesIn: 2150,
        caloriesBurned: 0,
        protein: 140,
        isRecorded: true,
        hasWorkout: false,
        isRestDay: true,
        logCount: 3,
      );
    }
    return DailyStats(
      date: d,
      caloriesIn: 2200.0 + (i * 60),
      caloriesBurned: 400.0 + (i * 35),
      protein: 145.0 + (i * 4),
      carbs: 250,
      fat: 65,
      isRecorded: true,
      hasWorkout: i.isEven,
      isRestDay: false,
      workoutTitle: i.isEven ? 'Strength Session' : null,
      workoutDurationMinutes: i.isEven ? 50 : 0,
      logCount: 4,
    );
  });

  return WeeklyReportEntity(
    days: days,
    avgCaloriesIn: 2350,
    targetCalories: 2200,
    avgCaloriesBurned: 460,
    targetBurned: 450,
    avgProtein: 152,
    targetProtein: 150,
    avgCarbs: 260,
    targetCarbs: 250,
    avgFat: 65,
    targetFat: 60,
    daysLogged: 6,
    activeDays: 4,
    totalCaloriesBurned: 2760,
    workoutSessions: [
      WorkoutSessionItem(
        title: 'Upper Body Hypertrophy',
        dayName: 'Mon',
        date: monday,
        durationMinutes: 52,
        caloriesBurned: 420,
        rpe: 8.0,
      ),
      WorkoutSessionItem(
        title: 'Zone 2 Cardio Run',
        dayName: 'Wed',
        date: monday.add(const Duration(days: 2)),
        durationMinutes: 45,
        caloriesBurned: 480,
        rpe: 7.5,
      ),
      WorkoutSessionItem(
        title: 'Lower Body Strength',
        dayName: 'Sat',
        date: monday.add(const Duration(days: 5)),
        durationMinutes: 58,
        caloriesBurned: 510,
        rpe: 8.5,
      ),
    ],
    avgWaterMl: 2400,
    targetWaterMl: 2500,
    takeaway: 'Protein intake was consistent this week, averaging 152g per day across 6 logged days.',
  );
}

WeeklyReportEntity _buildEmptyData(DateTime monday) {
  final days = List.generate(7, (i) {
    return DailyStats(
      date: monday.add(Duration(days: i)),
      caloriesIn: 0,
      caloriesBurned: 0,
      protein: 0,
      isRecorded: false,
      hasWorkout: false,
      isRestDay: false,
      logCount: 0,
    );
  });

  return WeeklyReportEntity(
    days: days,
    avgCaloriesIn: 0,
    targetCalories: 2000,
    avgCaloriesBurned: 0,
    targetBurned: 400,
    avgProtein: 0,
    targetProtein: 140,
    avgCarbs: 0,
    avgFat: 0,
    daysLogged: 0,
    activeDays: 0,
    totalCaloriesBurned: 0,
    workoutSessions: const [],
    avgWaterMl: 0,
    targetWaterMl: 2000,
    takeaway: 'No nutrition or workout data recorded for this week. Log meals and activities to view telemetry.',
  );
}

Future<void> _captureBoundary(WidgetTester tester, GlobalKey key, String fileName) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();

    const destDirs = [
      'd:/SamanDev/runtime_evidence/REPORT_ACTIVE_20261027/ui_evidence',
      'C:/Users/GL/.gemini/antigravity/brain/d27df13b-350c-4a1f-9667-ec208e55b85b/report_screenshots',
    ];

    for (final dirPath in destDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      File('$dirPath/$fileName').writeAsBytesSync(bytes);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testSize = Size(393, 852); // iPhone 15 Pro / standard viewport
  final monday = DateTime(2026, 10, 19);

  testWidgets('Capture Overview, Nutrition, Activity, DailyBreakdown and EmptyState', (tester) async {
    await tester.binding.setSurfaceSize(testSize);
    final repaintKey = GlobalKey();

    final fakeRepo = _RenderFakeReportRepository(
      reportBuilder: (d) => _buildSampleData(monday),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: const ReportScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Capture Overview Tab
    await _captureBoundary(tester, repaintKey, '01_report_overview.png');

    // 2. Switch to Nutrition Tab
    await tester.tap(find.text('Nutrition'));
    await tester.pumpAndSettle();
    await _captureBoundary(tester, repaintKey, '02_report_nutrition.png');

    // 3. Switch to Activity Tab
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await _captureBoundary(tester, repaintKey, '03_report_activity.png');
  });

  testWidgets('Capture Daily Breakdown Sheet', (tester) async {
    await tester.binding.setSurfaceSize(testSize);
    final repaintKey = GlobalKey();

    final sample = _buildSampleData(monday);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0C0D0E),
          body: RepaintBoundary(
            key: repaintKey,
            child: DailyBreakdownSheet(
              days: sample.days,
              targetCalories: sample.targetCalories,
              targetProtein: sample.targetProtein,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _captureBoundary(tester, repaintKey, '04_report_daily_breakdown.png');
  });

  testWidgets('Capture Empty State', (tester) async {
    await tester.binding.setSurfaceSize(testSize);
    final repaintKey = GlobalKey();

    final emptyRepo = _RenderFakeReportRepository(
      reportBuilder: (d) => _buildEmptyData(monday),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportRepositoryProvider.overrideWithValue(emptyRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: const ReportScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _captureBoundary(tester, repaintKey, '05_report_empty_state.png');
  });
}

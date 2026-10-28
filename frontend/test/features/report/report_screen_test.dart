import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/screens/report_screen.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import 'package:health_ai_app/features/report/data/repositories/report_repository_impl.dart';
import 'package:health_ai_app/features/report/presentation/providers/report_provider.dart';

class FakeReportRepository implements ReportRepository {
  final WeeklyReportEntity Function(DateTime date) reportBuilder;

  FakeReportRepository({required this.reportBuilder});

  @override
  Future<WeeklyReportEntity> getWeeklyReport(DateTime date) async {
    return reportBuilder(date);
  }
}

WeeklyReportEntity buildSampleWeeklyReport(DateTime monday) {
  final days = [
    // Mon: 2460 kcal, 148g protein, 520 kcal burned (logged)
    DailyStats(
      date: monday,
      caloriesIn: 2460,
      caloriesBurned: 520,
      protein: 148,
      carbs: 245,
      fat: 64,
      logCount: 3,
      isRecorded: true,
      hasWorkout: true,
      workoutTitle: 'Push & Core',
      workoutDurationMinutes: 45,
    ),
    // Tue: 2580 kcal, 165g protein, 610 kcal burned (logged)
    DailyStats(
      date: monday.add(const Duration(days: 1)),
      caloriesIn: 2580,
      caloriesBurned: 610,
      protein: 165,
      carbs: 260,
      fat: 68,
      logCount: 4,
      isRecorded: true,
      hasWorkout: true,
      workoutTitle: 'Leg Day & Posterior Chain',
      workoutDurationMinutes: 50,
      rpe: 8.5,
    ),
    // Wed: 2390 kcal, 155g protein, Rest day (0 kcal recorded)
    DailyStats(
      date: monday.add(const Duration(days: 2)),
      caloriesIn: 2390,
      caloriesBurned: 0,
      protein: 155,
      carbs: 240,
      fat: 62,
      logCount: 3,
      isRecorded: true,
      isRestDay: true,
      hasWorkout: false,
    ),
    // Thu: 2520 kcal, 162g protein, 480 kcal burned (logged)
    DailyStats(
      date: monday.add(const Duration(days: 3)),
      caloriesIn: 2520,
      caloriesBurned: 480,
      protein: 162,
      carbs: 250,
      fat: 65,
      logCount: 3,
      isRecorded: true,
      hasWorkout: true,
      workoutTitle: 'Upper Strength',
      workoutDurationMinutes: 40,
    ),
    // Fri: 2610 kcal, 140g protein, 550 kcal burned (logged)
    DailyStats(
      date: monday.add(const Duration(days: 4)),
      caloriesIn: 2610,
      caloriesBurned: 550,
      protein: 140,
      carbs: 255,
      fat: 66,
      logCount: 3,
      isRecorded: true,
      hasWorkout: true,
      workoutTitle: 'Conditioning',
      workoutDurationMinutes: 35,
    ),
    // Sat: 1900 kcal, 142g protein, 380 kcal burned (logged)
    DailyStats(
      date: monday.add(const Duration(days: 5)),
      caloriesIn: 1900,
      caloriesBurned: 380,
      protein: 142,
      carbs: 220,
      fat: 58,
      logCount: 2,
      isRecorded: true,
      hasWorkout: true,
      workoutTitle: 'Active Recovery',
      workoutDurationMinutes: 30,
    ),
    // Sun: Unlogged (gap with —)
    DailyStats(
      date: monday.add(const Duration(days: 6)),
      caloriesIn: 0,
      caloriesBurned: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      logCount: 0,
      isRecorded: false,
      hasWorkout: false,
    ),
  ];

  final sessions = [
    WorkoutSessionItem(
      title: 'Leg Day & Posterior Chain',
      dayName: 'Tuesday',
      date: monday.add(const Duration(days: 1)),
      durationMinutes: 50,
      caloriesBurned: 610,
      rpe: 8.5,
    ),
    WorkoutSessionItem(
      title: 'Conditioning',
      dayName: 'Friday',
      date: monday.add(const Duration(days: 4)),
      durationMinutes: 35,
      caloriesBurned: 550,
      rpe: 8.0,
    ),
    WorkoutSessionItem(
      title: 'Push & Core',
      dayName: 'Monday',
      date: monday,
      durationMinutes: 45,
      caloriesBurned: 520,
      rpe: 8.0,
    ),
    WorkoutSessionItem(
      title: 'Upper Strength',
      dayName: 'Thursday',
      date: monday.add(const Duration(days: 3)),
      durationMinutes: 40,
      caloriesBurned: 480,
    ),
    WorkoutSessionItem(
      title: 'Active Recovery',
      dayName: 'Saturday',
      date: monday.add(const Duration(days: 5)),
      durationMinutes: 30,
      caloriesBurned: 380,
    ),
  ];

  return WeeklyReportEntity(
    days: days,
    avgCaloriesIn: 2410,
    avgCaloriesBurned: 508,
    avgProtein: 152,
    avgCarbs: 245,
    avgFat: 64,
    targetCalories: 2500,
    targetProtein: 160,
    targetCarbs: 260,
    targetFat: 70,
    targetBurned: 400,
    daysLogged: 6,
    activeDays: 5,
    totalCaloriesBurned: 2540,
    workoutSessions: sessions,
    avgWaterMl: 2200,
    targetWaterMl: 2500,
    takeaway:
        'Caloric intake stayed within 4% of target while completing 5 training sessions this week.',
  );
}

WeeklyReportEntity buildEmptyWeeklyReport(DateTime monday) {
  return WeeklyReportEntity(
    days: List.generate(7, (i) {
      return DailyStats(
        date: monday.add(Duration(days: i)),
        caloriesIn: 0,
        caloriesBurned: 0,
        protein: 0,
        isRecorded: false,
      );
    }),
    avgCaloriesIn: 0,
    avgCaloriesBurned: 0,
    avgProtein: 0,
    targetCalories: 0,
    targetProtein: 0,
    targetCarbs: 0,
    targetFat: 0,
    targetBurned: 0,
    daysLogged: 0,
    activeDays: 0,
    totalCaloriesBurned: 0,
    workoutSessions: const [],
    avgWaterMl: 0,
    targetWaterMl: 0,
    takeaway:
        'No nutrition or workout logs recorded this week yet. Track daily to view your weekly performance.',
  );
}

void main() {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final weekMonday = DateTime(monday.year, monday.month, monday.day);

  group('ReportScreen UI & Tab Switching Tests', () {
    testWidgets('Renders Overview tab with all sections and headers',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildSampleWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReportScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Your progress, in perspective.'), findsOneWidget);

      // Check Tab Switcher
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);

      // Check Weekly Summary
      expect(find.text('YOUR WEEK, AT A GLANCE'), findsOneWidget);
      expect(find.text('6 / 7 days recorded'), findsOneWidget);
      expect(find.text('152'), findsNWidgets(2)); // Avg protein in Summary & Card
      expect(find.text('g / day'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // Active days

      // Check 3 Chart Cards
      expect(find.text('CALORIES CONSUMED'), findsOneWidget);
      expect(find.text('2,410'), findsOneWidget);
      expect(find.text('PROTEIN INTAKE'), findsOneWidget);
      expect(find.text('CALORIES BURNED'), findsOneWidget);

      // Check Takeaway & Daily breakdown button
      expect(find.textContaining('Weekly takeaway:'), findsOneWidget);
      expect(find.text('View daily breakdown'), findsOneWidget);
    });

    testWidgets('Switches to Nutrition tab and shows macro cards and hydration',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildSampleWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReportScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Nutrition tab
      await tester.tap(find.text('Nutrition'));
      await tester.pumpAndSettle();

      expect(find.text('NUTRITION BREAKDOWN'), findsOneWidget);
      expect(find.text('6 of 7 logged'), findsOneWidget);
      expect(find.text('PROTEIN'), findsOneWidget);
      expect(find.text('CARBS'), findsOneWidget);
      expect(find.text('FATS'), findsOneWidget);
      expect(find.text('AVERAGE WATER HYDRATION'), findsOneWidget);
      expect(find.text('2.2 L'), findsOneWidget);
    });

    testWidgets('Switches to Activity tab and shows sessions and exertion',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildSampleWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReportScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Activity tab
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(find.text('WEEKLY EXERTION'), findsOneWidget);
      expect(find.text('5 active days'), findsOneWidget);
      expect(find.text('TOTAL BURNED'), findsOneWidget);
      expect(find.text('TRAINING SESSIONS'), findsOneWidget);
      expect(find.text('LOGGED SESSIONS THIS WEEK'), findsOneWidget);
      expect(find.text('Leg Day & Posterior Chain'), findsOneWidget);
      expect(find.text('Push & Core'), findsOneWidget);
    });

    testWidgets('Tapping View daily breakdown opens DailyBreakdownSheet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildSampleWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReportScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to bottom and tap View daily breakdown
      await tester.ensureVisible(find.text('View daily breakdown'));
      await tester.tap(find.text('View daily breakdown'));
      await tester.pumpAndSettle();

      // Verify sheet is displayed
      expect(find.text('Daily Breakdown'), findsOneWidget);
      expect(find.text('Day-by-day telemetry and recorded sessions'),
          findsOneWidget);
      expect(find.text('3 logged'), findsWidgets);
    });

    testWidgets('Handles empty report gracefully without crashing',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildEmptyWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReportScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0 / 7 days recorded'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('No target set'), findsWidgets);
      expect(find.text('CALORIES CONSUMED'), findsOneWidget);
    });
  });

  group('Responsiveness & Layout Tests', () {
    testWidgets('Renders at 320x640 (compact) without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildSampleWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReportScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders with 1.3x large text scale without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final fakeRepo = FakeReportRepository(
        reportBuilder: (d) => buildSampleWeeklyReport(weekMonday),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MaterialApp(
              home: ReportScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

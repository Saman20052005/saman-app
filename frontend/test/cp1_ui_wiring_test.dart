import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/profile/presentation/providers/weight_history_provider.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_summary.dart';
import 'package:health_ai_app/screens/profile/widgets/weight_trend_card.dart';
import 'package:health_ai_app/theme/nutrition_home_theme.dart';

void main() {
  group('1. ExerciseSetLog serialization', () {
    test('toJson and fromJson preserve cvFormSummary correctly', () {
      final summary = <String, dynamic>{
        'valid_reps': 8,
        'fast_reps': 2,
        'avg_elbow_angle_deg': 85.5,
        'avg_tempo_sec': 2.3,
        'abort_count': 1,
      };

      final setLog = ExerciseSetLog(
        exerciseId: 'test_exercise_id',
        exerciseSlug: 'lat-pulldown',
        setNumber: 1,
        repsCompleted: 10,
        weightKg: 50.0,
        isCompleted: true,
        cvFormSummary: summary,
      );

      final json = setLog.toJson();
      expect(json['cvFormSummary'], equals(summary));

      final restored = ExerciseSetLog.fromJson(json);
      expect(restored.cvFormSummary, equals(summary));
      expect(restored.cvFormSummary!['valid_reps'], equals(8));
      expect(restored.cvFormSummary!['fast_reps'], equals(2));
      expect(restored.cvFormSummary!['avg_elbow_angle_deg'], equals(85.5));
      expect(restored.cvFormSummary!['avg_tempo_sec'], equals(2.3));
      expect(restored.cvFormSummary!['abort_count'], equals(1));
    });
  });

  group('2. NutritionSummary dynamic target and dayMode', () {
    testWidgets(
        'renders TRAINING DAY and 2,350 kcal when dayMode is training with dynamic target',
        (tester) async {
      final plan = NutritionPlan(
        date: '2026-05-01',
        meals: const [],
        dayMode: 'training',
        dynamicTarget: const DynamicNutritionTarget(
          calories: 2350,
          protein: 165,
          carbs: 260,
          fat: 70,
          calorieDelta: 250,
          baseCalories: 2100,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NutritionHomeTheme(
                child: NutritionSummary(
                  plan: plan,
                  profile: ProfileState.initial(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('TRAINING DAY'), findsOneWidget);
      expect(find.textContaining('2,350 kcal'), findsOneWidget);
    });

    testWidgets('renders REST DAY when dayMode is rest', (tester) async {
      final plan = NutritionPlan(
        date: '2026-05-01',
        meals: const [],
        dayMode: 'rest',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NutritionHomeTheme(
                child: NutritionSummary(
                  plan: plan,
                  profile: ProfileState.initial(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('REST DAY'), findsOneWidget);
    });
  });

  group('3. WeightTrendCard telemetry', () {
    testWidgets('empty entries render without crash and display no data message',
        (tester) async {
      const emptyData = WeightHistoryData(
        days: 30,
        entries: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weightHistoryProvider.overrideWith((ref) async => emptyData),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WeightTrendCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Chưa có lịch sử cân nặng'),
        findsOneWidget,
      );
    });

    testWidgets('single entry renders LineChart without minY == maxY crash',
        (tester) async {
      const singleEntryData = WeightHistoryData(
        days: 30,
        latestWeightKg: 70.0,
        entries: [
          WeightHistoryEntry(
            date: '2026-05-01',
            weightKg: 70.0,
            source: 'manual_log',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weightHistoryProvider.overrideWith((ref) async => singleEntryData),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WeightTrendCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('multiple entries render 70.0 kg and + Log button',
        (tester) async {
      const multiData = WeightHistoryData(
        days: 30,
        latestWeightKg: 70.0,
        deltaKg: 0.5,
        entries: [
          WeightHistoryEntry(
            date: '2026-04-20',
            weightKg: 69.5,
            source: 'manual_log',
          ),
          WeightHistoryEntry(
            date: '2026-05-01',
            weightKg: 70.0,
            source: 'manual_log',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weightHistoryProvider.overrideWith((ref) async => multiData),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WeightTrendCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('70.0'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('Log'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);
    });
  });
}

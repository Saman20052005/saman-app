import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/presentation/widgets/nutrition_home_components.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';
import 'package:health_ai_app/screens/nutrition/weekly_report_screen.dart';
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_logged_meal_card.dart';
import 'package:health_ai_app/theme/nutrition_home_theme.dart';

import 'nutrition_home_ui_test.dart' as existing;

class IntegrationNutritionNotifier extends existing.TestNutritionNotifier {
  IntegrationNutritionNotifier(NutritionPlan plan)
      : super(AsyncValue.data(plan));
  void display(NutritionPlan plan) => state = AsyncValue.data(plan);
}

/// Only dependencies are controlled; the screen, callbacks and navigation are
/// production code. This harness is never imported into lib/.
Widget integratedNutritionTestApp(IntegrationNutritionNotifier notifier,
        {double scale = 1}) =>
    ProviderScope(
      overrides: [
        profileProvider.overrideWith((ref) => existing.TestProfileNotifier()),
        nutritionProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
          body: const NutritionScreen(),
          bottomNavigationBar:
              SamanBottomNavigationBar(currentIndex: 3, onTap: (_) {}),
        ),
      ),
    );

NutritionPlan emptyIntegratedPlan() => existing.createSamplePlan().copyWith(
      entries: [],
      meals: [],
      totalCaloriesConsumed: 0,
      totalProteinConsumed: 0,
      totalCarbsConsumed: 0,
      totalFatConsumed: 0,
    );

void main() {
  testWidgets(
      'integrated screen reloads selected date and refreshes after successful log return',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = IntegrationNutritionNotifier(existing.createSamplePlan());
    await tester.pumpWidget(integratedNutritionTestApp(notifier));
    await tester.pump();
    final today = notifier.loadedDates.single;
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pump();
    final selected = notifier.loadedDates.last;
    expect(selected.day, today.subtract(const Duration(days: 1)).day);
    expect(find.text('TODAY'), findsNothing);
    final loads = notifier.loadDailyPlanCalls;
    await tester.tap(find.text('Log meal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final log = tester.widget<FoodLogScreen>(find.byType(FoodLogScreen));
    expect(log.selectedDate, selected);
    Navigator.of(tester.element(find.byType(FoodLogScreen))).pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(notifier.loadDailyPlanCalls, loads + 1);
    expect(notifier.loadedDates.last, selected);
    await tester.tap(find.text('Scan food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<LogMealSheet>(find.byType(LogMealSheet)).selectedDate,
        selected);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'server/provider updates replace intake and meal rows, with read-only entry details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = IntegrationNutritionNotifier(existing.createSamplePlan());
    await tester.pumpWidget(integratedNutritionTestApp(notifier));
    await tester.pump();
    expect(find.text('1,420'), findsOneWidget);
    await tester.tap(find.byType(NutritionLoggedMealCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final details = tester.widget<NutritionLoggedMealDetails>(
        find.byType(NutritionLoggedMealDetails));
    expect(details.entry.logId, 'log-1');
    await tester.tap(find.byTooltip('Close meal details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    notifier.display(emptyIntegratedPlan());
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(find.byType(NutritionLoggedMealCard), findsNothing);
    expect(find.text('Chưa có bữa ăn nào được ghi hôm nay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [true, false]) {
    testWidgets(
        '320 px and 200% text keeps the entire ${empty ? 'empty' : 'populated'} screen scrollable',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      final notifier = IntegrationNutritionNotifier(
          empty ? emptyIntegratedPlan() : existing.createSamplePlan());
      await tester.pumpWidget(integratedNutritionTestApp(notifier, scale: 2));
      await tester.pump();
      expect(
          MediaQuery.textScalerOf(
                  tester.element(find.byType(NutritionFoodHero)))
              .scale(14),
          28);
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(SamanBottomNavigationBar), findsOneWidget);
    });
  }

  testWidgets('Report remains the existing production report route',
      (tester) async {
    final notifier = IntegrationNutritionNotifier(existing.createSamplePlan());
    await tester.pumpWidget(integratedNutritionTestApp(notifier));
    await tester.pump();
    await tester.tap(find.text('Report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(WeeklyReportScreen), findsOneWidget);
  });

  testWidgets(
      'hero image failure retains readable title and working report callback',
      (tester) async {
    var reports = 0;
    await tester.pumpWidget(MaterialApp(
        home: NutritionHomeTheme(
            child: Scaffold(
                body: NutritionFoodHero(
      asset: 'missing-integration-hero.png',
      onReport: () => reports++,
      membershipBadge: const Text('PLUS'),
    )))));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Nutrition'), findsOneWidget);
    await tester.tap(find.text('Report'));
    expect(reports, 1);
    expect(tester.takeException(), isNull);
  });
}

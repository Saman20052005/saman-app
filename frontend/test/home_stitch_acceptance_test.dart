import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/screens/home/tokens/saman_home_tokens.dart';
import 'package:health_ai_app/screens/home/widgets/widgets.dart';

class _FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier({this.plan})
      : super(
          AsyncValue.data(
            plan ??
                NutritionPlan(
                  date: '2026-11-06',
                  meals: [],
                  currentWater: 0,
                  targetWater: 2400,
                  totalCaloriesConsumed: 0,
                  totalProteinConsumed: 0,
                  totalCarbsConsumed: 0,
                  totalFatConsumed: 0,
                ),
          ),
        );

  final NutritionPlan? plan;

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 3129,
        protein: 136,
        carbs: 451,
        fat: 87,
      );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  Future<void> updateWater(int amountMl, {required String date}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Saman Lifter',
      'user_email': 'saman@example.com',
    });
  });

  testWidgets('Verifies Saman Home Stitch Editorial design tokens & zero-state indicators', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sharedPrefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(
              calories: 3129,
              protein: 136,
              carbs: 451,
              fat: 87,
            ),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Verify Header and Greeting
    expect(find.text('Hello, Saman Lifter'), findsOneWidget);
    expect(find.byType(HomeHeader), findsOneWidget);

    // 2. Verify Ask Saman Bar & Amber lightning bolt
    expect(find.byType(SamanCompanionBar), findsOneWidget);
    final boltFinder = find.byIcon(Icons.bolt_rounded);
    expect(boltFinder, findsOneWidget);
    final boltIcon = tester.widget<Icon>(boltFinder);
    expect(boltIcon.color, equals(SamanHomeTokens.carbsAmber));

    // 3. Verify Workout Hero: Start Workout CTA button uses mint #54DFAC and dark text #092018
    expect(find.byType(WorkoutRecommendationCarousel), findsOneWidget);
    final startWorkoutBtnFinder = find.widgetWithText(ElevatedButton, 'Start Workout →');
    expect(startWorkoutBtnFinder, findsOneWidget);
    final startWorkoutBtn = tester.widget<ElevatedButton>(startWorkoutBtnFinder);
    final btnStyle = startWorkoutBtn.style!;
    expect(btnStyle.backgroundColor?.resolve({}), equals(SamanHomeTokens.mintAccent));
    expect(btnStyle.foregroundColor?.resolve({}), equals(SamanHomeTokens.mintCtaText));

    // Verify Exercise Chips
    expect(find.text('Squat (4×8)'), findsOneWidget);
    expect(find.text('RDL (3×10)'), findsOneWidget);
    expect(find.text('Bulgarian Split'), findsOneWidget);

    // 4. Verify Daily Targets zero state
    expect(find.byType(DailyTargetsCard), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('PROTEIN'), findsOneWidget);
    expect(find.text('CARBS'), findsOneWidget);
    expect(find.text('FAT'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);

    // 5. Verify Quick Action Dock
    expect(find.byType(QuickActionDock), findsOneWidget);
    expect(find.text('Log meal'), findsOneWidget);
    expect(find.text('Add water'), findsOneWidget);

    // 6. Verify Weekly Consistency Card
    expect(find.byType(WeeklyConsistencyCard), findsOneWidget);
    expect(find.text('WEEKLY CONSISTENCY'), findsOneWidget);

    // 7. Scroll and verify Saman Picks
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SamanPicksCarousel), findsOneWidget);
    expect(find.text('SAMAN JOURNAL'), findsOneWidget);
    expect(find.text('Recover better after Leg Day'), findsOneWidget);
    expect(find.text('SAMAN SHOP'), findsOneWidget);
  });
}

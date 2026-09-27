import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/screens/home/widgets/widgets.dart';

class FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  FakeNutritionNotifier({NutritionPlan? initialPlan})
      : super(
          AsyncValue.data(
            initialPlan ??
                NutritionPlan(
                  date: '2026-09-21',
                  meals: [],
                  currentWater: 1250,
                  targetWater: 2500,
                  totalCaloriesConsumed: 1850,
                  totalProteinConsumed: 140,
                  totalCarbsConsumed: 210,
                  totalFatConsumed: 55,
                ),
          ),
        );

  final List<String> capturedAddWaterKeys = [];
  final List<String> capturedAddWaterDates = [];
  String? _lastFailedKey;
  bool timeoutOnNextAddWater = false;

  @override
  String? get lastFailedWaterKey => _lastFailedKey;

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2400,
        protein: 180,
        carbs: 260,
        fat: 70,
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
  Future<String> addWater(int deltaMl, {required String date, String? idempotencyKey}) async {
    final key = idempotencyKey ??
        'water_mock_${DateTime.now().microsecondsSinceEpoch}_${capturedAddWaterKeys.length}';
    capturedAddWaterKeys.add(key);
    capturedAddWaterDates.add(date);

    if (timeoutOnNextAddWater) {
      timeoutOnNextAddWater = false;
      _lastFailedKey = key;
      throw TimeoutException('Request timed out');
    }

    final cur = state.valueOrNull?.currentWater ?? 1250;
    state = AsyncValue.data(state.valueOrNull?.copyWith(currentWater: cur + deltaMl));
    return key;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('HomeScreen renders all 7 modular sections with wired data', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Morgan',
      'user_email': 'alex@example.com',
    });
    final sharedPrefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          nutritionProvider.overrideWith((ref) => FakeNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(
              calories: 2400,
              protein: 180,
              carbs: 260,
              fat: 70,
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

    // Verify all 7 section widgets are present in the widget tree
    expect(find.byType(HomeHeader), findsOneWidget);
    expect(find.byType(SamanCompanionBar), findsOneWidget);
    expect(find.byType(WorkoutRecommendationCarousel), findsOneWidget);
    expect(find.byType(DailyTargetsCard), findsOneWidget);
    expect(find.byType(QuickActionDock), findsOneWidget);
    expect(find.byType(WeeklyConsistencyCard), findsOneWidget);

    // Scroll down to build and reveal SamanPicksCarousel
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SamanPicksCarousel), findsOneWidget);
  });

  testWidgets('HomeScreen water timeout retry reuses key while new tap generates fresh key', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Morgan',
      'user_email': 'alex@example.com',
    });
    final sharedPrefs = await SharedPreferences.getInstance();

    final fakeNotifier = FakeNutritionNotifier();
    fakeNotifier.timeoutOnNextAddWater = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          nutritionProvider.overrideWith((ref) => fakeNotifier),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(
              calories: 2400,
              protein: 180,
              carbs: 260,
              fat: 70,
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

    // 1. User taps "Add water" button on QuickActionDock
    final addWaterBtn = find.text('Add water');
    expect(addWaterBtn, findsOneWidget);
    await tester.tap(addWaterBtn);
    await tester.pumpAndSettle();

    // The first call timed out -> SnackBar shows Retry action
    expect(fakeNotifier.capturedAddWaterKeys.length, 1);
    final firstKey = fakeNotifier.capturedAddWaterKeys.first;
    expect(find.text('Failed to update water. Please try again.'), findsOneWidget);
    final retryBtn = find.text('Retry');
    expect(retryBtn, findsOneWidget);

    // 2. User taps "Retry" on SnackBar -> reuses CÙNG key and original date
    await tester.tap(retryBtn);
    await tester.pumpAndSettle();

    expect(fakeNotifier.capturedAddWaterKeys.length, 2);
    expect(fakeNotifier.capturedAddWaterKeys[1], equals(firstKey));
    expect(fakeNotifier.capturedAddWaterDates.length, 2);
    expect(fakeNotifier.capturedAddWaterDates[1], equals(fakeNotifier.capturedAddWaterDates[0]));
    expect(find.text('Retry'), findsNothing);

    // 3. User taps "Add water" button again -> MỘT lần bấm mới dùng key mới
    await tester.tap(addWaterBtn);
    await tester.pumpAndSettle();

    expect(fakeNotifier.capturedAddWaterKeys.length, 3);
    final newKey = fakeNotifier.capturedAddWaterKeys[2];
    expect(newKey, isNot(equals(firstKey)));
  });
}

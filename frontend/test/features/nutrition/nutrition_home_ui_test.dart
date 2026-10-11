import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import 'package:health_ai_app/screens/nutrition/meal_story_screen.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';
import 'package:health_ai_app/screens/nutrition/widgets/date_selector.dart';
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_summary.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_water_card.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_logged_meal_card.dart';
import 'package:health_ai_app/screens/nutrition/widgets/planned_meal_card.dart';

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestProfileNotifier extends ProfileNotifier {
  TestProfileNotifier({bool isValid = true, int targetCalories = 2300, int waterTargetMl = 2000})
      : super(_MockProfileRepository()) {
    if (isValid) {
      state = ProfileState(
        profile: const ProfileEntity(
          age: 28,
          gender: Gender.male,
          height: 178,
          weight: 75,
          activityLevel: ActivityLevel.medium,
          goal: Goal.gain_muscle,
        ),
        targetCalories: targetCalories,
        targetProtein: targetCalories > 0 ? 160 : 0,
        targetCarbs: targetCalories > 0 ? 240 : 0,
        targetFat: targetCalories > 0 ? 65 : 0,
        waterTargetMl: waterTargetMl,
        isLoading: false,
      );
    } else {
      state = ProfileState(profile: ProfileEntity.empty(), isLoading: false);
    }
  }
}

class TestNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  TestNutritionNotifier(AsyncValue<NutritionPlan?> initial) : super(initial);

  int addMealCalls = 0;
  List<Map<String, dynamic>> recordedAddMealArgs = [];
  Completer<bool>? addMealCompleter;
  bool addMealResult = true;

  int updateWaterCalls = 0;
  List<Map<String, dynamic>> recordedUpdateWaterArgs = [];
  Completer<void>? updateWaterCompleter;

  int loadDailyPlanCalls = 0;
  List<DateTime> loadedDates = [];

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2300,
        protein: 160,
        carbs: 240,
        fat: 65,
      );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {
    loadDailyPlanCalls++;
    loadedDates.add(date);
  }

  @override
  bool get isMealPlanGenerating => false;

  @override
  Future<void> updateWater(int amountMl, {required String date}) async {
    updateWaterCalls++;
    recordedUpdateWaterArgs.add({'amountMl': amountMl, 'date': date});
    if (updateWaterCompleter != null) {
      await updateWaterCompleter!.future;
    }
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(currentWater: amountMl));
    }
  }

  @override
  Future<bool> addMeal({
    required DateTime date,
    required String mealType,
    required String foodId,
    required String name,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required int weightGrams,
  }) async {
    addMealCalls++;
    recordedAddMealArgs.add({
      'date': date,
      'mealType': mealType,
      'foodId': foodId,
      'name': name,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'weightGrams': weightGrams,
    });
    if (addMealCompleter != null) {
      return addMealCompleter!.future;
    }
    return addMealResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NutritionPlan createSamplePlan() {
  return NutritionPlan(
    date: '2026-10-08',
    totalCaloriesConsumed: 1420,
    totalProteinConsumed: 118,
    totalCarbsConsumed: 142,
    totalFatConsumed: 42,
    currentWater: 750,
    targetWater: 2000,
    entries: [
      NutritionLogEntry(
        logId: 'log-1',
        foodName: 'Rolled Oats with Greek Yogurt & Berries',
        mealType: 'Breakfast',
        totalCalories: 480,
        protein: 32,
        carbs: 58,
        fat: 12,
      ),
      NutritionLogEntry(
        logId: 'log-2',
        foodName: 'Grilled Chicken Breast & Jasmine Rice',
        mealType: 'Lunch',
        totalCalories: 640,
        protein: 56,
        carbs: 54,
        fat: 18,
      ),
    ],
    meals: [
      Meal(
        foodId: 'plan-1',
        name: 'Salmon Fillet & Sweet Potato',
        calories: 520,
        protein: 44,
        carbs: 48,
        fat: 16,
        weightGrams: 250,
        mealType: 'Dinner',
        time: '19:30',
      ),
    ],
  );
}

Widget createTestWidget({
  AsyncValue<NutritionPlan?>? planState,
  TestNutritionNotifier? customNutritionNotifier,
  bool profileValid = true,
  int targetCalories = 2300,
  int waterTargetMl = 2000,
}) {
  final plan = planState ?? AsyncValue.data(createSamplePlan());
  final notifier = customNutritionNotifier ?? TestNutritionNotifier(plan);

  return ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => TestProfileNotifier(
            isValid: profileValid,
            targetCalories: targetCalories,
            waterTargetMl: waterTargetMl,
          )),
      nutritionProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: const NutritionScreen(),
    ),
  );
}

void main() {
  group('NutritionScreen Calm Athleticism UI & Behavioral Tests', () {
    testWidgets('Renders complete Nutrition Home layout matching design spec', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 1. Header elements
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('Fuel, log & track your day'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);

      // 2. DateSelector component
      expect(find.byType(DateSelector), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);

      // 3. Today's Intake (NutritionSummary)
      expect(find.byType(NutritionSummary), findsOneWidget);
      expect(find.text("TODAY'S INTAKE"), findsOneWidget);
      expect(find.text('LOGGED INTAKE'), findsOneWidget);
      expect(find.text('1,420'), findsOneWidget);
      expect(find.text('/ 2,300 kcal'), findsOneWidget);
      expect(find.text('880 kcal remaining'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('Carbs'), findsOneWidget);
      expect(find.text('Fat'), findsOneWidget);

      // 4. Fast Actions
      expect(find.text('Log meal'), findsOneWidget);
      expect(find.text('Scan food'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);

      // 5. Logged Meals Section
      expect(find.text('LOGGED MEALS'), findsOneWidget);
      expect(find.text('Meal Story'), findsOneWidget);
      expect(find.byType(NutritionLoggedMealCard), findsNWidgets(2));
      expect(find.text('Rolled Oats with Greek Yogurt & Berries'), findsOneWidget);
      expect(find.text('Grilled Chicken Breast & Jasmine Rice'), findsOneWidget);

      // 6. Water Card
      expect(find.byType(NutritionWaterCard), findsOneWidget);
      expect(find.text('WATER'), findsOneWidget);
      expect(find.text('750'), findsOneWidget);
      expect(find.text('/ 2,000 ml'), findsOneWidget);
      expect(find.text('250 ml'), findsOneWidget);

      // 7. Planned Meal Card
      expect(find.byType(PlannedMealCard), findsOneWidget);
      expect(find.text('MEAL PLAN'), findsOneWidget);
      expect(find.text('PLANNED'), findsOneWidget);
      expect(find.text('Review & log'), findsOneWidget);

      // 8. No second bottom navigation bar inside NutritionScreen
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('Renders empty logged meals state when no entries exist', (tester) async {
      final emptyPlan = createSamplePlan().copyWith(entries: [], totalCaloriesConsumed: 0, totalProteinConsumed: 0, totalCarbsConsumed: 0, totalFatConsumed: 0);

      await tester.pumpWidget(createTestWidget(planState: AsyncValue.data(emptyPlan)));
      await tester.pumpAndSettle();

      expect(find.text('Chưa có bữa ăn nào được ghi hôm nay'), findsOneWidget);
      expect(find.byType(NutritionLoggedMealCard), findsNothing);
    });

    testWidgets('Renders loading skeleton view during loading state', (tester) async {
      await tester.pumpWidget(createTestWidget(planState: const AsyncValue.loading()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text("TODAY'S INTAKE"), findsNothing);
    });

    testWidgets('Renders error view with retry action on error state', (tester) async {
      await tester.pumpWidget(createTestWidget(
        planState: AsyncValue.error('Network unreachable', StackTrace.empty),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải dữ liệu dinh dưỡng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
    });

    testWidgets('Renders profile incomplete view when profile is invalid', (tester) async {
      await tester.pumpWidget(createTestWidget(profileValid: false));
      await tester.pumpAndSettle();

      expect(find.text('Thiếu thông tin Profile'), findsOneWidget);
      expect(find.text('Cập nhật ngay'), findsOneWidget);
    });

    testWidgets('Adapts gracefully to accessibility text scale factor without overflow', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text("TODAY'S INTAKE"), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // BEHAVIORAL VERIFICATIONS
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('Behavioral: Opening Review & log does NOT trigger meal write (addMeal)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = TestNutritionNotifier(AsyncValue.data(createSamplePlan()));
      await tester.pumpWidget(createTestWidget(customNutritionNotifier: notifier));
      await tester.pumpAndSettle();

      // Tap Review & log button
      await tester.tap(find.text('Review & log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal sheet opens with details
      expect(find.text('Gợi ý bữa ăn'), findsOneWidget);
      expect(find.text('Salmon Fillet & Sweet Potato'), findsOneWidget);
      expect(find.text('Xác nhận & Ghi nhật ký'), findsOneWidget);

      // Verify ZERO write calls occurred merely from opening review
      expect(notifier.addMealCalls, 0);
    });

    testWidgets('Behavioral: Double tap Confirm only invokes addMeal once during in-flight debounce', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controlledCompleter = Completer<bool>();
      final notifier = TestNutritionNotifier(AsyncValue.data(createSamplePlan()));
      notifier.addMealCompleter = controlledCompleter;

      await tester.pumpWidget(createTestWidget(customNutritionNotifier: notifier));
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Review & log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // First tap Confirm
      await tester.tap(find.text('Xác nhận & Ghi nhật ký'));
      await tester.pump(); // Advance microtasks, button enters isSaving = true

      expect(notifier.addMealCalls, 1);

      // Second tap while still in flight
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();

      // Must remain exactly 1 call (in-flight suppressed)
      expect(notifier.addMealCalls, 1);

      // Complete async write
      controlledCompleter.complete(true);
      await tester.pumpAndSettle();

      // Sheet closes upon success
      expect(find.text('Gợi ý bữa ăn'), findsNothing);
      expect(notifier.addMealCalls, 1);
    });

    testWidgets('Behavioral: Save failure preserves bottom sheet and selected meal data with error message', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = TestNutritionNotifier(AsyncValue.data(createSamplePlan()));
      notifier.addMealResult = false; // Simulate backend write failure

      await tester.pumpWidget(createTestWidget(customNutritionNotifier: notifier));
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Review & log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Confirm
      await tester.tap(find.text('Xác nhận & Ghi nhật ký'));
      await tester.pumpAndSettle();

      // Sheet is still visible, data is preserved, error is shown
      expect(find.text('Gợi ý bữa ăn'), findsOneWidget);
      expect(find.text('Salmon Fillet & Sweet Potato'), findsOneWidget);
      expect(find.text('Không thể ghi nhận bữa ăn. Vui lòng thử lại.'), findsOneWidget);
    });

    testWidgets('Behavioral: Pending water update prevents duplicate tap and blocks date selector change', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final waterCompleter = Completer<void>();
      final notifier = TestNutritionNotifier(AsyncValue.data(createSamplePlan()));
      notifier.updateWaterCompleter = waterCompleter;

      await tester.pumpWidget(createTestWidget(customNutritionNotifier: notifier));
      await tester.pumpAndSettle();

      final initialLoadCalls = notifier.loadDailyPlanCalls;
      expect(initialLoadCalls, 1);

      // First water tap
      await tester.tap(find.text('250 ml'));
      await tester.pump(); // Sets _isWaterUpdating = true

      expect(notifier.updateWaterCalls, 1);

      // Duplicate tap on water button while updating
      await tester.tap(find.byType(NutritionWaterCard), warnIfMissed: false);
      await tester.pump();
      expect(notifier.updateWaterCalls, 1); // Still 1

      // Tap date navigation (chevron left) while water update is in flight
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();

      // Date load must NOT have been triggered while water update is pending
      expect(notifier.loadDailyPlanCalls, equals(initialLoadCalls));

      // Complete water write
      waterCompleter.complete();
      await tester.pumpAndSettle();

      // Lock is released
      expect(notifier.updateWaterCalls, 1);
      expect(find.text('1,000'), findsOneWidget); // 750 + 250 = 1000 ml
    });

    testWidgets('Behavioral: CTA actions (Log meal, Scan food, Meal Story) receive current selectedDate', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = TestNutritionNotifier(AsyncValue.data(createSamplePlan()));
      await tester.pumpWidget(createTestWidget(customNutritionNotifier: notifier));
      await tester.pumpAndSettle();

      // 1. Test Meal Story receives selectedDate
      await tester.tap(find.text('Meal Story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MealStoryScreen), findsOneWidget);
      final storyWidget = tester.widget<MealStoryScreen>(find.byType(MealStoryScreen));
      expect(storyWidget.date.year, equals(DateTime.now().year));

      // Pop back using Navigator directly to avoid indicator timeout
      Navigator.of(tester.element(find.byType(MealStoryScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 2. Test Scan food receives selectedDate
      await tester.tap(find.text('Scan food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(LogMealSheet), findsOneWidget);
      final scanSheet = tester.widget<LogMealSheet>(find.byType(LogMealSheet));
      expect(scanSheet.selectedDate.year, equals(DateTime.now().year));

      // Dismiss sheet
      Navigator.of(tester.element(find.byType(LogMealSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 3. Test Log meal receives selectedDate
      await tester.tap(find.text('Log meal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FoodLogScreen), findsOneWidget);
      final logScreen = tester.widget<FoodLogScreen>(find.byType(FoodLogScreen));
      expect(logScreen.selectedDate?.year, equals(DateTime.now().year));
    });

    testWidgets('Behavioral: Missing target displays — without fake fallback', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(
        targetCalories: 0,
        waterTargetMl: 0,
      ));
      await tester.pumpAndSettle();

      // Verify real consumed is preserved, target is —
      expect(find.text('1,420'), findsOneWidget);
      expect(find.text('/ — kcal'), findsOneWidget);
      expect(find.text('Set profile goal'), findsOneWidget);
      expect(find.text('No target configured'), findsOneWidget);
      expect(find.text('CONSUMED'), findsOneWidget);
      expect(find.textContaining('(chuẩn)'), findsNothing);
      expect(find.textContaining('BENCHMARK TARGET'), findsNothing);

      // Macro targets display / — and No target
      expect(find.text('/ —'), findsNWidgets(3));
      expect(find.text('No target'), findsNWidgets(3));

      // Water target is — ml, no 2000 fallback, Set hydration target shown
      expect(find.text('/ — ml'), findsOneWidget);
      expect(find.text('Set hydration target'), findsOneWidget);
      expect(find.text('Hydration goal not set'), findsOneWidget);
    });

    testWidgets('Behavioral: Displays Data needs refreshing and preserves intake when aggregate is positive but entries are empty', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = TestNutritionNotifier(AsyncValue.data(
        createSamplePlan().copyWith(
          totalCaloriesConsumed: 1879,
          totalProteinConsumed: 0,
          totalCarbsConsumed: 0,
          totalFatConsumed: 0,
          entries: [],
        ),
      ));

      await tester.pumpWidget(createTestWidget(customNutritionNotifier: notifier));
      await tester.pumpAndSettle();

      // 1. Preserves existing aggregate intake
      expect(find.text('1,879'), findsOneWidget);
      expect(find.text('/ 2,300 kcal'), findsOneWidget);

      // 2. Does NOT call it a normal unlogged day
      expect(find.text('Chưa có bữa ăn nào được ghi hôm nay'), findsNothing);

      // 3. Displays Data needs refreshing and Refresh CTA
      expect(find.text('Data needs refreshing'), findsOneWidget);
      expect(find.text('Logged entries do not match total consumed intake'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      // 4. Tap Refresh triggers data reload
      final initialLoads = notifier.loadDailyPlanCalls;
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(notifier.loadDailyPlanCalls, greaterThan(initialLoads));
    });

    testWidgets('Behavioral: Consumed exceeding target renders cleanly with warning metrics', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final overPlan = createSamplePlan().copyWith(
        totalCaloriesConsumed: 2800,
        totalProteinConsumed: 180,
      );

      await tester.pumpWidget(createTestWidget(
        planState: AsyncValue.data(overPlan),
        targetCalories: 2300,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('2,800'), findsOneWidget);
      expect(find.text('/ 2,300 kcal'), findsOneWidget);
      expect(find.text('500 kcal over'), findsOneWidget);
      expect(find.text('121.7% of goal'), findsOneWidget);
      expect(find.text('20g over'), findsOneWidget);
    });
  });
}

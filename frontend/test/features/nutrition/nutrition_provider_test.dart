// test/features/nutrition/nutrition_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/load_daily_plan_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/update_water_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_logged_meal_usecase.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';

class MockNutritionRepository extends Mock implements INutritionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(Meal(
      foodId: '0',
      name: '',
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      weightGrams: 0,
      mealType: '',
      time: '',
    ));
  });

  late MockNutritionRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockNutritionRepository();
    container = ProviderContainer(
      overrides: [
        nutritionProvider.overrideWith((ref) => NutritionNotifier(
              repository: mockRepository,
              loadDailyPlanUseCase: LoadDailyPlanUseCase(mockRepository),
              updateWaterUseCase: UpdateWaterUseCase(mockRepository),
              swapMealUseCase: SwapMealUseCase(mockRepository),
              swapLoggedMealUseCase: SwapLoggedMealUseCase(mockRepository),
            )),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('NutritionNotifier Tests', () {
    test('loadDailyPlan fetches data successfully and updates state', () async {
      final date = DateTime(2023, 10, 27);
      final dateStr = '2023-10-27';
      final mockPlan = NutritionPlan(
        date: dateStr,
        meals: [
          Meal(
            foodId: '1',
            name: 'Test Meal',
            calories: 100,
            protein: 10,
            carbs: 10,
            fat: 10,
            weightGrams: 100,
            mealType: 'lunch',
            time: '12:00',
          )
        ],
        currentWater: 500,
        targetWater: 2000,
      );

      when(() => mockRepository.getDailyPlan(any()))
          .thenAnswer((_) async => mockPlan);
      when(() => mockRepository.generatePlan(
            dateStr: any(named: 'dateStr'),
            goal: any(named: 'goal'),
            targetCalories: any(named: 'targetCalories'),
            remainingOnly: any(named: 'remainingOnly'), // Added remainingOnly
          )).thenAnswer((_) async => mockPlan);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(date);

      expect(container.read(nutritionProvider).value?.currentWater, 500);
      verify(() => mockRepository.getDailyPlan(dateStr)).called(1);
    });

    test('updateWater performs optimistic update and rolls back on failure',
        () async {
      final initialPlan = NutritionPlan(
        date: '2023-10-27',
        meals: [
          Meal(
              foodId: '1',
              name: 'Meal',
              calories: 100,
              protein: 10,
              carbs: 10,
              fat: 10,
              weightGrams: 100,
              mealType: 'lunch',
              time: '12:00')
        ],
        currentWater: 500,
      );

      final notifier = container.read(nutritionProvider.notifier);

      // Stub to return a non-empty plan to avoid auto-gen in updateWater setup
      when(() => mockRepository.getDailyPlan(any()))
          .thenAnswer((_) async => initialPlan);
      await notifier.loadDailyPlan(DateTime(2023, 10, 27));

      // Mock failure for update
      when(() => mockRepository.updateWater(any(), any()))
          .thenThrow(Exception('API Error'));

      // Trigger update
      final future = notifier.updateWater(1000, date: '2023-10-27');

      // Check optimistic update - it should be immediate
      expect(container.read(nutritionProvider).value?.currentWater, 1000);

      try {
        await future;
      } catch (_) {}

      // Check rollback
      expect(container.read(nutritionProvider).value?.currentWater, 500);
    });

    test('swapMeal updates plan successfully', () async {
      final oldMeal = Meal(
        foodId: '1',
        name: 'Old Meal',
        calories: 100,
        protein: 10,
        carbs: 10,
        fat: 10,
        weightGrams: 100,
        mealType: 'lunch',
        time: '12:00',
      );
      final newPlan = NutritionPlan(
        date: '2023-10-27',
        meals: [
          Meal(
            foodId: '2',
            name: 'New Meal',
            calories: 150,
            protein: 15,
            carbs: 15,
            fat: 15,
            weightGrams: 150,
            mealType: 'lunch',
            time: '12:00',
          )
        ],
      );

      when(() => mockRepository.swapMeal(any(), any(), any()))
          .thenAnswer((_) async => newPlan);

      final notifier = container.read(nutritionProvider.notifier);

      // Load initial plan first
      final initialPlan = NutritionPlan(date: '2023-10-27', meals: [oldMeal]);
      when(() => mockRepository.getDailyPlan(any()))
          .thenAnswer((_) async => initialPlan);
      await notifier.loadDailyPlan(DateTime(2023, 10, 27));

      await notifier.swapMeal(oldMeal, 'muscle_gain');

      expect(container.read(nutritionProvider).value?.meals.first.name,
          'New Meal');
      verify(() =>
              mockRepository.swapMeal('2023-10-27', oldMeal, 'muscle_gain'))
          .called(1);
    });

    test(
        'generateSmartPlan preserves existing intake and water if secondary getDailyPlan fails',
        () async {
      final date = DateTime(2023, 10, 27);
      const dateStr = '2023-10-27';

      final existingEntry = NutritionLogEntry(
        logId: 'log-101',
        foodName: 'Chicken Salad',
        mealType: 'lunch',
        totalCalories: 450,
        protein: 35,
        carbs: 10,
        fat: 12,
      );

      final initialPlan = NutritionPlan(
        date: dateStr,
        meals: [],
        entries: [existingEntry],
        currentWater: 800,
        targetWater: 2200,
        totalCaloriesConsumed: 450,
        totalProteinConsumed: 35,
        totalCarbsConsumed: 10,
        totalFatConsumed: 12,
      );

      final generatedPlanWithIntake = initialPlan.copyWith(
        meals: [
          Meal(
            foodId: 'm1',
            name: 'Salmon Bowl',
            calories: 600,
            protein: 40,
            carbs: 50,
            fat: 20,
            weightGrams: 300,
            mealType: 'dinner',
            time: '19:00',
          ),
        ],
      );

      when(() => mockRepository.generatePlan(
            dateStr: any(named: 'dateStr'),
            goal: any(named: 'goal'),
            mealCount: any(named: 'mealCount'),
            style: any(named: 'style'),
            remainingOnly: any(named: 'remainingOnly'),
          )).thenAnswer((_) async => generatedPlanWithIntake);

      when(() => mockRepository.getDailyPlan(dateStr))
          .thenThrow(Exception('Secondary Daily Plan Fetch Failed'));

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.generateSmartPlan(
        mealCount: 3,
        style: 'optimal',
        remainingOnly: true,
        date: date,
      );

      final state = container.read(nutritionProvider).value;
      expect(state, isNotNull);
      expect(state!.entries.length, 1);
      expect(state.entries.first.foodName, 'Chicken Salad');
      expect(state.currentWater, 800);
      expect(state.targetWater, 2200);
      expect(state.totalCaloriesConsumed, 450);
      expect(state.totalProteinConsumed, 35);
      expect(state.totalCarbsConsumed, 10);
      expect(state.totalFatConsumed, 12);
      expect(state.meals.length, 1);
      expect(state.meals.first.name, 'Salmon Bowl');
    });
  });
}

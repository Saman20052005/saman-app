import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/features/nutrition/data/models/nutrition_plan_dto.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/load_daily_plan_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/update_water_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_logged_meal_usecase.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';

class MockNutritionRepository extends Mock implements INutritionRepository {}

void main() {
  group('Water Intake Parsing & Provider Fix Tests', () {
    test('NutritionPlanDto parses water fields correctly in snake_case', () {
      final json = {
        '_id': 'plan_snake',
        'date': '2026-09-28',
        'current_water': 500,
        'water_target': 2500,
        'water_version': 3,
        'macro_targets': {'calories': 2000},
        'meals': [],
        'entries': [],
      };

      final dto = NutritionPlanDto.fromJson(json);
      expect(dto.currentWater, equals(500));
      expect(dto.targetWater, equals(2500));
      expect(dto.waterVersion, equals(3));

      final entity = dto.toEntity();
      expect(entity.currentWater, equals(500));
      expect(entity.targetWater, equals(2500));
      expect(entity.waterVersion, equals(3));
    });

    test('NutritionPlanDto parses water fields correctly in camelCase', () {
      final json = {
        '_id': 'plan_camel',
        'date': '2026-09-28',
        'currentWater': 750,
        'waterTarget': 3000,
        'waterVersion': 4,
        'macro_targets': {'calories': 2000},
        'meals': [],
        'entries': [],
      };

      final dto = NutritionPlanDto.fromJson(json);
      expect(dto.currentWater, equals(750));
      expect(dto.targetWater, equals(3000));
      expect(dto.waterVersion, equals(4));

      final entity = dto.toEntity();
      expect(entity.currentWater, equals(750));
      expect(entity.targetWater, equals(3000));
      expect(entity.waterVersion, equals(4));
    });

    test('NutritionPlanDto parses String, double, and alternative keys safely', () {
      final json = {
        '_id': 'plan_strings',
        'date': '2026-09-28',
        'water_intake': '600',
        'water_target_ml': '2400',
        'water_version': '5',
        'macro_targets': {'calories': 2000},
        'meals': [],
        'entries': [],
      };

      final dto = NutritionPlanDto.fromJson(json);
      expect(dto.currentWater, equals(600));
      expect(dto.targetWater, equals(2400));
      expect(dto.waterVersion, equals(5));

      final jsonDouble = {
        'current_water': 850.5,
        'target_water': 2200.0,
      };
      final dtoDouble = NutritionPlanDto.fromJson(jsonDouble);
      expect(dtoDouble.currentWater, equals(850));
      expect(dtoDouble.targetWater, equals(2200));
    });

    test('nutritionProvider holds current_water: 500 when loaded from getDailyPlan', () async {
      final mockRepo = MockNutritionRepository();
      final container = ProviderContainer(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(mockRepo),
          loadDailyPlanUseCaseProvider.overrideWithValue(LoadDailyPlanUseCase(mockRepo)),
          updateWaterUseCaseProvider.overrideWithValue(UpdateWaterUseCase(mockRepo)),
          swapMealUseCaseProvider.overrideWithValue(SwapMealUseCase(mockRepo)),
          swapLoggedMealUseCaseProvider.overrideWithValue(SwapLoggedMealUseCase(mockRepo)),
        ],
      );

      final dailyPlanWithWater = NutritionPlan(
        id: 'plan_1',
        date: '2026-09-28',
        meals: [
          Meal(
            foodId: 'f1',
            name: 'Chicken Rice',
            calories: 500,
            protein: 40,
            carbs: 60,
            fat: 10,
            weightGrams: 300,
            mealType: 'lunch',
            time: '12:00',
          ),
        ],
        entries: [],
        currentWater: 500,
        targetWater: 2000,
        waterVersion: 1,
      );

      when(() => mockRepo.getDailyPlan('2026-09-28'))
          .thenAnswer((_) async => dailyPlanWithWater);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime.parse('2026-09-28'));

      final stateValue = container.read(nutritionProvider).value;
      expect(stateValue, isNotNull);
      expect(stateValue?.currentWater, equals(500));
      expect(stateValue?.waterVersion, equals(1));
    });

    test('nutritionProvider preserves current_water: 500 and waterVersion during auto-pilot generation', () async {
      final mockRepo = MockNutritionRepository();
      final container = ProviderContainer(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(mockRepo),
          loadDailyPlanUseCaseProvider.overrideWithValue(LoadDailyPlanUseCase(mockRepo)),
          updateWaterUseCaseProvider.overrideWithValue(UpdateWaterUseCase(mockRepo)),
          swapMealUseCaseProvider.overrideWithValue(SwapMealUseCase(mockRepo)),
          swapLoggedMealUseCaseProvider.overrideWithValue(SwapLoggedMealUseCase(mockRepo)),
        ],
      );

      // Backend returns daily plan with 500ml water, but no meals/entries yet
      final emptyDayWithWater = NutritionPlan(
        date: '2026-09-28',
        meals: [],
        entries: [],
        currentWater: 500,
        targetWater: 2500,
        waterVersion: 2,
      );

      final generatedPlan = NutritionPlan(
        date: '2026-09-28',
        meals: [
          Meal(
            foodId: 'f2',
            name: 'Generated Meal',
            calories: 400,
            protein: 30,
            carbs: 40,
            fat: 10,
            weightGrams: 250,
            mealType: 'breakfast',
            time: '08:00',
          ),
        ],
        entries: [],
        currentWater: 0,
        waterVersion: 0,
      );

      when(() => mockRepo.getDailyPlan('2026-09-28'))
          .thenAnswer((_) async => emptyDayWithWater);

      when(() => mockRepo.generatePlan(
            goal: any(named: 'goal'),
            targetCalories: any(named: 'targetCalories'),
            mealCount: any(named: 'mealCount'),
            style: any(named: 'style'),
            remainingOnly: any(named: 'remainingOnly'),
          )).thenAnswer((_) async => generatedPlan);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime.parse('2026-09-28'));

      final stateValue = container.read(nutritionProvider).value;
      expect(stateValue, isNotNull);
      expect(stateValue?.currentWater, equals(500));
      expect(stateValue?.targetWater, equals(2500));
      expect(stateValue?.waterVersion, equals(2));
      expect(stateValue?.meals.length, equals(1));
    });

    test('generateSmartPlan preserves currentWater: 500 and waterVersion: 2', () async {
      final mockRepo = MockNutritionRepository();
      final container = ProviderContainer(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(mockRepo),
          loadDailyPlanUseCaseProvider.overrideWithValue(LoadDailyPlanUseCase(mockRepo)),
          updateWaterUseCaseProvider.overrideWithValue(UpdateWaterUseCase(mockRepo)),
          swapMealUseCaseProvider.overrideWithValue(SwapMealUseCase(mockRepo)),
          swapLoggedMealUseCaseProvider.overrideWithValue(SwapLoggedMealUseCase(mockRepo)),
        ],
      );

      final initialPlan = NutritionPlan(
        date: '2026-09-28',
        meals: [
          Meal(
            foodId: 'f1',
            name: 'Existing Meal',
            calories: 500,
            protein: 40,
            carbs: 60,
            fat: 10,
            weightGrams: 300,
            mealType: 'lunch',
            time: '12:00',
          ),
        ],
        entries: [],
        currentWater: 500,
        targetWater: 2000,
        waterVersion: 2,
      );

      final smartGeneratedPlan = NutritionPlan(
        date: '2026-09-28',
        meals: [
          Meal(
            foodId: 'f3',
            name: 'Smart Meal',
            calories: 600,
            protein: 45,
            carbs: 70,
            fat: 15,
            weightGrams: 350,
            mealType: 'dinner',
            time: '19:00',
          ),
        ],
        entries: [],
        currentWater: 0,
        waterVersion: 0,
      );

      when(() => mockRepo.getDailyPlan('2026-09-28'))
          .thenAnswer((_) async => initialPlan);

      when(() => mockRepo.generatePlan(
            goal: any(named: 'goal'),
            targetCalories: any(named: 'targetCalories'),
            mealCount: any(named: 'mealCount'),
            style: any(named: 'style'),
            remainingOnly: any(named: 'remainingOnly'),
          )).thenAnswer((_) async => smartGeneratedPlan);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime.parse('2026-09-28'));
      expect(container.read(nutritionProvider).value?.currentWater, equals(500));

      // Now invoke generateSmartPlan
      await notifier.generateSmartPlan(
        date: DateTime.parse('2026-09-28'),
        mealCount: 3,
        style: 'optimal',
      );

      final stateAfterSmartPlan = container.read(nutritionProvider).value;
      expect(stateAfterSmartPlan, isNotNull);
      expect(stateAfterSmartPlan?.currentWater, equals(500));
      expect(stateAfterSmartPlan?.waterVersion, equals(2));
      expect(stateAfterSmartPlan?.meals.first.name, equals('Smart Meal'));
    });

    test('generateAutoPlan preserves currentWater and waterVersion from state/cache', () async {
      final mockRepo = MockNutritionRepository();
      final container = ProviderContainer(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(mockRepo),
          loadDailyPlanUseCaseProvider.overrideWithValue(LoadDailyPlanUseCase(mockRepo)),
          updateWaterUseCaseProvider.overrideWithValue(UpdateWaterUseCase(mockRepo)),
          swapMealUseCaseProvider.overrideWithValue(SwapMealUseCase(mockRepo)),
          swapLoggedMealUseCaseProvider.overrideWithValue(SwapLoggedMealUseCase(mockRepo)),
        ],
      );

      final initialPlan = NutritionPlan(
        date: '2026-09-28',
        meals: [
          Meal(
            foodId: 'f1',
            name: 'Initial Meal',
            calories: 500,
            protein: 40,
            carbs: 60,
            fat: 10,
            weightGrams: 300,
            mealType: 'lunch',
            time: '12:00',
          ),
        ],
        entries: [],
        currentWater: 500,
        targetWater: 2200,
        waterVersion: 3,
      );

      final autoGeneratedPlan = NutritionPlan(
        date: '2026-09-28',
        meals: [
          Meal(
            foodId: 'f4',
            name: 'Auto Meal',
            calories: 450,
            protein: 35,
            carbs: 50,
            fat: 12,
            weightGrams: 280,
            mealType: 'breakfast',
            time: '08:00',
          ),
        ],
        entries: [],
        currentWater: 0,
        waterVersion: 0,
      );

      when(() => mockRepo.getDailyPlan('2026-09-28'))
          .thenAnswer((_) async => initialPlan);

      when(() => mockRepo.generatePlan(
            goal: any(named: 'goal'),
            targetCalories: any(named: 'targetCalories'),
            mealCount: any(named: 'mealCount'),
            style: any(named: 'style'),
            remainingOnly: any(named: 'remainingOnly'),
          )).thenAnswer((_) async => autoGeneratedPlan);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime.parse('2026-09-28'));
      expect(container.read(nutritionProvider).value?.currentWater, equals(500));

      // Directly invoke generateAutoPlan
      await notifier.generateAutoPlan(
        DateTime.parse('2026-09-28'),
        targetCalories: 2000,
        goal: 'maintain',
      );

      final stateAfterAutoPlan = container.read(nutritionProvider).value;
      expect(stateAfterAutoPlan, isNotNull);
      expect(stateAfterAutoPlan?.currentWater, equals(500));
      expect(stateAfterAutoPlan?.targetWater, equals(2200));
      expect(stateAfterAutoPlan?.waterVersion, equals(3));
      expect(stateAfterAutoPlan?.meals.first.name, equals('Auto Meal'));
    });
  });
}

import 'dart:async';
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
  group('Checkpoint 4a Nutrition Water Contract & Provider Tests', () {
    test('NutritionPlan and DTO parse water_version correctly from backend json', () {
      final json = {
        '_id': 'plan_1',
        'date': '2026-09-27',
        'current_water': 500,
        'water_version': 3,
        'water_target': 2000,
        'total_calories': 1800,
        'total_protein': 120,
        'total_carbs': 200,
        'total_fat': 60,
        'macro_targets': {
          'calories': 2000,
          'protein': 150,
          'carbs': 200,
          'fat': 67,
        },
        'meals': [],
        'entries': [],
      };

      final dto = NutritionPlanDto.fromJson(json);
      expect(dto.currentWater, 500);
      expect(dto.waterVersion, 3);

      final domain = dto.toEntity();
      expect(domain.currentWater, 500);
      expect(domain.waterVersion, 3);

      final model = NutritionPlan.fromJson(json);
      expect(model.currentWater, 500);
      expect(model.waterVersion, 3);
    });

    test('addWater performs optimistic update and sends delta_ml + idempotency_key', () async {
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
        date: '2026-09-27',
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
            time: '12:00',
          )
        ],
        currentWater: 500,
        waterVersion: 2,
      );

      when(() => mockRepo.getDailyPlan('2026-09-27'))
          .thenAnswer((_) async => initialPlan);

      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async => true);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));

      expect(container.read(nutritionProvider).value?.currentWater, 500);
      expect(container.read(nutritionProvider).value?.waterVersion, 2);

      await notifier.addWater(250, date: '2026-09-27', idempotencyKey: 'test_key_123');

      expect(container.read(nutritionProvider).value?.currentWater, 750);
      expect(container.read(nutritionProvider).value?.waterVersion, 3);

      verify(() => mockRepo.updateWater(
            '2026-09-27',
            null,
            deltaMl: 250,
            idempotencyKey: 'test_key_123',
          )).called(1);
    });

    test('updateWater sends current waterVersion for optimistic locking', () async {
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
        date: '2026-09-27',
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
            time: '12:00',
          )
        ],
        currentWater: 750,
        waterVersion: 4,
      );

      when(() => mockRepo.getDailyPlan('2026-09-27'))
          .thenAnswer((_) async => initialPlan);

      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async => true);

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));

      // Intentionally decreasing water to 500ml
      await notifier.updateWater(500, date: '2026-09-27');

      expect(container.read(nutritionProvider).value?.currentWater, 500);
      expect(container.read(nutritionProvider).value?.waterVersion, 5);

      verify(() => mockRepo.updateWater(
            '2026-09-27',
            500,
            version: 4,
          )).called(1);
    });

    test('Checkpoint 4a: addWater retains idempotency_key on timeout so retry uses the same key', () async {
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
        date: '2026-09-27',
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
            time: '12:00',
          )
        ],
        currentWater: 500,
        waterVersion: 1,
      );

      when(() => mockRepo.getDailyPlan('2026-09-27'))
          .thenAnswer((_) async => initialPlan);

      final capturedKeys = <String>[];
      var callCount = 0;
      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((invocation) async {
        callCount++;
        final key = invocation.namedArguments[#idempotencyKey] as String;
        capturedKeys.add(key);
        if (callCount == 1) {
          throw TimeoutException('Request timed out');
        }
        return true;
      });

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));

      // Attempt 1: fails with timeout
      try {
        await notifier.addWater(250, date: '2026-09-27');
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }

      // State is rolled back to initialPlan after timeout
      expect(container.read(nutritionProvider).value?.currentWater, 500);

      // Attempt 2: retry of the EXACT operation that timed out using its key
      final retryKey = notifier.lastFailedWaterKey;
      expect(retryKey, isNotNull);
      expect(retryKey, equals(capturedKeys[0]));
      await notifier.addWater(250, date: '2026-09-27', idempotencyKey: retryKey);

      // Invariant: Two calls made, but BOTH used the EXACT same idempotencyKey!
      expect(callCount, 2);
      expect(capturedKeys.length, 2);
      expect(capturedKeys[0], equals(capturedKeys[1]));

      // State is now successfully updated to 750ml
      expect(container.read(nutritionProvider).value?.currentWater, 750);
    });

    test('Checkpoint 4a: two consecutive taps for +250ml use different idempotency keys and accumulate total', () async {
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
        date: '2026-09-27',
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
            time: '12:00',
          )
        ],
        currentWater: 500,
        waterVersion: 1,
      );

      when(() => mockRepo.getDailyPlan('2026-09-27'))
          .thenAnswer((_) async => initialPlan);

      final capturedKeys = <String>[];
      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((invocation) async {
        final key = invocation.namedArguments[#idempotencyKey] as String;
        capturedKeys.add(key);
        return true;
      });

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));

      // Tap 1: add 250ml
      await notifier.addWater(250, date: '2026-09-27');
      expect(container.read(nutritionProvider).value?.currentWater, 750);
      expect(container.read(nutritionProvider).value?.waterVersion, 2);

      // Tap 2: add 250ml again (consecutive real taps)
      await notifier.addWater(250, date: '2026-09-27');
      expect(container.read(nutritionProvider).value?.currentWater, 1000);
      expect(container.read(nutritionProvider).value?.waterVersion, 3);

      // Invariant: Two different keys used, both operations succeeded
      expect(capturedKeys.length, 2);
      expect(capturedKeys[0], isNot(equals(capturedKeys[1])));
    });

    test('Checkpoint 4a: incremental rollback preserves concurrent operations on failure', () async {
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
        date: '2026-09-27',
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
            time: '12:00',
          )
        ],
        currentWater: 500,
        waterVersion: 1,
      );

      when(() => mockRepo.getDailyPlan('2026-09-27'))
          .thenAnswer((_) async => initialPlan);

      final completer1 = Completer<bool>();
      final completer2 = Completer<bool>();

      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((invocation) async {
        final key = invocation.namedArguments[#idempotencyKey] as String;
        if (key.contains('op1')) {
          return completer1.future;
        } else {
          return completer2.future;
        }
      });

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));

      // Trigger Op 1 (+250) and Op 2 (+250) concurrently
      final f1 = notifier.addWater(250, date: '2026-09-27', idempotencyKey: 'op1');
      final f2 = notifier.addWater(250, date: '2026-09-27', idempotencyKey: 'op2');

      // State optimistically shows 1000ml, version 3
      expect(container.read(nutritionProvider).value?.currentWater, 1000);
      expect(container.read(nutritionProvider).value?.waterVersion, 3);

      // Op 1 fails with timeout
      completer1.completeError(TimeoutException('Op 1 timeout'));
      // Op 2 succeeds
      completer2.complete(true);

      try {
        await f1;
      } catch (_) {}
      await f2;

      // Invariant: Op 1's 250ml is rolled back, but Op 2's 250ml remains! (500 + 250 = 750)
      expect(container.read(nutritionProvider).value?.currentWater, 750);
      expect(container.read(nutritionProvider).value?.waterVersion, 2);
    });

    test('Checkpoint 4a: simulated backend write succeeded but response timed out, retry reuses key so total only increases 250ml once', () async {
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
        date: '2026-09-27',
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
            time: '12:00',
          )
        ],
        currentWater: 500,
        waterVersion: 1,
      );

      when(() => mockRepo.getDailyPlan('2026-09-27'))
          .thenAnswer((_) async => initialPlan);

      // Simulate backend database state
      int backendWater = 500;
      int backendVersion = 1;
      final backendAppliedKeys = <String>{};
      final capturedCalls = <Map<String, dynamic>>[];

      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((invocation) async {
        final delta = invocation.namedArguments[#deltaMl] as int?;
        final key = invocation.namedArguments[#idempotencyKey] as String;
        capturedCalls.add({'delta': delta, 'key': key});

        if (backendAppliedKeys.contains(key)) {
          // Idempotent retry: backend already committed this key!
          // Does NOT increment water a second time.
          return true;
        }

        // Fresh operation: backend commits +250ml and records key
        if (delta != null) {
          backendWater += delta;
          backendVersion += 1;
          backendAppliedKeys.add(key);
        }

        // First call: backend committed, but response times out before reaching client!
        if (capturedCalls.length == 1) {
          throw TimeoutException('HTTP connection timed out');
        }

        return true;
      });

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));
      expect(container.read(nutritionProvider).value?.currentWater, 500);

      // 1. First tap: user taps +250ml
      try {
        await notifier.addWater(250, date: '2026-09-27');
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }

      // Backend committed +250ml (500 -> 750), but client encountered timeout
      expect(backendWater, 750);
      expect(backendVersion, 2);
      expect(backendAppliedKeys.length, 1);
      final firstKey = capturedCalls[0]['key'] as String;
      expect(firstKey, isNotEmpty);
      // Client state rolled back on timeout
      expect(container.read(nutritionProvider).value?.currentWater, 500);

      // 2. User retries the timed-out operation using the stored retry key
      final retryKey = notifier.lastFailedWaterKey;
      expect(retryKey, equals(firstKey));

      await notifier.addWater(250, date: '2026-09-27', idempotencyKey: retryKey);

      // Verification:
      // Backend received the retry with the SAME key
      expect(capturedCalls.length, 2);
      expect(capturedCalls[1]['key'], equals(firstKey));
      // Backend did NOT increment again because key was already applied
      expect(backendWater, 750);
      expect(backendVersion, 2);
      // Client state is now 750 (total only increased 250ml!)
      expect(container.read(nutritionProvider).value?.currentWater, 750);

      // 3. User performs a NEW distinct tap to add water
      await notifier.addWater(250, date: '2026-09-27');

      // Verification:
      // A new, different key was generated
      expect(capturedCalls.length, 3);
      final newKey = capturedCalls[2]['key'] as String;
      expect(newKey, isNot(equals(firstKey)));
      // Backend committed the new +250ml
      expect(backendWater, 1000);
      expect(backendVersion, 3);
      expect(container.read(nutritionProvider).value?.currentWater, 1000);
    });

    test('Checkpoint 4a: addWater retry across midnight retains original date and idempotency_key while subsequent new tap uses new date and new key', () async {
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

      const datePreMidnight = '2026-09-27';
      const datePostMidnight = '2026-09-28';

      final planPreMidnight = NutritionPlan(
        date: datePreMidnight,
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
            time: '12:00',
          )
        ],
        currentWater: 500,
        waterVersion: 1,
      );

      when(() => mockRepo.getDailyPlan(any()))
          .thenAnswer((_) async => planPreMidnight);

      final dbWater = <String, int>{datePreMidnight: 500, datePostMidnight: 0};
      final dbAppliedKeys = <String>{};
      final capturedCalls = <Map<String, dynamic>>[];

      when(() => mockRepo.updateWater(
            any(),
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((invocation) async {
        final date = invocation.positionalArguments[0] as String;
        final delta = invocation.namedArguments[#deltaMl] as int?;
        final key = invocation.namedArguments[#idempotencyKey] as String;
        capturedCalls.add({'date': date, 'delta': delta, 'key': key});

        if (dbAppliedKeys.contains(key)) {
          // Idempotent retry: do not double-increment
          return true;
        }

        if (delta != null) {
          dbWater[date] = (dbWater[date] ?? 0) + delta;
          dbAppliedKeys.add(key);
        }

        if (capturedCalls.length == 1) {
          throw TimeoutException('Pre-midnight request timed out');
        }

        return true;
      });

      final notifier = container.read(nutritionProvider.notifier);
      await notifier.loadDailyPlan(DateTime(2026, 9, 27));

      // 1. Pre-midnight: user initiates +250ml on 2026-09-27
      try {
        await notifier.addWater(250, date: datePreMidnight);
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }

      expect(dbWater[datePreMidnight], 750);
      expect(capturedCalls.length, 1);
      final preMidnightKey = capturedCalls[0]['key'] as String;
      expect(capturedCalls[0]['date'], equals(datePreMidnight));

      // 2. Midnight passes -> user retries the failed operation.
      // Caller reuses both the original date (datePreMidnight) and the original key!
      final retryKey = notifier.lastFailedWaterKey;
      expect(retryKey, equals(preMidnightKey));

      await notifier.addWater(250, date: datePreMidnight, idempotencyKey: retryKey);

      // Verify retry targeted datePreMidnight and preMidnightKey
      expect(capturedCalls.length, 2);
      expect(capturedCalls[1]['date'], equals(datePreMidnight));
      expect(capturedCalls[1]['key'], equals(preMidnightKey));
      // Backend was not double incremented
      expect(dbWater[datePreMidnight], 750);
      expect(dbWater[datePostMidnight], 0);

      // 3. User makes a fresh new tap after midnight on 2026-09-28
      await notifier.addWater(250, date: datePostMidnight);

      // Verify new tap targeted datePostMidnight and generated a fresh key
      expect(capturedCalls.length, 3);
      expect(capturedCalls[2]['date'], equals(datePostMidnight));
      final postMidnightKey = capturedCalls[2]['key'] as String;
      expect(postMidnightKey, isNot(equals(preMidnightKey)));
      expect(dbWater[datePreMidnight], 750);
      expect(dbWater[datePostMidnight], 250);
    });
  });
}

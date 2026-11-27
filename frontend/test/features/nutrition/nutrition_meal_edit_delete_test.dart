import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/load_daily_plan_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_logged_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/update_water_usecase.dart';
import 'package:health_ai_app/features/nutrition/presentation/widgets/nutrition_home_components.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_logged_meal_card.dart';
import 'package:health_ai_app/theme/nutrition_home_theme.dart';

class _MockNutritionRepository extends Mock implements INutritionRepository {}

void main() {
  NutritionLogEntry buildSampleEntry() {
    return NutritionLogEntry(
      logId: 'log-123',
      foodName: 'Ức gà & Cơm gạo lứt',
      mealType: 'lunch',
      totalCalories: 400,
      protein: 40,
      carbs: 45,
      fat: 6,
      foods: [
        {
          'name': 'Ức gà',
          'grams': 100,
          'calories': 200,
          'protein': 30.0,
          'carbs': 0.0,
          'fat': 4.0,
        },
        {
          'name': 'Cơm gạo lứt',
          'grams': 100,
          'calories': 200,
          'protein': 10.0,
          'carbs': 45.0,
          'fat': 2.0,
        },
      ],
    );
  }

  group('NutritionLoggedMealCard & NutritionLoggedMealDetails', () {
    testWidgets(
      'displays edit/delete buttons when callbacks provided and stays backward-compatible when omitted',
      (tester) async {
        final entry = buildSampleEntry();
        var editTapped = false;
        var deleteTapped = false;

        // Without callbacks (backward-compatible)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NutritionLoggedMealCard(entry: entry),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('meal_card_edit_log-123')),
            findsNothing);
        expect(find.byKey(const ValueKey('meal_card_delete_log-123')),
            findsNothing);

        // With callbacks on card
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NutritionLoggedMealCard(
                entry: entry,
                onEdit: () => editTapped = true,
                onDelete: () => deleteTapped = true,
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('meal_card_edit_log-123')));
        await tester.pump();
        expect(editTapped, isTrue);

        await tester
            .tap(find.byKey(const ValueKey('meal_card_delete_log-123')));
        await tester.pump();
        expect(deleteTapped, isTrue);

        // Details sheet with callbacks
        var detailEditTapped = false;
        var detailDeleteTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NutritionHomeTheme(
                child: NutritionLoggedMealDetails(
                  entry: entry,
                  onEdit: () => detailEditTapped = true,
                  onDelete: () => detailDeleteTapped = true,
                ),
              ),
            ),
          ),
        );

        expect(find.text('Ức gà'), findsOneWidget);
        expect(find.text('100g · 200 kcal'), findsNWidgets(2));

        await tester.tap(find.byKey(const ValueKey('meal_detail_edit_btn')));
        await tester.pump();
        expect(detailEditTapped, isTrue);

        await tester.tap(find.byKey(const ValueKey('meal_detail_delete_btn')));
        await tester.pump();
        expect(detailDeleteTapped, isTrue);
      },
    );
  });

  group('NutritionEditLoggedMealSheet', () {
    testWidgets(
      'changes meal type, increments grams (+25g), updates live preview, and sends PATCH payload',
      (tester) async {
        final entry = buildSampleEntry();
        String? savedMealType;
        List<Map<String, dynamic>>? savedFoods;
        double? savedMultiplier;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NutritionHomeTheme(
                child: NutritionEditLoggedMealSheet(
                  entry: entry,
                  onSave: ({
                    required String mealType,
                    List<Map<String, dynamic>>? foods,
                    double? portionMultiplier,
                  }) async {
                    savedMealType = mealType;
                    savedFoods = foods;
                    savedMultiplier = portionMultiplier;
                    return true;
                  },
                ),
              ),
            ),
          ),
        );

        expect(find.text('400 kcal'), findsOneWidget);

        // Change meal type: lunch -> dinner
        await tester.tap(find.byKey(const ValueKey('edit_meal_type_dinner')));
        await tester.pump();

        // Increment first food item by +25g (100g -> 125g => +50 kcal, +7.5g protein)
        await tester.tap(find.byKey(const ValueKey('edit_food_inc_0')));
        await tester.pump();

        expect(find.text('450 kcal'), findsOneWidget);
        expect(find.text('48g pro · 45g carb · 7g fat'), findsOneWidget);

        // Save
        final saveBtn = find.byKey(const ValueKey('edit_meal_save_btn'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(savedMealType, 'dinner');
        expect(savedMultiplier, isNull);
        expect(savedFoods, isNotNull);
        expect(savedFoods!.length, 2);
        expect(savedFoods![0]['grams'], 125);
        expect(savedFoods![0]['calories'], 250);
        expect(savedFoods![0]['protein'], 37.5);
      },
    );
  });

  group('Delete meal confirmation flow', () {
    testWidgets(
      'cancel keeps item, confirm deletes item and updates UI list',
      (tester) async {
        final entries = [buildSampleEntry()];

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                Future<void> confirmDelete(NutritionLogEntry entry) async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Xóa bữa ăn?'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Hủy'),
                        ),
                        TextButton(
                          key: const ValueKey('confirm_delete_meal_btn'),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Xóa'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    setState(() {
                      entries.removeWhere((e) => e.logId == entry.logId);
                    });
                  }
                }

                return Scaffold(
                  body: ListView(
                    children: [
                      for (final e in entries)
                        NutritionLoggedMealCard(
                          key: ValueKey(e.logId),
                          entry: e,
                          onDelete: () => confirmDelete(e),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        expect(find.text('Ức gà & Cơm gạo lứt'), findsOneWidget);

        // Tap delete -> Cancel
        await tester
            .tap(find.byKey(const ValueKey('meal_card_delete_log-123')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        expect(find.text('Ức gà & Cơm gạo lứt'), findsOneWidget);

        // Tap delete -> Confirm
        await tester
            .tap(find.byKey(const ValueKey('meal_card_delete_log-123')));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('confirm_delete_meal_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Ức gà & Cơm gạo lứt'), findsNothing);
      },
    );
  });

  group('NutritionNotifier updateLoggedMeal & deleteLoggedMeal', () {
    late _MockNutritionRepository mockRepository;
    late ProviderContainer container;

    setUp(() {
      mockRepository = _MockNutritionRepository();
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

    test(
      'updateLoggedMeal calls updateNutritionLog and reloads daily plan',
      () async {
        final date = DateTime(2026, 11, 27);
        final updatedPlan = NutritionPlan(
          date: '2026-11-27',
          meals: const [],
          entries: [
            NutritionLogEntry(
              logId: 'log-123',
              foodName: 'Ức gà & Cơm gạo lứt',
              mealType: 'dinner',
              totalCalories: 450,
              protein: 47.5,
              carbs: 45,
              fat: 7,
            ),
          ],
          totalCaloriesConsumed: 450,
          totalProteinConsumed: 48,
        );

        when(() => mockRepository.updateNutritionLog(
              logId: 'log-123',
              mealType: 'dinner',
              foods: any(named: 'foods'),
              portionMultiplier: any(named: 'portionMultiplier'),
              totalGrams: any(named: 'totalGrams'),
              notes: any(named: 'notes'),
              session: any(named: 'session'),
            )).thenAnswer((_) async => true);

        when(() => mockRepository.getDailyPlan('2026-11-27',
                session: any(named: 'session')))
            .thenAnswer((_) async => updatedPlan);
        when(() => mockRepository.generatePlan(
              dateStr: any(named: 'dateStr'),
              goal: any(named: 'goal'),
              targetCalories: any(named: 'targetCalories'),
              mealCount: any(named: 'mealCount'),
              style: any(named: 'style'),
              remainingOnly: any(named: 'remainingOnly'),
              session: any(named: 'session'),
            )).thenAnswer((_) async => updatedPlan);

        final notifier = container.read(nutritionProvider.notifier);
        final ok = await notifier.updateLoggedMeal(
          date: date,
          logId: 'log-123',
          mealType: 'dinner',
        );

        expect(ok, isTrue);
        verify(() => mockRepository.updateNutritionLog(
              logId: 'log-123',
              mealType: 'dinner',
              foods: null,
              portionMultiplier: null,
              totalGrams: null,
              notes: null,
              session: any(named: 'session'),
            )).called(1);
        verify(() => mockRepository.getDailyPlan('2026-11-27',
            session: any(named: 'session'))).called(1);
        expect(container.read(nutritionProvider).value?.entries.length, 1);
        expect(
          container.read(nutritionProvider).value?.entries.first.mealType,
          'dinner',
        );
      },
    );

    test(
      'deleteLoggedMeal calls deleteNutritionLog, reloads daily plan, and handles network error safely',
      () async {
        final date = DateTime(2026, 11, 27);
        final emptyPlan = NutritionPlan(
          date: '2026-11-27',
          meals: const [],
          entries: const [],
          totalCaloriesConsumed: 0,
        );

        when(() => mockRepository.deleteNutritionLog('log-123',
                session: any(named: 'session')))
            .thenAnswer((_) async => true);
        when(() => mockRepository.getDailyPlan('2026-11-27',
                session: any(named: 'session')))
            .thenAnswer((_) async => emptyPlan);
        when(() => mockRepository.generatePlan(
              dateStr: any(named: 'dateStr'),
              goal: any(named: 'goal'),
              targetCalories: any(named: 'targetCalories'),
              mealCount: any(named: 'mealCount'),
              style: any(named: 'style'),
              remainingOnly: any(named: 'remainingOnly'),
              session: any(named: 'session'),
            )).thenAnswer((_) async => emptyPlan);

        final notifier = container.read(nutritionProvider.notifier);
        final ok = await notifier.deleteLoggedMeal(
          date: date,
          logId: 'log-123',
        );

        expect(ok, isTrue);
        expect(container.read(nutritionProvider).value?.entries, isEmpty);

        // Network error returns false without crashing
        when(() => mockRepository.deleteNutritionLog('log-999',
                session: any(named: 'session')))
            .thenThrow(Exception('Network error'));

        final failed = await notifier.deleteLoggedMeal(
          date: date,
          logId: 'log-999',
        );
        expect(failed, isFalse);
        expect(container.read(nutritionProvider).hasError, isFalse);
      },
    );
  });
}

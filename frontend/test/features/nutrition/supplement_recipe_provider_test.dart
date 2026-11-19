import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:health_ai_app/features/nutrition/data/models/supplement_dto.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/nutrition/presentation/providers/recipes_supplements_provider.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';

class MockNutritionRepository extends Mock implements INutritionRepository {}

class FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  FakeNutritionNotifier() : super(const AsyncValue.data(null));

  int refreshCallCount = 0;
  String? lastRefreshDateStr;

  @override
  Future<void> refreshCurrentPlan({
    String? dateStr,
    bool forceRefresh = true,
  }) async {
    refreshCallCount++;
    lastRefreshDateStr = dateStr;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('1. SupplementDto & Supplement JSON Parsing Tests', () {
    test('SupplementDto.fromJson parses legacy keys correctly', () {
      final legacyJson = {
        'id': 'supp_dto_legacy_1',
        'name': 'Creatine Monohydrate',
        'amount': 5.0,
        'unit': 'g',
        'time': 'morning',
      };

      final dto = SupplementDto.fromJson(legacyJson);

      expect(dto.id, 'supp_dto_legacy_1');
      expect(dto.name, 'Creatine Monohydrate');
      expect(dto.amount, 5.0);
      expect(dto.unit, 'g');
      expect(dto.time, 'morning');
      expect(dto.dosage, isNull);
      expect(dto.notes, isNull);
      expect(dto.date, isNull);
    });

    test('SupplementDto.fromJson parses new backend keys correctly', () {
      final backendJson = {
        'id': 'supp_dto_new_1',
        'supplement_name': 'Whey Protein Isolate',
        'amount': 2.0,
        'unit': 'muỗng',
        'timing': 'post_workout',
        'dosage': '30g',
        'date': '2026-11-17',
        'notes': 'Take with water after lifting',
      };

      final dto = SupplementDto.fromJson(backendJson);

      expect(dto.id, 'supp_dto_new_1');
      expect(dto.name, 'Whey Protein Isolate');
      expect(dto.amount, 2.0);
      expect(dto.unit, 'muỗng');
      expect(dto.time, 'post_workout');
      expect(dto.dosage, '30g');
      expect(dto.date, '2026-11-17');
      expect(dto.notes, 'Take with water after lifting');

      final entity = dto.toEntity();
      expect(entity.id, 'supp_dto_new_1');
      expect(entity.name, 'Whey Protein Isolate');
      expect(entity.amount, 2.0);
      expect(entity.unit, 'muỗng');
      expect(entity.time, 'post_workout');
      expect(entity.dosage, '30g');
      expect(entity.date, '2026-11-17');
      expect(entity.notes, 'Take with water after lifting');
    });

    test('SupplementDto.fromJson uses expected default fallbacks when fields missing', () {
      final emptyJson = <String, dynamic>{};
      final dto = SupplementDto.fromJson(emptyJson);

      expect(dto.id, isNull);
      expect(dto.name, '');
      expect(dto.amount, 1.0);
      expect(dto.unit, 'viên');
      expect(dto.time, '');
      expect(dto.dosage, isNull);
      expect(dto.notes, isNull);
      expect(dto.date, isNull);
    });

    test('Supplement.fromJson parses legacy keys correctly', () {
      final legacyJson = {
        'id': 'supp_legacy_1',
        'name': 'Multivitamin',
        'amount': 2.0,
        'unit': 'viên',
        'time': 'with_breakfast',
      };

      final supplement = Supplement.fromJson(legacyJson);

      expect(supplement.id, 'supp_legacy_1');
      expect(supplement.name, 'Multivitamin');
      expect(supplement.amount, 2.0);
      expect(supplement.unit, 'viên');
      expect(supplement.time, 'with_breakfast');
      expect(supplement.dosage, isNull);
      expect(supplement.notes, isNull);
      expect(supplement.date, isNull);
    });

    test('Supplement.fromJson parses new backend keys correctly', () {
      final backendJson = {
        'id': 'supp_new_1',
        'supplement_name': 'Omega 3 Fish Oil',
        'amount': 1.0,
        'unit': 'viên',
        'timing': 'lunch',
        'dosage': '1000mg EPA/DHA',
        'date': '2026-11-17',
        'notes': 'Take after meal',
      };

      final supplement = Supplement.fromJson(backendJson);

      expect(supplement.id, 'supp_new_1');
      expect(supplement.name, 'Omega 3 Fish Oil');
      expect(supplement.amount, 1.0);
      expect(supplement.unit, 'viên');
      expect(supplement.time, 'lunch');
      expect(supplement.dosage, '1000mg EPA/DHA');
      expect(supplement.date, '2026-11-17');
      expect(supplement.notes, 'Take after meal');

      final jsonMap = supplement.toJson();
      expect(jsonMap['id'], 'supp_new_1');
      expect(jsonMap['name'], 'Omega 3 Fish Oil');
      expect(jsonMap['amount'], 1.0);
      expect(jsonMap['unit'], 'viên');
      expect(jsonMap['time'], 'lunch');
      expect(jsonMap['dosage'], '1000mg EPA/DHA');
      expect(jsonMap['date'], '2026-11-17');
      expect(jsonMap['notes'], 'Take after meal');
    });

    test('Supplement.fromJson uses default fallback values when keys missing', () {
      final emptyJson = <String, dynamic>{};
      final supplement = Supplement.fromJson(emptyJson);

      expect(supplement.id, isNull);
      expect(supplement.name, '');
      expect(supplement.amount, 0.0);
      expect(supplement.unit, 'viên');
      expect(supplement.time, '');
      expect(supplement.dosage, isNull);
      expect(supplement.notes, isNull);
      expect(supplement.date, isNull);
    });
  });

  group('2. RecipeModel JSON Parsing Tests', () {
    test('RecipeModel.fromJson parses camelCase keys and ingredients correctly', () {
      final json = {
        'id': 'recipe_camel_1',
        'name': 'Chicken Avocado Salad',
        'description': 'Nutritious lunch bowl',
        'servings': 2,
        'category': 'Lunch',
        'caloriesPerServing': 420.5,
        'proteinPerServing': 38.0,
        'carbsPerServing': 16.5,
        'fatPerServing': 18.2,
        'ingredients': [
          {
            'name': 'Chicken Breast',
            'quantity': 200.0,
            'unit': 'g',
            'calories': 330.0,
            'protein': 62.0,
            'carbs': 0.0,
            'fat': 7.2,
          },
          {
            'name': 'Avocado',
            'quantity': 100.0,
            'unit': 'g',
            'calories': 160.0,
            'protein': 2.0,
            'carbs': 8.5,
            'fat': 14.7,
          },
        ],
      };

      final recipe = RecipeModel.fromJson(json);

      expect(recipe.id, 'recipe_camel_1');
      expect(recipe.name, 'Chicken Avocado Salad');
      expect(recipe.description, 'Nutritious lunch bowl');
      expect(recipe.servings, 2);
      expect(recipe.category, 'Lunch');
      expect(recipe.caloriesPerServing, 420.5);
      expect(recipe.proteinPerServing, 38.0);
      expect(recipe.carbsPerServing, 16.5);
      expect(recipe.fatPerServing, 18.2);

      expect(recipe.ingredients.length, 2);
      final chicken = recipe.ingredients[0];
      expect(chicken.name, 'Chicken Breast');
      expect(chicken.quantity, 200.0);
      expect(chicken.unit, 'g');
      expect(chicken.calories, 330.0);
      expect(chicken.protein, 62.0);
      expect(chicken.carbs, 0.0);
      expect(chicken.fat, 7.2);

      final avocado = recipe.ingredients[1];
      expect(avocado.name, 'Avocado');
      expect(avocado.quantity, 100.0);
      expect(avocado.unit, 'g');
      expect(avocado.calories, 160.0);
      expect(avocado.protein, 2.0);
      expect(avocado.carbs, 8.5);
      expect(avocado.fat, 14.7);
    });

    test('RecipeModel.fromJson parses snake_case keys and _id correctly', () {
      final json = {
        '_id': 'recipe_snake_2',
        'name': 'Overnight Oats',
        'description': 'Easy prep breakfast',
        'servings': 1,
        'category': 'Breakfast',
        'calories_per_serving': 310.0,
        'protein_per_serving': 14.0,
        'carbs_per_serving': 48.0,
        'fat_per_serving': 6.0,
        'ingredients': [
          {
            'name': 'Rolled Oats',
            'quantity': 50.0,
            'unit': 'g',
            'calories': 190.0,
            'protein': 6.5,
            'carbs': 34.0,
            'fat': 3.0,
          },
        ],
      };

      final recipe = RecipeModel.fromJson(json);

      expect(recipe.id, 'recipe_snake_2');
      expect(recipe.name, 'Overnight Oats');
      expect(recipe.description, 'Easy prep breakfast');
      expect(recipe.servings, 1);
      expect(recipe.category, 'Breakfast');
      expect(recipe.caloriesPerServing, 310.0);
      expect(recipe.proteinPerServing, 14.0);
      expect(recipe.carbsPerServing, 48.0);
      expect(recipe.fatPerServing, 6.0);
      expect(recipe.ingredients.length, 1);
      expect(recipe.ingredients[0].name, 'Rolled Oats');
    });

    test('RecipeModel.fromJson handles null and missing fields gracefully', () {
      final json = <String, dynamic>{};
      final recipe = RecipeModel.fromJson(json);

      expect(recipe.id, '');
      expect(recipe.name, '');
      expect(recipe.description, '');
      expect(recipe.servings, 1);
      expect(recipe.category, '');
      expect(recipe.caloriesPerServing, 0.0);
      expect(recipe.proteinPerServing, 0.0);
      expect(recipe.carbsPerServing, 0.0);
      expect(recipe.fatPerServing, 0.0);
      expect(recipe.ingredients, isEmpty);
    });
  });

  group('3. RecipesNotifier Tests', () {
    late MockNutritionRepository mockRepository;
    late ProviderContainer container;
    var nutritionInvalidationCount = 0;

    setUp(() {
      mockRepository = MockNutritionRepository();
      nutritionInvalidationCount = 0;
      container = ProviderContainer(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(mockRepository),
          nutritionProvider.overrideWith((ref) {
            ref.onDispose(() {
              nutritionInvalidationCount++;
            });
            return FakeNutritionNotifier();
          }),
        ],
      );
      // Eagerly read nutritionProvider so it is active and listening
      container.read(nutritionProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('loadRecipes() loads list successfully into state', () async {
      final sampleRecipes = [
        RecipeModel(
          id: 'rec_1',
          name: 'Protein Shake',
          description: 'Post-workout shake',
          ingredients: [],
          servings: 1,
          category: 'Snack',
          caloriesPerServing: 250.0,
          proteinPerServing: 35.0,
          carbsPerServing: 10.0,
          fatPerServing: 3.0,
        ),
        RecipeModel(
          id: 'rec_2',
          name: 'Salmon & Asparagus',
          description: 'Keto dinner',
          ingredients: [],
          servings: 1,
          category: 'Dinner',
          caloriesPerServing: 500.0,
          proteinPerServing: 45.0,
          carbsPerServing: 5.0,
          fatPerServing: 28.0,
        ),
      ];

      when(() => mockRepository.getRecipes())
          .thenAnswer((_) async => sampleRecipes);

      final notifier = container.read(recipesProvider.notifier);

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.recipes, isEmpty);

      await notifier.loadRecipes();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.recipes, sampleRecipes);
      expect(notifier.state.error, isNull);

      verify(() => mockRepository.getRecipes()).called(1);
    });

    test('loadRecipes() handles error gracefully', () async {
      when(() => mockRepository.getRecipes())
          .thenThrow(Exception('Network connection failed'));

      final notifier = container.read(recipesProvider.notifier);
      await notifier.loadRecipes();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.recipes, isEmpty);
      expect(notifier.state.error, contains('Network connection failed'));
    });

    test('logRecipeServing() calls repository with correct parameters and triggers invalidate nutritionProvider', () async {
      when(() => mockRepository.logRecipe(
            any(),
            date: any(named: 'date'),
            mealType: any(named: 'mealType'),
            servingsConsumed: any(named: 'servingsConsumed'),
          )).thenAnswer((_) async => true);

      final notifier = container.read(recipesProvider.notifier);

      expect(nutritionInvalidationCount, 0);

      final result = await notifier.logRecipeServing(
        'recipe_101',
        date: '2026-11-17',
        mealType: 'lunch',
        servingsConsumed: 2.5,
      );

      expect(result, isTrue);
      expect(notifier.state.isMutating, isFalse);
      expect(notifier.state.error, isNull);

      verify(() => mockRepository.logRecipe(
            'recipe_101',
            date: '2026-11-17',
            mealType: 'lunch',
            servingsConsumed: 2.5,
          )).called(1);

      // Verify that nutritionProvider was refreshed in-place without invalidation
      final fakeNutrition =
          container.read(nutritionProvider.notifier) as FakeNutritionNotifier;
      expect(fakeNutrition.refreshCallCount, 1);
      expect(fakeNutrition.lastRefreshDateStr, '2026-11-17');
      expect(nutritionInvalidationCount, 0);
    });

    test('logRecipeServing() does not invalidate nutritionProvider if repository returns false', () async {
      when(() => mockRepository.logRecipe(
            any(),
            date: any(named: 'date'),
            mealType: any(named: 'mealType'),
            servingsConsumed: any(named: 'servingsConsumed'),
          )).thenAnswer((_) async => false);

      final notifier = container.read(recipesProvider.notifier);

      final result = await notifier.logRecipeServing(
        'recipe_102',
        date: '2026-11-17',
        mealType: 'dinner',
        servingsConsumed: 1.0,
      );

      expect(result, isFalse);
      expect(nutritionInvalidationCount, 0);
    });

    test('createRecipe() adds created recipe to the beginning of state.recipes', () async {
      final existingRecipe = RecipeModel(
        id: 'rec_existing',
        name: 'Boiled Eggs',
        description: '',
        ingredients: [],
        servings: 2,
        category: 'Breakfast',
        caloriesPerServing: 140.0,
        proteinPerServing: 12.0,
        carbsPerServing: 1.0,
        fatPerServing: 10.0,
      );

      when(() => mockRepository.getRecipes())
          .thenAnswer((_) async => [existingRecipe]);

      final notifier = container.read(recipesProvider.notifier);
      await notifier.loadRecipes();
      expect(notifier.state.recipes, [existingRecipe]);

      final newRecipe = RecipeModel(
        id: 'rec_new',
        name: 'Protein Smoothie',
        description: 'Berry protein',
        ingredients: [],
        servings: 1,
        category: 'Snack',
        caloriesPerServing: 220.0,
        proteinPerServing: 25.0,
        carbsPerServing: 20.0,
        fatPerServing: 2.0,
      );

      final payload = {'name': 'Protein Smoothie'};
      when(() => mockRepository.createRecipe(payload))
          .thenAnswer((_) async => newRecipe);

      final created = await notifier.createRecipe(payload);

      expect(created, newRecipe);
      expect(notifier.state.recipes.length, 2);
      expect(notifier.state.recipes.first, newRecipe);
      expect(notifier.state.isMutating, isFalse);
      verify(() => mockRepository.createRecipe(payload)).called(1);
    });

    test('deleteRecipe() removes recipe from state.recipes when successful', () async {
      final recipe1 = RecipeModel(
        id: 'rec_del_1',
        name: 'Greek Yogurt Bowl',
        description: '',
        ingredients: [],
        servings: 1,
        category: 'Snack',
        caloriesPerServing: 150.0,
        proteinPerServing: 15.0,
        carbsPerServing: 12.0,
        fatPerServing: 0.0,
      );
      final recipe2 = RecipeModel(
        id: 'rec_stay_2',
        name: 'Tuna Salad',
        description: '',
        ingredients: [],
        servings: 1,
        category: 'Lunch',
        caloriesPerServing: 250.0,
        proteinPerServing: 30.0,
        carbsPerServing: 5.0,
        fatPerServing: 8.0,
      );

      when(() => mockRepository.getRecipes())
          .thenAnswer((_) async => [recipe1, recipe2]);

      final notifier = container.read(recipesProvider.notifier);
      await notifier.loadRecipes();
      expect(notifier.state.recipes.length, 2);

      when(() => mockRepository.deleteRecipe('rec_del_1'))
          .thenAnswer((_) async => true);

      final ok = await notifier.deleteRecipe('rec_del_1');

      expect(ok, isTrue);
      expect(notifier.state.recipes.length, 1);
      expect(notifier.state.recipes.first.id, 'rec_stay_2');
      expect(notifier.state.isMutating, isFalse);
      verify(() => mockRepository.deleteRecipe('rec_del_1')).called(1);
    });
  });

  group('4. SupplementsNotifier Tests', () {
    late MockNutritionRepository mockRepository;
    late ProviderContainer container;
    var nutritionInvalidationCount = 0;
    const testDate = '2026-11-17';

    setUp(() {
      mockRepository = MockNutritionRepository();
      nutritionInvalidationCount = 0;
      container = ProviderContainer(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(mockRepository),
          nutritionProvider.overrideWith((ref) {
            ref.onDispose(() {
              nutritionInvalidationCount++;
            });
            return FakeNutritionNotifier();
          }),
        ],
      );
      container.read(nutritionProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('addSupplement() adds supplement and updates list for dateStr', () async {
      final initialList = <Supplement>[
        Supplement(
          id: 'supp_existing_1',
          name: 'Vitamin D3',
          amount: 1.0,
          unit: 'viên',
          time: 'morning',
          date: testDate,
        ),
      ];

      final newSupplement = Supplement(
        id: 'supp_added_2',
        name: 'Magnesium Glycinate',
        amount: 2.0,
        unit: 'viên',
        time: 'before_bed',
        date: testDate,
        dosage: '400mg',
        notes: 'Take before sleep',
      );

      final updatedList = [...initialList, newSupplement];

      when(() => mockRepository.getSupplements(testDate))
          .thenAnswer((_) async => initialList);

      final notifier = container.read(supplementsByDateProvider(testDate).notifier);

      // Wait for initial load to finish
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.value, initialList);

      final payload = {
        'supplement_name': 'Magnesium Glycinate',
        'amount': 2.0,
        'unit': 'viên',
        'timing': 'before_bed',
        'date': testDate,
        'dosage': '400mg',
        'notes': 'Take before sleep',
      };

      when(() => mockRepository.addSupplement(payload))
          .thenAnswer((_) async => newSupplement);
      when(() => mockRepository.getSupplements(testDate))
          .thenAnswer((_) async => updatedList);

      expect(nutritionInvalidationCount, 0);

      final success = await notifier.addSupplement(payload);

      expect(success, isTrue);
      expect(notifier.state.value, updatedList);

      verify(() => mockRepository.addSupplement(payload)).called(1);
      verify(() => mockRepository.getSupplements(testDate)).called(2); // Initial load + reload
      final fakeNutrition =
          container.read(nutritionProvider.notifier) as FakeNutritionNotifier;
      expect(fakeNutrition.refreshCallCount, 1);
      expect(fakeNutrition.lastRefreshDateStr, testDate);
      expect(nutritionInvalidationCount, 0);
    });

    test('deleteSupplement() deletes supplement and updates list for dateStr', () async {
      final supplement1 = Supplement(
        id: 'supp_del_1',
        name: 'Zinc Picolinate',
        amount: 1.0,
        unit: 'viên',
        time: 'morning',
        date: testDate,
      );
      final supplement2 = Supplement(
        id: 'supp_keep_2',
        name: 'B-Complex',
        amount: 1.0,
        unit: 'viên',
        time: 'lunch',
        date: testDate,
      );

      final initialList = [supplement1, supplement2];
      final afterDeleteList = [supplement2];

      when(() => mockRepository.getSupplements(testDate))
          .thenAnswer((_) async => initialList);

      final notifier = container.read(supplementsByDateProvider(testDate).notifier);

      // Wait for initial load to finish
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.value, initialList);

      when(() => mockRepository.deleteSupplement('supp_del_1'))
          .thenAnswer((_) async => true);
      when(() => mockRepository.getSupplements(testDate))
          .thenAnswer((_) async => afterDeleteList);

      expect(nutritionInvalidationCount, 0);

      final success = await notifier.deleteSupplement('supp_del_1');

      expect(success, isTrue);
      expect(notifier.state.value, afterDeleteList);

      verify(() => mockRepository.deleteSupplement('supp_del_1')).called(1);
      verify(() => mockRepository.getSupplements(testDate)).called(2); // Initial load + reload
      final fakeNutrition =
          container.read(nutritionProvider.notifier) as FakeNutritionNotifier;
      expect(fakeNutrition.refreshCallCount, 1);
      expect(fakeNutrition.lastRefreshDateStr, testDate);
      expect(nutritionInvalidationCount, 0);
    });
  });
}

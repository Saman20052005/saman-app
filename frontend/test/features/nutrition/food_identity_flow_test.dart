import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/nutrition/data/models/food_dto.dart';
import 'package:health_ai_app/features/nutrition/data/models/meal_dto.dart';
import 'package:health_ai_app/features/nutrition/domain/entities/food.dart';
import 'package:health_ai_app/features/nutrition/domain/entities/meal.dart';
import 'package:health_ai_app/features/nutrition/presentation/providers/nutrition_usual_foods_provider.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/food_model.dart';
import 'package:health_ai_app/models/nutrition_model.dart' as legacy_model;
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import 'package:health_ai_app/services/nutrition_service.dart';

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockNutritionService extends NutritionService {
  final Future<List<Food>> Function(String query, {int limit}) onSearch;
  final Future<Food?> Function(String foodId)? onGetById;

  _MockNutritionService({
    required this.onSearch,
    this.onGetById,
  });

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) {
    return onSearch(query, limit: limit);
  }

  @override
  Future<Food?> getFoodById(String foodId) async {
    if (onGetById != null) {
      return onGetById!(foodId);
    }
    final list = await onSearch('');
    for (final f in list) {
      if (f.id == foodId) return f;
    }
    return null;
  }
}

class _SpyNutritionNotifier extends StateNotifier<AsyncValue<legacy_model.NutritionPlan?>>
    implements NutritionNotifier {
  _SpyNutritionNotifier() : super(const AsyncValue.data(null));

  int addMealCalls = 0;
  List<Map<String, dynamic>> recordedAddMealArgs = [];
  bool addMealResult = true;

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
    return addMealResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestProfileNotifier extends ProfileNotifier {
  _TestProfileNotifier({String userId = 'user_a@saman.app'})
      : super(_MockProfileRepository()) {
    state = ProfileState(
      profile: const ProfileEntity(
        age: 28,
        gender: Gender.male,
        height: 178,
        weight: 75,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      ),
      targetCalories: 2300,
      targetProtein: 160,
      targetCarbs: 240,
      targetFat: 65,
      waterTargetMl: 2000,
      isLoading: false,
      confirmedUserId: userId,
      isNetworkConfirmed: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences mockPrefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockPrefs = await SharedPreferences.getInstance();
  });

  group('CP-NUTRITION-FOOD-IDENTITY-01: DTO & Identity Parsing Tests', () {
    test('FoodDto parses MongoDB _id and id into canonical entity id', () {
      final jsonWithUnderscoreId = {
        '_id': '650000000000000000000001',
        'name': 'Cơm tấm Sườn Bì Chả',
        'calories': 650,
        'protein': 30.5,
        'carbs': 85.0,
        'fat': 22.0,
        'tags': ['POPULAR', 'VIETNAMESE'],
      };
      final dto1 = FoodDto.fromJson(jsonWithUnderscoreId);
      final entity1 = dto1.toEntity();
      expect(entity1.id, '650000000000000000000001');
      expect(entity1.name, 'Cơm tấm Sườn Bì Chả');
      expect(entity1.calories, 650.0);

      final jsonWithId = {
        'id': '650000000000000000000002',
        'name': 'Phở Bò Tái',
        'calories': 480,
        'protein': 28.0,
        'carbs': 62.0,
        'fat': 13.0,
        'tags': ['PROTEIN'],
      };
      final dto2 = FoodDto.fromJson(jsonWithId);
      expect(dto2.id, '650000000000000000000002');
    });

    test('MealDto reads food_id from foods list, foodsList, or direct food_id', () {
      // 1. Log response with foods array
      final jsonWithFoods = {
        'meal_type': 'lunch',
        'total_calories': 450,
        'foods': [
          {
            'food_id': '650000000000000000000003',
            'name': 'Bún Bò Huế',
            'calories': 450,
            'protein': 25.0,
            'carbs': 55.0,
            'fat': 14.0,
            'weight_grams': 100,
          }
        ],
      };
      final meal1 = MealDto.fromJson(jsonWithFoods).toEntity();
      expect(meal1.foodId, '650000000000000000000003');
      expect(meal1.name, 'Bún Bò Huế');
      expect(meal1.calories, 450);

      // 2. Log response with foodsList (backend entry_data)
      final jsonWithFoodsList = {
        'meal_type': 'dinner',
        'food_id': '650000000000000000000004',
        'food_name': 'Canh Chua Cá Hồi',
        'calories': 250,
        'protein': 22.0,
        'carbs': 12.0,
        'fat': 8.0,
        'foodsList': [
          {
            'food_id': '650000000000000000000004',
            'name': 'Canh Chua Cá Hồi',
            'calories': 250,
            'weight_grams': 150,
          }
        ],
      };
      final meal2 = MealDto.fromJson(jsonWithFoodsList).toEntity();
      expect(meal2.foodId, '650000000000000000000004');
      expect(meal2.name, 'Canh Chua Cá Hồi');

      // 3. Legacy log without food_id
      final jsonLegacy = {
        'meal_type': 'breakfast',
        'name': 'Xôi Gà',
        'calories': 350,
      };
      final meal3 = MealDto.fromJson(jsonLegacy).toEntity();
      expect(meal3.foodId, '');
      expect(meal3.name, 'Xôi Gà');
    });
  });

  group('CP-NUTRITION-FOOD-IDENTITY-01: Recents & Favorites Identity Deduplication', () {
    test('Two foods with same name but DIFFERENT IDs are NOT merged or deduplicated', () async {
      final notifier = UsualFoodsNotifier(userId: 'test_user');

      final food1 = FoodModel(
        id: '650000000000000000000010',
        name: 'Phở Bò',
        calories: 450,
        protein: 25.0,
        carbs: 60.0,
        fat: 12.0,
        tags: const ['GLOBAL'],
      );
      final food2 = FoodModel(
        id: '650000000000000000000020',
        name: 'Phở Bò',
        calories: 550,
        protein: 35.0,
        carbs: 65.0,
        fat: 16.0,
        tags: ['CUSTOM'],
      );

      await notifier.recordRecent(food1);
      await notifier.recordRecent(food2);

      expect(notifier.state.recents.length, 2);
      expect(notifier.state.recents[0].id, '650000000000000000000020');
      expect(notifier.state.recents[1].id, '650000000000000000000010');
      expect(notifier.state.recents[0].name, 'Phở Bò');
      expect(notifier.state.recents[1].name, 'Phở Bò');
      expect(notifier.state.recents[0].calories, 550.0);
      expect(notifier.state.recents[1].calories, 450.0);
    });

    test('Upgrading legacy favorite reference replaces legacy key and preserves other favorites', () async {
      final notifier = UsualFoodsNotifier(userId: 'test_user');

      final legacyFav = UsualFoodItem(
        id: 'catalog_com_tam',
        name: 'Cơm Tấm',
        calories: 600,
        protein: 25,
        carbs: 80,
        fat: 20,
        lastUsedAt: DateTime(2026, 10, 1),
      );
      final stableFav = UsualFoodItem(
        id: '650000000000000000000099',
        name: 'Trứng Luộc',
        calories: 78,
        protein: 6.3,
        carbs: 0.6,
        fat: 5.3,
        lastUsedAt: DateTime(2026, 10, 2),
      );

      await mockPrefs.setString(
        UsualFoodsNotifier.favoritesKey('test_user'),
        jsonEncode([legacyFav.toJson(), stableFav.toJson()]),
      );

      await notifier.loadUsuals();
      expect(notifier.state.favorites.length, 2);
      expect(notifier.state.favoriteIds.contains('catalog_com_tam'), isTrue);
      expect(notifier.state.favoriteIds.contains('650000000000000000000099'), isTrue);

      final newCanonicalFood = FoodModel(
        id: '650000000000000000000088',
        name: 'Cơm Tấm',
        calories: 620,
        protein: 26,
        carbs: 82,
        fat: 21,
        tags: const [],
      );

      await notifier.upgradeLegacyReference(
        legacyId: 'catalog_com_tam',
        newFood: newCanonicalFood,
      );

      expect(notifier.state.favorites.length, 2);
      expect(notifier.state.favoriteIds.contains('catalog_com_tam'), isFalse);
      expect(notifier.state.favoriteIds.contains('650000000000000000000088'), isTrue);
      expect(notifier.state.favoriteIds.contains('650000000000000000000099'), isTrue);

      final storedRaw = mockPrefs.getString(UsualFoodsNotifier.favoritesKey('test_user'))!;
      final storedList = (jsonDecode(storedRaw) as List).cast<Map<String, dynamic>>();
      final ids = storedList.map((e) => e['id']).toList();
      expect(ids, contains('650000000000000000000088'));
      expect(ids, contains('650000000000000000000099'));
      expect(ids, isNot(contains('catalog_com_tam')));
    });
  });

  group('CP-NUTRITION-FOOD-IDENTITY-01: End-to-End Verification in FoodLogScreen', () {
    testWidgets('Valid stable ID resolves via getFoodById and saves reviewed snapshot without re-selection', (tester) async {
      final stableFood = FoodModel(
        id: '650000000000000000000001',
        name: 'Phở Bò Tái Chín',
        calories: 450,
        protein: 25.0,
        carbs: 60.0,
        fat: 12.0,
        tags: const ['PROTEIN'],
      );

      int getByIdCalls = 0;
      final mockService = _MockNutritionService(
        onSearch: (q, {limit = 20}) async => [],
        onGetById: (foodId) async {
          getByIdCalls++;
          if (foodId == '650000000000000000000001') {
            return const Food(
              id: '650000000000000000000001',
              name: 'Phở Bò Tái Chín',
              calories: 450,
              protein: 25.0,
              carbs: 60.0,
              fat: 12.0,
              tags: ['PROTEIN'],
            );
          }
          return null;
        },
      );

      final spyNutrition = _SpyNutritionNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => _TestProfileNotifier(userId: 'user_a@saman.app')),
            nutritionProvider.overrideWith((ref) => spyNutrition),
          ],
          child: MaterialApp(
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: FoodLogScreen(
              initialFood: stableFood,
              selectedDate: DateTime(2026, 10, 20),
              initialMealType: 'dinner',
              apiService: mockService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Portion review'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      expect(getByIdCalls, 1);
      expect(spyNutrition.addMealCalls, 1);
      final savedArgs = spyNutrition.recordedAddMealArgs.first;
      expect(savedArgs['foodId'], '650000000000000000000001');
      expect(savedArgs['name'], 'Phở Bò Tái Chín');
      expect(savedArgs['calories'], 450.0);
      expect(savedArgs['date'], DateTime(2026, 10, 20));
      expect(savedArgs['mealType'], 'dinner');

      final storedRecents = mockPrefs.getString(UsualFoodsNotifier.recentFoodsKey('user_a@saman.app'))!;
      expect(storedRecents, contains('650000000000000000000001'));
    });

    testWidgets('Food with 404 from getFoodById redirects to catalog re-selection with old name pre-filled', (tester) async {
      final missingFood = FoodModel(
        id: '650000000000000000000404',
        name: 'Món Đã Bị Xóa',
        calories: 300,
        protein: 15.0,
        carbs: 40.0,
        fat: 8.0,
        tags: const [],
      );

      final mockService = _MockNutritionService(
        onSearch: (q, {limit = 20}) async => [
          const Food(
            id: '650000000000000000000555',
            name: 'Món Thay Thế Mới',
            calories: 320,
            protein: 18.0,
            carbs: 38.0,
            fat: 9.0,
            tags: [],
          ),
        ],
        onGetById: (foodId) async => null,
      );

      final spyNutrition = _SpyNutritionNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => _TestProfileNotifier()),
            nutritionProvider.overrideWith((ref) => spyNutrition),
          ],
          child: MaterialApp(
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: FoodLogScreen(
              initialFood: missingFood,
              selectedDate: DateTime(2026, 11, 2),
              apiService: mockService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      expect(spyNutrition.addMealCalls, 0);

      expect(find.byKey(const Key('catalog_reselect_notice')), findsOneWidget);
      expect(find.text('Món Thay Thế Mới'), findsOneWidget);
      expect(find.textContaining('đã bị xóa'), findsNothing);
    });
  });
}

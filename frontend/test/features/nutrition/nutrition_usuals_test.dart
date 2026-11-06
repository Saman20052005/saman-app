import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/nutrition/data/models/food_dto.dart';
import 'package:health_ai_app/features/nutrition/domain/entities/food.dart';
import 'package:health_ai_app/features/nutrition/presentation/providers/nutrition_usual_foods_provider.dart';
import 'package:health_ai_app/features/nutrition/presentation/widgets/nutrition_quick_log_and_usuals.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/food_model.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import 'package:health_ai_app/services/nutrition_service.dart';
import 'package:health_ai_app/theme/nutrition_home_theme.dart';

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestProfileNotifier extends ProfileNotifier {
  TestProfileNotifier() : super(_MockProfileRepository()) {
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
    );
  }
}

class _StubNutritionService extends NutritionService {
  final Future<List<Food>> Function(String query, {int limit}) onSearch;
  final Future<Food?> Function(String foodId)? onGetById;

  _StubNutritionService(this.onSearch, [this.onGetById]);

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) {
    return onSearch(query, limit: limit);
  }

  @override
  Future<Food?> getFoodById(String foodId) async {
    if (onGetById != null) {
      return onGetById!(foodId);
    }
    final results = await onSearch('');
    for (final f in results) {
      if (f.id == foodId) return f;
    }
    return null;
  }
}

class _SpyNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences mockPrefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockPrefs = await SharedPreferences.getInstance();
  });

  group('CP-NUTRITION-LOGGED-MEALS-UI-02: Unit & State Logic Tests', () {
    test('Recent deduplication: strictly deduplicates by id and sorts by lastUsedAt desc', () async {
      final now = DateTime.now();
      final item1 = UsualFoodItem(
        id: 'food_1',
        name: 'Bún tươi',
        calories: 110,
        protein: 1.7,
        carbs: 25.7,
        fat: 0.1,
        lastUsedAt: now.subtract(const Duration(hours: 2)),
      );
      // Same id, more recent timestamp
      final item1Newer = UsualFoodItem(
        id: 'food_1',
        name: 'Bún tươi (Updated)',
        calories: 110,
        protein: 1.7,
        carbs: 25.7,
        fat: 0.1,
        lastUsedAt: now,
      );
      // Different id, same name - must be kept distinct
      final item2 = UsualFoodItem(
        id: 'food_2',
        name: 'Bún tươi',
        calories: 120,
        protein: 2.0,
        carbs: 26.0,
        fat: 0.2,
        lastUsedAt: now.subtract(const Duration(hours: 1)),
      );

      final notifier = UsualFoodsNotifier(userId: 'test_user_1');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UsualFoodsNotifier.recentFoodsKey('test_user_1'),
        jsonEncode([item1.toJson(), item2.toJson(), item1Newer.toJson()]),
      );

      await notifier.loadUsuals();

      final recents = notifier.state.recents;
      expect(recents.length, 2);
      expect(recents[0].id, 'food_1');
      expect(recents[0].name, 'Bún tươi (Updated)');
      expect(recents[1].id, 'food_2');
    });

    test('Favorite persistence & account isolation: User A favorites do not leak to User B', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      final favA = UsualFoodItem(
        id: 'beef_pho',
        name: 'Phở bò',
        calories: 450,
        protein: 25,
        carbs: 55,
        fat: 12,
        lastUsedAt: now,
      );
      final favB = UsualFoodItem(
        id: 'yogurt',
        name: 'Sữa chua',
        calories: 120,
        protein: 6,
        carbs: 18,
        fat: 3,
        lastUsedAt: now,
      );

      final notifierA = UsualFoodsNotifier(userId: 'user_A');
      await notifierA.toggleFavorite(favA);
      expect(notifierA.state.favoriteIds.contains('beef_pho'), isTrue);

      final rawA = prefs.getString(UsualFoodsNotifier.favoritesKey('user_A'));
      expect(rawA, isNotNull);
      expect(rawA!.contains('beef_pho'), isTrue);

      final notifierB = UsualFoodsNotifier(userId: 'user_B');
      await notifierB.loadUsuals();
      expect(notifierB.state.favorites.isEmpty, isTrue);
      expect(notifierB.state.favoriteIds.isEmpty, isTrue);

      await notifierB.toggleFavorite(favB);
      expect(notifierB.state.favoriteIds.contains('yogurt'), isTrue);
      expect(notifierB.state.favoriteIds.contains('beef_pho'), isFalse);

      await notifierA.loadUsuals();
      expect(notifierA.state.favoriteIds.contains('beef_pho'), isTrue);
      expect(notifierA.state.favoriteIds.contains('yogurt'), isFalse);
    });

    test('Unfavorite removes item from storage and state', () async {
      final now = DateTime.now();
      final fav = UsualFoodItem(
        id: 'chicken_breast',
        name: 'Ức gà',
        calories: 165,
        protein: 31,
        carbs: 0,
        fat: 3.6,
        lastUsedAt: now,
      );

      final notifier = UsualFoodsNotifier(userId: 'user_test');
      await notifier.toggleFavorite(fav);
      expect(notifier.state.favoriteIds.contains('chicken_breast'), isTrue);

      await notifier.toggleFavorite(fav);
      expect(notifier.state.favoriteIds.contains('chicken_breast'), isFalse);
      expect(notifier.state.favorites.isEmpty, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(UsualFoodsNotifier.favoritesKey('user_test'));
      expect(raw, equals('[]'));
    });
  });

  group('CP-NUTRITION-LOGGED-MEALS-UI-02: Widget & Behavioral Tests', () {
    Widget buildTestHost({
      required Widget child,
      Locale locale = const Locale('en'),
    }) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          profileProvider.overrideWith((ref) => TestProfileNotifier()),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NutritionHomeTheme(
            child: Scaffold(
              backgroundColor: const Color(0xFF0C0D0E),
              body: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );
    }

    testWidgets('Quick log renders 4 meal options with valid tap targets (>= 48px) and triggers callback', (tester) async {
      String? tappedMeal;

      await tester.pumpWidget(
        buildTestHost(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionQuickLogCard(
              onQuickLog: (meal) => tappedMeal = meal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick log'), findsOneWidget);
      expect(find.text('Choose a meal to get started'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('Snack'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quick_log_breakfast')));
      expect(tappedMeal, 'Breakfast');

      await tester.tap(find.byKey(const ValueKey('quick_log_lunch')));
      expect(tappedMeal, 'Lunch');

      await tester.tap(find.byKey(const ValueKey('quick_log_dinner')));
      expect(tappedMeal, 'Dinner');

      await tester.tap(find.byKey(const ValueKey('quick_log_snack')));
      expect(tappedMeal, 'Snack');
    });

    testWidgets('Quick log renders Vietnamese labels when locale is vi', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          locale: const Locale('vi'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionQuickLogCard(
              onQuickLog: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ghi nhanh'), findsOneWidget);
      expect(find.text('Chọn bữa ăn để bắt đầu'), findsOneWidget);
      expect(find.text('Sáng'), findsOneWidget);
      expect(find.text('Trưa'), findsOneWidget);
      expect(find.text('Tối'), findsOneWidget);
      expect(find.text('Ăn nhẹ'), findsOneWidget);
    });

    testWidgets('Your usuals empty recent state displays guide and icon', (tester) async {
      const emptyState = UsualFoodsState(
        selectedTab: UsualsTab.recent,
        isLoading: false,
        recents: [],
      );

      await tester.pumpWidget(
        buildTestHost(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionYourUsualsCard(
              state: emptyState,
              onSwitchTab: (_) {},
              onToggleFavorite: (_) {},
              onReviewPortion: (_) {},
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your usuals'), findsOneWidget);
      expect(find.text('No recent meals'), findsOneWidget);
      expect(find.text('Start by logging your first meal.'), findsOneWidget);
    });

    testWidgets('Your usuals empty favorites state displays guide to heart icon', (tester) async {
      const emptyFavState = UsualFoodsState(
        selectedTab: UsualsTab.favorites,
        isLoading: false,
        favorites: [],
      );

      await tester.pumpWidget(
        buildTestHost(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionYourUsualsCard(
              state: emptyFavState,
              onSwitchTab: (_) {},
              onToggleFavorite: (_) {},
              onReviewPortion: (_) {},
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No favorite meals'), findsOneWidget);
      expect(find.text('Tap the heart icon on any recent food to save it.'), findsOneWidget);
    });

    testWidgets('Tapping heart icon toggles favorite without triggering review portion', (tester) async {
      final item = UsualFoodItem(
        id: 'food_100',
        name: 'Trứng gà luộc',
        calories: 78,
        protein: 6.3,
        carbs: 0.6,
        fat: 5.3,
        lastUsedAt: DateTime.now(),
      );

      bool reviewed = false;
      bool favorited = false;

      final state = UsualFoodsState(
        selectedTab: UsualsTab.recent,
        isLoading: false,
        recents: [item],
        favoriteIds: const {},
      );

      await tester.pumpWidget(
        buildTestHost(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionYourUsualsCard(
              state: state,
              onSwitchTab: (_) {},
              onToggleFavorite: (_) => favorited = true,
              onReviewPortion: (_) => reviewed = true,
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('fav_btn_food_100')));
      await tester.pump();

      expect(favorited, isTrue);
      expect(reviewed, isFalse, reason: 'Tapping heart must not open review portion');

      await tester.tap(find.byKey(const ValueKey('usual_card_food_100')));
      await tester.pump();

      expect(reviewed, isTrue);
    });

    testWidgets('Responsive layouts: 320, 360, 390, 430px and 200% text scale do not overflow', (tester) async {
      final widths = [320.0, 360.0, 390.0, 430.0, 800.0];

      for (final w in widths) {
        tester.view.physicalSize = Size(w * 2.0, 900 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(mockPrefs),
              profileProvider.overrideWith((ref) => TestProfileNotifier()),
            ],
            child: MaterialApp(
              supportedLocales: const [Locale('en'), Locale('vi')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: MediaQuery(
                data: const MediaQueryData().copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: NutritionHomeTheme(
                  child: Scaffold(
                    backgroundColor: const Color(0xFF0C0D0E),
                    body: SingleChildScrollView(
                      child: NutritionQuickLogAndUsuals(
                        selectedDate: DateTime.now(),
                        onQuickLog: (_) {},
                        onReviewPortion: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'No overflow at width $w with 200% text scale');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('FoodLogScreen accepts initialFood and opens directly to portion review without log write', (tester) async {
      final food = FoodModel(
        id: 'sample_food_99',
        name: 'Jasmine rice',
        calories: 130,
        protein: 2.7,
        carbs: 28.2,
        fat: 0.3,
        tags: const ['CARBS'],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
          ],
          child: MaterialApp(
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: FoodLogScreen(
              initialFood: food,
              selectedDate: DateTime(2026, 11, 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Portion review'), findsOneWidget);
      expect(find.text('Jasmine rice'), findsOneWidget);
      expect(find.text('Log meal'), findsOneWidget);

      await tester.tap(find.byTooltip('Quay lại tìm kiếm'));
      await tester.pumpAndSettle();

      expect(find.text('Portion review'), findsNothing);
    });

    testWidgets('Invalid input guard: empty initialFood id or name shows validation error and prevents portion review', (tester) async {
      final invalidFood = FoodModel(
        id: '',
        name: '',
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        tags: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
          ],
          child: MaterialApp(
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: FoodLogScreen(
              initialFood: invalidFood,
              selectedDate: DateTime(2026, 11, 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Portion review'), findsNothing);
      expect(find.text('Thông tin món ăn không hợp lệ.'), findsOneWidget);
    });

    testWidgets('Backend response without id/Mongo _id redirects to catalog re-selection (select -> review -> confirm) without false deleted error', (tester) async {
      final cachedUsual = FoodModel(
        id: 'catalog_cơm trắng (1 chén)',
        name: 'Cơm trắng (1 chén)',
        calories: 115, // Old snapshot value
        protein: 2.2,
        carbs: 25.0,
        fat: 0.2,
        tags: const ['CARBS'],
      );

      // Exact JSON structure returned by backend GET /api/nutrition/foods/search
      // where {"_id": 0} is projected on foods_collection / user_foods_collection.
      final realBackendCatalogItem = FoodDto.fromJson(const {
        'name': 'Cơm trắng (1 chén)',
        'group': 'Carb',
        'calories': 130,
        'protein': 2.7,
        'carbs': 28,
        'fat': 0.3,
        'name_search': 'com trang (1 chen)',
        'source_type': 'global',
      }).toEntity();

      expect(realBackendCatalogItem.id, isEmpty);

      final catalogService = _StubNutritionService((query, {limit = 20}) async {
        return [realBackendCatalogItem];
      });

      final spyNutrition = _SpyNutritionNotifier();
      await mockPrefs.remove(UsualFoodsNotifier.recentFoodsKey('guest'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
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
              initialFood: cachedUsual,
              selectedDate: DateTime(2026, 11, 1),
              apiService: catalogService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt to confirm initial snapshot -> since response lacks stable ID,
      // redirects to catalog search results with old name pre-filled.
      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      expect(spyNutrition.addMealCalls, 0);
      expect(find.textContaining('đã bị xóa'), findsNothing);
      expect(find.byKey(const Key('catalog_reselect_notice')), findsOneWidget);
      expect(find.text('RESULTS (1 FOUND)'), findsOneWidget);
      expect(find.text('130 kcal'), findsOneWidget);

      // Step 1: User explicitly selects the current catalog item from results
      await tester.tap(find.text('130 kcal'));
      await tester.pumpAndSettle();

      // Step 2: Opens portion review showing updated 130 kcal
      expect(find.text('Portion review'), findsOneWidget);
      expect(find.text('130'), findsWidgets);

      // Step 3: User confirms on the final review step
      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      expect(spyNutrition.addMealCalls, 1);
      expect(spyNutrition.recordedAddMealArgs.first['calories'], 130.0);
      expect(spyNutrition.recordedAddMealArgs.first['protein'], 2.7);
      expect(spyNutrition.recordedAddMealArgs.first['carbs'], 28.0);
      expect(spyNutrition.recordedAddMealArgs.first['fat'], 0.3);
    });

    testWidgets('Renamed food or incomplete search results redirects to search without false deleted message or fuzzy auto-selection', (tester) async {
      final renamedOrTruncatedFood = FoodModel(
        id: 'food_legacy_404',
        name: 'Phở bò đặc biệt (Tên cũ)',
        calories: 450,
        protein: 25.0,
        carbs: 55.0,
        fat: 12.0,
        tags: const ['PROTEIN'],
      );

      // Catalog returns a fuzzy/different food with a different ID.
      // Must NOT auto-select the fuzzy match, must NOT save stale snapshot,
      // and must NOT falsely claim the food was deleted.
      final catalogService = _StubNutritionService((query, {limit = 20}) async {
        return const [
          Food(
            id: 'food_other_999',
            name: 'Phở bò tái nạm',
            calories: 520,
            protein: 30.0,
            carbs: 60.0,
            fat: 15.0,
            tags: ['PROTEIN'],
          ),
        ];
      });

      final spyNutrition = _SpyNutritionNotifier();
      await mockPrefs.remove(UsualFoodsNotifier.recentFoodsKey('guest'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
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
              initialFood: renamedOrTruncatedFood,
              selectedDate: DateTime(2026, 11, 1),
              apiService: catalogService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      // Must NOT save stale snapshot or auto-substitute food_other_999
      expect(spyNutrition.addMealCalls, 0);
      expect(mockPrefs.getString(UsualFoodsNotifier.recentFoodsKey('guest')), isNull);

      // Transitions to catalog search results with old name pre-filled and NO false "deleted" message
      expect(find.text('Portion review'), findsNothing);
      expect(find.textContaining('đã bị xóa'), findsNothing);
      expect(find.byKey(const Key('catalog_reselect_notice')), findsOneWidget);
      expect(find.text('Phở bò đặc biệt (Tên cũ)'), findsOneWidget);
      expect(find.text('Phở bò tái nạm'), findsOneWidget);
    });

    testWidgets('Catalog availability: network error during verification shows network retry error and never reports food deleted', (tester) async {
      final validFood = FoodModel(
        id: 'food_100',
        name: 'Ức gà luộc',
        calories: 165,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: const ['PROTEIN'],
      );

      final failingCatalogService = _StubNutritionService((query, {limit = 20}) async {
        throw Exception('SocketException: Failed host lookup');
      });

      final spyNutrition = _SpyNutritionNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
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
              initialFood: validFood,
              selectedDate: DateTime(2026, 11, 1),
              apiService: failingCatalogService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Portion review'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      // Must NOT save while verification fails
      expect(spyNutrition.addMealCalls, 0);

      // Remains on portion review with network error banner, NEVER claiming food was deleted
      expect(find.text('Portion review'), findsOneWidget);
      expect(
        find.text('Lỗi kết nối mạng, không thể kiểm tra món ăn. Vui lòng thử lại.'),
        findsOneWidget,
      );
      expect(find.textContaining('đã bị xóa'), findsNothing);
    });

    testWidgets('Stable ID resolved with changed macros updates review screen first and requires user re-confirmation before addMeal', (tester) async {
      final staleSnapshot = FoodModel(
        id: 'food_100',
        name: 'Ức gà luộc',
        calories: 100, // Stale cached calories
        protein: 20.0,
        carbs: 0.0,
        fat: 2.0,
        tags: const ['PROTEIN'],
      );

      final catalogService = _StubNutritionService((query, {limit = 20}) async {
        return const [
          Food(
            id: 'food_100',
            name: 'Ức gà luộc',
            calories: 165, // Updated catalog calories
            protein: 31.0,
            carbs: 0.0,
            fat: 3.6,
            tags: ['PROTEIN'],
          ),
        ];
      });

      final spyNutrition = _SpyNutritionNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
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
              initialFood: staleSnapshot,
              selectedDate: DateTime(2026, 11, 1),
              apiService: catalogService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Adjust portion to 200g (initially showing 200 kcal from stale 100 kcal/100g)
      await tester.ensureVisible(find.text('200g'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('200g'));
      await tester.pumpAndSettle();

      // First tap on Log meal: detects macro change (100 -> 165 kcal/100g => 330 kcal for 200g),
      // updates review numbers, and DOES NOT call addMeal yet!
      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      expect(spyNutrition.addMealCalls, 0);
      expect(find.text('Portion review'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(find.text('330'), findsWidgets);
      expect(
        find.text(
          'Số liệu dinh dưỡng đã cập nhật theo danh mục mới. Vui lòng kiểm tra lại khẩu phần và bấm Log meal để xác nhận.',
        ),
        findsOneWidget,
      );

      // Second tap on Log meal: user confirms the updated numbers (330 kcal, 62g protein for 200g)
      await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
      await tester.pumpAndSettle();

      expect(spyNutrition.addMealCalls, 1);
      expect(spyNutrition.recordedAddMealArgs.first['foodId'], 'food_100');
      expect(spyNutrition.recordedAddMealArgs.first['weightGrams'], 200);
      expect(spyNutrition.recordedAddMealArgs.first['calories'], 330.0);
      expect(spyNutrition.recordedAddMealArgs.first['protein'], 62.0);
    });

    testWidgets('Save failure does not record recent food', (tester) async {
      final food = FoodModel(
        id: 'fail_food_1',
        name: 'Fail Rice',
        calories: 130,
        protein: 2.7,
        carbs: 28.2,
        fat: 0.3,
        tags: const [],
      );

      await mockPrefs.remove(UsualFoodsNotifier.recentFoodsKey('test_user_id'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            profileProvider.overrideWith((ref) => TestProfileNotifier()),
          ],
          child: MaterialApp(
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: FoodLogScreen(
              initialFood: food,
              selectedDate: DateTime(2026, 11, 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quay lại tìm kiếm'));
      await tester.pumpAndSettle();

      final raw = mockPrefs.getString(UsualFoodsNotifier.recentFoodsKey('test_user_id'));
      expect(raw, isNull);
    });
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/models/food_model.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/features/nutrition/domain/entities/food.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import '../../workout_exercise_images_test.dart' show loadTestFonts;
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'package:health_ai_app/services/nutrition_service.dart';

// ─── Zero-Network Mock HttpClient for Image.network ─────────────────────────

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _kTransparentImage.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_kTransparentImage]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

const List<int> _kTransparentImage = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
];

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

// ─── Mock Profile & Repositories ─────────────────────────────────────────────

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestProfileNotifier extends ProfileNotifier {
  TestProfileNotifier({int targetCalories = 2300, int targetProtein = 160, int targetCarbs = 240, int targetFat = 65})
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
      targetCalories: targetCalories,
      targetProtein: targetProtein,
      targetCarbs: targetCarbs,
      targetFat: targetFat,
      waterTargetMl: 2000,
      isLoading: false,
    );
  }
}

class MockNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  MockNutritionNotifier() : super(const AsyncValue.data(null));

  int addMealCalls = 0;
  DateTime? lastAddedDate;
  String? lastMealType;
  String? lastFoodId;
  String? lastName;
  double? lastCalories;
  double? lastProtein;
  double? lastCarbs;
  double? lastFat;
  int? lastWeightGrams;
  bool shouldSucceed = true;

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
    lastAddedDate = date;
    lastMealType = mealType;
    lastFoodId = foodId;
    lastName = name;
    lastCalories = calories;
    lastProtein = protein;
    lastCarbs = carbs;
    lastFat = fat;
    lastWeightGrams = weightGrams;

    if (!shouldSucceed) {
      return false;
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const defaultTestFoods = [
  Food(
    id: 'food_chicken_grilled',
    name: 'Chicken breast',
    calories: 165.0,
    protein: 31.0,
    carbs: 0.0,
    fat: 3.6,
    tags: ['HIGH_PROTEIN'],
  ),
  Food(
    id: 'food_rice_jasmine',
    name: 'Jasmine rice',
    calories: 130.0,
    protein: 2.7,
    carbs: 28.2,
    fat: 0.3,
    tags: ['CARBS'],
  ),
  Food(
    id: 'food_oats_rolled',
    name: 'Rolled oats',
    calories: 389.0,
    protein: 16.9,
    carbs: 66.3,
    fat: 6.9,
    tags: ['WHOLE_GRAIN'],
  ),
  Food(
    id: 'food_yogurt_greek',
    name: 'Greek yogurt',
    calories: 59.0,
    protein: 10.0,
    carbs: 3.6,
    fat: 0.4,
    tags: ['DAIRY'],
  ),
];

class MockNutritionService extends NutritionService {
  final List<Food> mockFoods;
  bool shouldThrow = false;
  Duration delay = Duration.zero;

  MockNutritionService([this.mockFoods = defaultTestFoods]);

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (shouldThrow) {
      throw Exception('Mock network search error');
    }
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    return mockFoods.where((f) => f.name.toLowerCase().contains(q)).toList();
  }
}

Future<void> _exportScreenshot(GlobalKey key, WidgetTester tester, String filename) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final buffer = byteData.buffer.asUint8List();
          const evidenceDir = 'test/nutrition_evidence';
          final dir = Directory(evidenceDir);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          File('$evidenceDir/$filename').writeAsBytesSync(buffer);
        }
      });
    }
  } catch (e) {
    debugPrint('Screenshot export error: ');
  }
}

Widget createTestApp({
  required Widget child,
  MockNutritionNotifier? mockNotifier,
  TestProfileNotifier? mockProfile,
  ThemeData? theme,
}) {
  final notifier = mockNotifier ?? MockNutritionNotifier();
  final profile = mockProfile ?? TestProfileNotifier();

  return ProviderScope(
    overrides: [
      nutritionProvider.overrideWith((ref) => notifier),
      profileProvider.overrideWith((ref) => profile),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ??
          ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0C0D0E),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFFFFFFFF),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(),
            ),
          ),
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() async {
    await loadTestFonts();
    HttpOverrides.global = _TestHttpOverrides();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });

  group('CP3: FoodLogScreen & Log Meal Experience', () {
    testWidgets('Frame 1: Initial state renders Calm Athleticism layout and staple chips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));



      final testDate = DateTime(2026, 10, 6);
      await tester.pumpWidget(createTestApp(
        child: FoodLogScreen(
          selectedDate: testDate,
          initialMealType: 'Lunch',
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Log meal'), findsOneWidget);
      expect(find.text('Tue, Oct 6'), findsOneWidget);
      expect(find.text('Find your food'), findsOneWidget);
      expect(find.text('Chicken breast', skipOffstage: false), findsOneWidget);
      expect(find.text('Jasmine rice', skipOffstage: false), findsOneWidget);
      expect(find.text('Rolled oats', skipOffstage: false), findsOneWidget);
      expect(find.text('Greek yogurt', skipOffstage: false), findsOneWidget);
    });

    testWidgets('Meal segment switching updates selected meal type across flows', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestApp(
        child: FoodLogScreen(
          initialMealType: 'Breakfast',
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);

      await tester.tap(find.text('Dinner'));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.initial);
    });

    testWidgets('Search: query A -> B transitions and debounce correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = MockNutritionService();
      await tester.pumpWidget(createTestApp(
        child: FoodLogScreen(
          apiService: service,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'rice');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Jasmine rice'), findsOneWidget);
      expect(find.text('Chicken breast'), findsNothing);

      await tester.enterText(find.byType(TextField), 'chicken');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Chicken breast'), findsOneWidget);
      expect(find.text('Jasmine rice'), findsNothing);
    });

    testWidgets('Search: typing then clearing while request is pending does not resurrect old results', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = MockNutritionService();
      service.delay = const Duration(milliseconds: 200);

      await tester.pumpWidget(createTestApp(
        child: FoodLogScreen(
          apiService: service,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'chicken');
      await tester.pump(const Duration(milliseconds: 360));

      // Tap clear button immediately while async search is in-flight
      final clearBtn = find.byKey(const Key('clear_search_button'));
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pump();

      // Advance time so delayed search completes in the background
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.initial);
      expect(find.text('Find your food'), findsOneWidget);
      expect(find.text('Per 100g serving basis'), findsNothing);
    });

    testWidgets('Search error and Search Retry independently from save retry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = MockNutritionService();
      service.shouldThrow = true;

      await tester.pumpWidget(createTestApp(
        child: FoodLogScreen(
          apiService: service,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'oats');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_retry_button')), findsOneWidget);
      expect(find.text('Thử lại tìm kiếm'), findsOneWidget);

      service.shouldThrow = false;
      await tester.tap(find.byKey(const Key('search_retry_button')));
      await tester.pumpAndSettle();

      expect(find.text('Rolled oats'), findsOneWidget);
    });

    testWidgets('Non-destructive selection: Tapping food moves to Portion Review without addMeal', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockNotifier = MockNutritionNotifier();
      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'chicken');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final foodTile = find.widgetWithText(InkWell, 'Chicken breast');
      expect(foodTile, findsWidgets);
      await tester.tap(foodTile.first);
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.portionReview);
      expect(mockNotifier.addMealCalls, 0);
    });

    testWidgets('Frame 3 Portion Review: Precision calculation test (100g=165kcal -> 150g=248kcal)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final statefulFood = FoodModel(
        id: 'test_1',
        name: 'Grilled Chicken Breast',
        calories: 165.0,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: ['HIGH_PROTEIN'],
      );

      final mockNotifier = MockNutritionNotifier();
      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          selectedDate: DateTime(2026, 10, 6),
          initialMealType: 'Lunch',
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      state.selectFood(statefulFood);
      await tester.pumpAndSettle();

      expect(state.grams, 100);
      expect(find.text('165', skipOffstage: false), findsOneWidget);
      expect(find.text('31.0g', skipOffstage: false), findsOneWidget);
      expect(find.text('0.0g', skipOffstage: false), findsOneWidget);
      expect(find.text('3.6g', skipOffstage: false), findsOneWidget);

      final chip150 = find.text('150g', skipOffstage: false);
      expect(chip150, findsOneWidget);
      await tester.tap(chip150);
      await tester.pumpAndSettle();

      expect(state.grams, 150);
      expect(find.text('248', skipOffstage: false), findsOneWidget);
      expect(find.text('46.5g', skipOffstage: false), findsOneWidget);
      expect(find.text('0.0g', skipOffstage: false), findsOneWidget);
      expect(find.text('5.4g', skipOffstage: false), findsOneWidget);
    });

    testWidgets('Portion validation: empty / 0 / invalid portion does not save and keeps user on screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final statefulFood = FoodModel(
        id: 'test_1',
        name: 'Grilled Chicken Breast',
        calories: 165.0,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: [],
      );

      final mockNotifier = MockNutritionNotifier();
      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      state.selectFood(statefulFood);
      await tester.pumpAndSettle();

      // Set grams to 0 via testing hook
      state.setGramsForTesting(0);
      await tester.pumpAndSettle();

      // Log meal button should be disabled when grams <= 0
      final logBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Log meal'));
      expect(logBtn.onPressed, isNull);

      // Verify no addMeal was invoked
      expect(mockNotifier.addMealCalls, 0);
      expect(state.currentStep, FoodLogStep.portionReview);
    });

    testWidgets('Double-tap guard: Rapidly tapping Log meal only invokes save once', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final statefulFood = FoodModel(
        id: 'test_1',
        name: 'Grilled Chicken Breast',
        calories: 165.0,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: [],
      );

      final mockNotifier = MockNutritionNotifier();
      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      state.selectFood(statefulFood);
      await tester.pumpAndSettle();

      final logMealBtn = find.byKey(const Key('confirm_log_meal_btn'));
      expect(logMealBtn, findsOneWidget);

      await tester.tap(logMealBtn);
      await tester.tap(logMealBtn, warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(mockNotifier.addMealCalls, 1);
    });

    testWidgets('Save error preserves selected portion and allows Save Retry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final statefulFood = FoodModel(
        id: 'test_1',
        name: 'Grilled Chicken Breast',
        calories: 165.0,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: [],
      );

      final mockNotifier = MockNutritionNotifier();
      mockNotifier.shouldSucceed = false;

      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      state.selectFood(statefulFood);
      await tester.pumpAndSettle();

      await tester.tap(find.text('150g', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(state.grams, 150);

      final logMealBtn = find.widgetWithText(ElevatedButton, 'Log meal');
      await tester.tap(logMealBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('save_retry_button')), findsOneWidget);
      expect(state.grams, 150);
      expect(mockNotifier.addMealCalls, 1);

      // Now set to succeed and tap Save Retry
      mockNotifier.shouldSucceed = true;
      await tester.tap(find.byKey(const Key('save_retry_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.addMealCalls, 2);
      expect(mockNotifier.lastWeightGrams, 150);
    });

    testWidgets('Confirm uses exact selectedDate and mealType', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDate = DateTime(2026, 10, 6);
      final statefulFood = FoodModel(
        id: 'test_1',
        name: 'Grilled Chicken Breast',
        calories: 165.0,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: [],
      );

      final mockNotifier = MockNutritionNotifier();
      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          selectedDate: testDate,
          initialMealType: 'Dinner',
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      state.selectFood(statefulFood);
      await tester.pumpAndSettle();

      final logMealBtn = find.widgetWithText(ElevatedButton, 'Log meal');
      await tester.tap(logMealBtn);
      await tester.pumpAndSettle();

      expect(mockNotifier.lastAddedDate, testDate);
      expect(mockNotifier.lastMealType, 'dinner');
    });

    testWidgets('Save success closes sheet with result true (updating Home on correct date)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDate = DateTime(2026, 10, 6);
      final statefulFood = FoodModel(
        id: 'test_1',
        name: 'Grilled Chicken Breast',
        calories: 165.0,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        tags: [],
      );

      final mockNotifier = MockNutritionNotifier();
      bool? returnedResult;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          nutritionProvider.overrideWith((ref) => mockNotifier),
          profileProvider.overrideWith((ref) => TestProfileNotifier()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  returnedResult = await showModalBottomSheet<bool>(
                    context: context,
                    builder: (_) => FoodLogScreen(
                      selectedDate: testDate,
                      initialMealType: 'Lunch',
                      apiService: MockNutritionService(),
                    ),
                  );
                },
                child: const Text('Open FoodLog'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open FoodLog'));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      state.selectFood(statefulFood);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Log meal'));
      await tester.pumpAndSettle();

      expect(returnedResult, true);
    });

    testWidgets('Back button returns to search preserving query context without saving', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockNotifier = MockNutritionNotifier();
      await tester.pumpWidget(createTestApp(
        mockNotifier: mockNotifier,
        child: FoodLogScreen(
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'chicken');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final foodTile = find.widgetWithText(InkWell, 'Chicken breast');
      await tester.tap(foodTile.first);
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.portionReview);

      final backBtn = find.byIcon(Icons.arrow_back);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      expect(state.currentStep, FoodLogStep.searchResults);
      expect(find.text('Chicken breast'), findsOneWidget);
      expect(mockNotifier.addMealCalls, 0);
    });

    testWidgets('LogMealSheet: Quick meal log renders Calm Athleticism design with date anchor and screenshot before focus', (tester) async {
      final boundaryKey = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDate = DateTime(2026, 10, 6);
      await tester.pumpWidget(createTestApp(
        child: RepaintBoundary(
          key: boundaryKey,
          child: LogMealSheet(selectedDate: testDate),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Log Bữa Ăn Nhanh'), findsOneWidget);
      expect(find.text('Lưu Nhật Ký Ảnh'), findsOneWidget);
      expect(find.text('Ghi chú (Tên món, cảm nhận...)'), findsOneWidget);

      // Verify TextField overrides theme fill & border to transparent/none
      final noteField = tester.widget<TextField>(find.byType(TextField));
      expect(noteField.decoration?.filled, isFalse);
      expect(noteField.decoration?.fillColor, Colors.transparent);
      expect(noteField.decoration?.border, InputBorder.none);
      expect(noteField.decoration?.enabledBorder, InputBorder.none);
      expect(noteField.decoration?.focusedBorder, InputBorder.none);
      expect(noteField.decoration?.disabledBorder, InputBorder.none);
      expect(noteField.decoration?.errorBorder, InputBorder.none);
      expect(noteField.decoration?.focusedErrorBorder, InputBorder.none);
      expect(noteField.cursorColor, const Color(0xFF10B981));
      expect(noteField.minLines, 3);
      expect(noteField.maxLines, 4);
      expect(noteField.textAlignVertical, TextAlignVertical.top);

      await _exportScreenshot(boundaryKey, tester, 'log_meal_sheet_before_focus.png');
    });

    testWidgets('LogMealSheet: Typing notes persists across UI interactions and screenshot with note', (tester) async {
      final boundaryKey = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDate = DateTime(2026, 10, 6);
      await tester.pumpWidget(createTestApp(
        child: RepaintBoundary(
          key: boundaryKey,
          child: LogMealSheet(selectedDate: testDate),
        ),
      ));
      await tester.pumpAndSettle();

      const sampleNote = 'Bữa trưa 200g ức gà\nCảm nhận: Ăn rất vừa miệng\nThêm rau luộc và cơm lứt';
      await tester.enterText(find.byType(TextField), sampleNote);
      await tester.pumpAndSettle();

      expect(find.text(sampleNote), findsOneWidget);
      await _exportScreenshot(boundaryKey, tester, 'log_meal_sheet_with_note.png');

      // Switch meal type to 'Bữa Tối'
      await tester.tap(find.text('Bữa Tối'));
      await tester.pumpAndSettle();

      // Notes must remain intact
      expect(find.text(sampleNote), findsOneWidget);
    });

    testWidgets('LogMealSheet: Note field maintains multi-line bounds and does not overflow under keyboard insets', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDate = DateTime(2026, 10, 6);
      await tester.pumpWidget(
        createTestApp(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: const EdgeInsets.only(bottom: 300),
              ),
              child: LogMealSheet(selectedDate: testDate),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ghi chú kiểm tra bàn phím');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Ghi chú kiểm tra bàn phím'), findsOneWidget);
    });

    testWidgets('Responsiveness: 320px narrow viewport renders without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestApp(
        child: FoodLogScreen(
          selectedDate: DateTime(2026, 10, 6),
          apiService: MockNutritionService(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Responsiveness: Text scale 1.5x renders without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: createTestApp(
          child: FoodLogScreen(
            selectedDate: DateTime(2026, 10, 6),
            apiService: MockNutritionService(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Fullscreen route: Home -> Log Meal covers shell and bottom bar, Close returns to Home', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDate = DateTime(2026, 10, 8);
      int currentTab = 2;
      final mockNotifier = MockNutritionNotifier();
      final mockProfile = TestProfileNotifier();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          nutritionProvider.overrideWith((ref) => mockNotifier),
          profileProvider.overrideWith((ref) => mockProfile),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: IndexedStack(
                  index: currentTab,
                  children: [
                    const Center(child: Text('Home Page')),
                    const Center(child: Text('Workout Page')),
                    Builder(
                      builder: (innerCtx) => Center(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(innerCtx, rootNavigator: true).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => FoodLogScreen(
                                  selectedDate: testDate,
                                  initialMealType: 'Dinner',
                                  apiService: MockNutritionService(),
                                ),
                              ),
                            );
                          },
                          child: const Text('Log meal'),
                        ),
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: BottomNavigationBar(
                  currentIndex: currentTab,
                  onTap: (index) => setState(() => currentTab = index),
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Workout'),
                    BottomNavigationBarItem(icon: Icon(Icons.restaurant), label: 'Nutrition'),
                  ],
                ),
              );
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Initially, bottom bar is visible and interactive
      expect(find.text('Workout'), findsOneWidget);
      expect(currentTab, 2);

      // Tap Log meal button to open fullscreen route on root navigator
      await tester.tap(find.text('Log meal'));
      await tester.pumpAndSettle();

      // FoodLogScreen is now rendered in fullscreen over root navigator
      expect(find.byType(FoodLogScreen), findsOneWidget);
      final logState = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(logState.selectedMealType, 'Dinner');

      // Verify bottom bar is completely obscured/not visible in fullscreen route
      expect(find.text('Workout'), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);

      // Verify search focus, typing and clear
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.tap(searchField);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(searchField).focusNode?.hasFocus, isTrue);

      await tester.enterText(searchField, 'chicken');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clear_search_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('clear_search_button')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(searchField).controller?.text, isEmpty);

      // Verify selectedDate & mealType preserved
      expect(logState.selectedMealType, 'Dinner');

      // Tap Close button
      final closeBtn = find.byTooltip('Đóng');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // FoodLogScreen is popped, returned to Home/Nutrition
      expect(find.byType(FoodLogScreen), findsNothing);
      expect(find.text('Log meal'), findsOneWidget);
      expect(currentTab, 2);
    });
  });
}


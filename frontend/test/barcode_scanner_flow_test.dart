import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import 'package:health_ai_app/features/nutrition/domain/entities/food.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/models/food_model.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import 'package:health_ai_app/screens/nutrition/barcode_scanner_screen.dart';
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'package:health_ai_app/services/nutrition_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'workout_exercise_images_test.dart' show loadTestFonts;

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestProfileNotifier extends ProfileNotifier {
  _TestProfileNotifier() : super(_MockProfileRepository()) {
    state = ProfileState(
      profile: const ProfileEntity(
        age: 26,
        gender: Gender.male,
        height: 175,
        weight: 70,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      ),
      targetCalories: 2200,
      targetProtein: 150,
      targetCarbs: 240,
      targetFat: 70,
      waterTargetMl: 2000,
      isLoading: false,
    );
  }
}

class _TestNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _TestNutritionNotifier() : super(const AsyncValue.data(null));

  int addMealCalls = 0;
  String? lastMealType;
  String? lastFoodId;
  String? lastName;
  double? lastCalories;
  double? lastProtein;
  double? lastCarbs;
  double? lastFat;
  int? lastWeightGrams;

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
    lastMealType = mealType;
    lastFoodId = foodId;
    lastName = name;
    lastCalories = calories;
    lastProtein = protein;
    lastCarbs = carbs;
    lastFat = fat;
    lastWeightGrams = weightGrams;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockNutritionRepository extends Mock implements INutritionRepository {}

class _MockNutritionService extends Mock implements NutritionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadTestFonts();
    registerFallbackValue(XFile('fallback.jpg'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P1.1 ExerciseLibraryScreen - no coming soon & Equipment filter', () {
    for (final entry in <String, ThemeData Function()>{
      'Light': SamanTheme.light,
      'Dark': SamanTheme.dark,
    }.entries) {
      testWidgets(
          '${entry.key} theme: no coming soon text and Equipment filter works accurately',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              exerciseLibraryListProvider
                  .overrideWith((ref) async => curatedExerciseLibrary),
            ],
            child: MaterialApp(
              theme: entry.value(),
              home: const ExerciseLibraryScreen(initialCategory: 'All'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);

        void assertNoComingSoon() {
          final texts = tester.widgetList<Text>(find.byType(Text));
          for (final w in texts) {
            final value = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
            expect(value.contains('coming soon'), isFalse,
                reason: 'Found unexpected "coming soon" text: $value');
          }
        }

        assertNoComingSoon();

        // Filter by Dumbbells using the Equipment chip
        final equipChip = find.byKey(const Key('exercise_equipment_chip'));
        await tester.ensureVisible(equipChip);
        await tester.pump();
        await tester.tap(equipChip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const Key('equipment_option_Dumbbells')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Dumbbell Bench Press'), findsOneWidget);
        expect(find.text('Barbell Back Squat'), findsNothing);
        expect(find.text('Plank'), findsNothing);
        assertNoComingSoon();

        // Filter by Barbell using the Icons.tune button
        await tester.tap(find.byKey(const Key('exercise_filter_tune_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const Key('equipment_option_Barbell')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Barbell Back Squat'), findsOneWidget);
        expect(find.text('Dumbbell Bench Press'), findsNothing);
        assertNoComingSoon();

        // Switch to Core while Barbell filter is active -> honest empty state, no "coming soon"
        final coreTab = find.text('Core');
        await tester.ensureVisible(coreTab);
        await tester.pump();
        await tester.tap(coreTab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('No exercises match this filter'), findsOneWidget);
        expect(
          find.text('Try clearing your search or equipment filter.'),
          findsOneWidget,
        );
        assertNoComingSoon();

        // Clear filters via empty state action and verify Core exercises appear
        await tester.tap(find.text('Clear filters'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Plank'), findsOneWidget);
        assertNoComingSoon();

        // Filter by Bodyweight
        await tester.ensureVisible(equipChip);
        await tester.pump();
        await tester.tap(equipChip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('equipment_option_Bodyweight')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Plank'), findsOneWidget);
        expect(find.text('Cable Woodchopper'), findsNothing);
      });
    }
  });

  group('P1.2 FoodLogScreen - BarcodeLookupResult portionReview & themes', () {
    const scannedFood = Food(
      id: 'off_8934563138165',
      name: 'Sữa tươi Vinamilk ít đường',
      calories: 60.0,
      protein: 3.0,
      carbs: 4.8,
      fat: 3.2,
      tags: ['barcode', 'open_food_facts'],
    );

    const barcodeResult = BarcodeLookupResult(
      food: scannedFood,
      barcode: '8934563138165',
      brand: 'Vinamilk',
      servingSize: '180 ml',
      suggestedGrams: 180,
      source: 'open_food_facts',
    );

    for (final entry in <String, ThemeData Function()>{
      'Light': SamanTheme.light,
      'Dark': SamanTheme.dark,
    }.entries) {
      testWidgets(
          '${entry.key} theme: FoodLogScreen applies BarcodeLookupResult into portionReview with scaled macros and no overflow',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final nutritionNotifier = _TestNutritionNotifier();
        final profileNotifier = _TestProfileNotifier();
        final mockService = _MockNutritionService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              nutritionProvider.overrideWith((ref) => nutritionNotifier),
              profileProvider.overrideWith((ref) => profileNotifier),
            ],
            child: MaterialApp(
              theme: entry.value(),
              home: FoodLogScreen(
                selectedDate: DateTime(2026, 11, 20),
                initialMealType: 'Snack',
                apiService: mockService,
                onScanBarcode: (_) async => barcodeResult,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('barcode_scan_button')), findsOneWidget);
        expect(
          find.byKey(const Key('barcode_quick_action_button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('barcode_scan_button')));
        await tester.pumpAndSettle();

        final state =
            tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
        expect(state.currentStep, FoodLogStep.portionReview);
        expect(state.grams, 180);

        // 60 kcal/100g * 180g = 108 kcal
        expect(find.text('108'), findsOneWidget);
        // 3.0g * 1.8 = 5.4g protein, 4.8g * 1.8 = 8.6g carbs, 3.2g * 1.8 = 5.8g fat
        expect(find.text('5.4g'), findsOneWidget);
        expect(find.text('8.6g'), findsOneWidget);
        expect(find.text('5.8g'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('confirm_log_meal_btn')));
        await tester.pumpAndSettle();

        expect(nutritionNotifier.addMealCalls, 1);
        expect(nutritionNotifier.lastWeightGrams, 180);
        expect(nutritionNotifier.lastCalories, closeTo(108.0, 0.01));
        expect(nutritionNotifier.lastProtein, closeTo(5.4, 0.01));
      });
    }

    testWidgets(
        'FoodLogScreen with initialFood & initialGrams renders portionReview cleanly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final nutritionNotifier = _TestNutritionNotifier();
      final profileNotifier = _TestProfileNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionProvider.overrideWith((ref) => nutritionNotifier),
            profileProvider.overrideWith((ref) => profileNotifier),
          ],
          child: MaterialApp(
            theme: SamanTheme.light(),
            home: FoodLogScreen(
              selectedDate: DateTime(2026, 11, 20),
              initialMealType: 'Breakfast',
              initialFood: FoodModel(
                id: 'off_123',
                name: 'Granola Bar',
                calories: 400,
                protein: 10,
                carbs: 60,
                fat: 12,
                tags: const ['barcode'],
              ),
              initialGrams: 50,
              isInitialFoodVerified: true,
              apiService: _MockNutritionService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.portionReview);
      expect(state.grams, 50);
      expect(find.text('200'), findsOneWidget); // 400 * 50 / 100
      expect(tester.takeException(), isNull);
    });
  });

  group('P1.2 BarcodeScannerScreen & LogMealSheet flow', () {
    testWidgets(
        'BarcodeScannerScreen handles BarcodeNotFoundException -> AI label -> 403 opens UpgradeBottomSheet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockRepo = _MockNutritionRepository();
      when(() => mockRepo.lookupBarcode('8930000000001')).thenThrow(
        const BarcodeNotFoundException(
          '8930000000001',
          'Sản phẩm chưa có trên Open Food Facts.',
        ),
      );
      when(() => mockRepo.analyzeNutritionLabel(
            barcode: '8930000000001',
            imageFile: any(named: 'imageFile'),
          )).thenThrow(
        DioException(
          requestOptions:
              RequestOptions(path: '/api/nutrition/barcode/analyze-label'),
          response: Response(
            requestOptions:
                RequestOptions(path: '/api/nutrition/barcode/analyze-label'),
            statusCode: 403,
            data: {'detail': 'Plus membership required'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: BarcodeScannerScreen(
              repository: mockRepo,
              enableCamera: false,
              imagePicker: (_) async => XFile('label.jpg'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manual_barcode_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('manual_barcode_input')),
        '8930000000001',
      );
      await tester.tap(find.byKey(const Key('manual_barcode_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('barcode_not_found_panel')), findsOneWidget);
      expect(find.byKey(const Key('ai_analyze_label_button')), findsOneWidget);
      expect(
        find.byKey(const Key('scan_another_barcode_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ai_analyze_label_button')));
      await tester.pumpAndSettle();

      expect(find.byType(UpgradeBottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'LogMealSheet Quét Barcode button navigates to FoodLogScreen portionReview',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final nutritionNotifier = _TestNutritionNotifier();
      final profileNotifier = _TestProfileNotifier();

      const scannedResult = BarcodeLookupResult(
        food: Food(
          id: 'off_555',
          name: 'Yến mạch Quaker',
          calories: 380,
          protein: 13,
          carbs: 67,
          fat: 7,
          tags: ['barcode'],
        ),
        barcode: '030000010204',
        suggestedGrams: 40,
        source: 'open_food_facts',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionProvider.overrideWith((ref) => nutritionNotifier),
            profileProvider.overrideWith((ref) => profileNotifier),
          ],
          child: MaterialApp(
            theme: SamanTheme.light(),
            home: Scaffold(
              body: LogMealSheet(
                selectedDate: DateTime(2026, 11, 20),
                onScanBarcode: (_) async => scannedResult,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('log_meal_sheet_barcode_btn'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byType(FoodLogScreen), findsOneWidget);
      final state =
          tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.portionReview);
      expect(state.grams, 40);
      expect(find.text('152'), findsOneWidget); // 380 * 40 / 100
      expect(tester.takeException(), isNull);
    });
  });
}


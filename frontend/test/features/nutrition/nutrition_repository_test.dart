import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:health_ai_app/features/nutrition/data/datasources/nutrition_remote_data_source.dart';
import 'package:health_ai_app/features/nutrition/data/repositories/nutrition_repository_impl.dart';

class MockNutritionRemoteDataSource extends Mock
    implements INutritionRemoteDataSource {}

void main() {
  late MockNutritionRemoteDataSource mockRemoteDataSource;
  late NutritionRepositoryImpl repository;

  setUp(() {
    mockRemoteDataSource = MockNutritionRemoteDataSource();
    repository =
        NutritionRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  group('NutritionRepositoryImpl - generatePlan contract tests', () {
    test('1. Throws ArgumentError when dateStr is missing or empty (no fallback to DateTime.now())',
        () async {
      // Empty string
      expect(
        () => repository.generatePlan(dateStr: '', goal: 'maintain'),
        throwsArgumentError,
      );

      // Whitespace only
      expect(
        () => repository.generatePlan(dateStr: '   ', goal: 'maintain'),
        throwsArgumentError,
      );

      verifyZeroInteractions(mockRemoteDataSource);
    });

    test('2. Ngày chưa log: meals từ generate-plan, consumed và entries là 0/rỗng (không lấy planned calories làm consumed)',
        () async {
      const dateStr = '2026-10-08';

      // Remote generatePlan returns planned meals with 2200 planned calories
      when(() => mockRemoteDataSource.generatePlan(
            goal: 'maintain',
            targetCalories: 0,
            mealCount: null,
            style: null,
            remainingOnly: false,
          )).thenAnswer((_) async => {
            'plan': {
              'date': '2026-10-08',
              'total_calories': 2200,
              'meals': [
                {
                  'food_id': 'm1',
                  'name': 'Oatmeal & Berries',
                  'calories': 400,
                  'protein': 15.0,
                  'carbs': 65.0,
                  'fat': 8.0,
                  'weight_grams': 250,
                  'meal_type': 'breakfast',
                  'time': '08:00',
                },
                {
                  'food_id': 'm2',
                  'name': 'Grilled Chicken Bowl',
                  'calories': 700,
                  'protein': 55.0,
                  'carbs': 60.0,
                  'fat': 18.0,
                  'weight_grams': 400,
                  'meal_type': 'lunch',
                  'time': '12:30',
                },
              ],
            },
            'macro_targets': {
              'calories': 2200,
              'protein': 140.0,
              'carbs': 250.0,
              'fat': 65.0,
            },
          });

      // Remote getDailyPlan returns 0 intake and empty entries for unlogged day
      when(() => mockRemoteDataSource.getDailyPlan(dateStr))
          .thenAnswer((_) async => {
                'date': dateStr,
                'entries': [],
                'total_calories': 0,
                'total_protein': 0.0,
                'total_carbs': 0.0,
                'total_fat': 0.0,
                'current_water': 0,
                'water_target': 2000,
                'rollover_calories': 0,
              });

      final result = await repository.generatePlan(
        dateStr: dateStr,
        goal: 'maintain',
      );

      // Meals come from generate-plan
      expect(result.meals.length, 2);
      expect(result.meals.first.name, 'Oatmeal & Berries');

      // Actual consumed metrics come from getDailyPlan (0, NOT 2200)
      expect(result.entries, isEmpty);
      expect(result.totalCaloriesConsumed, 0);
      expect(result.totalProteinConsumed, 0);
      expect(result.totalCarbsConsumed, 0);
      expect(result.totalFatConsumed, 0);
      expect(result.currentWater, 0);
      expect(result.date, dateStr);
    });

    test('3. Ngày đã log: meals từ generate-plan, bảo toàn entries và consumed từ GET daily',
        () async {
      const dateStr = '2026-10-08';

      // Remote generatePlan returns new AI meal suggestions
      when(() => mockRemoteDataSource.generatePlan(
            goal: 'weight_loss',
            targetCalories: 1800,
            mealCount: 3,
            style: 'optimal',
            remainingOnly: true,
          )).thenAnswer((_) async => {
            'plan': {
              'date': '2026-10-08',
              'total_calories': 1800,
              'meals': [
                {
                  'food_id': 'm_new',
                  'name': 'Protein Smoothie',
                  'calories': 350,
                  'protein': 30.0,
                  'carbs': 35.0,
                  'fat': 6.0,
                  'weight_grams': 300,
                  'meal_type': 'snack',
                  'time': '16:00',
                },
              ],
            },
          });

      // Remote getDailyPlan returns 2 logged foods with 850 kcal
      when(() => mockRemoteDataSource.getDailyPlan(dateStr))
          .thenAnswer((_) async => {
                'date': dateStr,
                'entries': [
                  {
                    'log_id': 'log_1',
                    'food_name': 'Scrambled Eggs',
                    'meal_type': 'breakfast',
                    'total_calories': 350,
                    'protein': 24.0,
                    'carbs': 4.0,
                    'fat': 22.0,
                  },
                  {
                    'log_id': 'log_2',
                    'food_name': 'Beef Steak',
                    'meal_type': 'lunch',
                    'total_calories': 500,
                    'protein': 45.0,
                    'carbs': 0.0,
                    'fat': 30.0,
                  },
                ],
                'total_calories': 850,
                'total_protein': 69.0,
                'total_carbs': 4.0,
                'total_fat': 52.0,
                'current_water': 1250,
                'water_target': 2500,
                'rollover_calories': 0,
              });

      final result = await repository.generatePlan(
        dateStr: dateStr,
        goal: 'weight_loss',
        targetCalories: 1800,
        mealCount: 3,
        style: 'optimal',
        remainingOnly: true,
      );

      // Meals are updated with AI plan
      expect(result.meals.length, 1);
      expect(result.meals.first.name, 'Protein Smoothie');

      // Actual intake and logged meals are strictly preserved from GET daily
      expect(result.entries.length, 2);
      expect(result.entries.first.foodName, 'Scrambled Eggs');
      expect(result.entries.last.foodName, 'Beef Steak');
      expect(result.totalCaloriesConsumed, 850);
      expect(result.totalProteinConsumed, 69);
      expect(result.totalCarbsConsumed, 4);
      expect(result.totalFatConsumed, 52);
      expect(result.currentWater, 1250);
      expect(result.targetWater, 2500);
      expect(result.date, dateStr);
    });

    test('4. selectedDate khác hôm nay: gọi getDailyPlan đúng ngày được chọn và gắn date chính xác',
        () async {
      const pastDate = '2026-10-01';

      when(() => mockRemoteDataSource.generatePlan(
            goal: 'maintain',
            targetCalories: 0,
            mealCount: null,
            style: null,
            remainingOnly: false,
          )).thenAnswer((_) async => {
            'plan': {
              'date': '2026-10-08', // Backend may return today
              'total_calories': 2000,
              'meals': [],
            },
          });

      when(() => mockRemoteDataSource.getDailyPlan(pastDate))
          .thenAnswer((_) async => {
                'date': pastDate,
                'entries': [],
                'total_calories': 400,
                'total_protein': 30.0,
                'total_carbs': 40.0,
                'total_fat': 10.0,
                'current_water': 500,
                'water_target': 2000,
              });

      final result = await repository.generatePlan(
        dateStr: pastDate,
        goal: 'maintain',
      );

      // Verify getDailyPlan was called with the exact selectedDate
      verify(() => mockRemoteDataSource.getDailyPlan(pastDate)).called(1);
      expect(result.date, pastDate);
      expect(result.totalCaloriesConsumed, 400);
      expect(result.currentWater, 500);
    });

    test('5. GET daily lỗi: phải propagate lỗi ra ngoài, tuyệt đối không fallback về 0',
        () async {
      const dateStr = '2026-10-08';

      when(() => mockRemoteDataSource.generatePlan(
            goal: 'maintain',
            targetCalories: 0,
            mealCount: null,
            style: null,
            remainingOnly: false,
          )).thenAnswer((_) async => {
            'plan': {
              'date': dateStr,
              'total_calories': 2000,
              'meals': [],
            },
          });

      // GET daily fails with server error
      when(() => mockRemoteDataSource.getDailyPlan(dateStr))
          .thenThrow(Exception('Server error: 500 Internal Server Error'));

      expect(
        () => repository.generatePlan(
          dateStr: dateStr,
          goal: 'maintain',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('500 Internal Server Error'),
        )),
      );
    });

    test('6. Bảo toàn macros và water: giữ nguyên các trường từ GET daily',
        () async {
      const dateStr = '2026-10-08';

      when(() => mockRemoteDataSource.generatePlan(
            goal: 'maintain',
            targetCalories: 0,
            mealCount: null,
            style: null,
            remainingOnly: false,
          )).thenAnswer((_) async => {
            'plan': {
              'date': dateStr,
              'total_calories': 2100,
              'meals': [],
            },
          });

      when(() => mockRemoteDataSource.getDailyPlan(dateStr))
          .thenAnswer((_) async => {
                'date': dateStr,
                'entries': [],
                'total_calories': 1420,
                'total_protein': 115.5,
                'total_carbs': 160.0,
                'total_fat': 45.2,
                'current_water': 1750,
                'water_target': 3000,
                'rollover_calories': 180,
              });

      final result = await repository.generatePlan(
        dateStr: dateStr,
        goal: 'maintain',
      );

      expect(result.currentWater, 1750);
      expect(result.targetWater, 3000);
      expect(result.totalCaloriesConsumed, 1420);
      expect(result.totalProteinConsumed, 115);
      expect(result.totalCarbsConsumed, 160);
      expect(result.totalFatConsumed, 45);
      expect(result.rolloverCalories, 180);
    });
  });
}

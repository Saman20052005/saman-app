import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';

class _FakeProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestProfileNotifier extends ProfileNotifier {
  _TestProfileNotifier({bool isValid = true, int targetCalories = 2300})
      : super(_FakeProfileRepository()) {
    if (isValid) {
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
        targetProtein: 160,
        targetCarbs: 240,
        targetFat: 65,
        waterTargetMl: 2000,
        isLoading: false,
      );
    } else {
      state = ProfileState(profile: ProfileEntity.empty(), isLoading: false);
    }
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

class _TestNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _TestNutritionNotifier(super.initial);

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2300,
        protein: 160,
        carbs: 240,
        fat: 65,
      );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  bool get isMealPlanGenerating => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NutritionPlan _createEmptySamplePlan() {
  return NutritionPlan(
    date: '2026-11-07',
    totalCaloriesConsumed: 0,
    totalProteinConsumed: 0,
    totalCarbsConsumed: 0,
    totalFatConsumed: 0,
    currentWater: 0,
    meals: [],
  );
}

Widget _buildLocalizedApp({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(languageProvider);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        );
      },
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'language_mode': 'vi',
      'language_code': 'vi',
    });
  });

  group('Checkpoint LOC-04: AppTranslations Nutrition & Workout Dictionary Parity', () {
    test('en and vi translation maps contain all required Nutrition & Workout keys with non-empty content', () {
      final requiredNutritionKeys = [
        'nutrition_title',
        'meal_suggestion_title',
        'meal_logged_success',
        'confirm_and_log',
        'missing_profile_info',
        'missing_profile_desc',
        'update_profile_now',
        'macro_calories',
        'macro_protein',
        'macro_carbs',
        'macro_fat',
        'meal_breakfast',
        'meal_lunch',
        'meal_dinner',
        'meal_snack',
        'log_meal_btn',
        'meal_plan_heading',
        'no_meal_plan_badge',
        'create_meal_plan_ai',
        'create_plan_btn',
        'load_nutrition_failed',
      ];

      final requiredWorkoutKeys = [
        'workout_title',
        'workout_home_subtitle',
        'my_plans',
        'today_scheduled_session',
        'start_workout',
        'view_plan',
        'quick_start',
        'quick_start_desc',
        'browse_library',
        'explore_exercises',
        'train_by_focus',
        'all_categories',
        'your_plan',
        'view_full_plan',
        'last_workout',
        'view_history',
        'no_saved_workouts',
        'rest_timer',
        'next_exercise',
        'log_set',
        'finish_workout',
        'sets_completed',
        'workout_summary_title',
      ];

      final allKeys = [...requiredNutritionKeys, ...requiredWorkoutKeys];

      for (final key in allKeys) {
        final viText = AppTranslations.text(key, const Locale('vi'));
        final enText = AppTranslations.text(key, const Locale('en'));

        expect(viText, isNotEmpty, reason: 'Key $key should not be empty in VI');
        expect(enText, isNotEmpty, reason: 'Key $key should not be empty in EN');
        expect(viText, isNot(equals(key)), reason: 'Key $key must have a VI translation');
        expect(enText, isNot(equals(key)), reason: 'Key $key must have an EN translation');
        expect(viText, isNot(equals(enText)), reason: 'Key $key should differ between VI and EN');
      }
    });

    test('AppTranslations falls back cleanly to English or key itself when unknown', () {
      expect(AppTranslations.text('unknown_key_xyz', const Locale('vi')), equals('unknown_key_xyz'));
      expect(AppTranslations.text('nutrition_title', const Locale('fr')), equals('Nutrition'));
    });
  });

  group('Checkpoint LOC-04: NutritionScreen Reactive Localization Switch', () {
    testWidgets('NutritionScreen switches Incomplete Profile notice reactively VI <-> EN <-> VI', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) => _TestProfileNotifier(isValid: false)),
          nutritionProvider.overrideWith((ref) => _TestNutritionNotifier(const AsyncValue.loading())),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildLocalizedApp(
        container: container,
        child: const NutritionScreen(),
      ));
      await tester.pumpAndSettle();

      // 1. Initial VI state
      expect(find.text('Thiếu thông tin Profile'), findsOneWidget);
      expect(find.text('Cập nhật ngay'), findsOneWidget);
      expect(find.text('Vui lòng cập nhật thông tin cá nhân để tính toán mục tiêu dinh dưỡng.'), findsOneWidget);

      // 2. Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Missing Profile information'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Please update personal details to calculate nutrition goals.'), findsOneWidget);

      // 3. Switch back to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Thiếu thông tin Profile'), findsOneWidget);
      expect(find.text('Cập nhật ngay'), findsOneWidget);
    });

    testWidgets('NutritionScreen switches Empty Meal Plan notice reactively VI <-> EN <-> VI', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) => _TestProfileNotifier(isValid: true)),
          nutritionProvider.overrideWith(
            (ref) => _TestNutritionNotifier(AsyncValue.data(_createEmptySamplePlan())),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildLocalizedApp(
        container: container,
        child: const NutritionScreen(),
      ));
      await tester.pumpAndSettle();

      // 1. Initial VI state
      expect(find.text('KẾ HOẠCH BỮA ĂN'), findsOneWidget);
      expect(find.text('CHƯA CÓ KẾ HOẠCH'), findsOneWidget);
      expect(find.text('Tạo kế hoạch ăn uống với AI'), findsOneWidget);
      expect(find.text('Tạo kế hoạch'), findsOneWidget);

      // 2. Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('MEAL PLAN'), findsOneWidget);
      expect(find.text('NO MEAL PLAN'), findsOneWidget);
      expect(find.text('Create meal plan with AI'), findsOneWidget);
      expect(find.text('Create Plan'), findsOneWidget);

      // 3. Switch back to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('KẾ HOẠCH BỮA ĂN'), findsOneWidget);
      expect(find.text('CHƯA CÓ KẾ HOẠCH'), findsOneWidget);
    });

    testWidgets('NutritionScreen switches Error state card reactively VI <-> EN <-> VI', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) => _TestProfileNotifier(isValid: true)),
          nutritionProvider.overrideWith(
            (ref) => _TestNutritionNotifier(const AsyncValue.error('Network unreachable', StackTrace.empty)),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildLocalizedApp(
        container: container,
        child: const NutritionScreen(),
      ));
      await tester.pumpAndSettle();

      // 1. Initial VI state
      expect(find.text('Không thể tải dữ liệu dinh dưỡng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      // 2. Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Could not load nutrition data'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // 3. Switch back to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải dữ liệu dinh dưỡng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
    });
  });

  group('Checkpoint LOC-04: WorkoutHomeScreen Reactive Localization Switch', () {
    testWidgets('WorkoutHomeScreen switches headers, hero, quick actions, train by focus and plans reactively VI <-> EN <-> VI', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(390 * 2.0, 1400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildLocalizedApp(
        container: container,
        child: const WorkoutHomeScreen(),
      ));
      await tester.pumpAndSettle();

      // 1. Initial VI state
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('Tập luyện, ghi nhật ký & khám phá chuyển động'), findsOneWidget);
      expect(find.text('Kế hoạch của tôi'), findsOneWidget);
      expect(find.text('BUỔI TẬP ĐÃ LÊN LỊCH HÔM NAY'), findsOneWidget);
      expect(find.text('Bắt đầu tập'), findsOneWidget);
      expect(find.text('Xem kế hoạch'), findsOneWidget);
      expect(find.text('Bắt đầu nhanh'), findsOneWidget);
      expect(find.text('Tập không theo kế hoạch'), findsOneWidget);
      expect(find.text('Duyệt thư viện'), findsOneWidget);
      expect(find.text('Khám phá bài tập'), findsOneWidget);
      expect(find.text('TẬP THEO NHÓM CƠ'), findsOneWidget);
      expect(find.text('Tất cả danh mục'), findsOneWidget);
      expect(find.text('KẾ HOẠCH CỦA BẠN'), findsOneWidget);
      expect(find.text('Xem toàn bộ kế hoạch'), findsOneWidget);
      expect(find.text('BUỔI TẬP GẦN NHẤT'), findsOneWidget);
      expect(find.text('Xem lịch sử'), findsOneWidget);

      // 2. Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Train, log & explore movements'), findsOneWidget);
      expect(find.text('My Plans'), findsOneWidget);
      expect(find.text('TODAY’S SCHEDULED SESSION'), findsOneWidget);
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('View plan'), findsOneWidget);
      expect(find.text('Quick start'), findsOneWidget);
      expect(find.text('Train without a plan'), findsOneWidget);
      expect(find.text('Browse library'), findsOneWidget);
      expect(find.text('Explore exercises'), findsOneWidget);
      expect(find.text('TRAIN BY FOCUS'), findsOneWidget);
      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('View full plan'), findsOneWidget);
      expect(find.text('LAST WORKOUT'), findsOneWidget);
      expect(find.text('View history'), findsOneWidget);

      // 3. Switch back to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('BUỔI TẬP ĐÃ LÊN LỊCH HÔM NAY'), findsOneWidget);
      expect(find.text('Kế hoạch của tôi'), findsOneWidget);
    });
  });
}

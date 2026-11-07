import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/membership_overview_screen.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

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

Widget _buildFullAppTestWrapper({
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

  group('Checkpoint LOC-05: Bottom Navigation Bar 5-Tab E2E Localization Switch', () {
    testWidgets('Toggles all 5 Navigation Tab labels between Vietnamese and English reactively', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: Scaffold(
            bottomNavigationBar: SamanBottomNavigationBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial Vietnamese State
      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('Saman'), findsOneWidget);
      expect(find.text('Dinh dưỡng'), findsOneWidget);
      expect(find.text('Hồ sơ'), findsOneWidget);

      expect(find.text('Home'), findsNothing);
      expect(find.text('Workout'), findsNothing);
      expect(find.text('Nutrition'), findsNothing);
      expect(find.text('Profile'), findsNothing);

      // 2. Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Saman'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      expect(find.text('Trang chủ'), findsNothing);
      expect(find.text('Tập luyện'), findsNothing);
      expect(find.text('Dinh dưỡng'), findsNothing);
      expect(find.text('Hồ sơ'), findsNothing);

      // 3. Switch back to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('Saman'), findsOneWidget);
      expect(find.text('Dinh dưỡng'), findsOneWidget);
      expect(find.text('Hồ sơ'), findsOneWidget);
    });
  });

  group('Checkpoint LOC-05: E2E Verification Across All 5 Main Tabs (VI <-> EN <-> VI)', () {
    testWidgets('Tab 1 (Home & Membership Overview) reflects dynamic language switch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. VI
      expect(find.text('GÓI HIỆN TẠI: MIỄN PHÍ'), findsOneWidget);
      expect(find.text('So sánh tất cả các gói'), findsOneWidget);
      expect(find.text('BẢN XEM TRƯỚC HỘI VIÊN'), findsOneWidget);

      // 2. Switch EN
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('CURRENT PLAN: FREE'), findsOneWidget);
      expect(find.text('Compare all plans'), findsOneWidget);
      expect(find.text('MEMBERSHIP PREVIEW'), findsOneWidget);

      // 3. Switch VI
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('GÓI HIỆN TẠI: MIỄN PHÍ'), findsOneWidget);
      expect(find.text('So sánh tất cả các gói'), findsOneWidget);
    });

    testWidgets('Tab 2 (Workout Subsystem) reflects dynamic language switch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: const WorkoutHomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. VI
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('BUỔI TẬP ĐÃ LÊN LỊCH HÔM NAY'), findsOneWidget);
      expect(find.text('Bắt đầu tập'), findsOneWidget);
      expect(find.text('Kế hoạch của tôi'), findsOneWidget);
      expect(find.text('Bắt đầu nhanh'), findsOneWidget);
      expect(find.text('Tập không theo kế hoạch'), findsOneWidget);
      expect(find.text('Duyệt thư viện'), findsOneWidget);
      expect(find.text('Khám phá bài tập'), findsOneWidget);
      expect(find.text('TẬP THEO NHÓM CƠ'), findsOneWidget);
      expect(find.text('KẾ HOẠCH CỦA BẠN'), findsOneWidget);
      expect(find.text('BUỔI TẬP GẦN NHẤT'), findsOneWidget);
      expect(find.text('Xem lịch sử'), findsOneWidget);

      // 2. Switch EN
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('TODAY’S SCHEDULED SESSION'), findsOneWidget);
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('My Plans'), findsOneWidget);
      expect(find.text('Quick start'), findsOneWidget);
      expect(find.text('Train without a plan'), findsOneWidget);
      expect(find.text('Browse library'), findsOneWidget);
      expect(find.text('Explore exercises'), findsOneWidget);
      expect(find.text('TRAIN BY FOCUS'), findsOneWidget);
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('LAST WORKOUT'), findsOneWidget);
      expect(find.text('View history'), findsOneWidget);

      // 3. Switch VI
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('BUỔI TẬP ĐÃ LÊN LỊCH HÔM NAY'), findsOneWidget);
      expect(find.text('Kế hoạch của tôi'), findsOneWidget);
    });

    testWidgets('Tab 3 (Nutrition Subsystem) reflects dynamic language switch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) => _TestProfileNotifier(isValid: true)),
          nutritionProvider.overrideWith(
            (ref) => _TestNutritionNotifier(AsyncValue.data(_createEmptySamplePlan())),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: const NutritionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. VI
      expect(find.text('KẾ HOẠCH BỮA ĂN'), findsOneWidget);
      expect(find.text('CHƯA CÓ KẾ HOẠCH'), findsOneWidget);
      expect(find.text('Tạo kế hoạch ăn uống với AI'), findsOneWidget);
      expect(find.text('Tạo kế hoạch'), findsOneWidget);

      // 2. Switch EN
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('MEAL PLAN'), findsOneWidget);
      expect(find.text('NO MEAL PLAN'), findsOneWidget);
      expect(find.text('Create meal plan with AI'), findsOneWidget);
      expect(find.text('Create Plan'), findsOneWidget);

      // 3. Switch VI
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('KẾ HOẠCH BỮA ĂN'), findsOneWidget);
      expect(find.text('CHƯA CÓ KẾ HOẠCH'), findsOneWidget);
    });

    testWidgets('Tab 4 (Community Subsystem) reflects dynamic language switch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: const CommunityFeedScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. VI
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Đang theo dõi'), findsOneWidget);
      expect(find.text('Hỏi & Đáp'), findsOneWidget);
      expect(find.text('Saman Community'), findsOneWidget);

      // 2. Switch EN
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Q&A'), findsOneWidget);
      expect(find.text('Saman Community'), findsOneWidget);

      // 3. Switch VI
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Đang theo dõi'), findsOneWidget);
      expect(find.text('Hỏi & Đáp'), findsOneWidget);
    });

    testWidgets('Tab 5 (Profile Subsystem) reflects dynamic language switch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) => _TestProfileNotifier(isValid: true)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. VI
      expect(find.text('Hồ sơ'), findsOneWidget);
      expect(find.text('Hồ sơ Saman của bạn'), findsOneWidget);
      expect(find.text('MỤC TIÊU CỦA BẠN'), findsOneWidget);
      expect(find.text('THÔNG TIN CỦA BẠN'), findsOneWidget);
      expect(find.text('Tuổi'), findsOneWidget);
      expect(find.text('Chiều cao'), findsOneWidget);
      expect(find.text('Cân nặng'), findsOneWidget);
      expect(find.text('HÀNH TRÌNH & ĐIỂM THƯỞNG'), findsOneWidget);
      expect(find.text('TÀI KHOẢN'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);

      // 2. Switch EN
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Your Saman profile'), findsOneWidget);
      expect(find.text('YOUR GOAL'), findsOneWidget);
      expect(find.text('YOUR DETAILS'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('JOURNEY & REWARDS'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      // 3. Switch VI
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ'), findsOneWidget);
      expect(find.text('Hồ sơ Saman của bạn'), findsOneWidget);
      expect(find.text('MỤC TIÊU CỦA BẠN'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);
    });
  });

  group('Checkpoint LOC-05: Stress & Continuous Multi-Round Language Toggling', () {
    testWidgets('Rapid repetitive language switching does not leak or produce exceptions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildFullAppTestWrapper(
          container: container,
          child: Scaffold(
            bottomNavigationBar: SamanBottomNavigationBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        await container.read(languageProvider.notifier).changeLanguage('en');
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Workout'), findsOneWidget);

        await container.read(languageProvider.notifier).changeLanguage('vi');
        await tester.pumpAndSettle();
        expect(find.text('Trang chủ'), findsOneWidget);
        expect(find.text('Tập luyện'), findsOneWidget);
      }
    });
  });
}

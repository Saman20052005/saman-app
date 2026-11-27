import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/core/widgets/coach_marks/coach_tour_service.dart';
import 'package:health_ai_app/core/widgets/coach_marks/saman_coach_overlay.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_account_popup_menu.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestProfileNotifier extends ProfileNotifier {
  _TestProfileNotifier() : super(_MockProfileRepository()) {
    const entity = ProfileEntity(
      age: 28,
      gender: Gender.male,
      height: 175,
      weight: 70,
      activityLevel: ActivityLevel.medium,
      goal: Goal.gain_muscle,
    );
    state = ProfileState(
      profile: entity,
      snapshot: const ProfileSnapshot(
        profile: entity,
        fullName: 'Saman Athlete',
        email: 'athlete@saman.app',
      ),
      targetCalories: 2200,
      targetProtein: 150,
      targetCarbs: 230,
      targetFat: 65,
      waterTargetMl: 2000,
      status: ProfileStatus.ready,
      isLoading: false,
    );
  }
}

class _TestNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _TestNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-11-27',
              meals: const [],
              entries: const [],
              currentWater: 500,
              targetWater: 2000,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2200,
        protein: 150,
        carbs: 230,
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
  Future<String> addWater(
    int amountMl, {
    required String date,
    String? idempotencyKey,
  }) async =>
      'ok';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCommunityNotificationsNotifier
    extends StateNotifier<CommunityNotificationsState>
    implements CommunityNotificationsNotifier {
  _FakeCommunityNotificationsNotifier()
      : super(const CommunityNotificationsState(allNotifications: []));

  @override
  Future<void> loadNotifications() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CoachTourService.isTestBypassEnabled = false;
    SamanCoachOverlay.dismissActive();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Saman Athlete',
      'user_email': 'athlete@saman.app',
    });
  });

  tearDown(() {
    SamanCoachOverlay.dismissActive();
  });

  testWidgets(
    'Help dialog in SamanAccountPopupMenu resets all 3 coach tours when tapped',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);
      await service.markSeen(CoachTourService.homeScreenId);
      await service.markSeen(CoachTourService.nutritionScreenId);
      await service.markSeen(CoachTourService.workoutScreenId);

      expect(await service.shouldShow(CoachTourService.homeScreenId), isFalse);
      expect(
        await service.shouldShow(CoachTourService.nutritionScreenId),
        isFalse,
      );
      expect(
        await service.shouldShow(CoachTourService.workoutScreenId),
        isFalse,
      );

      var menuOpen = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachTourServiceProvider.overrideWithValue(service),
            profileProvider.overrideWith((ref) => _TestProfileNotifier()),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  if (!menuOpen) return const SizedBox.shrink();
                  return SamanAccountPopupMenu(
                    onClose: () => setState(() => menuOpen = false),
                    onOpenPreferences: () {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Trợ giúp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trợ giúp'));
      await tester.pumpAndSettle();

      expect(find.text('Xem lại hướng dẫn tương tác'), findsOneWidget);
      await tester.tap(find.text('Xem lại hướng dẫn tương tác'));
      await tester.pumpAndSettle();

      expect(await service.shouldShow(CoachTourService.homeScreenId), isTrue);
      expect(
        await service.shouldShow(CoachTourService.nutritionScreenId),
        isTrue,
      );
      expect(
        await service.shouldShow(CoachTourService.workoutScreenId),
        isTrue,
      );
      expect(
        find.text(
          'Đã đặt lại hướng dẫn tương tác. Mở lại Home, Dinh dưỡng hoặc Tập luyện để xem!',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'HomeScreen auto-shows Coach Marks step 1/3 when home_v1 not seen and Skip marks seen',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);

      final container = ProviderContainer(
        overrides: [
          coachTourServiceProvider.overrideWithValue(service),
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileProvider.overrideWith((ref) => _TestProfileNotifier()),
          nutritionProvider.overrideWith((ref) => _TestNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(calories: 2200, protein: 150, carbs: 230, fat: 65),
          ),
          communityNotificationsProvider.overrideWith(
            (ref) => _FakeCommunityNotificationsNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(SamanCoachOverlay.isShowing, isTrue);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Mục tiêu hôm nay'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coach_tour_skip_button')));
      await tester.pumpAndSettle();

      expect(SamanCoachOverlay.isShowing, isFalse);
      expect(find.text('1/3'), findsNothing);
      expect(await service.shouldShow(CoachTourService.homeScreenId), isFalse);
    },
  );

  testWidgets(
    'IndexedStack guard prevents HomeScreen tour on Workout tab and activates Nutrition tour on tab 3 after resetAll',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);
      // Mark Workout seen so tab 1 stays clear while verifying Home (tab 0) does not overlap.
      await service.markSeen(CoachTourService.workoutScreenId);

      final container = ProviderContainer(
        overrides: [
          mainNavIndexProvider.overrideWith((ref) => 1),
          coachTourServiceProvider.overrideWithValue(service),
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileProvider.overrideWith((ref) => _TestProfileNotifier()),
          nutritionProvider.overrideWith((ref) => _TestNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(calories: 2200, protein: 150, carbs: 230, fat: 65),
          ),
          communityNotificationsProvider.overrideWith(
            (ref) => _FakeCommunityNotificationsNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                final index = ref.watch(mainNavIndexProvider);
                return IndexedStack(
                  index: index,
                  children: const [
                    HomeScreen(),
                    WorkoutHomeScreen(),
                    SizedBox.shrink(),
                    NutritionScreen(),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // HomeScreen (tab 0) must NOT show its coach tour while mainNavIndexProvider == 1.
      expect(SamanCoachOverlay.isShowing, isFalse);
      expect(find.text('Mục tiêu hôm nay'), findsNothing);

      // Mark nutrition seen, then resetAll and switch to tab 3 (Nutrition).
      await service.markSeen(CoachTourService.nutritionScreenId);
      await service.resetAll();
      container.read(mainNavIndexProvider.notifier).state = 3;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(SamanCoachOverlay.isShowing, isTrue);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Chụp ảnh AI & Quét Barcode'), findsOneWidget);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/onboarding_flow_screen.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';

class _FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-09-21',
              meals: [],
              currentWater: 1800,
              targetWater: 2500,
              totalCaloriesConsumed: 1850,
              totalProteinConsumed: 120,
              totalCarbsConsumed: 210,
              totalFatConsumed: 55,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2500,
        protein: 160,
        carbs: 280,
        fat: 75,
      );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProfileRepo implements ProfileRepository {
  ProfileSnapshot? snapshotToReturn;
  OnboardingDraft? storedDraft;
  int updateCallCount = 0;
  int saveDraftCallCount = 0;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    return snapshotToReturn;
  }

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    updateCallCount++;
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshotToReturn?.profile;

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {
    saveDraftCallCount++;
    storedDraft = draft;
  }

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => storedDraft;

  @override
  Future<void> clearDraft(String userId) async {
    storedDraft = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Widget createTestWidget({
    required ProviderContainer container,
    required VoidCallback onLogout,
    void Function(OnboardingDraft)? onConfirmIntegration,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SamanTheme.dark(),
        home: Scaffold(
          body: OnboardingFlowScreen(
            onLogout: onLogout,
            onConfirmIntegration: onConfirmIntegration,
          ),
        ),
      ),
    );
  }

  group('Onboarding Step Navigation & Review-Edit Tests', () {
    testWidgets('Full linear navigation 1 to 5 and Back preserves all inputs',
        (tester) async {
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_nav_1',
        profile: ProfileEntity(userId: 'usr_nav_1'),
        isFromCache: false,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      // Force load incomplete profile state
      await container.read(profileProvider.notifier).loadProfile();

      await tester.pumpWidget(createTestWidget(
        container: container,
        onLogout: () {},
      ));
      await tester.pumpAndSettle();

      // Step 1: Goal
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.text('What’s your\nmain goal?'), findsOneWidget);

      // Continue is disabled initially
      final continueBtn1 = find.byKey(const Key('goal_continue_button'));
      expect(continueBtn1, findsOneWidget);

      // Select 'Build muscle'
      final goalGainMuscle = find.byKey(const Key('goal_option_gain_muscle'));
      await tester.ensureVisible(goalGainMuscle);
      await tester.tap(goalGainMuscle);
      await tester.pumpAndSettle();

      // Tap Continue -> Step 2
      await tester.tap(continueBtn1);
      await tester.pumpAndSettle();

      // Step 2: Age & Gender
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(find.text('A little about you'), findsOneWidget);

      // Enter Age: 25
      await tester.enterText(find.byKey(const Key('age_input_field')), '25');
      // Select Gender: Male
      await tester.tap(find.byKey(const Key('gender_option_male')));
      await tester.pumpAndSettle();

      // Continue -> Step 3
      await tester.tap(find.byKey(const Key('age_gender_continue_button')));
      await tester.pumpAndSettle();

      // Step 3: Body
      expect(find.text('Step 3 of 5'), findsOneWidget);
      expect(find.text('Your body measurements'), findsOneWidget);

      // Enter Height: 175.5, Weight: 72.5
      await tester.enterText(find.byKey(const Key('height_input_field')), '175.5');
      await tester.enterText(find.byKey(const Key('weight_input_field')), '72.5');
      await tester.pumpAndSettle();

      // Continue -> Step 4
      await tester.tap(find.byKey(const Key('body_continue_button')));
      await tester.pumpAndSettle();

      // Step 4: Activity
      expect(find.text('Step 4 of 5'), findsOneWidget);
      expect(find.text('How active is your usual week?'), findsOneWidget);

      // Select Moderately active
      final actModerate = find.byKey(const Key('activity_option_moderate'));
      await tester.ensureVisible(actModerate);
      await tester.tap(actModerate);
      await tester.pumpAndSettle();

      // Continue -> Step 5 (Review)
      await tester.tap(find.byKey(const Key('activity_continue_button')));
      await tester.pumpAndSettle();

      // Step 5: Review
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('Take a final look'), findsOneWidget);
      expect(find.text('Build muscle'), findsOneWidget);
      expect(find.text('25 years'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('175.5 cm'), findsOneWidget);
      expect(find.text('72.5 kg'), findsOneWidget);
      expect(find.text('Moderately active'), findsOneWidget);

      // Now test Back: Step 5 back -> Step 4
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 4 of 5'), findsOneWidget);

      // Step 4 back -> Step 3
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 3 of 5'), findsOneWidget);
      // Decimals preserved!
      expect(find.text('175.5'), findsOneWidget);
      expect(find.text('72.5'), findsOneWidget);

      // Step 3 back -> Step 2
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);

      // Step 2 back -> Step 1
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('Step 1 Back opens logout dialog and does not open Main',
        (tester) async {
      bool logoutCalled = false;
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_logout_test',
        profile: ProfileEntity(userId: 'usr_logout_test'),
        isFromCache: false,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileProvider.notifier).loadProfile();

      await tester.pumpWidget(createTestWidget(
        container: container,
        onLogout: () {
          logoutCalled = true;
        },
      ));
      await tester.pumpAndSettle();

      // Back on Step 1
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();

      // Logout dialog appears
      expect(find.text('Đăng xuất'), findsWidgets);
      expect(find.byType(MainScreen), findsNothing);

      // Tap confirm logout
      await tester.tap(find.byKey(const Key('onboarding_logout_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(logoutCalled, isTrue);
    });

    testWidgets('Review-Edit on Goal returns directly to Review without altering other fields',
        (tester) async {
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_edit_test',
        profile: ProfileEntity(
          userId: 'usr_edit_test',
          age: 28,
          gender: Gender.female,
          height: 168.0,
          weight: 58.0,
          activityLevel: ActivityLevel.medium,
          goal: Goal.lose_weight,
        ),
        isFromCache: false,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileProvider.notifier).loadProfile();

      await tester.pumpWidget(createTestWidget(
        container: container,
        onLogout: () {},
      ));
      await tester.pumpAndSettle();

      // Starts at Step 5 because all fields are present
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('Lose weight'), findsOneWidget);
      expect(find.text('28 years'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);

      // Tap Edit Goal
      await tester.tap(find.byKey(const Key('review_edit_goal')));
      await tester.pumpAndSettle();

      // Should be on Step 1 with Review-Edit CTA
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.text('Back to review'), findsOneWidget);

      // Change Goal to 'Maintain weight'
      await tester.tap(find.byKey(const Key('goal_option_maintain_weight')));
      await tester.pumpAndSettle();

      // Tap Back to review
      await tester.tap(find.byKey(const Key('goal_continue_button')));
      await tester.pumpAndSettle();

      // Returned directly to Step 5 (Review)
      expect(find.text('Step 5 of 5'), findsOneWidget);
      // Goal updated
      expect(find.text('Maintain weight'), findsOneWidget);
      // Other 5 fields completely preserved!
      expect(find.text('28 years'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('168 cm'), findsOneWidget);
      expect(find.text('58 kg'), findsOneWidget);
      expect(find.text('Moderately active'), findsOneWidget);
    });

    testWidgets('gender.other in raw profile is preserved and not forced to change',
        (tester) async {
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_other_test',
        profile: ProfileEntity(
          userId: 'usr_other_test',
          gender: Gender.other,
        ),
        isFromCache: false,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileProvider.notifier).loadProfile();

      await tester.pumpWidget(createTestWidget(
        container: container,
        onLogout: () {},
      ));
      await tester.pumpAndSettle();

      // Goal is missing, starts at Step 1
      expect(find.text('Step 1 of 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('goal_option_lose_weight')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal_continue_button')));
      await tester.pumpAndSettle();

      // Step 2: Enter age only
      expect(find.text('Step 2 of 5'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('age_input_field')), '24');
      await tester.pumpAndSettle();

      // User did NOT tap Male or Female. Continue IS ENABLED because gender.other is already held!
      final continueBtn = find.byKey(const Key('age_gender_continue_button'));
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      // Successfully progressed to Step 3
      expect(find.text('Step 3 of 5'), findsOneWidget);
    });

    testWidgets('Confirm button on Step 5 invokes CP4 integration point and shows SnackBar',
        (tester) async {
      OnboardingDraft? confirmedDraft;
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_confirm_test',
        profile: ProfileEntity(
          userId: 'usr_confirm_test',
          age: 30,
          gender: Gender.male,
          height: 180.0,
          weight: 75.0,
          activityLevel: ActivityLevel.high,
          goal: Goal.gain_muscle,
        ),
        isFromCache: false,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileProvider.notifier).loadProfile();

      await tester.pumpWidget(createTestWidget(
        container: container,
        onLogout: () {},
        onConfirmIntegration: (draft) {
          confirmedDraft = draft;
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('Step 5 of 5'), findsOneWidget);

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pump();

      // Shows 'Chưa thể lưu lúc này.'
      expect(find.text('Chưa thể lưu lúc này.'), findsOneWidget);

      // Integration callback received validated draft
      expect(confirmedDraft, isNotNull);
      expect(confirmedDraft!.userId, equals('usr_confirm_test'));
      expect(confirmedDraft!.age, equals(30));
      expect(confirmedDraft!.goal, equals(Goal.gain_muscle));
      expect(confirmedDraft!.activityChoice, equals(OnboardingActivityChoice.active));

      // No update API was invoked
      expect(repo.updateCallCount, equals(0));
      // Did NOT navigate to Main
      expect(find.byType(MainScreen), findsNothing);
      // Remained on Review
      expect(find.text('Step 5 of 5'), findsOneWidget);
    });

    testWidgets('Draft retains high-precision biometric values across navigation',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_nav_precision',
        profile: ProfileEntity(
          userId: 'usr_nav_precision',
          goal: Goal.maintain_weight,
          age: 28,
          gender: Gender.male,
        ),
        isFromCache: false,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          profileRepositoryProvider.overrideWithValue(repo),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileProvider.notifier).loadProfile();

      await tester.pumpWidget(createTestWidget(
        container: container,
        onLogout: () {},
      ));
      await tester.pumpAndSettle();

      // Step 3
      expect(find.text('Step 3 of 5'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('height_input_field')), '178.50001');
      await tester.enterText(
          find.byKey(const Key('weight_input_field')), '72.50001');
      await tester.pumpAndSettle();

      // Check draft persistence
      expect(repo.storedDraft?.height, equals(178.50001));
      expect(repo.storedDraft?.weight, equals(72.50001));

      // Continue to Step 4
      await tester.tap(find.byKey(const Key('body_continue_button')));
      await tester.pumpAndSettle();

      // Select Activity choice
      await tester.tap(find.byKey(const Key('activity_option_light')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity_continue_button')));
      await tester.pumpAndSettle();

      // Step 5 Review
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('178.50001 cm'), findsOneWidget);
      expect(find.text('72.50001 kg'), findsOneWidget);
    });
  });
}

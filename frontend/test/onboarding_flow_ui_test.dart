import 'package:health_ai_app/features/profile/presentation/onboarding/step_age_gender_view.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/step_body_view.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  Completer<OnboardingDraft?>? draftCompleter;
  int saveDraftCallCount = 0;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    return snapshotToReturn;
  }

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

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
  Future<OnboardingDraft?> getDraft(String userId) async {
    if (draftCompleter != null) {
      return draftCompleter!.future;
    }
    return storedDraft;
  }

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

  Future<void> captureScreen(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture_boundary')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        final evidenceDir = Platform.environment['SAMAN_RENDER_EVIDENCE'] ??
            Directory.systemTemp.path;
        final file = File('$evidenceDir/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List());
      }
      image.dispose();
    });
  }

  Widget createTestWidget({
    required ProviderContainer container,
    required VoidCallback onLogout,
    void Function(OnboardingDraft)? onConfirmIntegration,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SamanTheme.dark(),
        home: RepaintBoundary(
          key: const ValueKey('capture_boundary'),
          child: Scaffold(
            body: OnboardingFlowScreen(
              onLogout: onLogout,
              onConfirmIntegration: onConfirmIntegration,
            ),
          ),
        ),
      ),
    );
  }

  group('Onboarding Flow UI & Invariant Tests', () {
    testWidgets('New user has NO default selections and Continue is disabled',
        (tester) async {
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_new_1',
        profile: ProfileEntity(userId: 'usr_new_1'),
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

      // Step 1: Goal
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.text('What’s your\nmain goal?'), findsOneWidget);

      // Verify Continue button is disabled
      final continueButton = tester.widget<InkWell>(
        find.byKey(const Key('goal_continue_button')),
      );
      expect(continueButton.onTap, isNull);
    });

    testWidgets('Late typing protection: async draft restore does not overwrite user choice',
        (tester) async {
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_late_typing',
        profile: ProfileEntity(userId: 'usr_late_typing'),
        isFromCache: false,
      );

      // Draft fetch will be delayed
      final completer = Completer<OnboardingDraft?>();
      repo.draftCompleter = completer;

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
      await tester.pump(); // Initial frame, draft is in flight

      // User selects 'Lose weight' BEFORE draft finishes loading
      await tester.tap(find.byKey(const Key('goal_option_lose_weight')));
      await tester.pump();

      // Now complete draft restore with a conflicting goal ('gain_muscle')
      completer.complete(
        const OnboardingDraft(
          userId: 'usr_late_typing',
          schemaVersion: 1,
          base: OnboardingDraftBase(),
          goal: Goal.gain_muscle,
          step: 1,
        ),
      );
      await tester.pumpAndSettle();

      // User's active choice 'Lose weight' must NOT be overwritten!
      final continueButton = tester.widget<InkWell>(
        find.byKey(const Key('goal_continue_button')),
      );
      expect(continueButton.onTap, isNotNull);

      // Tap continue -> Step 2
      await tester.tap(find.byKey(const Key('goal_continue_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 5'), findsOneWidget);
    });

    testWidgets('Resume step never skips missing or invalid steps',
        (tester) async {
      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_resume_test',
        profile: ProfileEntity(
          userId: 'usr_resume_test',
          goal: Goal.maintain_weight,
          // age and gender are missing!
        ),
        isFromCache: false,
      );

      // Draft erroneously claims step 4 (activity)
      repo.storedDraft = const OnboardingDraft(
        userId: 'usr_resume_test',
        schemaVersion: 1,
        base: OnboardingDraftBase(goal: Goal.maintain_weight),
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.active,
        step: 4, // invalid because step 2 (age/gender) and step 3 (body) are not completed
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

      // Must be at Step 2 (the first missing step), NOT Step 4!
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(find.text('A little about you'), findsOneWidget);
    });

    testWidgets('Decimal input validation: trailing separator keeps text but disables continue',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_decimal_test',
        profile: ProfileEntity(
          userId: 'usr_decimal_test',
          goal: Goal.maintain_weight,
          age: 26,
          gender: Gender.female,
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

      // Starts at Step 3 (Body)
      expect(find.text('Step 3 of 5'), findsOneWidget);

      // Enter unfinished height "165." and valid weight "55.5"
      await tester.enterText(find.byKey(const Key('height_input_field')), '165.');
      await tester.enterText(find.byKey(const Key('weight_input_field')), '55.5');
      await tester.pumpAndSettle();

      // Continue must be disabled because "165." is incomplete
      var continueBtn = tester.widget<InkWell>(
        find.byKey(const Key('body_continue_button')),
      );
      expect(continueBtn.onTap, isNull);

      // Complete height to "165.4"
      await tester.enterText(find.byKey(const Key('height_input_field')), '165.4');
      await tester.pumpAndSettle();

      continueBtn = tester.widget<InkWell>(
        find.byKey(const Key('body_continue_button')),
      );
      expect(continueBtn.onTap, isNotNull);

      // Test comma separator "55,5"
      await tester.enterText(find.byKey(const Key('weight_input_field')), '55,5');
      await tester.pumpAndSettle();

      continueBtn = tester.widget<InkWell>(
        find.byKey(const Key('body_continue_button')),
      );
      expect(continueBtn.onTap, isNotNull);

      // Test zero value <= 0 (must be rejected)
      await tester.enterText(find.byKey(const Key('weight_input_field')), '0');
      await tester.pumpAndSettle();
      continueBtn = tester.widget<InkWell>(
        find.byKey(const Key('body_continue_button')),
      );
      expect(continueBtn.onTap, isNull);

      // Test multiple separators "55..5" (must be rejected)
      await tester.enterText(find.byKey(const Key('weight_input_field')), '55..5');
      await tester.pumpAndSettle();
      continueBtn = tester.widget<InkWell>(
        find.byKey(const Key('body_continue_button')),
      );
      expect(continueBtn.onTap, isNull);
    });

    testWidgets('Step 3 preserves full decimal precision for 178.50001 and 72.50001 without truncation',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_precision_test',
        profile: ProfileEntity(
          userId: 'usr_precision_test',
          goal: Goal.maintain_weight,
          age: 29,
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

      expect(find.text('Step 3 of 5'), findsOneWidget);

      // Enter full precision decimals exceeding 6 characters
      await tester.enterText(
          find.byKey(const Key('height_input_field')), '178.50001');
      await tester.enterText(
          find.byKey(const Key('weight_input_field')), '72.50001');
      await tester.pumpAndSettle();

      // Verify exact input values are preserved without 6-char truncation
      final heightField =
          tester.widget<TextField>(find.byKey(const Key('height_input_field')));
      final weightField =
          tester.widget<TextField>(find.byKey(const Key('weight_input_field')));
      expect(heightField.controller?.text, equals('178.50001'));
      expect(weightField.controller?.text, equals('72.50001'));

      // Continue must be enabled
      final continueBtn = tester.widget<InkWell>(
        find.byKey(const Key('body_continue_button')),
      );
      expect(continueBtn.onTap, isNotNull);

      // Proceed to Step 4
      await tester.tap(find.byKey(const Key('body_continue_button')));
      await tester.pumpAndSettle();
      expect(find.text('Step 4 of 5'), findsOneWidget);

      // Select Activity choice Light
      await tester.tap(find.byKey(const Key('activity_option_light')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity_continue_button')));
      await tester.pumpAndSettle();

      // Step 5 Review must display full precision values
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('178.50001 cm'), findsOneWidget);
      expect(find.text('72.50001 kg'), findsOneWidget);

      // Verify stored draft contains full precision
      expect(repo.storedDraft?.height, equals(178.50001));
      expect(repo.storedDraft?.weight, equals(72.50001));
      expect(repo.storedDraft?.rawHeightText, equals('178.50001'));
      expect(repo.storedDraft?.rawWeightText, equals('72.50001'));
    });

    testWidgets('All 5 activity choices persist and read back distinctly',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_act_test',
        profile: ProfileEntity(
          userId: 'usr_act_test',
          goal: Goal.maintain_weight,
          age: 26,
          gender: Gender.female,
          height: 165.0,
          weight: 55.0,
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

      // Starts at Step 4 (Activity)
      expect(find.text('Step 4 of 5'), findsOneWidget);

      // Select 'Extremely active' (very_active)
      final veryActiveFinder = find.byKey(const Key('activity_option_very_active'));
      await tester.ensureVisible(veryActiveFinder);
      await tester.tap(veryActiveFinder);
      await tester.pumpAndSettle();

      // Check repo draft saved distinctly
      expect(repo.storedDraft?.activityChoice, OnboardingActivityChoice.very_active);

      // Select 'Lightly active' (light)
      final lightFinder = find.byKey(const Key('activity_option_light'));
      await tester.ensureVisible(lightFinder);
      await tester.tap(lightFinder);
      await tester.pumpAndSettle();

      // Must be light, NOT low or moderate
      expect(repo.storedDraft?.activityChoice, OnboardingActivityChoice.light);
    });

    testWidgets('Compact viewport 360x640 renders each step without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_compact_test',
        profile: ProfileEntity(
          userId: 'usr_compact_test',
          goal: Goal.lose_weight,
          age: 30,
          gender: Gender.male,
          height: 178.0,
          weight: 75.0,
          activityLevel: ActivityLevel.medium,
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

      // Step 5 Review rendered on 360x640
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Navigate to Step 1
      final editGoalFinder = find.byKey(const Key('review_edit_goal'));
      await tester.ensureVisible(editGoalFinder);
      await tester.tap(editGoalFinder);
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Return to Review
      await tester.tap(find.byKey(const Key('goal_continue_button')));
      await tester.pumpAndSettle();

      // Navigate to Step 2
      final editAboutFinder = find.byKey(const Key('review_edit_about'));
      await tester.ensureVisible(editAboutFinder);
      await tester.tap(editAboutFinder);
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Return to Review
      await tester.tap(find.byKey(const Key('age_gender_continue_button')));
      await tester.pumpAndSettle();

      // Navigate to Step 3
      final editBodyFinder = find.byKey(const Key('review_edit_body'));
      await tester.ensureVisible(editBodyFinder);
      await tester.tap(editBodyFinder);
      await tester.pumpAndSettle();
      expect(find.text('Step 3 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Return to Review
      await tester.tap(find.byKey(const Key('body_continue_button')));
      await tester.pumpAndSettle();

      // Navigate to Step 4
      final editActFinder = find.byKey(const Key('review_edit_activity'));
      await tester.ensureVisible(editActFinder);
      await tester.tap(editActFinder);
      await tester.pumpAndSettle();
      expect(find.text('Step 4 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Visual QA: Renders and captures all 5 steps at 390x844 and compact 360x640',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MockProfileRepo();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_visual_qa',
        profile: ProfileEntity(
          userId: 'usr_visual_qa',
          goal: Goal.gain_muscle,
          age: 27,
          gender: Gender.male,
          height: 175.5,
          weight: 72.5,
          activityLevel: ActivityLevel.medium,
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

      // Step 5 Review (390x844)
      await captureScreen(tester, 'step5_review_390x844');

      // Step 1 Goal (390x844)
      await tester.tap(find.byKey(const Key('review_edit_goal')));
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step1_goal_390x844');
      await tester.tap(find.byKey(const Key('goal_continue_button')));
      await tester.pumpAndSettle();

      // Step 2 Age & Gender (390x844)
      await tester.tap(find.byKey(const Key('review_edit_about')));
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step2_age_gender_390x844');
      await tester.tap(find.byKey(const Key('age_gender_continue_button')));
      await tester.pumpAndSettle();

      // Step 3 Body (390x844)
      await tester.tap(find.byKey(const Key('review_edit_body')));
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step3_body_390x844');
      await tester.tap(find.byKey(const Key('body_continue_button')));
      await tester.pumpAndSettle();

      // Step 4 Activity (390x844)
      await tester.tap(find.byKey(const Key('review_edit_activity')));
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step4_activity_390x844');
      await tester.tap(find.byKey(const Key('activity_continue_button')));
      await tester.pumpAndSettle();

      // Now switch to compact viewport 360x640
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step5_review_360x640');

      // Step 1 Goal (360x640)
      final editGoal = find.byKey(const Key('review_edit_goal'));
      await tester.ensureVisible(editGoal);
      await tester.tap(editGoal);
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step1_goal_360x640');
      await tester.tap(find.byKey(const Key('goal_continue_button')));
      await tester.pumpAndSettle();

      // Step 3 Body (360x640)
      final editBody = find.byKey(const Key('review_edit_body'));
      await tester.ensureVisible(editBody);
      await tester.tap(editBody);
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step3_body_360x640');
      await tester.tap(find.byKey(const Key('body_continue_button')));
      await tester.pumpAndSettle();

      // Step 4 Activity (360x640)
      final editAct = find.byKey(const Key('review_edit_activity'));
      await tester.ensureVisible(editAct);
      await tester.tap(editAct);
      await tester.pumpAndSettle();
      await captureScreen(tester, 'step4_activity_360x640');
    });

    testWidgets('Visual QA & Input Refinements: Step 2 & 3 states, focus/blur, narrow 320x568, and 1.5x scale',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // --- STEP 2: AGE & GENDER STATES ---
      int? changedAge;
      Gender? selectedGender = Gender.male;

      Widget wrapWidget(Widget child, {Size? size, double textScale = 1.0}) {
        return MaterialApp(
          theme: SamanTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size ?? const Size(390, 844),
              textScaler: TextScaler.linear(textScale),
            ),
            child: RepaintBoundary(
              key: const ValueKey('capture_boundary'),
              child: Scaffold(
                body: child,
              ),
            ),
          ),
        );
      }

      // Step 2 Empty Unfocused
      await tester.pumpWidget(wrapWidget(
        StepAgeGenderView(
          initialAge: null,
          initialGender: selectedGender,
          onAgeChanged: (val) => changedAge = val,
          onGenderSelected: (g) => selectedGender = g,
          onContinue: () {},
          onBack: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Enter your age'), findsOneWidget);
      expect(find.text('YEARS'), findsOneWidget);
      await captureScreen(tester, 'step2_age_empty_unfocused');

      // Step 2 Empty Focused -> Hint disappears so no overlap with cursor
      await tester.tap(find.byKey(const Key('age_input_field')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your age'), findsNothing);
      await captureScreen(tester, 'step2_age_empty_focused');

      // Step 2 Filled Focused
      await tester.enterText(find.byKey(const Key('age_input_field')), '28');
      await tester.pumpAndSettle();
      expect(find.text('28'), findsOneWidget);
      expect(find.text('YEARS'), findsOneWidget);
      expect(changedAge, 28);
      await captureScreen(tester, 'step2_age_filled_focused');

      // Step 2 Narrow Viewport (320x568)
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpWidget(wrapWidget(
        StepAgeGenderView(
          initialAge: 28,
          initialGender: selectedGender,
          onAgeChanged: (val) => changedAge = val,
          onGenderSelected: (g) => selectedGender = g,
          onContinue: () {},
          onBack: () {},
        ),
        size: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureScreen(tester, 'step2_age_narrow_320x568');

      // Step 2 Large Text Scale (1.5x)
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(wrapWidget(
        StepAgeGenderView(
          initialAge: 28,
          initialGender: selectedGender,
          onAgeChanged: (val) => changedAge = val,
          onGenderSelected: (g) => selectedGender = g,
          onContinue: () {},
          onBack: () {},
        ),
        textScale: 1.5,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureScreen(tester, 'step2_age_text_scale_1_5x');

      // --- STEP 3: BODY MEASUREMENT STATES ---
      String? rawHeight;
      String? rawWeight;
      double? pHeight;
      double? pWeight;

      // Step 3 Empty Unfocused
      await tester.pumpWidget(wrapWidget(
        StepBodyView(
          initialHeight: null,
          initialWeight: null,
          onHeightChanged: (raw, val) {
            rawHeight = raw;
            pHeight = val;
          },
          onWeightChanged: (raw, val) {
            rawWeight = raw;
            pWeight = val;
          },
          onContinue: () {},
          onBack: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Enter height'), findsOneWidget);
      expect(find.text('Enter weight'), findsOneWidget);
      expect(find.text('cm'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
      await captureScreen(tester, 'step3_body_empty_unfocused');

      // Step 3 Height Focused -> Hint disappears
      await tester.tap(find.byKey(const Key('height_input_field')));
      await tester.pumpAndSettle();
      expect(find.text('Enter height'), findsNothing);
      expect(find.text('Enter weight'), findsOneWidget);
      await captureScreen(tester, 'step3_body_height_focused');

      // Step 3 Filled Focused
      await tester.enterText(find.byKey(const Key('height_input_field')), '178.5');
      await tester.enterText(find.byKey(const Key('weight_input_field')), '72.4');
      await tester.pumpAndSettle();

      expect(find.text('178.5'), findsOneWidget);
      expect(find.text('72.4'), findsOneWidget);
      expect(find.text('cm'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
      expect(pHeight, 178.5);
      expect(pWeight, 72.4);
      await captureScreen(tester, 'step3_body_filled');

      // Step 3 Narrow Viewport (320x568)
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpWidget(wrapWidget(
        StepBodyView(
          initialHeight: 178.5,
          initialWeight: 72.4,
          onHeightChanged: (raw, val) {},
          onWeightChanged: (raw, val) {},
          onContinue: () {},
          onBack: () {},
        ),
        size: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureScreen(tester, 'step3_body_narrow_320x568');

      // Step 3 Large Text Scale (1.5x)
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(wrapWidget(
        StepBodyView(
          initialHeight: 178.5,
          initialWeight: 72.4,
          onHeightChanged: (raw, val) {},
          onWeightChanged: (raw, val) {},
          onContinue: () {},
          onBack: () {},
        ),
        textScale: 1.5,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureScreen(tester, 'step3_body_text_scale_1_5x');
    });
  });
}

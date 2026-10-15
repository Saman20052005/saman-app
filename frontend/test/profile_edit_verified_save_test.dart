import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _FakeVerifiedProfileRepo implements ProfileRepository {
  int syncCallCount = 0;
  int fetchCallCount = 0;
  ProfileModel? lastSyncedModel;
  ProfileSnapshot? snapshotToReturn;
  ProfileSnapshot? forcedReadbackSnapshot;
  Completer<void>? syncCompleter;
  Completer<ProfileSnapshot?>? fetchCompleter;
  Object? syncException;
  Object? fetchException;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false}) async {
    fetchCallCount++;
    if (fetchException != null) {
      throw fetchException!;
    }
    if (fetchCompleter != null) {
      return await fetchCompleter!.future;
    }
    return forcedReadbackSnapshot ?? snapshotToReturn;
  }

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshotToReturn?.profile;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    syncCallCount++;
    if (profile is ProfileModel) {
      lastSyncedModel = profile;
    } else {
      lastSyncedModel = ProfileModel.fromEntity(profile);
    }
    if (syncCompleter != null) {
      await syncCompleter!.future;
    }
    if (syncException != null) {
      throw syncException!;
    }
    // Update local snapshot so subsequent verified readback reflects this synced profile
    snapshotToReturn = ProfileSnapshot(
      userId: profile.userId,
      profile: profile,
      targetCalories: 2200,
      targetProtein: 150,
      targetCarbs: 220,
      targetFat: 65,
    );
  }

  int cacheCallCount = 0;

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    cacheCallCount++;
  }

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}
}

class _FakeNutritionNotifier
    extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-10-15',
              meals: [],
              currentWater: 1500,
              targetWater: 2000,
              totalCaloriesConsumed: 1200,
              totalProteinConsumed: 80,
              totalCarbsConsumed: 150,
              totalFatConsumed: 40,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2200,
        protein: 150,
        carbs: 220,
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void setMobileView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildTestApp({
  required Widget child,
  required _FakeVerifiedProfileRepo repo,
  ProfileState? initialState,
  Key? key,
}) {
  return ProviderScope(
    key: key,
    overrides: [
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      profileRepositoryProvider.overrideWithValue(repo),
      nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
      if (initialState != null)
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(repo);
          notifier.state = initialState;
          return notifier;
        }),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'John Athlete',
      'user_email': 'john@saman.test',
    });
  });

  group('CP5 - Profile & Edit Profile Verified Save Contract Tests', () {
    testWidgets('1. Summary dung data that, khong sample/fallback so lieu',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_real_john',
        age: 29,
        gender: Gender.male,
        height: 178.5,
        weight: 72.4,
        goal: Goal.maintain_weight,
        activityLevel: ActivityLevel.medium,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_real_john',
        profile: profile,
        targetCalories: 2200,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_real_john',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Real user identity, not Alex Morgan or placeholder
      expect(find.text('John Athlete'), findsOneWidget);
      expect(find.text('JA'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsNothing);

      // Read-only summary values with exact precision
      expect(find.text('Maintain weight'), findsOneWidget);
      expect(find.text('29'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('178.5 cm'), findsOneWidget);
      expect(find.text('72.4 kg'), findsOneWidget);
      expect(find.text('Moderately active'), findsOneWidget);

      // No vanity/fake metrics
      expect(find.text('BMI'), findsNothing);
      expect(find.text('Body fat'), findsNothing);
      expect(find.text('Saman+'), findsNothing);
    });

    testWidgets('2. Mot Edit CTA, mot bottom nav', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_one_cta',
        age: 30,
        gender: Gender.female,
        height: 165.0,
        weight: 58.0,
        goal: Goal.lose_weight,
        activityCanonical: 'light',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_one_cta',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const MainScreen(loadProfileOnInit: false),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_one_cta',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // Exactly one Edit CTA button
      expect(find.byKey(const Key('edit_profile_cta_button')), findsOneWidget);
      // Exactly one SamanBottomNavigationBar
      expect(find.byType(SamanBottomNavigationBar), findsOneWidget);
    });

    testWidgets('3. Prefill dung sau fields va decimals', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_prefill',
        age: 31,
        gender: Gender.female,
        height: 172.55,
        weight: 64.85,
        goal: Goal.maintain_weight,
        activityLevel: ActivityLevel.low,
        activityCanonical: 'sedentary',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_prefill',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_prefill',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check all 6 fields prefilled
      expect(find.text('31'), findsOneWidget);
      expect(find.text('172.55'), findsOneWidget);
      expect(find.text('64.85'), findsOneWidget);
      expect(find.text('Maintain weight'), findsOneWidget);
      expect(find.text('Mostly sitting'), findsOneWidget);
      // Gender female is visually selected
      expect(find.byKey(const Key('enum_female')), findsOneWidget);
    });

    testWidgets('4. Gender.other giu nguyen khi sua weight', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_other',
        age: 26,
        gender: Gender.other,
        height: 170.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_other',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_other',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User modifies only weight
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '71.5');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCallCount, equals(1));
      expect(repo.lastSyncedModel?.gender, equals(Gender.other));
      expect(repo.lastSyncedModel?.weight, equals(71.5));
    });

    testWidgets('5. Nam canonical activity values prefill/save/readback dung',
        (tester) async {
      setMobileView(tester);

      final choices = [
        OnboardingActivityChoice.sedentary,
        OnboardingActivityChoice.light,
        OnboardingActivityChoice.moderate,
        OnboardingActivityChoice.active,
        OnboardingActivityChoice.very_active,
      ];

      for (int i = 0; i < choices.length; i++) {
        final choice = choices[i];
        final repo = _FakeVerifiedProfileRepo();
        final profile = ProfileEntity(
          userId: 'usr_act_$i',
          age: 28,
          gender: Gender.male,
          height: 180.0,
          weight: 75.0,
          goal: Goal.maintain_weight,
          activityLevel: choice.toLegacy(),
          activityCanonical: choice.apiValue,
        );
        repo.snapshotToReturn = ProfileSnapshot(
          userId: 'usr_act_$i',
          profile: profile,
        );

        await tester.pumpWidget(
          _buildTestApp(
            key: ValueKey('test_act_$i'),
            child: const EditHealthProfileScreen(),
            repo: repo,
            initialState: ProfileState(
              status: ProfileStatus.ready,
              profile: profile,
              confirmedUserId: 'usr_act_$i',
              isNetworkConfirmed: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify title prefilled
        expect(find.text(choice.title), findsOneWidget);

        // Edit age slightly to enable save
        await tester.enterText(
            find.byKey(const Key('edit_profile_age_input')), '${30 + i}');
        await tester.pump();

        await tester.tap(find.byKey(const Key('edit_profile_save_button')));
        await tester.pumpAndSettle();

        expect(repo.syncCallCount, equals(1));
        expect(repo.lastSyncedModel?.rawActivityCanonical, equals(choice.apiValue));
        expect(repo.lastSyncedModel?.activityLevel, equals(choice.toLegacy()));
      }
    });

    testWidgets('6. Chi weight 72.5 -> 73.2: nam fields khac giu nguyen',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_preserve',
        age: 30,
        gender: Gender.male,
        height: 175.5,
        weight: 72.5,
        goal: Goal.lose_weight,
        activityLevel: ActivityLevel.medium,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_preserve',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_preserve',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only change weight
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '73.2');
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCallCount, equals(1));
      final synced = repo.lastSyncedModel!;
      expect(synced.weight, equals(73.2));
      // All other 5 fields strictly preserved
      expect(synced.age, equals(30));
      expect(synced.height, equals(175.5));
      expect(synced.gender, equals(Gender.male));
      expect(synced.goal, equals(Goal.lose_weight));
      expect(synced.rawActivityCanonical, equals('moderate'));
    });

    testWidgets('7. Goal/activity sheet Apply/cancel dung', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_sheets',
        age: 25,
        gender: Gender.male,
        height: 170.0,
        weight: 65.0,
        goal: Goal.lose_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_sheets',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_sheets',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Open Goal sheet and close without applying
      await tester.tap(find.byKey(const Key('edit_profile_goal_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enum_gain_muscle')));
      // Close with close icon button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Goal tile still shows Lose weight
      expect(find.text('Lose weight'), findsOneWidget);

      // 2. Open Goal sheet and apply
      await tester.tap(find.byKey(const Key('edit_profile_goal_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enum_gain_muscle')));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Goal tile now shows Build muscle
      expect(find.text('Build muscle'), findsOneWidget);

      // 3. Open Activity sheet and close without applying
      await tester.ensureVisible(find.byKey(const Key('edit_profile_activity_tile')));
      await tester.tap(find.byKey(const Key('edit_profile_activity_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity_option_sedentary')));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Activity tile still shows Moderately active
      expect(find.text('Moderately active'), findsOneWidget);

      // 4. Open Activity sheet and apply
      await tester.ensureVisible(find.byKey(const Key('edit_profile_activity_tile')));
      await tester.tap(find.byKey(const Key('edit_profile_activity_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity_option_active')));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Activity tile now shows Very active
      expect(find.text('Very active'), findsOneWidget);
    });

    testWidgets('8. Unchanged Save disabled; raw input invalid khong submit',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_valid_check',
        age: 30,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_valid_check',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_valid_check',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Unchanged: tap save does nothing
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();
      expect(repo.syncCallCount, equals(0));

      // 2. Invalid age: 12
      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '12');
      await tester.pump();
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();
      expect(repo.syncCallCount, equals(0));
      expect(find.text('Tuổi phải từ 13 đến 120'), findsOneWidget);

      // 3. Invalid height: -5
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '-5');
      await tester.pump();
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();
      expect(repo.syncCallCount, equals(0));
      expect(find.text('Chiều cao phải lớn hơn 0'), findsOneWidget);
    });

    testWidgets('9. Header/system Back dirty confirmation', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_back_check',
        age: 27,
        gender: Gender.female,
        height: 168.0,
        weight: 60.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_back_check',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => const EditHealthProfileScreen(),
            ),
          ),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_back_check',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clean: tap back pops directly without discard dialog
      // Modify input to make it dirty
      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '28');
      await tester.pump();

      // Tap header back
      await tester.tap(find.byKey(const Key('edit_profile_back_button')));
      await tester.pumpAndSettle();

      // Discard dialog is displayed
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byKey(const Key('discard_dialog_keep_editing')), findsOneWidget);
      expect(find.byKey(const Key('discard_dialog_discard')), findsOneWidget);

      // Tap Keep editing
      await tester.tap(find.byKey(const Key('discard_dialog_keep_editing')));
      await tester.pumpAndSettle();

      // Dialog dismissed, still on Edit screen
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
    });

    testWidgets('10. Double-tap chi mot mutation', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      final syncCompleter = Completer<void>();
      repo.syncCompleter = syncCompleter;
      const profile = ProfileEntity(
        userId: 'usr_double_tap',
        age: 30,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_double_tap',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_double_tap',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '71.0');
      await tester.pump();

      // Rapidly tap twice
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      // Exactly 1 sync call
      expect(repo.syncCallCount, equals(1));

      syncCompleter.complete();
      await tester.pumpAndSettle();

      expect(repo.syncCallCount, equals(1));
    });

    testWidgets('11. POST success + GET fail khong pop/toast success',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      repo.fetchException = Exception('GET readback timeout 504');
      const profile = ProfileEntity(
        userId: 'usr_get_fail',
        age: 28,
        gender: Gender.male,
        height: 172.0,
        weight: 68.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_get_fail',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_get_fail',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '69.0');
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // POST succeeded
      expect(repo.syncCallCount, equals(1));
      // Screen did NOT pop
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      // No "Profile updated" toast
      expect(find.text('Profile updated'), findsNothing);
      // Check again banner appears
      expect(find.byKey(const Key('edit_profile_check_again_button')),
          findsOneWidget);
    });

    testWidgets('12. Check again/status chi GET', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_check_again',
        age: 28,
        gender: Gender.male,
        height: 172.0,
        weight: 69.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_check_again',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.readbackPending,
            profile: profile,
            confirmedUserId: 'usr_check_again',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_profile_check_again_button')),
          findsOneWidget);

      final initialSyncs = repo.syncCallCount;
      final initialFetches = repo.fetchCallCount;

      // Tap Check again
      await tester.tap(find.byKey(const Key('edit_profile_check_again_button')));
      await tester.pumpAndSettle();

      // Only GET fetch was executed, 0 POST syncs!
      expect(repo.syncCallCount, equals(initialSyncs));
      expect(repo.fetchCallCount, equals(initialFetches + 1));
      // Verified readback popped screen
      expect(find.byType(EditHealthProfileScreen), findsNothing);
    });

    testWidgets('13. Wrong owner/epoch khong pop/apply/cache', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const legitimateOwner = 'usr_legit_owner';
      const wrongOwner = 'usr_wrong_imposter';

      const profile = ProfileEntity(
        userId: legitimateOwner,
        age: 30,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );

      // On sync, we simulate server returning wrong owner on readback
      repo.forcedReadbackSnapshot = const ProfileSnapshot(
        userId: wrongOwner,
        profile: ProfileEntity(
          userId: wrongOwner,
          age: 30,
          gender: Gender.male,
          height: 175.0,
          weight: 71.0,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: legitimateOwner,
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '71.0');
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // Screen did NOT pop
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      // Identity mismatch banner displayed
      expect(find.textContaining('Xác thực thất bại'), findsWidgets);
    });

    testWidgets('14. Conflict giu draft; khong overwrite tu dong',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      repo.syncException = ProfileConflictException('409 Conflict: modified by another device');

      const profile = ProfileEntity(
        userId: 'usr_conflict',
        age: 30,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_conflict',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_conflict',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '72.8');
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // Screen did NOT pop
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      // Conflict banner appears
      expect(find.textContaining('cập nhật từ thiết bị khác'), findsOneWidget);
      // User's draft weight "72.8" is preserved and not overwritten!
      expect(find.text('72.8'), findsOneWidget);
    });

    testWidgets('15. Verified readback -> Profile summary dung', (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_full_pop',
        age: 28,
        gender: Gender.male,
        height: 178.0,
        weight: 72.0,
        goal: Goal.maintain_weight,
        activityLevel: ActivityLevel.medium,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_full_pop',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_full_pop',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('72 kg'), findsOneWidget);

      // Open Edit Profile
      await tester.tap(find.byKey(const Key('edit_profile_cta_button')));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);

      // Modify weight to 74.5
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '74.5');
      await tester.pump();

      // Tap save
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // Popped back to ProfileScreen
      expect(find.byType(EditHealthProfileScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);

      // Summary shows verified readback weight 74.5 kg!
      expect(find.text('74.5 kg'), findsOneWidget);
    });

    testWidgets('16. CP5-FIX: Thay doi nho o ca height va weight (175.5 -> 175.50001, 72.5 -> 72.50001) dirty va save',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_tiny_change',
        age: 28,
        gender: Gender.male,
        height: 175.5,
        weight: 72.5,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_tiny_change',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_tiny_change',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter tiny changes without tolerance
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175.50001');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '72.50001');
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCallCount, equals(1));
      expect(repo.lastSyncedModel?.height, equals(175.50001));
      expect(repo.lastSyncedModel?.weight, equals(72.50001));
      expect(find.byType(EditHealthProfileScreen), findsNothing);
    });

    testWidgets('17. CP5-FIX: Hai cach bieu dien cung gia tri khong tao dirty gia',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_same_rep',
        age: 28,
        gender: Gender.male,
        height: 175.5,
        weight: 72.5,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_same_rep',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_same_rep',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter trailing zero representations of same values
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175.50');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '72.50');
      await tester.pump();

      // Tap save: must NOT submit because values are numerically unchanged
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();
      expect(repo.syncCallCount, equals(0));

      // Tap back: must pop immediately without showing discard dialog
      await tester.tap(find.byKey(const Key('edit_profile_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(EditHealthProfileScreen), findsNothing);
    });

    testWidgets('18. CP5-FIX: Input chua hoan chinh (72.) invalid nhung khong bi mat khi Back',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_incomplete_input',
        age: 28,
        gender: Gender.male,
        height: 175.0,
        weight: 72.5,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_incomplete_input',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const EditHealthProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_incomplete_input',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter incomplete decimal input
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '72.');
      await tester.pump();

      // Tap save: must NOT trigger mutation because input is incomplete / invalid
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();
      expect(repo.syncCallCount, equals(0));
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);

      // Tap Back: must show discard dialog
      await tester.tap(find.byKey(const Key('edit_profile_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Tap Keep editing: must dismiss dialog and PRESERVE incomplete input '72.'
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      expect(find.text('72.'), findsOneWidget);

      // Tap Back again and choose Discard changes: pops screen
      await tester.tap(find.byKey(const Key('edit_profile_back_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);
    });

    testWidgets('19. CP5-FIX: Payload va readback giu nguyen gia tri chinh xac, khong lam tron',
        (tester) async {
      setMobileView(tester);
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_exact_decimals',
        age: 30,
        gender: Gender.female,
        height: 168.12345,
        weight: 54.98765,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_exact_decimals',
        profile: profile,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProfileScreen(),
          repo: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: profile,
            confirmedUserId: 'usr_exact_decimals',
            isNetworkConfirmed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial read-only displays exact decimals
      expect(find.text('168.12345 cm'), findsOneWidget);
      expect(find.text('54.98765 kg'), findsOneWidget);

      // Open Edit
      await tester.tap(find.byKey(const Key('edit_profile_cta_button')));
      await tester.pumpAndSettle();

      // Modify to another multi-decimal precision
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '168.123456');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '54.987654');
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCallCount, equals(1));
      // Synced model retains exact unrounded values
      expect(repo.lastSyncedModel?.height, equals(168.123456));
      expect(repo.lastSyncedModel?.weight, equals(54.987654));

      // Popped back to profile and displays exact verified readback values
      expect(find.byType(EditHealthProfileScreen), findsNothing);
      expect(find.text('168.123456 cm'), findsOneWidget);
      expect(find.text('54.987654 kg'), findsOneWidget);
    });

    test('20. Thieu confirmed owner -> 0 POST, giu form va bao loi',
        () async {
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_unconfirmed',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_unconfirmed',
        profile: profile,
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.ready,
        profile: profile,
        confirmedUserId: null, // Thiếu confirmed owner
        isNetworkConfirmed: false,
      );

      final success = await notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 175,
        weight: 71,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      expect(success, isFalse);
      expect(repo.syncCallCount, equals(0)); // 0 POST!
      expect(notifier.state.status, equals(ProfileStatus.saveError));
      expect(notifier.state.errorMessage,
          contains('Cần tải lại dữ liệu từ máy chủ để xác minh danh tính'));
    });

    test('21. Snapshot cache co userId nhung chua xac nhan -> 0 POST',
        () async {
      final repo = _FakeVerifiedProfileRepo();
      const profile = ProfileEntity(
        userId: 'usr_cached_only',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_cached_only',
        profile: profile,
        isFromCache: true,
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.offline,
        profile: profile,
        snapshot: const ProfileSnapshot(
          userId: 'usr_cached_only',
          profile: profile,
          isFromCache: true,
        ),
        confirmedUserId: null,
        isNetworkConfirmed: false,
        isFromCache: true,
      );

      final success = await notifier.saveAndVerifyEditProfile(
        age: 30,
        height: 175,
        weight: 72,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      expect(success, isFalse);
      expect(repo.syncCallCount, equals(0)); // 0 POST!
      expect(notifier.state.status, equals(ProfileStatus.saveError));
      expect(notifier.state.errorMessage,
          contains('Cần tải lại dữ liệu từ máy chủ để xác minh danh tính'));
    });

    test(
        '22. Doi phien trong luc readback dang cho -> khong ap dung ket qua cu, khong bao thanh cong',
        () async {
      final repo = _FakeVerifiedProfileRepo();
      repo.fetchCompleter = Completer<ProfileSnapshot?>();

      const profileUserA = ProfileEntity(
        userId: 'usr_session_A',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'usr_session_A',
        profile: profileUserA,
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.ready,
        profile: profileUserA,
        confirmedUserId: 'usr_session_A',
        isNetworkConfirmed: true,
        isFromCache: false,
      );

      // Start save in flight
      final saveFuture = notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 176,
        weight: 71,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      // Wait until sync has completed and readback is pending
      await pumpEventQueue();
      expect(repo.syncCallCount, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.readbackPending));

      // User logs out or switches account during readback
      notifier.resetSession();
      expect(notifier.sessionEpoch, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.initial));

      // Now complete the delayed readback for User A
      repo.fetchCompleter!.complete(const ProfileSnapshot(
        userId: 'usr_session_A',
        profile: ProfileEntity(
          userId: 'usr_session_A',
          age: 29,
          height: 176,
          weight: 71,
          gender: Gender.male,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
      ));

      final success = await saveFuture;

      // MUST NOT report success to the new session
      expect(success, isFalse);
      // State MUST NOT be updated with User A's data
      expect(notifier.state.confirmedUserId, isNull);
      expect(notifier.state.status, equals(ProfileStatus.initial));
    });

    test(
        '23. Doi phien trong luc conflict refresh 409 dang cho -> khong cap nhat phien moi, khong bao thanh cong',
        () async {
      final repo = _FakeVerifiedProfileRepo();
      repo.syncException = ProfileConflictException('Data changed on another device');
      repo.fetchCompleter = Completer<ProfileSnapshot?>();

      const profileUserA = ProfileEntity(
        userId: 'usr_session_conflict_A',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.ready,
        profile: profileUserA,
        confirmedUserId: 'usr_session_conflict_A',
        isNetworkConfirmed: true,
        isFromCache: false,
      );

      final saveFuture = notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 175,
        weight: 71,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      await pumpEventQueue();
      expect(repo.syncCallCount, equals(1));

      // User logs out while conflict refresh GET is in flight
      notifier.resetSession();
      expect(notifier.sessionEpoch, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.initial));

      // Conflict refresh completes
      repo.fetchCompleter!.complete(const ProfileSnapshot(
        userId: 'usr_session_conflict_A',
        profile: profileUserA,
      ));

      final success = await saveFuture;

      expect(success, isFalse);
      // State MUST NOT be contaminated with saveConflict from old session
      expect(notifier.state.status, equals(ProfileStatus.initial));
      expect(notifier.state.errorMessage, isNull);
    });

    test(
        '24. Readback du 6 field nhung thieu ca hai owner ID: khong thanh cong, khong cache/apply',
        () async {
      final repo = _FakeVerifiedProfileRepo();
      const initialProfile = ProfileEntity(
        userId: 'usr_legit_owner',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.ready,
        profile: initialProfile,
        confirmedUserId: 'usr_legit_owner',
        isNetworkConfirmed: true,
        isFromCache: false,
      );

      // Readback returns all 6 fields matched, but NO owner ID anywhere
      repo.forcedReadbackSnapshot = const ProfileSnapshot(
        userId: null,
        profile: ProfileEntity(
          userId: null,
          age: 29,
          height: 175,
          weight: 71,
          gender: Gender.male,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
      );

      final success = await notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 175,
        weight: 71,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      // Must not report success
      expect(success, isFalse);
      // Must not cache or apply
      expect(repo.cacheCallCount, equals(0));
      expect(notifier.state.profile.age, equals(28)); // Not applied!
      // Must remain in readbackPending allowing GET-only reconciliation
      expect(notifier.state.status, equals(ProfileStatus.readbackPending));
      expect(notifier.state.errorMessage,
          contains('thiếu thông tin xác thực chủ tài khoản'));
    });

    test('25. Hai owner ID mau thuan: identityMismatch', () async {
      final repo = _FakeVerifiedProfileRepo();
      const initialProfile = ProfileEntity(
        userId: 'usr_legit_owner',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.ready,
        profile: initialProfile,
        confirmedUserId: 'usr_legit_owner',
        isNetworkConfirmed: true,
        isFromCache: false,
      );

      // Snapshot has expected owner, but inner profile has conflicting imposter ID
      repo.forcedReadbackSnapshot = const ProfileSnapshot(
        userId: 'usr_legit_owner',
        profile: ProfileEntity(
          userId: 'usr_imposter_mismatch',
          age: 29,
          height: 175,
          weight: 71,
          gender: Gender.male,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
      );

      final success = await notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 175,
        weight: 71,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      expect(success, isFalse);
      expect(repo.cacheCallCount, equals(0));
      expect(notifier.state.status, equals(ProfileStatus.identityMismatch));
      expect(notifier.state.errorMessage,
          contains('Xác thực thất bại: Chủ tài khoản không khớp'));

      // Subsequent save call locked
      final retrySuccess = await notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 175,
        weight: 71,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );
      expect(retrySuccess, isFalse);
      expect(repo.syncCallCount, equals(1)); // Still only 1 POST!
    });

    test(
        '26. POST thanh cong, readback thieu field: pending; goi save lan nua van 1 POST; reconciliation chi GET va chi thanh cong khi owner + 6 field khop',
        () async {
      final repo = _FakeVerifiedProfileRepo();
      const initialProfile = ProfileEntity(
        userId: 'usr_owner_reconcile',
        age: 28,
        gender: Gender.male,
        height: 175,
        weight: 70,
        goal: Goal.maintain_weight,
        activityCanonical: 'moderate',
      );

      final notifier = ProfileNotifier(repo);
      notifier.state = ProfileState(
        status: ProfileStatus.ready,
        profile: initialProfile,
        confirmedUserId: 'usr_owner_reconcile',
        isNetworkConfirmed: true,
        isFromCache: false,
      );

      // Step A: POST succeeds, but readback returns incomplete profile (missing age & height)
      repo.forcedReadbackSnapshot = const ProfileSnapshot(
        userId: 'usr_owner_reconcile',
        profile: ProfileEntity(
          userId: 'usr_owner_reconcile',
          age: null, // missing!
          height: null, // missing!
          weight: 72,
          gender: Gender.male,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
      );

      final save1 = await notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 176,
        weight: 72,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      expect(save1, isFalse);
      expect(repo.syncCallCount, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.readbackPending));

      // Step B: Calling save again while pending does NOT issue a second POST
      final save2 = await notifier.saveAndVerifyEditProfile(
        age: 29,
        height: 176,
        weight: 72,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      expect(save2, isFalse);
      expect(repo.syncCallCount, equals(1)); // VẪN TỔNG CỘNG 1 POST!

      // Step C: Reconcile while still incomplete -> GET only, stays pending
      final initialFetches = repo.fetchCallCount;
      final recFail = await notifier.reconcileEditProfile(
        age: 29,
        height: 176,
        weight: 72,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );
      expect(recFail, isFalse);
      expect(repo.syncCallCount, equals(1)); // 0 POST!
      expect(repo.fetchCallCount, equals(initialFetches + 1)); // Exactly 1 GET!
      expect(notifier.state.status, equals(ProfileStatus.readbackPending));

      // Step D: Backend now returns matching owner + all 6 complete fields
      repo.forcedReadbackSnapshot = const ProfileSnapshot(
        userId: 'usr_owner_reconcile',
        profile: ProfileEntity(
          userId: 'usr_owner_reconcile',
          age: 29,
          height: 176,
          weight: 72,
          gender: Gender.male,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
      );

      final recPass = await notifier.reconcileEditProfile(
        age: 29,
        height: 176,
        weight: 72,
        gender: Gender.male,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
      );

      expect(recPass, isTrue);
      expect(repo.syncCallCount, equals(1)); // Still only 1 POST in total!
      expect(notifier.state.status, equals(ProfileStatus.ready));
      expect(notifier.state.profile.age, equals(29));
      expect(notifier.state.profile.height, equals(176));
      expect(notifier.state.profile.weight, equals(72));
      expect(repo.cacheCallCount, equals(1));
    });
  });
}

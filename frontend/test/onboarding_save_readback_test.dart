import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/presentation/profile_gate.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';

class _TestScriptedAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  _TestScriptedAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-10-15',
              meals: [],
              currentWater: 1500,
              targetWater: 2500,
              totalCaloriesConsumed: 1800,
              totalProteinConsumed: 120,
              totalCarbsConsumed: 200,
              totalFatConsumed: 50,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2200,
        protein: 150,
        carbs: 250,
        fat: 70,
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

class _ControllableProfileRepo implements ProfileRepository {
  ProfileSnapshot? initialSnapshot;
  ProfileSnapshot? readbackSnapshot;
  OnboardingDraft? storedDraft;

  int syncProfileCallCount = 0;
  int readbackCallCount = 0;
  int clearDraftCallCount = 0;
  ProfileEntity? lastSyncedProfile;

  Exception? syncException;
  Exception? readbackException;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false}) async {
    readbackCallCount++;
    if (syncProfileCallCount == 0) {
      return initialSnapshot;
    }
    if (readbackException != null) {
      throw readbackException!;
    }
    return readbackSnapshot ?? initialSnapshot;
  }

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    syncProfileCallCount++;
    lastSyncedProfile = profile;
    if (syncException != null) {
      throw syncException!;
    }
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => initialSnapshot?.profile;

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {
    storedDraft = draft;
  }

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => storedDraft;

  @override
  Future<void> clearDraft(String userId) async {
    clearDraftCallCount++;
    storedDraft = null;
  }
}

Widget createTestApp({
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: SamanTheme.dark(),
      home: const ProfileGate(),
      routes: {
        AppRoutes.login: (context) => const Scaffold(
              key: Key('mock_login_screen'),
              body: Text('Login Screen'),
            ),
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CP4 - Onboarding Save, Preservation & Verified Readback Contract Tests', () {
    testWidgets('1. Confirm full flow: single save POST -> fresh readback GET -> MainScreen',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_success',
        profile: ProfileEntity(userId: 'usr_cp4_success'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 28,
        gender: Gender.male,
        height: 178.0,
        weight: 72.5,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );

      // Prepared readback snapshot matching all 6 submitted fields exactly + server stats
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_success',
        profile: ProfileEntity(
          userId: 'usr_cp4_success',
          age: 28,
          gender: Gender.male,
          height: 178.0,
          weight: 72.5,
          goal: Goal.maintain_weight,
          activityLevel: ActivityLevel.medium,
          activityCanonical: 'moderate',
        ),
        targetCalories: 2400,
        targetProtein: 150,
        targetCarbs: 280,
        targetFat: 70,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // On Review screen
      expect(find.text('Take a final look'), findsOneWidget);
      expect(find.text('178 cm'), findsOneWidget);
      expect(find.text('72.5 kg'), findsOneWidget);

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Exactly 1 save call made
      expect(repo.syncProfileCallCount, equals(1));
      expect(repo.lastSyncedProfile?.rawActivityCanonical, equals('moderate'));
      expect(repo.lastSyncedProfile?.height, equals(178.0));
      expect(repo.lastSyncedProfile?.weight, equals(72.5));

      // Readback verified
      expect(repo.readbackCallCount, greaterThanOrEqualTo(1));
      expect(repo.clearDraftCallCount, equals(1));

      // Admitted to MainScreen
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('2. Double-tap protection: locks mutation in-flight, renders loading indicator',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_double_tap',
        profile: ProfileEntity(userId: 'usr_cp4_double_tap'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 25,
        gender: Gender.female,
        height: 165.0,
        weight: 55.0,
        goal: Goal.lose_weight,
        activityChoice: OnboardingActivityChoice.light,
        step: 5,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Set state to saving to simulate in-flight request
      container.read(profileProvider.notifier).state =
          container.read(profileProvider).copyWith(status: ProfileStatus.saving);
      await tester.pump();

      // Loading state visible
      expect(find.byKey(const Key('onboarding_confirm_loading')), findsOneWidget);
      expect(find.text('Đang lưu...'), findsOneWidget);

      // Tapping loading button does not trigger additional sync
      await tester.tap(find.byKey(const Key('onboarding_confirm_loading')));
      await tester.pump();
      expect(repo.syncProfileCallCount, equals(0));
    });

    testWidgets('3. Save OK + Readback error: stays on Review, locks conflicting edits, Check again triggers GET only',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_readback_err',
        profile: ProfileEntity(userId: 'usr_cp4_readback_err'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 32,
        gender: Gender.male,
        height: 175.0,
        weight: 80.0,
        goal: Goal.gain_muscle,
        activityChoice: OnboardingActivityChoice.active,
        step: 5,
      );

      // Save will succeed, but readback fails initially
      repo.readbackException = Exception('Network error during readback');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Save was invoked once
      expect(repo.syncProfileCallCount, equals(1));

      // Remained on Review screen, MainScreen NOT rendered
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(const Key('onboarding_save_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_check_again_button')), findsOneWidget);

      // Edit buttons disabled
      await tester.tap(find.byKey(const Key('review_edit_goal')));
      await tester.pumpAndSettle();
      // Should STILL be on Step 5 (Review), not navigating to Step 1
      expect(find.text('Take a final look'), findsOneWidget);

      // Now prepare readback to succeed on retry
      repo.readbackException = null;
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_readback_err',
        profile: ProfileEntity(
          userId: 'usr_cp4_readback_err',
          age: 32,
          gender: Gender.male,
          height: 175.0,
          weight: 80.0,
          goal: Goal.gain_muscle,
          activityLevel: ActivityLevel.high,
          activityCanonical: 'active',
        ),
        targetCalories: 2600,
        targetProtein: 170,
        targetCarbs: 300,
        targetFat: 80,
        isFromCache: false,
      );

      // Tap 'Check again'
      await tester.ensureVisible(find.byKey(const Key('onboarding_check_again_button')));
      await tester.tap(find.byKey(const Key('onboarding_check_again_button')));
      await tester.pumpAndSettle();

      // Still exactly 1 save call (no duplicate save POST mutation!)
      expect(repo.syncProfileCallCount, equals(1));
      // Now enters MainScreen
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('4. Save timeout unknown: does NOT auto-retry POST, provides Check status GET only',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_timeout',
        profile: ProfileEntity(userId: 'usr_cp4_timeout'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 30,
        gender: Gender.female,
        height: 160.0,
        weight: 50.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.sedentary,
        step: 5,
      );

      // Save times out
      repo.syncException = const ProfileTimeoutException('Connection timed out');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Sync attempted once
      expect(repo.syncProfileCallCount, equals(1));

      // Shows timeout status banner and 'Kiểm tra trạng thái' button
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(const Key('onboarding_save_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_check_status_button')), findsOneWidget);

      // Prepare server state to show it was processed
      repo.syncException = null;
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_timeout',
        profile: ProfileEntity(
          userId: 'usr_cp4_timeout',
          age: 30,
          gender: Gender.female,
          height: 160.0,
          weight: 50.0,
          goal: Goal.maintain_weight,
          activityLevel: ActivityLevel.low,
          activityCanonical: 'sedentary',
        ),
        targetCalories: 1800,
        targetProtein: 90,
        targetCarbs: 220,
        targetFat: 50,
        isFromCache: false,
      );

      // Tap 'Kiểm tra trạng thái'
      await tester.ensureVisible(find.byKey(const Key('onboarding_check_status_button')));
      await tester.tap(find.byKey(const Key('onboarding_check_status_button')));
      await tester.pumpAndSettle();

      // No new save POST called (remains 1)
      expect(repo.syncProfileCallCount, equals(1));
      // Reconciled into MainScreen
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('5. Readback mismatch: GET 200 with wrong owner or mismatched values does NOT enter Main',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_mismatch',
        profile: ProfileEntity(userId: 'usr_cp4_mismatch'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 26,
        gender: Gender.male,
        height: 172.0,
        weight: 68.0,
        goal: Goal.gain_muscle,
        activityChoice: OnboardingActivityChoice.very_active,
        step: 5,
      );

      // Server returns mismatched height (180.0 instead of 172.0)
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_mismatch',
        profile: ProfileEntity(
          userId: 'usr_cp4_mismatch',
          age: 26,
          gender: Gender.male,
          height: 180.0, // MISMATCH
          weight: 68.0,
          goal: Goal.gain_muscle,
          activityLevel: ActivityLevel.high,
          activityCanonical: 'very_active',
        ),
        targetCalories: 2700,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Rejected due to mismatch, does NOT enter MainScreen
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(const Key('onboarding_save_error_banner')), findsOneWidget);
      expect(find.text('Dữ liệu máy chủ không khớp với thông tin đã nhập.'), findsOneWidget);
    });

    testWidgets('6. Backend 409 Conflict: shows conflict banner and allows profile reload',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_conflict',
        profile: ProfileEntity(userId: 'usr_cp4_conflict'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 24,
        gender: Gender.female,
        height: 162.0,
        weight: 52.0,
        goal: Goal.lose_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );

      // Save encounters 409 CAS conflict
      repo.syncException = const ProfileConflictException('Dữ liệu hồ sơ đã được thay đổi từ một phiên khác.');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Shows conflict banner with reload button
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(const Key('onboarding_save_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_reload_profile_button')), findsOneWidget);
    });

    testWidgets('7. Backend 422 Validation error: displays error message and preserves editable form',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_val_err',
        profile: ProfileEntity(userId: 'usr_cp4_val_err'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 20,
        gender: Gender.male,
        height: 170.0,
        weight: 65.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.light,
        step: 5,
      );

      // 422 validation failure
      repo.syncException = const ProfileValidationException('Chiều cao không hợp lệ');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Confirm and start
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Shows error banner
      expect(find.byKey(const Key('onboarding_save_error_banner')), findsOneWidget);
      expect(find.text('Chiều cao không hợp lệ'), findsOneWidget);

      // Form remains editable (can navigate to edit body measurements)
      await tester.ensureVisible(find.byKey(const Key('review_edit_body')));
      await tester.tap(find.byKey(const Key('review_edit_body')));
      await tester.pumpAndSettle();
      expect(find.text('Your body measurements'), findsOneWidget);
    });

    testWidgets('8. All 5 activity choices round-trip with exact fidelity',
        (tester) async {
      final choices = [
        OnboardingActivityChoice.sedentary,
        OnboardingActivityChoice.light,
        OnboardingActivityChoice.moderate,
        OnboardingActivityChoice.active,
        OnboardingActivityChoice.very_active,
      ];

      for (final choice in choices) {
        final repo = _ControllableProfileRepo();
        final userId = 'usr_act_${choice.name}';
        final initialSnapshot = ProfileSnapshot(
          userId: userId,
          profile: ProfileEntity(userId: userId),
          isFromCache: false,
        );
        repo.initialSnapshot = initialSnapshot;
        repo.storedDraft = OnboardingDraft.forSnapshot(
          initialSnapshot,
          age: 27,
          gender: Gender.male,
          height: 175.0,
          weight: 70.0,
          goal: Goal.maintain_weight,
          activityChoice: choice,
          step: 5,
        );
        repo.readbackSnapshot = ProfileSnapshot(
          userId: userId,
          profile: ProfileEntity(
            userId: userId,
            age: 27,
            gender: Gender.male,
            height: 175.0,
            weight: 70.0,
            goal: Goal.maintain_weight,
            activityLevel: choice.toLegacy(),
            activityCanonical: choice.apiValue,
          ),
          targetCalories: 2200,
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

        await container.read(profileProvider.notifier).loadProfile();

        await tester.pumpWidget(createTestApp(container: container));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
        await tester.pumpAndSettle();

        expect(repo.lastSyncedProfile?.rawActivityCanonical, equals(choice.apiValue));
        expect(find.byType(MainScreen), findsOneWidget);

        container.dispose();
      }
    });

    testWidgets('9. Session epoch change during save/readback discards late response',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_epoch',
        profile: ProfileEntity(userId: 'usr_cp4_epoch'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      final draft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 25,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
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
      final oldEpoch = container.read(profileProvider.notifier).sessionEpoch;

      // Invalidate session epoch (simulating logout/re-login)
      container.read(profileProvider.notifier).resetSession();
      expect(container.read(profileProvider.notifier).sessionEpoch, greaterThan(oldEpoch));

      // Attempting to verify readback with old epoch
      final result = await container.read(profileProvider.notifier).verifyReadback(
            immutableDraft: draft,
            epoch: oldEpoch,
            ownerId: 'usr_cp4_epoch',
          );

      expect(result, isFalse);
      expect(container.read(profileProvider).isCompleteAndConfirmed, isFalse);
    });

    testWidgets('10. 401 Unauthorized during save triggers central logout to login screen',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_unauth',
        profile: ProfileEntity(userId: 'usr_cp4_unauth'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 25,
        gender: Gender.female,
        height: 165.0,
        weight: 55.0,
        goal: Goal.lose_weight,
        activityChoice: OnboardingActivityChoice.light,
        step: 5,
      );

      // Save encounters 401 Unauthorized
      repo.syncException = const UnauthorizedException('Token expired');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Gate handles 401 and navigates to Login
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
    });

    testWidgets('11. Completion succeeds and enters MainScreen when 6 fields match even if targetCalories is 0 or negative',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_zero_cals',
        profile: ProfileEntity(userId: 'usr_cp4_zero_cals'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 26,
        gender: Gender.male,
        height: 176.0,
        weight: 71.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );

      // Server readback matches all 6 fields, but targetCalories is 0 (or negative)
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_zero_cals',
        profile: ProfileEntity(
          userId: 'usr_cp4_zero_cals',
          age: 26,
          gender: Gender.male,
          height: 176.0,
          weight: 71.0,
          goal: Goal.maintain_weight,
          activityLevel: ActivityLevel.medium,
          activityCanonical: 'moderate',
        ),
        targetCalories: 0, // Zero calories must not block completion
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Readback verified and admitted to MainScreen
      expect(repo.clearDraftCallCount, equals(1));
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('12. Readback mismatch shows Check Again button which issues GET only without retry POST',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_mismatch_retry',
        profile: ProfileEntity(userId: 'usr_cp4_mismatch_retry'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 28,
        gender: Gender.female,
        height: 160.0,
        weight: 50.0,
        goal: Goal.lose_weight,
        activityChoice: OnboardingActivityChoice.light,
        step: 5,
      );

      // Initial readback returns mismatched weight
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_mismatch_retry',
        profile: ProfileEntity(
          userId: 'usr_cp4_mismatch_retry',
          age: 28,
          gender: Gender.female,
          height: 160.0,
          weight: 55.0, // Mismatch (draft was 50.0)
          goal: Goal.lose_weight,
          activityLevel: ActivityLevel.low,
          activityCanonical: 'light',
        ),
        targetCalories: 1600,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap confirm
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      expect(repo.syncProfileCallCount, equals(1));
      final readbackCountBefore = repo.readbackCallCount;

      // Shows error banner and check again button
      expect(find.byKey(const Key('onboarding_save_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_check_again_button')), findsOneWidget);

      // Now server has the correct weight
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_cp4_mismatch_retry',
        profile: ProfileEntity(
          userId: 'usr_cp4_mismatch_retry',
          age: 28,
          gender: Gender.female,
          height: 160.0,
          weight: 50.0, // Matches now
          goal: Goal.lose_weight,
          activityLevel: ActivityLevel.low,
          activityCanonical: 'light',
        ),
        targetCalories: 1550,
        isFromCache: false,
      );

      // Tap Check Again button
      await tester.ensureVisible(find.byKey(const Key('onboarding_check_again_button')));
      await tester.tap(find.byKey(const Key('onboarding_check_again_button')));
      await tester.pumpAndSettle();

      // Zero new POST mutations: syncProfileCallCount remains 1
      expect(repo.syncProfileCallCount, equals(1));
      // Only GET readback called
      expect(repo.readbackCallCount, greaterThan(readbackCountBefore));
      // Now completes and admits to MainScreen
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('13. Readback with wrong owner identity rejects completion and preserves user draft',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_active_owner',
        profile: ProfileEntity(userId: 'usr_active_owner'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 30,
        gender: Gender.male,
        height: 180.0,
        weight: 75.0,
        goal: Goal.gain_muscle,
        activityChoice: OnboardingActivityChoice.active,
        step: 5,
      );

      // Readback returns different user_id
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_different_owner',
        profile: ProfileEntity(
          userId: 'usr_different_owner',
          age: 30,
          gender: Gender.male,
          height: 180.0,
          weight: 75.0,
          goal: Goal.gain_muscle,
          activityLevel: ActivityLevel.high,
          activityCanonical: 'active',
        ),
        targetCalories: 2500,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      // Blocked from MainScreen
      expect(find.byType(MainScreen), findsNothing);
      expect(find.text('Xác thực thất bại: Chủ tài khoản không khớp.'), findsOneWidget);
      // Draft was not cleared
      expect(repo.clearDraftCallCount, equals(0));
      expect(repo.storedDraft, isNotNull);
    });

    test('14. Direct Notifier calls reject new mutations during saveTimeoutUnknown, readbackPending, or identityMismatch',
        () async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_provider_guard',
        profile: ProfileEntity(userId: 'usr_provider_guard'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      final draft1 = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 25,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );
      final draft2 = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 26,
        gender: Gender.male,
        height: 176.0,
        weight: 71.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.active,
        step: 5,
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      // Simulate save timeout
      repo.syncException = const ProfileTimeoutException('Timeout');
      final firstSave = await notifier.saveAndVerifyOnboarding(draft1);
      expect(firstSave, isFalse);
      expect(notifier.state.status, equals(ProfileStatus.saveTimeoutUnknown));
      expect(repo.syncProfileCallCount, equals(1));

      // Attempt second save with different draft while in saveTimeoutUnknown
      final blockedSave = await notifier.saveAndVerifyOnboarding(draft2);
      expect(blockedSave, isFalse);
      expect(repo.syncProfileCallCount, equals(1),
          reason: 'Must not trigger POST mutation during timeoutUnknown');

      // Reconcile performs GET only without calling syncProfile
      repo.syncException = null;
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_provider_guard',
        profile: ProfileEntity(
          userId: 'usr_provider_guard',
          age: 25,
          gender: Gender.male,
          height: 175.0,
          weight: 70.0,
          goal: Goal.maintain_weight,
          activityLevel: ActivityLevel.medium,
          activityCanonical: 'moderate',
        ),
        targetCalories: 2100,
        isFromCache: false,
      );
      final reconciled = await notifier.reconcileOnboarding(draft1);
      expect(reconciled, isTrue);
      expect(repo.syncProfileCallCount, equals(1),
          reason: 'Reconcile must be pure GET readback');
      expect(notifier.state.isCompleteAndConfirmed, isTrue);

      // Validation failure (422) allows retry
      notifier.resetSession();
      await notifier.loadProfile();
      repo.syncException = const ProfileValidationException('Invalid age');
      final valSave = await notifier.saveAndVerifyOnboarding(draft1);
      expect(valSave, isFalse);
      expect(notifier.state.status, equals(ProfileStatus.saveError));

      repo.syncException = null;
      final retrySave = await notifier.saveAndVerifyOnboarding(draft1);
      expect(retrySave, isTrue);
    });

    test('15. Direct Notifier call rejected when status is identityMismatch',
        () async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_guard_owner',
        profile: ProfileEntity(userId: 'usr_guard_owner'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      final draft1 = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 29,
        gender: Gender.female,
        height: 165.0,
        weight: 55.0,
        goal: Goal.lose_weight,
        activityChoice: OnboardingActivityChoice.light,
        step: 5,
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      // Readback returns different user
      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_impostor',
        profile: ProfileEntity(
          userId: 'usr_impostor',
          age: 29,
          gender: Gender.female,
          height: 165.0,
          weight: 55.0,
          goal: Goal.lose_weight,
          activityCanonical: 'light',
        ),
        targetCalories: 1700,
        isFromCache: false,
      );

      final firstSave = await notifier.saveAndVerifyOnboarding(draft1);
      expect(firstSave, isFalse);
      expect(notifier.state.status, equals(ProfileStatus.identityMismatch));
      expect(repo.syncProfileCallCount, equals(1));

      // Attempting any save while in identityMismatch is rejected
      final secondSave = await notifier.saveAndVerifyOnboarding(draft1);
      expect(secondSave, isFalse);
      expect(repo.syncProfileCallCount, equals(1),
          reason: 'Zero new mutations on identity mismatch');
    });

    testWidgets('16. Wrong owner locks Confirm, shows Logout button, tapping Confirm triggers 0 mutations',
        (tester) async {
      final repo = _ControllableProfileRepo();
      final initialSnapshot = const ProfileSnapshot(
        userId: 'usr_owner_lock',
        profile: ProfileEntity(userId: 'usr_owner_lock'),
        isFromCache: false,
      );
      repo.initialSnapshot = initialSnapshot;
      repo.storedDraft = OnboardingDraft.forSnapshot(
        initialSnapshot,
        age: 31,
        gender: Gender.male,
        height: 175.0,
        weight: 72.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );

      repo.readbackSnapshot = const ProfileSnapshot(
        userId: 'usr_wrong_owner_77',
        profile: ProfileEntity(
          userId: 'usr_wrong_owner_77',
          age: 31,
          gender: Gender.male,
          height: 175.0,
          weight: 72.0,
          goal: Goal.maintain_weight,
          activityCanonical: 'moderate',
        ),
        targetCalories: 2200,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')));
      await tester.pumpAndSettle();

      expect(repo.syncProfileCallCount, equals(1));
      expect(find.text('Xác thực thất bại: Chủ tài khoản không khớp.'), findsOneWidget);

      // Confirm button is disabled
      final confirmBtn = tester.widget<InkWell>(
        find.byKey(const Key('onboarding_confirm_button')),
      );
      expect(confirmBtn.onTap, isNull, reason: 'Confirm button must be disabled on identity mismatch');

      // Attempt to tap Confirm again
      await tester.tap(find.byKey(const Key('onboarding_confirm_button')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.syncProfileCallCount, equals(1), reason: 'Zero new mutations on subsequent tap');

      // Logout button is present in error banner
      expect(find.byKey(const Key('onboarding_logout_button')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('onboarding_logout_button')));
      await tester.tap(find.byKey(const Key('onboarding_logout_button')));
      await tester.pumpAndSettle();

      // Logout navigated to mock login screen
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
    });

    test('17. Real ProfileRepositoryImpl: save 200 + fresh GET 500 error does NOT fallback to cache or cache new snapshot',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localDataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      // Pre-seed an old cache in local storage
      final oldModel = ProfileSnapshotModel(
        userId: 'usr_real_repo_1',
        profile: const ProfileModel(
          userId: 'usr_real_repo_1',
          age: 20,
          gender: Gender.male,
          height: 170.0,
          weight: 60.0,
        ),
        targetCalories: 1800,
      );
      await localDataSource.cacheSnapshot(oldModel);

      bool initialLoad = true;
      int postCount = 0;
      int getCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      dio.httpClientAdapter = _TestScriptedAdapter((options) {
        if (options.method == 'POST') {
          postCount++;
          return ResponseBody.fromString(
            jsonEncode({'message': 'profile updated'}),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else if (options.method == 'GET') {
          getCount++;
          if (initialLoad) {
            return ResponseBody.fromString(
              jsonEncode({
                'user_id': 'usr_real_repo_1',
                'profile': {
                  'user_id': 'usr_real_repo_1',
                  'age': 20,
                  'gender': 'male',
                  'height': 170.0,
                  'weight': 60.0,
                },
                'health_stats': {'daily_calories': 1800},
              }),
              200,
              headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
            );
          }
          // Subsequent GET (fresh readback) returns 500
          return ResponseBody.fromString(
            jsonEncode({'detail': 'Internal Server Error'}),
            500,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final remoteDataSource = ProfileRemoteDataSourceImpl(dio: dio);
      final realRepo = ProfileRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
      );

      final notifier = ProfileNotifier(realRepo);
      await notifier.loadProfile();
      expect(notifier.state.confirmedUserId, equals('usr_real_repo_1'));
      expect(notifier.state.isNetworkConfirmed, isTrue);

      initialLoad = false; // Next GET will return 500

      // Direct verification: realRepo.fetchProfileSnapshot must throw on network error, NOT return cached
      expect(
        () => realRepo.fetchProfileSnapshot(cacheOnSuccess: false),
        throwsA(isA<Exception>()),
      );

      final draft = OnboardingDraft(
        userId: 'usr_real_repo_1',
        age: 28,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );

      final result = await notifier.saveAndVerifyOnboarding(draft);
      expect(result, isFalse);
      expect(postCount, equals(1));
      expect(getCount, greaterThanOrEqualTo(2));
      expect(notifier.state.status, equals(ProfileStatus.readbackPending));
      expect(notifier.state.isCompleteAndConfirmed, isFalse);

      // Verify local cache still contains the old snapshot, not overwritten by unverified draft
      final cachedSnapshot = await localDataSource.getLastSnapshot();
      expect(cachedSnapshot?.profile.age, equals(20));
      expect(cachedSnapshot?.profile.height, equals(170.0));
    });

    test('18. Real ProfileRepositoryImpl: save 200 + fresh GET wrong owner rejects completion and does NOT cache snapshot',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localDataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      bool initialLoad = true;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      dio.httpClientAdapter = _TestScriptedAdapter((options) {
        if (options.method == 'POST') {
          return ResponseBody.fromString(
            jsonEncode({'message': 'profile updated'}),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else if (options.method == 'GET') {
          if (initialLoad) {
            return ResponseBody.fromString(
              jsonEncode({
                'user_id': 'usr_legitimate_owner',
                'profile': {
                  'user_id': 'usr_legitimate_owner',
                },
              }),
              200,
              headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
            );
          }
          return ResponseBody.fromString(
            jsonEncode({
              'user_id': 'usr_impostor_99',
              'profile': {
                'user_id': 'usr_impostor_99',
                'age': 28,
                'gender': 'male',
                'height': 175.0,
                'weight': 70.0,
                'goal': 'maintain_weight',
                'activity_level': 'moderate',
                'activityCanonical': 'moderate',
              },
              'health_stats': {
                'daily_calories': 2200,
              },
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final remoteDataSource = ProfileRemoteDataSourceImpl(dio: dio);
      final realRepo = ProfileRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
      );

      final notifier = ProfileNotifier(realRepo);
      await notifier.loadProfile();
      expect(notifier.state.confirmedUserId, equals('usr_legitimate_owner'));

      initialLoad = false; // Next GET returns wrong owner

      final draft = OnboardingDraft(
        userId: 'usr_legitimate_owner',
        age: 28,
        gender: Gender.male,
        height: 175.0,
        weight: 70.0,
        goal: Goal.maintain_weight,
        activityChoice: OnboardingActivityChoice.moderate,
        step: 5,
      );
      await realRepo.saveDraft(draft);

      final result = await notifier.saveAndVerifyOnboarding(draft);
      expect(result, isFalse);
      expect(notifier.state.status, equals(ProfileStatus.identityMismatch));
      expect(notifier.state.isCompleteAndConfirmed, isFalse);

      // Draft must NOT be cleared on wrong owner
      final savedDraft = await realRepo.getDraft('usr_legitimate_owner');
      expect(savedDraft, isNotNull);

      // Impostor snapshot must NOT be cached in local storage
      final impostorCache = await localDataSource.getLastSnapshot(expectedUserId: 'usr_impostor_99');
      expect(impostorCache, isNull);

      // And legitimate owner's cache was NOT updated with the submitted draft values (age is still null)
      final legitCache = await localDataSource.getLastSnapshot(expectedUserId: 'usr_legitimate_owner');
      expect(legitCache?.profile.age, isNull);
    });
  });
}

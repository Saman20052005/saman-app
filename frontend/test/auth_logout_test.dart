import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dio/dio.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/onboarding_flow_screen.dart';
import 'package:health_ai_app/features/profile/presentation/profile_gate.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

class _FailingSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values;
  _FailingSecureStorage(this.values);

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    // Simulate persistent storage failure when deleting auth_token / jwt_token
    if (key == 'auth_token' || key == 'jwt_token') {
      return; // Key is NOT deleted from values!
    }
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(values);
  }
}

class _ControllableSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values;
  final Completer<void>? deleteCompleter;
  final bool shouldFail;

  _ControllableSecureStorage(
    this.values, {
    this.deleteCompleter,
    this.shouldFail = false,
  });

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (deleteCompleter != null && !deleteCompleter!.isCompleted) {
      await deleteCompleter!.future;
    }
    if (shouldFail && (key == 'auth_token' || key == 'jwt_token')) {
      return; // Simulate persistent failure
    }
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(values);
  }
}

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

class _OfflineFailingProfileRepository implements ProfileRepository {
  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    throw Exception('Connection refused: Backend is completely offline');
  }

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    throw Exception('Connection refused');
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => null;

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}
}

class _DelayedProfileRepository implements ProfileRepository {
  final Completer<ProfileSnapshot?> completer = Completer<ProfileSnapshot?>();

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) {
    return completer.future;
  }

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => null;

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthHelper.logout - Token and Cache Cleanup', () {
    test('removes all auth tokens and identity from secure storage and prefs',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'secret_auth_token_123',
        'jwt_token': 'secret_jwt_token_456',
        'user_email': 'test@example.com',
        'user_fullname': 'Test Athlete',
      });

      SharedPreferences.setMockInitialValues({
        'cached_profile': '{"age": 25, "height": 175}',
        'cached_profile_snapshot_v2': '{"profile": {"age": 25}}',
        'cached_profile_snapshot_v2_user_test_99':
            '{"user_id": "user_test_99", "profile": {"age": 25}}',
        'onboarding_draft_user_test_99':
            '{"user_id": "user_test_99", "age": 25, "step": 2}',
        'language_code': 'vi',
        'is_dark_mode': true,
        'user_email': 'test@example.com',
        'user_fullname': 'Test Athlete',
      });

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );

      // Seed active state with userId to test owner capture
      container.read(profileProvider.notifier).state = ProfileState(
        profile: const ProfileEntity(
          userId: 'user_test_99',
          age: 25,
          height: 175,
          weight: 70,
        ),
        confirmedUserId: 'user_test_99',
      );

      // Perform logout
      await AuthHelper.logout(container);

      // Verify secure storage cleanup
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'auth_token'), isNull);
      expect(await secure.read(key: 'jwt_token'), isNull);
      expect(await secure.read(key: 'user_email'), isNull);
      expect(await secure.read(key: 'user_fullname'), isNull);

      // Verify SharedPreferences cleanup
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cached_profile'), isFalse);
      expect(prefs.containsKey('cached_profile_snapshot_v2'), isFalse);
      expect(
          prefs.containsKey('cached_profile_snapshot_v2_user_test_99'), isFalse);
      expect(prefs.containsKey('onboarding_draft_user_test_99'), isFalse);
      expect(prefs.containsKey('user_email'), isFalse);
      expect(prefs.containsKey('user_fullname'), isFalse);

      // Verify preserved settings
      expect(prefs.getString('language_code'), equals('vi'));
      expect(prefs.getBool('is_dark_mode'), isTrue);
    });

    test('increments Profile session epoch and resets profile state', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      final notifier = container.read(profileProvider.notifier);
      final initialEpoch = notifier.sessionEpoch;

      await AuthHelper.logout(container);

      expect(notifier.sessionEpoch, equals(initialEpoch + 1));
      final state = container.read(profileProvider);
      expect(state.status, equals(ProfileStatus.initial));
      expect(state.profile.isValid, isFalse);
    });

    test('is idempotent when called multiple times sequentially', () async {
      SharedPreferences.setMockInitialValues({
        'language_code': 'en',
        'is_dark_mode': false,
      });

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      await AuthHelper.logout(container);
      await AuthHelper.logout(container);
      await AuthHelper.logout(container);

      expect(prefs.getString('language_code'), equals('en'));
      expect(prefs.getBool('is_dark_mode'), isFalse);
      expect(await AuthHelper.hasValidSession(), isFalse);
    });
  });

  group('Regression: CP-AUTH-LOGOUT-FIX', () {
    test('1. Logout -> Login; reopening stays on Login', () async {
      // Simulate existing session on device
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'active_device_token_xyz',
        'jwt_token': 'active_jwt_xyz',
        'user_email': 'sony_athlete@example.com',
      });
      SharedPreferences.setMockInitialValues({
        'cached_profile_snapshot_v2': '{"profile":{"age":28}}',
        'user_email': 'sony_athlete@example.com',
      });

      expect(await AuthHelper.isLoggedIn(), isTrue);
      expect(await AuthHelper.hasValidSession(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      // Perform clean logout
      await AuthHelper.logout(container);

      // Verification: local credentials and session are invalidated
      expect(await AuthHelper.isLoggedIn(), isFalse);
      expect(await AuthHelper.getToken(), isNull);
      expect(await AuthHelper.hasValidSession(), isFalse);

      // Simulate closing app from recent apps and reopening
      // SplashScreen calls AuthHelper.isLoggedIn() -> must be false
      final reopenIsLoggedIn = await AuthHelper.isLoggedIn();
      expect(reopenIsLoggedIn, isFalse);
    });

    test(
        '2. Request profile cu hoan tat sau logout khong phuc hoi session',
        () async {
      final delayedRepo = _DelayedProfileRepository();
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          profileRepositoryProvider.overrideWithValue(delayedRepo),
        ],
      );

      final notifier = container.read(profileProvider.notifier);
      final initialEpoch = notifier.sessionEpoch;

      // Start an authenticated profile load under epoch 0
      final loadFuture = notifier.loadProfile();
      expect(container.read(profileProvider).status, ProfileStatus.loading);

      // User performs logout while request is still pending
      await AuthHelper.logout(container);
      expect(notifier.sessionEpoch, equals(initialEpoch + 1));
      expect(container.read(profileProvider).status, ProfileStatus.initial);

      // Delayed network response arrives with complete profile data
      delayedRepo.completer.complete(
        const ProfileSnapshot(
          userId: 'stale_user_99',
          profile: ProfileEntity(
            userId: 'stale_user_99',
            age: 28,
            gender: Gender.male,
            height: 175.0,
            weight: 72.0,
            activityLevel: ActivityLevel.high,
            goal: Goal.maintain_weight,
          ),
          isFromCache: false,
        ),
      );

      await loadFuture;

      // Crucial verification: stale response was discarded!
      // State remains initial, NOT complete or ready, userId remains null.
      final stateAfterStaleResponse = container.read(profileProvider);
      expect(stateAfterStaleResponse.status, ProfileStatus.initial);
      expect(stateAfterStaleResponse.userId, isNull);
      expect(stateAfterStaleResponse.isCompleteAndConfirmed, isFalse);
    });

    test('3. Logout khi backend mat ket noi (offline)', () async {
      // Backend is completely offline / unreachable
      final failingRepo = _OfflineFailingProfileRepository();
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'offline_token_xyz',
        'jwt_token': 'offline_jwt_xyz',
      });
      SharedPreferences.setMockInitialValues({
        'cached_profile_snapshot_v2': '{"profile":{"age":30}}',
        'user_email': 'offline_user@example.com',
      });

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          profileRepositoryProvider.overrideWithValue(failingRepo),
        ],
      );

      // Local logout must NOT throw and must NOT depend on backend
      await expectLater(AuthHelper.logout(container), completes);

      // Verify tokens and user caches were wiped locally
      expect(await AuthHelper.isLoggedIn(), isFalse);
      expect(await AuthHelper.getToken(), isNull);
      final updatedPrefs = await SharedPreferences.getInstance();
      expect(updatedPrefs.containsKey('cached_profile_snapshot_v2'), isFalse);
      expect(updatedPrefs.containsKey('user_email'), isFalse);
    });

    testWidgets(
        '4. Dang nhap user incomplete -> onboarding; user complete -> Home',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();

      // Case A: User with network-confirmed INCOMPLETE profile -> Onboarding
      final containerIncomplete = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );

      containerIncomplete.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'incomplete_user_01',
        profile: const ProfileEntity(
          userId: 'incomplete_user_01',
          age: null,
          height: null,
          weight: null,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: containerIncomplete,
          child: const MaterialApp(
            home: ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);

      // Case B: User with network-confirmed COMPLETE profile -> MainScreen (Home)
      final containerComplete = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );

      containerComplete.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'complete_user_02',
        profile: const ProfileEntity(
          userId: 'complete_user_02',
          age: 28,
          gender: Gender.male,
          height: 175.0,
          weight: 72.0,
          activityLevel: ActivityLevel.high,
          goal: Goal.maintain_weight,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: containerComplete,
          child: const MaterialApp(
            home: ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(OnboardingFlowScreen), findsNothing);
    });

    testWidgets(
        '5. Mount ProfileGate, bam Logout tren UI ProfileScreen thuc te khong bi disposed-ref va ve dung Login',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'active_token_sony_01',
        'jwt_token': 'active_jwt_sony_01',
        'user_email': 'sony_athlete@example.com',
      });
      SharedPreferences.setMockInitialValues({
        'cached_profile_snapshot_v2': '{"profile":{"age":28}}',
        'user_email': 'sony_athlete@example.com',
      });

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'sony_user_live',
        profile: const ProfileEntity(
          userId: 'sony_user_live',
          age: 28,
          gender: Gender.male,
          height: 175.0,
          weight: 70.0,
          activityLevel: ActivityLevel.medium,
          goal: Goal.maintain_weight,
        ),
      );

      // Switch to Profile tab (index 4)
      container.read(mainNavIndexProvider.notifier).state = 4;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);

      // Locate logout button on ProfileScreen and scroll to it
      final logoutBtn = find.byIcon(Icons.logout_rounded);
      await tester.scrollUntilVisible(logoutBtn, 200);
      expect(logoutBtn, findsOneWidget);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      // Locate confirmation dialog button
      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Log out'),
      );
      expect(confirmBtn, findsOneWidget);

      // Verify no authenticated requests are fired during logout
      int newRequestsDuringLogout = 0;
      final logoutRequestInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.headers.containsKey('Authorization')) {
            newRequestsDuringLogout++;
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.add(logoutRequestInterceptor);
      addTearDown(() => ApiClient.dio.interceptors.remove(logoutRequestInterceptor));

      // Tap confirm logout: this triggers AuthHelper.logout(ref)
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // CRITICAL ASSERTION: No new authenticated requests fired due to rebuild or invalidation
      expect(newRequestsDuringLogout, equals(0));

      // CRITICAL ASSERTION: No unhandled exception from disposed ref!
      expect(tester.takeException(), isNull);

      // Verify routing successfully replaced stack with LoginScreen
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsNothing);

      // Verify local storage and state are cleared
      expect(await AuthHelper.isLoggedIn(), isFalse);
      expect(await AuthHelper.getToken(), isNull);
      expect(container.read(authLoggingOutProvider), isFalse);
    });

    testWidgets(
        '6. Mount ProfileGate, bam Logout tren UI HomeScreen thuc te khong bi disposed-ref va ve dung Login',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'token_home_01',
        'jwt_token': 'jwt_home_01',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'home_user_01',
        profile: const ProfileEntity(
          userId: 'home_user_01',
          age: 25,
          gender: Gender.female,
          height: 165.0,
          weight: 55.0,
          activityLevel: ActivityLevel.high,
          goal: Goal.maintain_weight,
        ),
      );

      // Ensure on Home tab (index 0)
      container.read(mainNavIndexProvider.notifier).state = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);

      // Open settings bottom sheet from header
      final settingsBtn = find.byIcon(Icons.settings_outlined);
      expect(settingsBtn, findsOneWidget);
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();

      // Tap logout tile in bottom sheet
      final logoutTile = find.byIcon(Icons.logout_rounded);
      expect(logoutTile, findsOneWidget);
      await tester.tap(logoutTile);
      await tester.pumpAndSettle();

      // Confirm dialog
      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton),
      );
      expect(confirmBtn, findsOneWidget);

      // Verify no authenticated requests are fired during logout
      int newRequestsDuringLogout = 0;
      final logoutRequestInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.headers.containsKey('Authorization')) {
            newRequestsDuringLogout++;
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.add(logoutRequestInterceptor);
      addTearDown(() => ApiClient.dio.interceptors.remove(logoutRequestInterceptor));

      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // CRITICAL ASSERTION: No new authenticated requests fired due to rebuild or invalidation
      expect(newRequestsDuringLogout, equals(0));

      // Assertions
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(await AuthHelper.isLoggedIn(), isFalse);
      expect(container.read(authLoggingOutProvider), isFalse);
    });

    testWidgets(
        '7. Logout tu GateErrorView ket thuc dung ve Login',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'token_error_gate',
        'jwt_token': 'jwt_error_gate',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      // Set profile to load error state
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.error,
        errorMessage: 'Connection failed',
        profile: const ProfileEntity(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final errorLogoutBtn = find.byKey(const Key('profile_gate_error_logout_button'));
      expect(errorLogoutBtn, findsOneWidget);

      await tester.tap(errorLogoutBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
      expect(await AuthHelper.isLoggedIn(), isFalse);
    });

    testWidgets(
        '8. Logout tu Step 1 Onboarding ket thuc dung ve Login',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'token_onboarding_step1',
        'jwt_token': 'jwt_onboarding_step1',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      // Incomplete user -> admitted to OnboardingFlowScreen
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'onboarding_user_01',
        profile: const ProfileEntity(userId: 'onboarding_user_01'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowScreen), findsOneWidget);

      // Tap back button on Step 1 (leading back icon)
      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Confirm dialog appears
      final confirmLogoutBtn = find.byKey(const Key('onboarding_logout_dialog_confirm'));
      expect(confirmLogoutBtn, findsOneWidget);
      await tester.tap(confirmLogoutBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
      expect(find.byType(OnboardingFlowScreen), findsNothing);
      expect(await AuthHelper.isLoggedIn(), isFalse);
    });

    testWidgets(
        '9. Khi storage xoa loi hoac token con: quang LogoutException, co duoc giai phong, khong dieu huong va key ngoai le nguyen ven',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storageValues = <String, String>{
        'auth_token': 'stuck_auth_token_999',
        'jwt_token': 'stuck_jwt_token_999',
        'user_email': 'athlete_stuck@example.com',
        'app_theme_mode': 'dark_athletic',
        'app_language': 'vi_VN',
        'device_custom_uuid': 'sony_custom_id_456',
      };

      final failingStorage = _FailingSecureStorage(storageValues);
      AuthHelper.setStorageForTesting(failingStorage);
      addTearDown(AuthHelper.resetStorageForTesting);

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'sony_user_stuck',
        profile: const ProfileEntity(
          userId: 'sony_user_stuck',
          age: 29,
          gender: Gender.male,
          height: 180.0,
          weight: 75.0,
          activityLevel: ActivityLevel.high,
          goal: Goal.maintain_weight,
        ),
      );

      // 1. Direct invocation test:
      // Calling AuthHelper.logout throws LogoutException, releases authLoggingOutProvider,
      // and leaves non-credential keys completely intact.
      await expectLater(
        () => AuthHelper.logout(container),
        throwsA(isA<LogoutException>()),
      );
      expect(container.read(authLoggingOutProvider), isFalse,
          reason: 'Co logout phai duoc giai phong (false) ngay ca khi nem LogoutException');
      expect(storageValues['app_theme_mode'], equals('dark_athletic'),
          reason: 'Key khong thuoc credentials phai nguyen ven');
      expect(storageValues['app_language'], equals('vi_VN'),
          reason: 'Key khong thuoc credentials phai nguyen ven');
      expect(storageValues['device_custom_uuid'], equals('sony_custom_id_456'),
          reason: 'Key khong thuoc credentials phai nguyen ven');
      expect(storageValues['auth_token'], equals('stuck_auth_token_999'),
          reason: 'Token con lai do delete that bai');

      // 2. Widget UI test:
      // Mount ProfileGate -> user on ProfileScreen attempts logout -> fails -> SnackBar shown,
      // no navigation to LoginScreen, screen remains interactive and retryable.
      container.read(mainNavIndexProvider.notifier).state = 4;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);

      final logoutBtn = find.byIcon(Icons.logout_rounded);
      await tester.scrollUntilVisible(logoutBtn, 200);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Log out'),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // UI caught LogoutException:
      // 1. Did NOT navigate to LoginScreen!
      expect(find.byKey(const Key('mock_login_screen')), findsNothing);
      // 2. MainScreen and ProfileScreen remain mounted (recovery/retry screen intact)
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);
      // 3. Error recovery SnackBar with 'Thu lai' is presented
      expect(find.textContaining('Đăng xuất thất bại'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      // 4. Logout flag is released
      expect(container.read(authLoggingOutProvider), isFalse);
      // 5. Non-credential keys remain intact in storage
      expect(storageValues['app_theme_mode'], equals('dark_athletic'));
      expect(storageValues['app_language'], equals('vi_VN'));
    });

    testWidgets(
        '10. Storage Completer in-flight: Gate rebuild giu nguyen State Main/Profile, thao tac bi khoa -> hoan tat ve Login khong disposed-ref',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storageValues = <String, String>{
        'auth_token': 'token_inflight_01',
        'jwt_token': 'jwt_inflight_01',
        'user_email': 'athlete_inflight@example.com',
      };
      final deleteCompleter = Completer<void>();
      final storage = _ControllableSecureStorage(
        storageValues,
        deleteCompleter: deleteCompleter,
        shouldFail: false,
      );
      AuthHelper.setStorageForTesting(storage);
      addTearDown(AuthHelper.resetStorageForTesting);

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'sony_user_inflight',
        profile: const ProfileEntity(
          userId: 'sony_user_inflight',
          age: 26,
          gender: Gender.male,
          height: 178.0,
          weight: 72.0,
          activityLevel: ActivityLevel.high,
          goal: Goal.maintain_weight,
        ),
      );

      container.read(mainNavIndexProvider.notifier).state = 4;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);

      final mainStateBefore = tester.state(find.byType(MainScreen));
      final profileStateBefore = tester.state(find.byType(ProfileScreen));

      // Open logout dialog
      final logoutBtn = find.byIcon(Icons.logout_rounded);
      await tester.scrollUntilVisible(logoutBtn, 200);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Log out'),
      );
      expect(confirmBtn, findsOneWidget);

      // Confirm logout: triggers AuthHelper.logout(ref) which awaits deleteCompleter.future
      await tester.tap(confirmBtn);

      // Call pump to allow dialog to dismiss and ProfileGate to rebuild while storage delete is awaiting
      await tester.pump();

      // Verify logout flag is active
      expect(container.read(authLoggingOutProvider), isTrue);

      // Verify MainScreen and ProfileScreen are NOT remounted - State instances are identical
      final mainStateDuring = tester.state(find.byType(MainScreen));
      final profileStateDuring = tester.state(find.byType(ProfileScreen));
      expect(identical(mainStateDuring, mainStateBefore), isTrue,
          reason: 'State cua MainScreen phai la instance cu');
      expect(identical(profileStateDuring, profileStateBefore), isTrue,
          reason: 'State cua ProfileScreen phai la instance cu');

      // Verify interaction is blocked (IgnorePointer.ignoring == true)
      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(ProfileGate),
          matching: find.byType(IgnorePointer),
        ).first,
      );
      expect(ignorePointer.ignoring, isTrue,
          reason: 'Thao tac phai bi khoa bang IgnorePointer(ignoring: true)');

      // Complete storage deletion
      deleteCompleter.complete();
      await tester.pumpAndSettle();

      // Navigation succeeds cleanly without disposed ref error
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mock_login_screen')), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(container.read(authLoggingOutProvider), isFalse);
    });

    testWidgets(
        '11. Storage Completer in-flight roi that bai: State Main/Profile giu nguyen, recovery hoat dong, co duoc giai phong',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storageValues = <String, String>{
        'auth_token': 'token_fail_inflight',
        'jwt_token': 'jwt_fail_inflight',
        'user_email': 'athlete_fail@example.com',
        'app_theme_mode': 'dark_athletic',
      };
      final deleteCompleter = Completer<void>();
      final storage = _ControllableSecureStorage(
        storageValues,
        deleteCompleter: deleteCompleter,
        shouldFail: true,
      );
      AuthHelper.setStorageForTesting(storage);
      addTearDown(AuthHelper.resetStorageForTesting);

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        ],
      );
      addTearDown(container.dispose);

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        isNetworkConfirmed: true,
        isFromCache: false,
        confirmedUserId: 'sony_user_fail_inflight',
        profile: const ProfileEntity(
          userId: 'sony_user_fail_inflight',
          age: 27,
          gender: Gender.male,
          height: 176.0,
          weight: 71.0,
          activityLevel: ActivityLevel.high,
          goal: Goal.maintain_weight,
        ),
      );

      container.read(mainNavIndexProvider.notifier).state = 4;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              AppRoutes.login: (ctx) => const Scaffold(
                    key: Key('mock_login_screen'),
                    body: Text('Login Screen'),
                  ),
            },
            home: const ProfileGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mainStateBefore = tester.state(find.byType(MainScreen));
      final profileStateBefore = tester.state(find.byType(ProfileScreen));

      // Open logout dialog
      final logoutBtn = find.byIcon(Icons.logout_rounded);
      await tester.scrollUntilVisible(logoutBtn, 200);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Log out'),
      );
      await tester.tap(confirmBtn);

      // Pump to trigger rebuild with in-flight logout
      await tester.pump();

      expect(container.read(authLoggingOutProvider), isTrue);
      expect(identical(tester.state(find.byType(MainScreen)), mainStateBefore), isTrue);
      expect(identical(tester.state(find.byType(ProfileScreen)), profileStateBefore), isTrue);

      final ignorePointerDuring = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(ProfileGate),
          matching: find.byType(IgnorePointer),
        ).first,
      );
      expect(ignorePointerDuring.ignoring, isTrue);

      // Now complete the completer (which simulates deletion failure)
      deleteCompleter.complete();
      await tester.pumpAndSettle();

      // UI caught LogoutException:
      // 1. Did NOT navigate to Login
      expect(find.byKey(const Key('mock_login_screen')), findsNothing);
      // 2. MainScreen and ProfileScreen remain mounted, still the same instances
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(identical(tester.state(find.byType(MainScreen)), mainStateBefore), isTrue);
      expect(identical(tester.state(find.byType(ProfileScreen)), profileStateBefore), isTrue);
      // 3. Error recovery SnackBar is present with 'Thử lại'
      expect(find.textContaining('Đăng xuất thất bại'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      // 4. Logout flag is released
      expect(container.read(authLoggingOutProvider), isFalse);
      // 5. Interaction is UNBLOCKED (ignoring: false) so user can tap retry
      final ignorePointerAfter = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(ProfileGate),
          matching: find.byType(IgnorePointer),
        ).first,
      );
      expect(ignorePointerAfter.ignoring, isFalse);
    });
  });
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/login/login_screen.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

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

class _TestControlledProfileRepository implements ProfileRepository {
  int fetchCount = 0;
  int updateCallCount = 0;
  int clearCount = 0;
  ProfileSnapshot? snapshotToReturn;
  Object? errorToThrow;
  Completer<ProfileSnapshot?>? completer;

  /// Scripted responses consumed one per fetch, before the fallbacks above.
  final List<Completer<ProfileSnapshot?>> queue = [];

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    fetchCount++;
    if (queue.isNotEmpty) {
      return queue.removeAt(0).future;
    }
    if (completer != null) {
      return completer!.future;
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
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
  Future<void> clearLocalProfile({String? userId}) async {
    clearCount++;
  }

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
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'test_auth_token_mock',
      'user_email': 'athlete@example.com',
    });
  });

  Widget createTestApp({
    required ProviderContainer container,
    String initialRoute = AppRoutes.main,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SamanTheme.dark(),
        initialRoute: initialRoute,
        onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(settings),
      ),
    );
  }

  group('ProfileGate - Central Routing Gate Contract Tests', () {
    testWidgets('shows neutral loading screen while request in flight',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      final inFlight = Completer<ProfileSnapshot?>();
      repo.completer = inFlight;

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pump();

      // Neutral loading view rendered; MainScreen NOT rendered behind
      expect(find.byKey(const Key('profile_gate_loading_view')), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);

      // Complete request
      inFlight.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'complete and network-confirmed profile renders MainScreen',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'confirmed_user_123',
        profile: ProfileEntity(
          userId: 'confirmed_user_123',
          age: 25,
          height: 175.0,
          weight: 70.0,
          gender: Gender.male,
          activityLevel: ActivityLevel.medium,
          goal: Goal.maintain_weight,
        ),
        targetCalories: 2300,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byKey(const Key('profile_gate_loading_view')), findsNothing);
      expect(find.byKey(const Key('profile_gate_incomplete_view')), findsNothing);
      expect(find.byKey(const Key('profile_gate_error_view')), findsNothing);
    });

    testWidgets(
        'HTTP 200 with profile null and valid ID renders approved onboarding flow (CP3)',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      // Server returned valid userId with empty/null profile
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'fresh_registered_user_456',
        profile: ProfileEntity(userId: 'fresh_registered_user_456'),
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Renders incomplete view with Step 1 of Onboarding Flow
      expect(find.byKey(const Key('profile_gate_incomplete_view')), findsOneWidget);
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.text("What’s your\nmain goal?"), findsOneWidget);
      expect(find.byKey(const Key('goal_continue_button')), findsOneWidget);

      // Verifies NO skip, NO bypass into Main
      expect(find.text('Bỏ qua'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.byType(MainScreen), findsNothing);
    });

    testWidgets('GET network error without cache renders load_error, not onboarding',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      repo.errorToThrow = Exception('Network connection timed out');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Must be error view, NEVER onboarding incomplete view
      expect(find.byKey(const Key('profile_gate_error_view')), findsOneWidget);
      expect(find.byKey(const Key('profile_gate_incomplete_view')), findsNothing);
      expect(find.byType(MainScreen), findsNothing);

      // Shows retry button and logout button
      expect(find.byKey(const Key('profile_gate_retry_button')), findsOneWidget);
      expect(find.byKey(const Key('profile_gate_error_logout_button')), findsOneWidget);
    });

    testWidgets('cache complete does NOT open gate when remote GET failed',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      // Returns a cached snapshot (isFromCache: true)
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'stale_user_789',
        profile: ProfileEntity(
          userId: 'stale_user_789',
          age: 30,
          height: 180,
          weight: 75,
          gender: Gender.male,
          activityLevel: ActivityLevel.high,
          goal: Goal.gain_muscle,
        ),
        targetCalories: 2600,
        isFromCache: true, // From local cache, unconfirmed by network in current session
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Gate rejects unconfirmed cache: does NOT enter MainScreen
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(const Key('profile_gate_error_view')), findsOneWidget);
    });

    testWidgets('retry button in error view calls GET loadProfile and NOT update API',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      repo.errorToThrow = Exception('Initial connection failure');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_gate_error_view')), findsOneWidget);
      expect(repo.fetchCount, equals(1));
      expect(repo.updateCallCount, equals(0));

      // Now set recovery response for retry
      repo.errorToThrow = null;
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'retry_success_user',
        profile: ProfileEntity(
          userId: 'retry_success_user',
          age: 26,
          height: 170,
          weight: 65,
          gender: Gender.female,
          activityLevel: ActivityLevel.medium,
          goal: Goal.maintain_weight,
        ),
        isFromCache: false,
      );

      // Tap retry
      await tester.tap(find.byKey(const Key('profile_gate_retry_button')));
      await tester.pumpAndSettle();

      // Re-invoked GET, never called sync/update
      expect(repo.fetchCount, equals(2));
      expect(repo.updateCallCount, equals(0));

      // Successfully admitted to MainScreen
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('401 unauthorized in ProfileGate navigates to Login once',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      repo.errorToThrow = const UnauthorizedException('Token expired');

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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Navigated to Login
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome Back!'), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(await AuthHelper.isLoggedIn(), isFalse);
    });

    testWidgets(
        'once MainScreen is entered, background edit loading does NOT unmount MainScreen',
        (tester) async {
      final repo = _TestControlledProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        userId: 'active_session_user',
        profile: ProfileEntity(
          userId: 'active_session_user',
          age: 28,
          height: 175,
          weight: 70,
          gender: Gender.male,
          activityLevel: ActivityLevel.medium,
          goal: Goal.maintain_weight,
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

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);

      // Simulate an in-flight profile edit setting status to loading
      container.read(profileProvider.notifier).state =
          container.read(profileProvider).copyWith(status: ProfileStatus.loading);
      await tester.pump();

      // MainScreen remains mounted and active; NOT replaced by loading screen
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byKey(const Key('profile_gate_loading_view')), findsNothing);
    });
  });

  group('ProfileGate - Owner and Session Lifecycle', () {
    const loadingKey = Key('profile_gate_loading_view');
    const incompleteKey = Key('profile_gate_incomplete_view');

    ProfileSnapshot completeFor(String id) => ProfileSnapshot(
          userId: id,
          profile: ProfileEntity(
            userId: id,
            age: 28,
            height: 175,
            weight: 70,
            gender: Gender.male,
            activityLevel: ActivityLevel.medium,
            goal: Goal.maintain_weight,
          ),
        );

    ProfileSnapshot incompleteFor(String id) =>
        ProfileSnapshot(userId: id, profile: ProfileEntity(userId: id));

    Future<ProviderContainer> pumpGate(
      WidgetTester tester,
      _TestControlledProfileRepository repo, {
      NavigatorObserver? observer,
    }) async {
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SamanTheme.dark(),
            initialRoute: AppRoutes.main,
            navigatorObservers: [if (observer != null) observer],
            onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(settings),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Key? mainKey(WidgetTester tester) =>
        tester.widget<MainScreen>(find.byType(MainScreen)).key;

    testWidgets('A complete -> logout/reset -> B incomplete never mounts Main',
        (tester) async {
      final repo = _TestControlledProfileRepository()
        ..snapshotToReturn = completeFor('owner_a');
      final container = await pumpGate(tester, repo);
      expect(find.byType(MainScreen), findsOneWidget);

      repo.snapshotToReturn = incompleteFor('owner_b');
      await tester.runAsync(() => AuthHelper.logout(container));
      await tester.pump();

      // Reset revoked A's entry immediately; nothing of A stays on screen.
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(loadingKey), findsOneWidget);

      // B's session loads and is confirmed incomplete.
      await container.read(profileProvider.notifier).loadProfile();
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(incompleteKey), findsOneWidget);
      expect(container.read(profileProvider).confirmedUserId, 'owner_b');
    });

    testWidgets('owner change in the same Gate lifecycle does not keep Main A',
        (tester) async {
      final repo = _TestControlledProfileRepository()
        ..snapshotToReturn = completeFor('owner_a');
      final container = await pumpGate(tester, repo);
      expect(find.byType(MainScreen), findsOneWidget);

      // Same epoch, but the confirmed owner is now B (incomplete).
      repo.snapshotToReturn = incompleteFor('owner_b');
      await container.read(profileProvider.notifier).loadProfile();
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(incompleteKey), findsOneWidget);
    });

    testWidgets('owner change to a complete B remounts Main with fresh state and key',
        (tester) async {
      final repo = _TestControlledProfileRepository()
        ..snapshotToReturn = completeFor('owner_a');
      final container = await pumpGate(tester, repo);
      final stateA = tester.state(find.byType(MainScreen));
      final keyA = mainKey(tester);

      repo.snapshotToReturn = completeFor('owner_b');
      await container.read(profileProvider.notifier).loadProfile();
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(mainKey(tester), isNot(equals(keyA)));
      expect(identical(tester.state(find.byType(MainScreen)), stateA), isFalse);
    });

    testWidgets('epoch change with the SAME owner requires re-confirmation',
        (tester) async {
      final repo = _TestControlledProfileRepository()
        ..snapshotToReturn = completeFor('owner_a');
      final container = await pumpGate(tester, repo);
      final notifier = container.read(profileProvider.notifier);
      final stateA = tester.state(find.byType(MainScreen));
      final keyA = mainKey(tester);

      notifier.resetSession();
      await tester.pump();
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(loadingKey), findsOneWidget);

      final reconfirm = Completer<ProfileSnapshot?>();
      repo.queue.add(reconfirm);
      final reload = notifier.loadProfile();
      await tester.pump();
      // Pending confirmation: still no Main although the owner will be the same.
      expect(find.byType(MainScreen), findsNothing);

      reconfirm.complete(completeFor('owner_a'));
      await reload;
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(mainKey(tester), isNot(equals(keyA)));
      expect(identical(tester.state(find.byType(MainScreen)), stateA), isFalse);
      expect(repo.fetchCount, equals(2));
    });

    testWidgets('loading or failing in the same owner/epoch keeps the same Main instance',
        (tester) async {
      final repo = _TestControlledProfileRepository()
        ..snapshotToReturn = completeFor('owner_a');
      final container = await pumpGate(tester, repo);
      final notifier = container.read(profileProvider.notifier);
      final stateA = tester.state(find.byType(MainScreen));
      final keyA = mainKey(tester);
      final epoch = notifier.sessionEpoch;

      // Background reload in flight.
      final inFlight = Completer<ProfileSnapshot?>();
      repo.queue.add(inFlight);
      final reload = notifier.loadProfile();
      await tester.pump();
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byKey(loadingKey), findsNothing);
      expect(identical(tester.state(find.byType(MainScreen)), stateA), isTrue);

      // Reload finishes for the same owner.
      inFlight.complete(completeFor('owner_a'));
      await reload;
      await tester.pumpAndSettle();
      expect(identical(tester.state(find.byType(MainScreen)), stateA), isTrue);

      // A later transient failure (no identity in state) still keeps Main.
      final failing = Completer<ProfileSnapshot?>();
      repo.queue.add(failing);
      final failedReload = notifier.loadProfile();
      failing.completeError(Exception('offline'));
      await failedReload;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_gate_error_view')), findsNothing);
      expect(identical(tester.state(find.byType(MainScreen)), stateA), isTrue);
      expect(mainKey(tester), equals(keyA));
      expect(notifier.sessionEpoch, equals(epoch));
    });

    testWidgets('401 after Main was entered logs out and navigates exactly once',
        (tester) async {
      final observer = _PushCountingObserver();
      final repo = _TestControlledProfileRepository()
        ..snapshotToReturn = completeFor('owner_a');
      final container = await pumpGate(tester, repo, observer: observer);
      final notifier = container.read(profileProvider.notifier);
      expect(find.byType(MainScreen), findsOneWidget);

      final pushesBefore = observer.pushed.length;
      final epochBefore = notifier.sessionEpoch;

      final unauthorized = Completer<ProfileSnapshot?>();
      repo.queue.add(unauthorized);
      final reload = notifier.loadProfile();
      unauthorized.completeError(const UnauthorizedException('Token expired'));
      await reload;
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(repo.clearCount, equals(1));
      expect(notifier.sessionEpoch, equals(epochBefore + 1));
      expect(observer.pushed.length - pushesBefore, equals(1));
      expect(await AuthHelper.isLoggedIn(), isFalse);
    });
  });
}

class _PushCountingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

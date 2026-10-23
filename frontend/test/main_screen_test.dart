import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/login/login_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _FakeProfileRepository implements ProfileRepository {
  final bool isValid;
  _FakeProfileRepository({this.isValid = true});

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    final profile = await fetchProfile();
    return profile == null ? null : ProfileSnapshot(profile: profile);
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => isValid
      ? const ProfileEntity(
          age: 28,
          gender: Gender.male,
          height: 178,
          weight: 75,
          activityLevel: ActivityLevel.medium,
          goal: Goal.gain_muscle,
        )
      : ProfileEntity.empty();
}

class FakeProfileNotifier extends ProfileNotifier {
  FakeProfileNotifier({bool isValid = true})
      : super(_FakeProfileRepository(isValid: isValid)) {
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
      );
    } else {
      state = ProfileState(profile: ProfileEntity.empty());
    }
  }

  @override
  Future<void> loadProfile() async {}
}

class FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  FakeNutritionNotifier()
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
        carbs: 260,
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
  bool get isMealPlanGenerating => false;

  bool get isGenerating => false;

  @override
  Future<void> updateWater(int amountMl, {required String date}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledProfileRepository extends _FakeProfileRepository {
  final requests = <Completer<ProfileSnapshot?>>[];
  final cachedSnapshots = <ProfileSnapshot>[];
  int clearCount = 0;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) {
    final request = Completer<ProfileSnapshot?>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    cachedSnapshots.add(snapshot);
  }

  @override
  Future<void> clearLocalProfile({String? userId}) async {
    clearCount++;
    cachedSnapshots.clear();
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}

const _freshSnapshot = ProfileSnapshot(
  profile: ProfileEntity(age: 28, height: 178, weight: 75),
  targetCalories: 2400,
);
const _sessionMarker = 'widget-test-session';
const _expiredMessage = 'Session expired. Please sign in again.';

Future<ProviderContainer> _sessionContainer(
    WidgetTester tester, _ControlledProfileRepository repository) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  // In-memory plugin fixture only; no live credentials or auth API involved.
  FlutterSecureStorage.setMockInitialValues({
    'auth_token': _sessionMarker,
    'user_email': 'widget-test@example.com',
  });
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider
        .overrideWithValue(await SharedPreferences.getInstance()),
    profileRepositoryProvider.overrideWithValue(repository),
    nutritionProvider.overrideWith((ref) => FakeNutritionNotifier()),
  ]);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final request in repository.requests) {
      if (!request.isCompleted) request.complete(null);
    }
    await tester.pump(Duration.zero);
    container.dispose();
  });
  return container;
}

Future<void> _seedUnauthorized(ProviderContainer container,
    _ControlledProfileRepository repository) async {
  final load = container.read(profileProvider.notifier).loadProfile();
  repository.requests.last.completeError(
      const UnauthorizedException('Pre-login request unauthorized'));
  await load;
  expect(container.read(profileProvider).status, ProfileStatus.unauthorized);
}

Future<void> _pumpSessionMain(WidgetTester tester, ProviderContainer container,
    {VoidCallback? onUnauthorizedLogout,
    NavigatorObserver? observer}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: SamanTheme.dark(),
      navigatorObservers: [if (observer != null) observer],
      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
      },
      home: MainScreen(onUnauthorizedLogout: onUnauthorizedLogout),
    ),
  ));
  await tester.pump(Duration.zero);
}

void main() {
  group('MainScreen fresh profile session', () {
    testWidgets('stale unauthorized starts a fresh load without clearing session',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      await _seedUnauthorized(container, repository);
      var logoutCount = 0;

      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);

      expect(logoutCount, 0);
      expect(repository.clearCount, 0);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'),
          _sessionMarker);
      expect(repository.requests, hasLength(2));
      expect(container.read(profileProvider).status, ProfileStatus.loading);
      expect(find.text(_expiredMessage), findsNothing);
      repository.requests.last.complete(_freshSnapshot);
      await tester.pump(Duration.zero);
    });

    testWidgets('fresh success retains session after pre-login unauthorized',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      await _seedUnauthorized(container, repository);
      var logoutCount = 0;
      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);
      expect(repository.requests, hasLength(2));
      repository.requests.last.complete(_freshSnapshot);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(container.read(profileProvider).status, ProfileStatus.ready);
      expect(container.read(profileProvider).targetCalories, 2400);
      expect(repository.cachedSnapshots, [_freshSnapshot]);
      expect(repository.requests, hasLength(2));
      expect(repository.clearCount, 0);
      expect(logoutCount, 0);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'),
          _sessionMarker);
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text(_expiredMessage), findsNothing);
    });

    testWidgets('fresh unauthorized clears session and navigates to login once',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      final observer = _RecordingNavigatorObserver();
      await _pumpSessionMain(tester, container, observer: observer);
      expect(repository.requests, hasLength(1));
      repository.requests.single
          .completeError(const UnauthorizedException('Fresh session expired'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      // Finish the real navigation and LoginScreen entrance animations.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(repository.clearCount, 1);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(observer.pushedRoutes, hasLength(2));
      await tester.pump(Duration.zero);
      expect(observer.pushedRoutes, hasLength(2));
      expect(repository.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeated unauthorized notification logs out only once',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      var logoutCount = 0;
      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);
      repository.requests.single
          .completeError(const UnauthorizedException('Fresh session expired'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(logoutCount, 1);
      expect(repository.clearCount, 1);

      final repeatedLoad =
          container.read(profileProvider.notifier).loadProfile();
      repository.requests.last
          .completeError(const UnauthorizedException('Still unauthorized'));
      await repeatedLoad;
      await tester.pump(Duration.zero);
      expect(logoutCount, 1);
      expect(repository.clearCount, 1);
      expect(repository.requests, hasLength(2));
      expect(await const FlutterSecureStorage().read(key: 'auth_token'), isNull);
    });

    testWidgets('200 null profile remains incomplete and keeps profile guard',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      await _seedUnauthorized(container, repository);
      var logoutCount = 0;
      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);
      // Parse the actual successful-response body through the existing model.
      expect(repository.requests, hasLength(2));
      repository.requests.last.complete(ProfileSnapshotModel.fromJson({
        'email': 'widget-test@example.com',
        'profile': null,
        'health_stats': null,
      }));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(container.read(profileProvider).status, ProfileStatus.incomplete);
      expect(container.read(profileProvider).isProfileValid, isFalse);
      expect(logoutCount, 0);
      expect(repository.clearCount, 0);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'),
          _sessionMarker);
      expect(find.text(_expiredMessage), findsNothing);
      await tester.tap(find.text('Nutrition'));
      await tester.pump(Duration.zero);
      expect(container.read(mainNavIndexProvider), 4);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Hồ sơ chưa hoàn thiện'), findsOneWidget);
      expect(repository.requests, hasLength(2));
    });

    testWidgets('non-auth error preserves session and permits explicit reload',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      var logoutCount = 0;
      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);
      repository.requests.single.completeError(Exception('Network unavailable'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(container.read(profileProvider).status, ProfileStatus.error);
      expect(container.read(profileProvider).errorMessage,
          contains('Network unavailable'));
      expect(logoutCount, 0);
      expect(repository.clearCount, 0);
      expect(repository.requests, hasLength(1));
      expect(await const FlutterSecureStorage().read(key: 'auth_token'),
          _sessionMarker);
      expect(find.text(_expiredMessage), findsNothing);

      final retry = container.read(profileProvider.notifier).loadProfile();
      expect(container.read(profileProvider).status, ProfileStatus.loading);
      repository.requests.last.complete(_freshSnapshot);
      await retry;
      await tester.pump(Duration.zero);
      expect(container.read(profileProvider).status, ProfileStatus.ready);
      expect(repository.requests, hasLength(2));
      expect(logoutCount, 0);
      expect(repository.clearCount, 0);
    });

    testWidgets('pre-login in-flight 401 cannot overwrite the fresh profile load',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      final notifier = container.read(profileProvider.notifier);
      final oldLoad = notifier.loadProfile();
      var logoutCount = 0;
      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);
      expect(repository.requests, hasLength(2));

      repository.requests.first
          .completeError(const UnauthorizedException('Late pre-login 401'));
      await oldLoad;
      await tester.pump(Duration.zero);
      expect(container.read(profileProvider).status, ProfileStatus.loading);
      expect(logoutCount, 0);
      expect(repository.clearCount, 0);
      repository.requests.last.complete(_freshSnapshot);
      await tester.pump(Duration.zero);
      expect(container.read(profileProvider).status, ProfileStatus.ready);
      expect(repository.cachedSnapshots, [_freshSnapshot]);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'),
          _sessionMarker);
      await tester.pump(Duration.zero);
    });

    testWidgets('pending fresh response after MainScreen disposal cannot logout',
        (tester) async {
      final repository = _ControlledProfileRepository();
      final container = await _sessionContainer(tester, repository);
      var logoutCount = 0;
      await _pumpSessionMain(tester, container,
          onUnauthorizedLogout: () => logoutCount++);
      expect(repository.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      repository.requests.single
          .completeError(const UnauthorizedException('Response after unmount'));
      await tester.pump(Duration.zero);

      expect(logoutCount, 0);
      expect(repository.clearCount, 0);
      expect(await const FlutterSecureStorage().read(key: 'auth_token'),
          _sessionMarker);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'MainScreen renders approved 5-tab Saman navigation bar with wired tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Morgan',
      'user_email': 'alex@example.com',
    });
    final sharedPrefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileProvider
              .overrideWith((ref) => FakeProfileNotifier(isValid: true)),
          nutritionProvider.overrideWith((ref) => FakeNutritionNotifier()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SamanTheme.dark(),
          home: const MainScreen(),
        ),
      ),
    );

    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 1. Verify SamanBottomNavigationBar exists
    expect(find.byType(SamanBottomNavigationBar), findsOneWidget);

    // 2. Verify all 5 tab labels are present
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Saman'), findsWidgets);
    expect(find.text('Nutrition'), findsWidgets);
    expect(find.text('Profile'), findsOneWidget);

    // 3. Tab switching works (test Profile and Home tabs)
    await tester.tap(find.text('Profile'));
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Home').first);
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets(
      'SamanBottomNavigationBar renders all 5 tabs and calls onTap callback',
      (tester) async {
    int tappedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SamanBottomNavigationBar(
            currentIndex: 0,
            onTap: (index) => tappedIndex = index,
          ),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Saman'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('Workout'));
    expect(tappedIndex, 1);

    await tester.tap(find.text('Saman'));
    expect(tappedIndex, 2);

    await tester.tap(find.text('Nutrition'));
    expect(tappedIndex, 3);

    await tester.tap(find.text('Profile'));
    expect(tappedIndex, 4);

    await tester.tap(find.text('Home'));
    expect(tappedIndex, 0);
  });
}

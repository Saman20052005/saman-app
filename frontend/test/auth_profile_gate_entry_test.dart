import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/presentation/profile_gate.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/login/login_controller.dart';
import 'package:health_ai_app/screens/login/login_screen.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/splash_screen.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

/// Entry-point tests: every flow starts from the REAL route / LoginScreen /
/// SplashScreen and must reach the ProfileGate. Network is a scripted Dio
/// adapter, profile loading is a scripted repository, storage is in-memory.
/// Social providers (Google/Apple/Facebook plugins) are replaced by a controller
/// fake that emits the same typed outcome after saving a token.

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

class _ScriptedProfileRepository implements ProfileRepository {
  int fetchCount = 0;
  int clearCount = 0;
  ProfileSnapshot? snapshotToReturn;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    fetchCount++;
    return snapshotToReturn;
  }

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

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

/// Scripted HTTP layer behind the app-wide `ApiClient.dio`.
class _ScriptedAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = [];

  /// Token returned by the login endpoint.
  String loginToken = 'token_from_this_login';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    requestedPaths.add(path);
    late final int status;
    late final Object body;
    if (path.endsWith('/api/auth/login')) {
      status = 200;
      body = {'access_token': loginToken};
    } else if (path.endsWith('/api/auth/register')) {
      status = 201;
      body = {'message': 'created'};
    } else if (path.endsWith('/api/auth/reset-password')) {
      status = 200;
      body = {'message': 'ok'};
    } else {
      // Anything Main's tabs request is irrelevant here.
      status = 400;
      body = {'detail': 'not scripted'};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Replaces the plugin-based social sign-in: stores a token, then emits the
/// same typed outcome the real controller emits after `_saveAuthData`.
class _FakeSocialLoginController extends LoginController {
  @override
  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true);
    await const FlutterSecureStorage()
        .write(key: 'auth_token', value: 'token_from_social');
    state = state.copyWith(
      isLoading: false,
      isSuccess: true,
      successMessage: 'Login with google success!',
      outcome: AuthOutcome.authenticated,
    );
  }
}

class _PushCountingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

ProfileSnapshot _complete(String id) => ProfileSnapshot(
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

ProfileSnapshot _incomplete(String id) =>
    ProfileSnapshot(userId: id, profile: ProfileEntity(userId: id));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const loadingKey = Key('profile_gate_loading_view');
  const incompleteKey = Key('profile_gate_incomplete_view');

  late _ScriptedAdapter adapter;
  late HttpClientAdapter originalAdapter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    adapter = _ScriptedAdapter();
    originalAdapter = ApiClient.dio.httpClientAdapter;
    ApiClient.dio.httpClientAdapter = adapter;

    // Fluttertoast has no platform side in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async => true,
    );
  });

  tearDown(() {
    ApiClient.dio.httpClientAdapter = originalAdapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), null);
  });

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    required _ScriptedProfileRepository repo,
    String initialRoute = AppRoutes.login,
    GlobalKey<NavigatorState>? navigatorKey,
    NavigatorObserver? observer,
    bool fakeSocial = false,
    bool splashHome = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        profileRepositoryProvider.overrideWithValue(repo),
        nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
        if (fakeSocial)
          loginControllerProvider
              .overrideWith((ref) => _FakeSocialLoginController()),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: SamanTheme.dark(),
          navigatorKey: navigatorKey,
          navigatorObservers: [if (observer != null) observer],
          initialRoute: splashHome ? AppRoutes.splash : initialRoute,
          onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(
            settings,
            enableSplashAnimations: false,
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> settleLoginScreen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> enterText(WidgetTester tester, int fieldIndex, String text) async {
    await tester.enterText(find.byType(TextFormField).at(fieldIndex), text);
  }

  Future<void> submitLogin(
      WidgetTester tester, String email, String password) async {
    await enterText(tester, 0, email);
    await enterText(tester, 1, password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  Future<void> switchToRegisterMode(WidgetTester tester) async {
    final switchFinder =
        find.textContaining("Don't have an account?", findRichText: true);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await settleLoginScreen(tester);
    expect(find.text('Create Account'), findsOneWidget);
  }

  group('Auth entry points reach the ProfileGate', () {
    testWidgets(
        'email authenticated success -> /main -> gate; previous confirmed '
        'profile is NOT reused and token was saved before the outcome',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final repo = _ScriptedProfileRepository()
        ..snapshotToReturn = _incomplete('new_user');
      adapter.loginToken = 'token_email_new';
      final container = await pumpApp(tester, repo: repo);

      // Leftover confirmed+complete state of a previous session in memory.
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: _complete('old_user').profile,
        snapshot: _complete('old_user'),
        confirmedUserId: 'old_user',
        isNetworkConfirmed: true,
      );
      final epochBefore = container.read(profileProvider.notifier).sessionEpoch;

      Future<String?>? tokenAtOutcome;
      container.listen<LoginState>(loginControllerProvider, (prev, next) {
        if (next.outcome == AuthOutcome.authenticated) {
          tokenAtOutcome =
              const FlutterSecureStorage().read(key: 'auth_token');
        }
      });

      await submitLogin(tester, 'new@example.com', 'secret1');

      expect(await tokenAtOutcome, 'token_email_new');
      expect(find.byType(LoginScreen), findsNothing);
      expect(repo.fetchCount, equals(1));
      expect(container.read(profileProvider.notifier).sessionEpoch,
          equals(epochBefore + 1));
      // Old complete profile must not open Main; new owner's data decides.
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(incompleteKey), findsOneWidget);
      expect(container.read(profileProvider).confirmedUserId, 'new_user');
    });

    testWidgets('social authenticated success while UI is in register mode -> gate',
        (tester) async {
      final repo = _ScriptedProfileRepository()
        ..snapshotToReturn = _complete('social_user');
      await pumpApp(tester, repo: repo, fakeSocial: true);

      await switchToRegisterMode(tester);
      await tester.tap(find.byIcon(Icons.g_mobiledata));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(repo.fetchCount, equals(1));
      expect(find.byType(MainScreen), findsOneWidget);
      expect(await AuthHelper.getToken(), 'token_from_social');
    });

    testWidgets(
        'registration success with a stale token in storage -> login mode, '
        'no Gate and no Main', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'stale_old_token'});
      final repo = _ScriptedProfileRepository()
        ..snapshotToReturn = _complete('must_not_be_loaded');
      final observer = _PushCountingObserver();
      await pumpApp(tester, repo: repo, observer: observer);
      final pushesBefore = observer.pushed.length;

      await switchToRegisterMode(tester);
      // Register mode fields: name, phone, email, password, confirm password.
      await enterText(tester, 0, 'New Person');
      await enterText(tester, 1, '0901234567');
      await enterText(tester, 2, 'person@example.com');
      await enterText(tester, 3, 'secret123');
      await enterText(tester, 4, 'secret123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
      await settleLoginScreen(tester);

      expect(adapter.requestedPaths.any((p) => p.endsWith('/api/auth/register')),
          isTrue);
      expect(find.text('Welcome Back!'), findsOneWidget); // back in login mode
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ProfileGate), findsNothing);
      expect(find.byType(MainScreen), findsNothing);
      expect(repo.fetchCount, equals(0));
      expect(observer.pushed.length, equals(pushesBefore));
      expect(await AuthHelper.getToken(), 'stale_old_token'); // untouched
    });

    testWidgets('password-reset success never enters Main, even with a stored token',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'stale_old_token'});
      final repo = _ScriptedProfileRepository()
        ..snapshotToReturn = _complete('must_not_be_loaded');
      final container = await pumpApp(tester, repo: repo);

      final outcomes = <AuthOutcome?>[];
      container.listen<LoginState>(loginControllerProvider, (prev, next) {
        if (next.outcome != null) outcomes.add(next.outcome);
      });

      final resetFuture = container
          .read(loginControllerProvider.notifier)
          .resetPassword('person@example.com', '123456', 'newsecret1');
      await settleLoginScreen(tester);
      final ok = await resetFuture;

      expect(ok, isTrue);
      expect(outcomes, equals([AuthOutcome.passwordReset]));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ProfileGate), findsNothing);
      expect(find.byType(MainScreen), findsNothing);
      expect(repo.fetchCount, equals(0));
    });

    testWidgets('restore session from Splash -> gate', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'restored_token'});
      final repo = _ScriptedProfileRepository()
        ..snapshotToReturn = _complete('restored_user');
      await pumpApp(tester, repo: repo, splashHome: true);
      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsNothing);
      expect(repo.fetchCount, equals(1));
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('Splash without a token goes to Login and never loads a profile',
        (tester) async {
      final repo = _ScriptedProfileRepository();
      await pumpApp(tester, repo: repo, splashHome: true);

      await tester.pump(const Duration(milliseconds: 2300));
      await settleLoginScreen(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ProfileGate), findsNothing);
      expect(repo.fetchCount, equals(0));
    });

    testWidgets('direct /main route goes through the gate', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'some_token'});
      final repo = _ScriptedProfileRepository();
      final inFlight = Completer<ProfileSnapshot?>();
      final container = await pumpApp(
        tester,
        repo: _GatedRepo(repo, inFlight),
        initialRoute: AppRoutes.main,
      );

      expect(find.byType(ProfileGate), findsOneWidget);
      expect(find.byKey(loadingKey), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);

      inFlight.complete(_complete('direct_user'));
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
      expect(container.read(profileProvider).confirmedUserId, 'direct_user');
    });

    testWidgets(
        'A complete session -> logout to Login -> email login as B (incomplete): '
        'B reaches the gate and Main is never mounted for B', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'token_a'});
      final navKey = GlobalKey<NavigatorState>();
      final repo = _ScriptedProfileRepository()
        ..snapshotToReturn = _complete('owner_a');
      final container = await pumpApp(
        tester,
        repo: repo,
        initialRoute: AppRoutes.main,
        navigatorKey: navKey,
      );
      await tester.pumpAndSettle();
      expect(find.byType(MainScreen), findsOneWidget);

      // Logout exactly as the app does: clear session, then replace the stack.
      await tester.runAsync(() => AuthHelper.logout(container));
      navKey.currentState!
          .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      await settleLoginScreen(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(repo.clearCount, equals(1));

      repo.snapshotToReturn = _incomplete('owner_b');
      adapter.loginToken = 'token_b';
      await submitLogin(tester, 'b@example.com', 'secret1');

      expect(find.byType(MainScreen), findsNothing);
      expect(find.byKey(incompleteKey), findsOneWidget);
      expect(container.read(profileProvider).confirmedUserId, 'owner_b');
      expect(repo.fetchCount, equals(2));
    });
  });
}

/// Delegates to [_ScriptedProfileRepository] but holds the first fetch open.
class _GatedRepo extends _ScriptedProfileRepository {
  _GatedRepo(this._inner, this._gate);

  final _ScriptedProfileRepository _inner;
  final Completer<ProfileSnapshot?> _gate;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    _inner.fetchCount++;
    fetchCount = _inner.fetchCount;
    return _gate.future;
  }
}

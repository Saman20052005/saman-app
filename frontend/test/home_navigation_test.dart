import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/screens/main_screen.dart';

class _FakeProfileRepo implements ProfileRepository {
  @override
  Future<void> syncProfile(ProfileEntity profile) async {}
  @override
  Future<ProfileEntity?> fetchProfile() async => null;
  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
          {bool cacheOnSuccess = false}) async =>
      null;
  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}
  @override
  Future<void> clearLocalProfile() async {}
}

class _ControlledProfileNotifier extends ProfileNotifier {
  _ControlledProfileNotifier(ProfileState initialState,
      {ProfileRepository? repo})
      : super(repo ?? _FakeProfileRepo()) {
    state = initialState;
  }

  @override
  Future<void> loadProfile() async {}
}

class _DummyNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _DummyNutritionNotifier() : super(const AsyncValue.data(null));

  @override
  MacroTargets? get macroTargets => null;

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
  Future<void> updateWater(int amountMl, {required String date}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Morgan',
      'user_email': 'alex@example.com',
    });
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp({
    required Widget child,
    required ProfileState profileState,
  }) {
    final fakeRepo = _FakeProfileRepo();
    return ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(fakeRepo),
        profileProvider.overrideWith(
          (ref) => _ControlledProfileNotifier(profileState, repo: fakeRepo),
        ),
        nutritionProvider.overrideWith(
          (ref) => _DummyNutritionNotifier(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SamanTheme.dark(),
        home: child,
      ),
    );
  }

  group('Home to Profile Navigation & MainScreen Guards', () {
    testWidgets(
        'HomeScreen calls onOpenProfile when Profile item is tapped in settings sheet',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool onOpenProfileCalled = false;

      await tester.pumpWidget(
        buildTestApp(
          profileState: ProfileState.initial(),
          child: HomeScreen(
            onOpenProfile: () {
              onOpenProfileCalled = true;
            },
          ),
        ),
      );
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Find Settings button in header
      final settingsBtn = find.byIcon(Icons.settings_outlined);
      expect(settingsBtn, findsOneWidget);

      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();

      // Modal bottom sheet should now be visible with 'Profile & Health Details'
      final profileTile = find.text('Profile & Health Details');
      expect(profileTile, findsOneWidget);

      await tester.tap(profileTile);
      await tester.pumpAndSettle();

      expect(onOpenProfileCalled, isTrue);
    });

    testWidgets(
        'MainScreen does NOT redirect or show error for Nutrition tab while Profile is loading/initial',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Status is loading -> unresolved
      final loadingProfileState = ProfileState(
        status: ProfileStatus.loading,
        profile: ProfileEntity.empty(),
      );

      await tester.pumpWidget(
        buildTestApp(
          profileState: loadingProfileState,
          child: const MainScreen(),
        ),
      );
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Tap Nutrition tab (index 3)
      final navBar = tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar),
      );
      navBar.onTap(3);
      await tester.pump();

      // Should NOT show warning SnackBar
      expect(
        find.text('⚠️ Vui lòng cập nhật Hồ sơ sức khỏe để tính Calories!'),
        findsNothing,
      );

      // Current index of bottom navigation bar should be 3
      final updatedNavBar = tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar),
      );
      expect(updatedNavBar.currentIndex, equals(3));
    });

    testWidgets(
        'MainScreen redirects to Profile tab when Profile is resolved and incomplete',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Status is incomplete -> resolved but invalid
      final incompleteProfileState = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
        isLoading: false,
      );

      await tester.pumpWidget(
        buildTestApp(
          profileState: incompleteProfileState,
          child: const MainScreen(),
        ),
      );
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Tap Nutrition tab (index 3)
      final navBar = tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar),
      );
      navBar.onTap(3);
      await tester.pump();

      // Should show warning SnackBar
      expect(
        find.text('⚠️ Vui lòng cập nhật Hồ sơ sức khỏe để tính Calories!'),
        findsOneWidget,
      );

      // Should redirect to Profile tab (index 4)
      final updatedNavBar = tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar),
      );
      expect(updatedNavBar.currentIndex, equals(4));
    });

    testWidgets(
        'Unauthorized Profile state triggers centralized logout, removes tokens, and navigates once',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'active_auth_token_xyz',
        'jwt_token': 'active_jwt_token_abc',
        'user_fullname': 'Alex Morgan',
        'user_email': 'alex@example.com',
      });
      SharedPreferences.setMockInitialValues({
        'language_code': 'vi',
        'is_dark_mode': true,
      });

      int logoutCallCount = 0;

      final unauthorizedProfileState = ProfileState(
        status: ProfileStatus.unauthorized,
        profile: ProfileEntity.empty(),
        isLoading: false,
      );

      await tester.pumpWidget(
        buildTestApp(
          profileState: unauthorizedProfileState,
          child: MainScreen(
            onUnauthorizedLogout: () {
              logoutCallCount++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // SnackBar displayed
      expect(
        find.text('Session expired. Please sign in again.'),
        findsOneWidget,
      );

      // Verify tokens removed
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'auth_token'), isNull);
      expect(await secure.read(key: 'jwt_token'), isNull);

      // Verify preferences preserved
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language_code'), equals('vi'));
      expect(prefs.getBool('is_dark_mode'), isTrue);

      // Runs exactly once
      expect(logoutCallCount, equals(1));
    });

    testWidgets('Generic network error does NOT force logout or remove tokens',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'active_auth_token_xyz',
        'jwt_token': 'active_jwt_token_abc',
      });

      int logoutCallCount = 0;

      final errorProfileState = ProfileState(
        status: ProfileStatus.error,
        profile: ProfileEntity.empty(),
        isLoading: false,
      );

      await tester.pumpWidget(
        buildTestApp(
          profileState: errorProfileState,
          child: MainScreen(
            onUnauthorizedLogout: () {
              logoutCallCount++;
            },
          ),
        ),
      );
      await tester.pump();
      for (int i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // No session expired snackbar
      expect(
        find.text('Session expired. Please sign in again.'),
        findsNothing,
      );

      // Tokens remain in storage
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'auth_token'),
          equals('active_auth_token_xyz'));
      expect(
          await secure.read(key: 'jwt_token'), equals('active_jwt_token_abc'));

      // Logout callback was not called
      expect(logoutCallCount, equals(0));
    });
  });
}

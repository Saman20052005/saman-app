import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_metadata.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/screens/settings/app_settings_screen.dart';
import 'package:health_ai_app/services/unit_converter.dart';

class _FakeProfileRepository implements ProfileRepository {
  ProfileSnapshot? snapshot;
  _FakeProfileRepository([this.snapshot]);

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false}) async =>
      snapshot;

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshot?.profile;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    snapshot = ProfileSnapshot(profile: profile);
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<void> clearLocalProfile({String? userId}) async {
    snapshot = null;
  }

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}
}

class _CustomProfileNotifier extends ProfileNotifier {
  _CustomProfileNotifier(super.repository, ProfileState initialState) {
    state = initialState;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

Widget _buildTestApp({
  required Widget child,
  ProfileEntity? profile,
  String initialLanguage = 'en',
  UnitSystem initialUnit = UnitSystem.metric,
  String appVersion = '1.0.0 (1)',
}) {
  SharedPreferences.setMockInitialValues({
    'language_code': initialLanguage,
    'language_mode': initialLanguage,
    'saman_unit_system': initialUnit == UnitSystem.imperial ? 'imperial' : 'metric',
  });

  final testProfile = profile ??
      const ProfileEntity(
        age: 21,
        height: 171.0,
        weight: 68.0,
        gender: Gender.male,
        activityCanonical: 'high',
        goal: Goal.gain_muscle,
      );

  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      profileProvider.overrideWith(
        (ref) => _CustomProfileNotifier(
          _FakeProfileRepository(ProfileSnapshot(profile: testProfile)),
          ProfileState(status: ProfileStatus.ready, profile: testProfile),
        ),
      ),
      appVersionProvider.overrideWithValue(appVersion),
    ],
    child: MaterialApp(
      theme: SamanTheme.dark(),
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Profile Screen — App settings Navigation & Layout Tests', () {
    testWidgets(
        'ACCOUNT section maintains exact order: Manage membership -> App settings -> Log out',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(child: const ProfileScreen()),
      );
      await tester.pumpAndSettle();

      // Find all 3 rows in Account section
      final membershipFinder = find.byKey(const Key('manage_membership_nav_row'));
      final settingsFinder = find.byKey(const Key('app_settings_nav_row'));
      final logoutFinder = find.text('Log out');

      expect(membershipFinder, findsOneWidget);
      expect(settingsFinder, findsOneWidget);
      expect(logoutFinder, findsOneWidget);

      // Verify vertical order
      final membershipY = tester.getTopLeft(membershipFinder).dy;
      final settingsY = tester.getTopLeft(settingsFinder).dy;
      final logoutY = tester.getTopLeft(logoutFinder).dy;

      expect(membershipY, lessThan(settingsY),
          reason: 'Manage membership must be ABOVE App settings');
      expect(settingsY, lessThan(logoutY),
          reason: 'App settings must be ABOVE Log out');

      // Verify outline gear icon
      expect(
        find.descendant(
          of: settingsFinder,
          matching: find.byIcon(Icons.settings_outlined),
        ),
        findsOneWidget,
      );

      // Verify chevron
      expect(
        find.descendant(
          of: settingsFinder,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Tapping App settings row navigates to AppSettingsScreen and back pops cleanly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(child: const ProfileScreen()),
      );
      await tester.pumpAndSettle();

      // Scroll down if necessary
      await tester.ensureVisible(find.byKey(const Key('app_settings_nav_row')));
      await tester.tap(find.byKey(const Key('app_settings_nav_row')));
      await tester.pumpAndSettle();

      // Verify AppSettingsScreen is pushed
      expect(find.byType(AppSettingsScreen), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);

      // Verify Back button pops cleanly back to ProfileScreen
      await tester.tap(find.byKey(const Key('app_settings_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(AppSettingsScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('AppSettingsScreen — Visual Structure & Elements', () {
    testWidgets('Renders all required sections and items per specification',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const AppSettingsScreen(),
          appVersion: '1.0.0 (1)',
        ),
      );
      await tester.pumpAndSettle();

      // Header
      expect(find.text('App settings'), findsOneWidget);
      expect(find.byKey(const Key('app_settings_back_button')), findsOneWidget);

      // SECTION 1: PREFERENCES
      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.byKey(const Key('setting_row_language')), findsOneWidget);
      expect(find.text('Ngôn ngữ / Language'), findsOneWidget);
      expect(find.byKey(const Key('setting_row_units')), findsOneWidget);
      expect(find.text('Units'), findsOneWidget);

      // SECTION 2: ABOUT SAMAN
      expect(find.text('ABOUT SAMAN'), findsOneWidget);
      expect(find.byKey(const Key('link_privacy_policy')), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.byKey(const Key('link_terms_of_service')), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);
      expect(find.byKey(const Key('link_help_support')), findsOneWidget);
      expect(find.text('Help & support'), findsOneWidget);

      // SECTION 3: APP INFORMATION
      expect(find.text('APP INFORMATION'), findsOneWidget);
      expect(find.byKey(const Key('info_row_version')), findsOneWidget);
      expect(find.text('App version'), findsOneWidget);
      expect(find.text('1.0.0 (1)'), findsOneWidget);

      // Footer
      expect(find.text('Saman · Your fitness companion'), findsOneWidget);

      // Exclude out-of-scope sections
      expect(find.text('Appearance'), findsNothing);
      expect(find.text('Notifications'), findsNothing);
      expect(find.text('Dark mode'), findsNothing);
    });

    testWidgets('App version row is read-only and does not show chevron',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const AppSettingsScreen(),
          appVersion: '2.4.0 (42)',
        ),
      );
      await tester.pumpAndSettle();

      final versionRow = find.byKey(const Key('info_row_version'));
      expect(versionRow, findsOneWidget);
      expect(find.text('2.4.0 (42)'), findsOneWidget);

      // Must NOT contain chevron
      expect(
        find.descendant(
          of: versionRow,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );
    });
  });

  group('AppSettingsScreen — Interactive Flows (Language & Units & About)', () {
    testWidgets('Language row opens modal bottom sheet with 3 options and updates selection',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const AppSettingsScreen(),
          initialLanguage: 'en',
        ),
      );
      await tester.pumpAndSettle();

      // Tap Language row
      await tester.tap(find.byKey(const Key('setting_row_language')));
      await tester.pumpAndSettle();

      // Verify bottom sheet options
      expect(find.byKey(const Key('language_option_system')), findsOneWidget);
      expect(find.byKey(const Key('language_option_vi')), findsOneWidget);
      expect(find.byKey(const Key('language_option_en')), findsOneWidget);

      // Tap Tiếng Việt option
      await tester.tap(find.byKey(const Key('language_option_vi')));
      await tester.pumpAndSettle();

      // Bottom sheet closes
      expect(find.byKey(const Key('language_option_vi')), findsNothing);

      // Check SharedPreferences updated
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language_mode'), equals('vi'));
    });

    testWidgets('Units row opens modal bottom sheet with 2 options and updates selection',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const AppSettingsScreen(),
          initialUnit: UnitSystem.metric,
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows Metric and kg, cm
      expect(find.text('Metric'), findsOneWidget);
      expect(find.text('kg, cm'), findsOneWidget);

      // Tap Units row
      await tester.tap(find.byKey(const Key('setting_row_units')));
      await tester.pumpAndSettle();

      // Verify bottom sheet options
      expect(find.byKey(const Key('unit_option_metric')), findsOneWidget);
      expect(find.byKey(const Key('unit_option_imperial')), findsOneWidget);

      // Tap Imperial
      await tester.tap(find.byKey(const Key('unit_option_imperial')));
      await tester.pumpAndSettle();

      // Bottom sheet closes
      expect(find.byKey(const Key('unit_option_imperial')), findsNothing);

      // Setting row displays Imperial and lb, ft/in
      expect(find.text('Imperial'), findsOneWidget);
      expect(find.text('lb, ft/in'), findsOneWidget);

      // Check SharedPreferences updated
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saman_unit_system'), equals('imperial'));
    });

    testWidgets('About items open informative non-silent dialog and close cleanly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(child: const AppSettingsScreen()),
      );
      await tester.pumpAndSettle();

      // 1. Privacy Policy
      await tester.tap(find.byKey(const Key('link_privacy_policy')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Privacy policy'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // 2. Terms of service
      await tester.tap(find.byKey(const Key('link_terms_of_service')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Terms of service'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // 3. Help & support
      await tester.tap(find.byKey(const Key('link_help_support')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Help & support'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Profile Details — Unit Conversion Display Integration', () {
    testWidgets('Displays metric values (cm, kg) when Metric unit is active',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const profile = ProfileEntity(
        age: 21,
        height: 171.0,
        weight: 68.0,
        gender: Gender.male,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProfileScreen(),
          profile: profile,
          initialUnit: UnitSystem.metric,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('171 cm'), findsOneWidget);
      expect(find.text('68 kg'), findsOneWidget);
    });

    testWidgets('Displays imperial values (5\'7", 149.9 lb) when Imperial unit is active',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const profile = ProfileEntity(
        age: 21,
        height: 171.0,
        weight: 68.0,
        gender: Gender.male,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProfileScreen(),
          profile: profile,
          initialUnit: UnitSystem.imperial,
        ),
      );
      await tester.pumpAndSettle();

      // 171cm -> 5'7", 68kg -> 149.9 lb
      expect(find.text("5'7\""), findsOneWidget);
      expect(find.text('149.9 lb'), findsOneWidget);
    });

    testWidgets('EditHealthProfileScreen reflects Imperial units for inputs',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const profile = ProfileEntity(
        age: 25,
        height: 175.26, // 69 inches
        weight: 68.0388, // 150 lbs
        gender: Gender.male,
        activityCanonical: 'moderate',
        goal: Goal.maintain_weight,
      );

      final fakeRepo = _FakeProfileRepository(const ProfileSnapshot(profile: profile));

      SharedPreferences.setMockInitialValues({
        'saman_unit_system': 'imperial',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            profileRepositoryProvider.overrideWithValue(fakeRepo),
            profileProvider.overrideWith(
              (ref) => _CustomProfileNotifier(
                fakeRepo,
                ProfileState(status: ProfileStatus.ready, profile: profile),
              ),
            ),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check suffixes are Imperial
      expect(find.text('lb'), findsOneWidget);
      expect(find.text('in'), findsOneWidget);
    });
  });

  group('Responsiveness & Layout Boundaries', () {
    testWidgets('AppSettingsScreen renders at 390x844 without any overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(child: const AppSettingsScreen()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('AppSettingsScreen renders with 1.3x text scale without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: _buildTestApp(child: const AppSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Row touch targets satisfy minimum 48px height',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(child: const AppSettingsScreen()),
      );
      await tester.pumpAndSettle();

      final languageSize = tester.getSize(find.byKey(const Key('setting_row_language')));
      final unitsSize = tester.getSize(find.byKey(const Key('setting_row_units')));
      final privacySize = tester.getSize(find.byKey(const Key('link_privacy_policy')));

      expect(languageSize.height, greaterThanOrEqualTo(48.0));
      expect(unitsSize.height, greaterThanOrEqualTo(48.0));
      expect(privacySize.height, greaterThanOrEqualTo(48.0));
    });
  });
}

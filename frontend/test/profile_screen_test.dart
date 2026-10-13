import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';
import 'package:health_ai_app/screens/profile/widgets/profile_widgets.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _FakeProfileRepository implements ProfileRepository {
  ProfileSnapshot? snapshot;

  _FakeProfileRepository([this.snapshot]);

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false}) async {
    return snapshot;
  }

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
  Future<void> clearLocalProfile() async {
    snapshot = null;
  }
}

class _CustomProfileNotifier extends ProfileNotifier {
  _CustomProfileNotifier(super.repository, ProfileState initialState) {
    state = initialState;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

Widget _buildTestWrapper({
  required Widget child,
  ProfileState? initialState,
  ProfileRepository? repository,
}) {
  SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      if (repository != null) profileRepositoryProvider.overrideWithValue(repository),
      if (initialState != null)
        profileProvider.overrideWith(
          (ref) => _CustomProfileNotifier(
            repository ?? _FakeProfileRepository(),
            initialState,
          ),
        ),
    ],
    child: MaterialApp(
      theme: SamanTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileScreen - Stitch Redesign Component Composition', () {
    testWidgets('renders all 8 Stitch modular widgets and excludes legacy layout',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 26,
        height: 175,
        weight: 72,
        gender: Gender.male,
        activityLevel: ActivityLevel.high,
        goal: Goal.gain_muscle,
      );

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const ProfileScreen(),
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: testProfile,
            targetCalories: 2600,
            targetProtein: 165,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all modular Stitch widgets are present
      expect(find.byType(ProfileHeader), findsOneWidget);
      expect(find.byType(PersonalIdentityCard), findsOneWidget);
      expect(find.byType(ProgressSnapshotCard), findsOneWidget);
      expect(find.byType(SamanPlusCard), findsOneWidget);
      expect(find.byType(ProfileSectionGroup), findsNWidgets(3)); // Health, Prefs, Account
      expect(find.byType(ProfileNavRow), findsWidgets);
      expect(find.byType(LogoutRow), findsOneWidget);

      // Verify legacy elements are completely absent
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('displays real health metrics and does NOT show fake defaults',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 28,
        height: 182,
        weight: 78,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      );

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const ProfileScreen(),
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: testProfile,
            targetCalories: 2450,
            targetProtein: 160,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Real health data rendered
      expect(find.text('182 cm'), findsOneWidget);
      expect(find.text('78 kg'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.text('Build muscle'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('2450 kcal · 160g protein'), findsOneWidget);

      // Fake metrics MUST NOT be present
      expect(find.text('24 workouts'), findsNothing);
      expect(find.text('7d'), findsNothing); // Streak fallback is em-dash
      expect(find.text('82%'), findsNothing);
      expect(find.text('Free plan'), findsNothing);
      expect(find.text('Member since 2026'), findsNothing);

      // Long-term progress card displays em-dash for unbacked metrics
      expect(find.text('—'), findsWidgets);

      // Saman+ displays Coming Soon, not a fake action
      expect(find.text('Coming soon'), findsWidgets);
    });

    testWidgets('edit button on identity card navigates to EditHealthProfileScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 25,
        height: 170,
        weight: 68,
        gender: Gender.male,
      );

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const ProfileScreen(),
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: testProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_profile_cta_button')));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);

      // Pop back
      Navigator.of(tester.element(find.byType(EditHealthProfileScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('complete profile banner navigates to EditHealthProfileScreen when incomplete',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const ProfileScreen(),
          initialState: ProfileState(
            status: ProfileStatus.incomplete,
            profile: ProfileEntity.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ chưa hoàn thiện'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('complete_profile_cta_button')));
      await tester.tap(find.byKey(const Key('complete_profile_cta_button')));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
    });

    testWidgets('unimplemented rows have no fake navigation or chevron click actions',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const ProfileScreen(),
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: const ProfileEntity(age: 25, height: 175, weight: 70),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure visible and tap on unimplemented rows
      await tester.ensureVisible(find.text('Medical information'));
      await tester.tap(find.text('Medical information'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);

      await tester.ensureVisible(find.text('Measurements & photos'));
      await tester.tap(find.text('Measurements & photos'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);

      await tester.ensureVisible(find.text('Units'));
      await tester.tap(find.text('Units'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);

      await tester.ensureVisible(find.text('Manage membership'));
      await tester.tap(find.text('Manage membership'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);
    });

    testWidgets('language, appearance and logout callbacks work as expected',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const ProfileScreen(),
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: const ProfileEntity(age: 25, height: 175, weight: 70),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Language bottom sheet
      await tester.ensureVisible(find.text('Language'));
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsWidgets);
      expect(find.widgetWithText(ListTile, 'Tiếng Việt'), findsOneWidget);

      // Dismiss bottom sheet by tapping English in the list
      await tester.tap(find.widgetWithText(ListTile, 'English'));
      await tester.pumpAndSettle();

      // Logout dialog appears
      await tester.ensureVisible(find.byType(LogoutRow));
      await tester.tap(find.byType(LogoutRow));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('MainScreen has exactly one bottom navigation bar with ProfileScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeProfileRepository(
        const ProfileSnapshot(
          profile: ProfileEntity(age: 25, height: 175, weight: 70),
        ),
      );

      await tester.pumpWidget(
        _buildTestWrapper(
          child: const MainScreen(),
          repository: repo,
          initialState: ProfileState(
            status: ProfileStatus.ready,
            profile: const ProfileEntity(age: 25, height: 175, weight: 70),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ProfileScreen), findsOneWidget);
      // MainScreen has exactly 1 SamanBottomNavigationBar
      expect(find.byType(SamanBottomNavigationBar), findsOneWidget);
      // ProfileScreen does NOT create a second bottom navigation bar
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });
  });
}

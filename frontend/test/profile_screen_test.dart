import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';
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

Widget _buildTestWrapper({
  Key? key,
  required Widget child,
  ProfileState? initialState,
  ProfileRepository? repository,
}) {
  SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

  return ProviderScope(
    key: key,
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

  group('ProfileScreen - Screen 06 Calm Athleticism Verification', () {
    testWidgets('renders Screen 06 structure with read-only summary and excludes legacy/fake metrics',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 25,
        height: 175.5,
        weight: 72.5,
        gender: Gender.male,
        activityCanonical: 'moderate',
        goal: Goal.gain_muscle,
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

      // Screen title and verified identity
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Your Saman profile'), findsOneWidget);

      // Section titles
      expect(find.text('YOUR GOAL'), findsOneWidget);
      expect(find.text('YOUR DETAILS'), findsOneWidget);
      expect(find.text('ACTIVITY LEVEL'), findsOneWidget);

      // Exact values rendered (no rounding loss)
      expect(find.text('Build muscle'), findsOneWidget);
      expect(find.text('Focus on building muscle.'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('175.5 cm'), findsOneWidget);
      expect(find.text('72.5 kg'), findsOneWidget);
      expect(find.text('Moderately active'), findsOneWidget);
      expect(find.text('Regular exercise and some movement during the day.'), findsOneWidget);

      // Single Edit CTA and Account
      expect(find.byKey(const Key('edit_profile_cta_button')), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      // NO vanity metrics, fake cards, BMI, or inline form
      expect(find.text('BMI'), findsNothing);
      expect(find.text('Body fat'), findsNothing);
      expect(find.text('Free plan'), findsNothing);
      expect(find.text('Member since 2026'), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('displays all 5 canonical activity titles without truncation or legacy projection',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final choice in OnboardingActivityChoice.values) {
        final profile = ProfileEntity(
          age: 28,
          height: 180.0,
          weight: 75.0,
          gender: Gender.female,
          activityCanonical: choice.name,
          goal: Goal.maintain_weight,
        );

        await tester.pumpWidget(
          _buildTestWrapper(
            key: ValueKey(choice),
            child: const ProfileScreen(),
            initialState: ProfileState(
              status: ProfileStatus.ready,
              profile: profile,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(choice.title), findsOneWidget);
      }
    });

    testWidgets('edit button navigates to EditHealthProfileScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 25,
        height: 170.0,
        weight: 68.0,
        gender: Gender.male,
        activityCanonical: 'moderate',
        goal: Goal.maintain_weight,
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

    testWidgets('logout button opens confirmation dialog and cancel dismisses it',
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

      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
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

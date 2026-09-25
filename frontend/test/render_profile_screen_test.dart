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
import 'package:health_ai_app/screens/profile_screen.dart';

class _MockRepo implements ProfileRepository {
  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false}) async => null;
  @override
  Future<ProfileEntity?> fetchProfile() async => null;
  @override
  Future<void> syncProfile(ProfileEntity profile) async {}
  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}
  @override
  Future<void> clearLocalProfile() async {}
}

class _StaticProfileNotifier extends ProfileNotifier {
  _StaticProfileNotifier(super.repository, ProfileState state) {
    this.state = state;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

Widget _buildRenderTestApp({
  required Widget child,
  double textScaleFactor = 1.0,
  ProfileState? state,
}) {
  SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      profileRepositoryProvider.overrideWithValue(_MockRepo()),
      if (state != null)
        profileProvider.overrideWith(
          (ref) => _StaticProfileNotifier(_MockRepo(), state),
        ),
    ],
    child: MaterialApp(
      theme: SamanTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const completeProfile = ProfileEntity(
    age: 29,
    height: 185,
    weight: 85,
    gender: Gender.male,
    activityLevel: ActivityLevel.high,
    goal: Goal.gain_muscle,
  );

  final completeState = ProfileState(
    status: ProfileStatus.ready,
    profile: completeProfile,
    targetCalories: 2800,
    targetProtein: 180,
  );

  final incompleteState = ProfileState(
    status: ProfileStatus.incomplete,
    profile: const ProfileEntity(),
  );

  group('ProfileScreen - Responsive Layout & Overflow Verification', () {
    final viewports = [
      const Size(320, 600), // Narrow compact mobile
      const Size(375, 812), // Standard iPhone / mobile
      const Size(430, 932), // Large Pro Max viewport
    ];

    for (final size in viewports) {
      testWidgets('renders cleanly with 0 overflow at width ${size.width.toInt()}px',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildRenderTestApp(
            child: const ProfileScreen(),
            state: completeState,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileScreen), findsOneWidget);

        // Also test incomplete state
        await tester.pumpWidget(
          _buildRenderTestApp(
            child: const ProfileScreen(),
            state: incompleteState,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileScreen), findsOneWidget);
      });
    }

    testWidgets('renders safely under text scale 1.0 and 2.0 without exceptions',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1.0 Scale
      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const ProfileScreen(),
          textScaleFactor: 1.0,
          state: completeState,
        ),
      );
      // 2.0 Scale (Accessibility large text)
      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const ProfileScreen(),
          textScaleFactor: 2.0,
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

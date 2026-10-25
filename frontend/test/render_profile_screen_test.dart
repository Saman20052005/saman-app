import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
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
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';

class _MockRepo implements ProfileRepository {
  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
          {bool cacheOnSuccess = false}) async =>
      null;
  @override
  Future<ProfileEntity?> fetchProfile() async => null;
  @override
  Future<void> syncProfile(ProfileEntity profile) async {}
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
}

class _StaticProfileNotifier extends ProfileNotifier {
  _StaticProfileNotifier(super.repository, ProfileState state) {
    this.state = state;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

class _FakeNutritionNotifier
    extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-10-15',
              meals: [],
              currentWater: 1500,
              targetWater: 2000,
              totalCaloriesConsumed: 1200,
              totalProteinConsumed: 80,
              totalCarbsConsumed: 150,
              totalFatConsumed: 40,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2200,
        protein: 150,
        carbs: 220,
        fat: 65,
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

Future<void> _captureScreen(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('render_capture_boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      final evidenceDir = Platform.environment['SAMAN_RENDER_EVIDENCE'] ??
          Directory.systemTemp.path;
      final file = File('$evidenceDir/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
    }
    image.dispose();
  });
}

Widget _buildRenderTestApp({
  required Widget child,
  double textScaleFactor = 1.0,
  ProfileState? state,
  EdgeInsets? viewInsets,
}) {
  SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      profileRepositoryProvider.overrideWithValue(_MockRepo()),
      nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
      if (state != null)
        profileProvider.overrideWith(
          (ref) => _StaticProfileNotifier(_MockRepo(), state),
        ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      builder: (context, navigatorChild) => RepaintBoundary(
        key: const ValueKey('render_capture_boundary'),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
            viewInsets: viewInsets ?? MediaQuery.of(context).viewInsets,
          ),
          child: navigatorChild!,
        ),
      ),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const completeProfile = ProfileEntity(
    userId: 'usr_cp5_render',
    age: 29,
    height: 178.5,
    weight: 72.4,
    gender: Gender.male,
    activityLevel: ActivityLevel.medium,
    activityCanonical: 'moderate',
    goal: Goal.maintain_weight,
  );

  final completeState = ProfileState(
    status: ProfileStatus.ready,
    profile: completeProfile,
    confirmedUserId: 'usr_cp5_render',
    isNetworkConfirmed: true,
    targetCalories: 2800,
    targetProtein: 180,
  );

  final incompleteState = ProfileState(
    status: ProfileStatus.incomplete,
    profile: const ProfileEntity(),
  );

  final loadingState = ProfileState(
    status: ProfileStatus.loading,
    profile: const ProfileEntity(),
  );

  final errorState = ProfileState(
    status: ProfileStatus.error,
    profile: const ProfileEntity(),
    errorMessage: 'Test-only profile error',
  );

  group('ProfileScreen - Responsive Layout & Overflow Verification', () {
    final viewports = [
      const Size(320, 600), // Narrow compact mobile
      const Size(375, 812), // Standard iPhone / mobile
      const Size(430, 932), // Large Pro Max viewport
    ];

    for (final size in viewports) {
      testWidgets(
          'renders cleanly with 0 overflow at width ${size.width.toInt()}px',
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

    testWidgets(
        'renders safely under text scale 1.0 and 2.0 without exceptions',
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

    for (final entry in {
      'loading': loadingState,
      'error': errorState,
      'empty': incompleteState,
    }.entries) {
      testWidgets('${entry.key} state renders without exceptions',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildRenderTestApp(
            child: const ProfileScreen(),
            state: entry.value,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileScreen), findsOneWidget);
      });
    }
  });

  group('CP5 Visual QA & Evidence Screen Captures (390x844)', () {
    testWidgets('1. profile_top_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterSecureStorage.setMockInitialValues({
        'user_fullname': 'John Athlete',
        'user_email': 'athlete@example.com',
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const ProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'profile_top_390x844.png');
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('John Athlete'), findsOneWidget);
      expect(find.text('Maintain weight'), findsOneWidget);
    });

    testWidgets('2. profile_bottom_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterSecureStorage.setMockInitialValues({
        'user_fullname': 'John Athlete',
        'user_email': 'athlete@example.com',
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const ProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to bottom
      await tester.drag(find.byType(ProfileScreen), const Offset(0, -600));
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'profile_bottom_390x844.png');
      expect(find.byKey(const Key('edit_profile_cta_button')), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('3. edit_initial_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const EditHealthProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'edit_initial_390x844.png');
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('72.4'), findsOneWidget);
    });

    testWidgets('4. edit_dirty_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const EditHealthProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      // Modify weight to make dirty
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '74.2');
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'edit_dirty_390x844.png');
      expect(find.text('74.2'), findsOneWidget);
      expect(find.byKey(const Key('edit_profile_save_button')), findsOneWidget);
    });

    testWidgets('5. edit_goal_sheet_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const EditHealthProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_profile_goal_tile')));
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'edit_goal_sheet_390x844.png');
      expect(find.text('Choose your goal'), findsOneWidget);
      expect(find.byKey(const Key('goal_sheet_apply_button')), findsOneWidget);
    });

    testWidgets('6. edit_activity_sheet_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const EditHealthProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to make activity tile visible before tapping
      await tester.ensureVisible(find.byKey(const Key('edit_profile_activity_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_profile_activity_tile')));
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'edit_activity_sheet_390x844.png');
      expect(find.text('Activity level'), findsOneWidget);
      expect(find.byKey(const Key('activity_sheet_apply_button')),
          findsOneWidget);
    });

    testWidgets('7. edit_discard_dialog_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const EditHealthProfileScreen(),
          state: completeState,
        ),
      );
      await tester.pumpAndSettle();

      // Make dirty
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '74.2');
      await tester.pumpAndSettle();

      // Tap back button to trigger discard dialog
      await tester.tap(find.byKey(const Key('edit_profile_back_button')));
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'edit_discard_dialog_390x844.png');
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Discard changes'), findsOneWidget);
    });

    testWidgets('8. edit_keyboard_viewport_390x844.png', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildRenderTestApp(
          child: const EditHealthProfileScreen(),
          state: completeState,
          viewInsets: const EdgeInsets.only(bottom: 280),
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'edit_keyboard_viewport_390x844.png');
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      expect(find.byKey(const Key('edit_profile_weight_input')), findsOneWidget);
      // Per Frame G, save button is hidden while keyboard is open
      expect(find.byKey(const Key('edit_profile_save_button')), findsNothing);
    });
  });
}

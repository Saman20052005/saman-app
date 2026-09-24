import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/main_screen.dart';

class _FakeProfileRepository implements ProfileRepository {
  final bool isValid;
  _FakeProfileRepository({this.isValid = true});

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

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

  @override
  Future<void> clearLocalProfile() async {}

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    final profile = await fetchProfile();
    if (profile == null) return null;
    return ProfileSnapshot(
      profile: profile,
    );
  }
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

void main() {
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

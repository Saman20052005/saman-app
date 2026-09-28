import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _MockProfileRepository implements ProfileRepository {
  int fetchCount = 0;
  int syncCount = 0;
  ProfileEntity? lastSyncedProfile;
  Completer<void>? syncCompleter;
  Object? syncError;
  ProfileSnapshot? snapshotToReturn;
  Completer<ProfileSnapshot?>? fetchCompleter;
  Object? fetchError;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    fetchCount++;
    if (fetchError != null) {
      throw fetchError!;
    }
    if (fetchCompleter != null) {
      return fetchCompleter!.future;
    }
    return snapshotToReturn;
  }

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshotToReturn?.profile;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    syncCount++;
    lastSyncedProfile = profile;
    if (syncCompleter != null) {
      await syncCompleter!.future;
    }
    if (syncError != null) {
      throw syncError!;
    }
    // Update local snapshotToReturn so subsequent fetch returns the new profile
    snapshotToReturn = ProfileSnapshot(
      profile: profile,
      targetCalories: 2200,
    );
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<void> clearLocalProfile() async {}
}

class _FakeNutritionNotifier
    extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-09-24',
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
        calories: 2000,
        protein: 150,
        carbs: 200,
        fat: 60,
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

  @override
  Future<void> updateWater(int amountMl, {required String date}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void setMobileView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _createTestApp({
  required Widget child,
  required _MockProfileRepository repository,
  ProfileState? initialState,
  SharedPreferences? prefs,
}) {
  return ProviderScope(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      profileRepositoryProvider.overrideWithValue(repository),
      if (initialState != null)
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(repository);
          notifier.state = initialState;
          return notifier;
        }),
      nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: child,
    ),
  );
}

Future<void> _pumpTestApp(
  WidgetTester tester, {
  required Widget child,
  required _MockProfileRepository repository,
  ProfileState? initialState,
  SharedPreferences? prefs,
}) async {
  setMobileView(tester);
  await tester.pumpWidget(
    _createTestApp(
      child: child,
      repository: repository,
      initialState: initialState,
      prefs: prefs,
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Tester',
      'user_email': 'alex@saman.test',
    });
  });

  group('EditHealthProfileScreen - Allergies Exclusion Contract', () {
    test('ProfileModel.toUpdateJson excludes allergies key completely', () {
      const model = ProfileModel(
        age: 28,
        height: 175.0,
        weight: 70.0,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
        allergies: ['Peanuts', 'Shellfish'],
      );

      final updatePayload = model.toUpdateJson();

      expect(updatePayload.containsKey('allergies'), isFalse,
          reason: 'Backend UserProfileInput does not support allergies');
      expect(updatePayload['age'], equals(28));
      expect(updatePayload['height'], equals(175.0));
      expect(updatePayload['weight'], equals(70.0));
      expect(updatePayload['gender'], equals('male'));
      expect(updatePayload['activity_level'], equals('medium'));
      expect(updatePayload['goal'], equals('maintain_weight'));
      expect(updatePayload.keys.length, equals(6));
    });

    test('ProfileRemoteDataSourceImpl sends toUpdateJson without allergies',
        () async {
      RequestOptions? capturedOptions;
      dynamic capturedData;

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            capturedData = options.data;
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'status': 'ok'},
              ),
            );
          },
        ),
      );

      final dataSource = ProfileRemoteDataSourceImpl(dio: dio);
      const model = ProfileModel(
        age: 30,
        height: 180.0,
        weight: 75.0,
        gender: Gender.female,
        activityLevel: ActivityLevel.high,
        goal: Goal.gain_muscle,
        allergies: ['Gluten'],
      );

      final success = await dataSource.updateProfile(model);

      expect(success, isTrue);
      expect(capturedOptions?.path, equals(ApiConfig.profileUpdateEndpoint));
      expect(capturedData, isA<Map<String, dynamic>>());
      final dataMap = capturedData as Map<String, dynamic>;
      expect(dataMap.containsKey('allergies'), isFalse,
          reason: 'HTTP request body must not contain allergies');
      expect(dataMap['age'], equals(30));
      expect(dataMap['height'], equals(180.0));
      expect(dataMap['weight'], equals(75.0));
      expect(dataMap['gender'], equals('female'));
      expect(dataMap['activity_level'], equals('high'));
      expect(dataMap['goal'], equals('gain_muscle'));
    });
  });

  group('EditHealthProfileScreen - Validation', () {
    testWidgets(
        'validates age boundaries: 12 fail, 13 pass, 120 pass, 121 fail',
        (tester) async {
      final repo = _MockProfileRepository();
      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      // age = 12 (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '12');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '170');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '65');
      await tester.pump();

      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Tuổi phải từ 13 đến 120'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // age = 121 (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '121');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Tuổi phải từ 13 đến 120'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // age = 13 (pass boundary)
      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '13');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.age, equals(13));
    });

    testWidgets(
        'validates age upper boundary: 120 pass',
        (tester) async {
      final repo = _MockProfileRepository();
      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '120');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '170');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '65');
      await tester.pump();

      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.age, equals(120));
    });

    testWidgets('form invalid does not call repository', (tester) async {
      final repo = _MockProfileRepository();
      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      // Leave fields empty and tap save
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(repo.syncCount, equals(0));
      expect(find.text('Vui lòng nhập tuổi'), findsOneWidget);
      expect(find.text('Vui lòng nhập chiều cao'), findsOneWidget);
      expect(find.text('Vui lòng nhập cân nặng'), findsOneWidget);
    });

    testWidgets(
        'validates height: empty fail, non-numeric fail, 0 fail, negative fail, positive pass',
        (tester) async {
      final repo = _MockProfileRepository();
      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '25');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '70');

      // Empty height (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Vui lòng nhập chiều cao'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Non-numeric height (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), 'abc');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Chiều cao phải là số hợp lệ'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Height = 0 (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '0');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Chiều cao phải lớn hơn 0'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Negative height (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '-170');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Chiều cao phải lớn hơn 0'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Positive height (pass)
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175.5');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.height, equals(175.5));
    });

    testWidgets(
        'validates weight: empty fail, non-numeric fail, 0 fail, negative fail, positive pass',
        (tester) async {
      final repo = _MockProfileRepository();
      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '25');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175');

      // Empty weight (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Vui lòng nhập cân nặng'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Non-numeric weight (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), 'xyz');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Cân nặng phải là số hợp lệ'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Weight = 0 (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '0');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Cân nặng phải lớn hơn 0'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Negative weight (fail)
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '-65');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(find.text('Cân nặng phải lớn hơn 0'), findsOneWidget);
      expect(repo.syncCount, equals(0));

      // Positive weight (pass)
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '68.5');
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.weight, equals(68.5));
    });

    testWidgets('accepts valid biometrics and sends selected enums to backend',
        (tester) async {
      final repo = _MockProfileRepository();
      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '29');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '182.5');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '78.5');

      // Tap Goal = gain_muscle
      await tester.ensureVisible(find.byKey(const Key('enum_gain_muscle')));
      await tester.tap(find.byKey(const Key('enum_gain_muscle')));
      // Tap ActivityLevel = high
      await tester.ensureVisible(find.byKey(const Key('enum_high')));
      await tester.tap(find.byKey(const Key('enum_high')));
      // Tap Gender = female
      await tester.ensureVisible(find.byKey(const Key('enum_female')));
      await tester.tap(find.byKey(const Key('enum_female')));
      await tester.pump();

      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.age, equals(29));
      expect(repo.lastSyncedProfile?.height, equals(182.5));
      expect(repo.lastSyncedProfile?.weight, equals(78.5));
      expect(repo.lastSyncedProfile?.goal, equals(Goal.gain_muscle));
      expect(
          repo.lastSyncedProfile?.activityLevel, equals(ActivityLevel.high));
      expect(repo.lastSyncedProfile?.gender, equals(Gender.female));
      // Allergies must remain empty (not collected)
      expect(repo.lastSyncedProfile?.allergies, isEmpty);
    });
  });

  group('EditHealthProfileScreen - State, Lifecycle & Late Arrival', () {
    testWidgets('prefills existing profile data on initial build',
        (tester) async {
      final repo = _MockProfileRepository();
      const initialProfile = ProfileEntity(
        age: 32,
        height: 176,
        weight: 72,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
      );

      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
        initialState: ProfileState(
          status: ProfileStatus.ready,
          profile: initialProfile,
        ),
      );

      expect(find.text('32'), findsOneWidget);
      expect(find.text('176'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
    });

    testWidgets(
        'late arriving profile prefills form if user has not typed (clean)',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );
      // Starts incomplete/empty
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
      );
      await tester.pump();

      // Verify fields are empty initially
      expect(find.text(''), findsWidgets);

      // Late profile arrives from background load
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(
          age: 42,
          height: 180,
          weight: 85,
        ),
      );
      await tester.pump();

      // Form is clean, so it prefills with late profile data
      expect(find.text('42'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
    });

    testWidgets(
        'provider rebuild or late async load does not overwrite dirty user input',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();
      const initialProfile = ProfileEntity(
        age: 20,
        height: 160,
        weight: 55,
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );
      // Set initial profile
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: initialProfile,
      );
      await tester.pump();

      // User modifies the age to 28
      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '28');
      await tester.pump();

      // Simulate a background provider update / rebuild with late data
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(
          age: 99,
          height: 199,
          weight: 99,
        ),
      );
      await tester.pump();

      // The dirty input MUST remain '28', NOT overwritten by '99'
      expect(find.text('28'), findsOneWidget);
      expect(find.text('99'), findsNothing);
    });

    testWidgets('save button prevents double submit while in-flight',
        (tester) async {
      final repo = _MockProfileRepository();
      final syncCompleter = Completer<void>();
      repo.syncCompleter = syncCompleter;

      await _pumpTestApp(
        tester,
        child: const EditHealthProfileScreen(),
        repository: repo,
      );

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '30');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '170');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '70');
      await tester.pump();

      // First tap launches save
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump(); // Enter loading state

      expect(repo.syncCount, equals(1));
      // Loading indicator should appear
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Second tap while in-flight should NOT trigger second sync
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();
      expect(repo.syncCount, equals(1));

      // Resolve in-flight sync
      syncCompleter.complete();
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
    });

    testWidgets('push, pop, and reopen does not leak or cause dispose errors',
        (tester) async {
      final repo = _MockProfileRepository();

      await _pumpTestApp(
        tester,
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                  builder: (_) => const EditHealthProfileScreen()),
            ),
            child: const Text('Open Edit'),
          ),
        ),
        repository: repo,
      );

      // 1st open
      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);

      // Pop back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);

      // 2nd open
      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);

      // Pop again cleanly
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsNothing);
    });
  });

  group('EditHealthProfileScreen - Production Save Error & Success Contract',
      () {
    testWidgets(
        'real ProfileNotifier rethrows on save failure: UI stays, input kept, no refresh called',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();
      repo.syncError = Exception('Server 500 error: Database offline');

      // Use REAL ProfileNotifier wired to the repo
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider
              .overrideWithValue(const FlutterSecureStorage()),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '33');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '75');
      await tester.pump();

      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // 1. Error message displayed in SnackBar
      expect(find.textContaining('Server 500 error'), findsOneWidget);

      // 2. User inputs remain completely intact
      expect(find.text('33'), findsOneWidget);
      expect(find.text('175'), findsOneWidget);
      expect(find.text('75'), findsOneWidget);

      // 3. Screen did NOT pop
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);

      // 4. Loading indicator is gone (button restored)
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 5. No refresh/loadProfile GET call made after update failure
      expect(repo.fetchCount, equals(0));
      expect(repo.syncCount, equals(1));
    });

    testWidgets(
        'save success calls refresh exactly once and pops after canonical state update',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider
                .overrideWithValue(const FlutterSecureStorage()),
            profileRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no GET was made by Edit screen
      expect(repo.fetchCount, equals(0));

      // Open Edit Screen via CTA
      await tester.tap(find.byKey(const Key('complete_profile_cta_button')));
      await tester.pumpAndSettle();
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);

      // Opening screen does NOT generate GET requests
      expect(repo.fetchCount, equals(0));

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '27');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '180');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '75');
      await tester.pump();

      // Tap save
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // Exactly 1 sync (POST) and exactly 1 refresh (GET) were executed
      expect(repo.syncCount, equals(1));
      expect(repo.fetchCount, equals(1));

      // Returned to ProfileScreen
      expect(find.byType(EditHealthProfileScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);

      // ProfileScreen shows updated canonical state
      expect(find.text('27'), findsOneWidget);
      expect(find.text('180 cm'), findsOneWidget);
      expect(find.text('75 kg'), findsOneWidget);
      expect(find.byKey(const Key('edit_profile_cta_button')), findsOneWidget);
    });
  });

  group('ProfileScreen & Navigation Continuity', () {
    testWidgets('ProfileScreen has no inline form and shows incomplete CTA',
        (tester) async {
      final repo = _MockProfileRepository();

      await _pumpTestApp(
        tester,
        child: const ProfileScreen(),
        repository: repo,
        initialState: ProfileState(
          status: ProfileStatus.incomplete,
          profile: ProfileEntity.empty(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify NO inline Form widget exists
      expect(find.byType(Form), findsNothing);
      expect(find.byType(TextFormField), findsNothing);

      // Prominent incomplete card and CTA exists
      expect(find.text('Hồ sơ chưa hoàn thiện'), findsOneWidget);
      expect(
          find.byKey(const Key('complete_profile_cta_button')), findsOneWidget);
    });

    testWidgets(
        'Nutrition redirect switches tab to Profile without pushing second route',
        (tester) async {
      final repo = _MockProfileRepository();

      await _pumpTestApp(
        tester,
        child: const MainScreen(),
        repository: repo,
        initialState: ProfileState(
          status: ProfileStatus.incomplete,
          profile: ProfileEntity.empty(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Nutrition tab (Index 3)
      await tester.tap(find.text('Nutrition'));
      await tester.pumpAndSettle();

      // Guard redirects to Profile tab (Index 4)
      expect(find.textContaining('Vui lòng cập nhật Hồ sơ sức khỏe'),
          findsOneWidget);
      expect(find.text('Hồ sơ chưa hoàn thiện'), findsOneWidget);

      // Verify Navigator cannot pop (it was a tab switch in IndexedStack, not a push)
      final navigatorState =
          tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigatorState.canPop(), isFalse);
    });
  });

  group('ProfileModel - Alias Mapping & Contract Tests', () {
    test('parses legacy and alternative enum aliases correctly from backend json',
        () {
      // Test goal aliases
      final jsonLose = {'goal': 'weight_loss', 'activity_level': 'sedentary', 'gender': 'female'};
      final modelLose = ProfileModel.fromJson(jsonLose);
      expect(modelLose.goal, equals(Goal.lose_weight));
      expect(modelLose.activityLevel, equals(ActivityLevel.low));
      expect(modelLose.gender, equals(Gender.female));

      final jsonGain = {'goal': 'muscle_gain', 'activity_level': 'active', 'gender': 'other'};
      final modelGain = ProfileModel.fromJson(jsonGain);
      expect(modelGain.goal, equals(Goal.gain_muscle));
      expect(modelGain.activityLevel, equals(ActivityLevel.high));
      expect(modelGain.gender, equals(Gender.other));

      final jsonMaintain = {'goal': 'maintain', 'activity_level': 'moderate', 'gender': 'male'};
      final modelMaintain = ProfileModel.fromJson(jsonMaintain);
      expect(modelMaintain.goal, equals(Goal.maintain_weight));
      expect(modelMaintain.activityLevel, equals(ActivityLevel.medium));
      expect(modelMaintain.gender, equals(Gender.male));
    });

    test('toUpdateJson contains strictly 6 health fields and NO allergies', () {
      const model = ProfileModel(
        age: 30,
        height: 180,
        weight: 75,
        gender: Gender.male,
        activityLevel: ActivityLevel.high,
        goal: Goal.gain_muscle,
        allergies: ['peanuts', 'seafood'],
      );

      final updatePayload = model.toUpdateJson();
      expect(updatePayload.containsKey('allergies'), isFalse);
      expect(updatePayload.length, equals(6));
      expect(updatePayload['age'], equals(30));
      expect(updatePayload['height'], equals(180));
      expect(updatePayload['weight'], equals(75));
      expect(updatePayload['gender'], equals('male'));
      expect(updatePayload['activity_level'], equals('high'));
      expect(updatePayload['goal'], equals('gain_muscle'));
    });
  });

  group('EditHealthProfileScreen - Incomplete / Partial Late Prefill', () {
    testWidgets(
        'partial profile with age only (isValid == false) still prefills clean form',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );

      // Initially empty
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
      );
      await tester.pump();

      // Partial profile arrives with ONLY age set, height and weight are null (so isValid is false)
      const partialProfile = ProfileEntity(
        age: 26,
        height: null,
        weight: null,
      );
      expect(partialProfile.isValid, isFalse);

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: partialProfile,
      );
      await tester.pump();

      // Form is clean, so it prefills the age even though profile is not valid
      expect(find.text('26'), findsOneWidget);
    });

    testWidgets('1. profile arriving late with gender only prefills gender correctly',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
      );
      await tester.pump();

      // Late profile arrives with ONLY gender = female
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(gender: Gender.female),
      );
      await tester.pump();

      // Enter biometrics and save to verify prefilled gender was preserved
      await tester.enterText(find.byKey(const Key('edit_profile_age_input')), '25');
      await tester.enterText(find.byKey(const Key('edit_profile_height_input')), '165');
      await tester.enterText(find.byKey(const Key('edit_profile_weight_input')), '55');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.gender, equals(Gender.female));
    });

    testWidgets('2. profile arriving late with activity level only prefills correctly',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
      );
      await tester.pump();

      // Late profile arrives with ONLY activityLevel = high
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(activityLevel: ActivityLevel.high),
      );
      await tester.pump();

      // Enter biometrics and save to verify prefilled activity level
      await tester.enterText(find.byKey(const Key('edit_profile_age_input')), '28');
      await tester.enterText(find.byKey(const Key('edit_profile_height_input')), '175');
      await tester.enterText(find.byKey(const Key('edit_profile_weight_input')), '70');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.activityLevel, equals(ActivityLevel.high));
    });

    testWidgets('3. profile arriving late with goal only prefills correctly',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
      );
      await tester.pump();

      // Late profile arrives with ONLY goal = gain_muscle
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(goal: Goal.gain_muscle),
      );
      await tester.pump();

      // Enter biometrics and save to verify prefilled goal
      await tester.enterText(find.byKey(const Key('edit_profile_age_input')), '30');
      await tester.enterText(find.byKey(const Key('edit_profile_height_input')), '180');
      await tester.enterText(find.byKey(const Key('edit_profile_weight_input')), '75');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.goal, equals(Goal.gain_muscle));
    });

    testWidgets('4. user selects enum before profile arrives does not overwrite user choice',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.incomplete,
        profile: ProfileEntity.empty(),
      );
      await tester.pump();

      // User actively selects Goal = lose_weight first (marks form dirty)
      await tester.ensureVisible(find.byKey(const Key('enum_lose_weight')));
      await tester.tap(find.byKey(const Key('enum_lose_weight')));
      await tester.pump();

      // Now late profile arrives with goal = gain_muscle
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(goal: Goal.gain_muscle),
      );
      await tester.pump();

      // Complete biometrics and save
      await tester.enterText(find.byKey(const Key('edit_profile_age_input')), '24');
      await tester.enterText(find.byKey(const Key('edit_profile_height_input')), '168');
      await tester.enterText(find.byKey(const Key('edit_profile_weight_input')), '60');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pumpAndSettle();

      // User's choice of lose_weight MUST NOT have been overwritten by gain_muscle
      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.goal, equals(Goal.lose_weight));
    });

    testWidgets('5. provider rebuild after typing or prefilling does not reset form',
        (tester) async {
      setMobileView(tester);
      final repo = _MockProfileRepository();

      late ProviderContainer container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider
                  .overrideWithValue(const FlutterSecureStorage()),
              profileRepositoryProvider.overrideWithValue(repo),
            ],
          ),
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const EditHealthProfileScreen(),
          ),
        ),
      );

      // Start with initial profile
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: const ProfileEntity(
          age: 22,
          height: 165,
          weight: 58,
        ),
      );
      await tester.pump();

      // User types custom age = 99
      await tester.enterText(find.byKey(const Key('edit_profile_age_input')), '99');
      await tester.pump();
      expect(find.text('99'), findsOneWidget);

      // Provider emits multiple rebuilds (e.g. offline status, new snapshot)
      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.offline,
        profile: const ProfileEntity(
          age: 22,
          height: 165,
          weight: 58,
        ),
      );
      await tester.pump();

      // Form MUST still hold '99' and not be reset to '22'
      expect(find.text('99'), findsOneWidget);
    });
  });

  group('ProfileNotifier - POST Success but Canonical GET Refresh Failure', () {
    testWidgets(
        'when syncProfile succeeds but fetchProfileSnapshot throws in refresh, updateProfile completes and handles error gracefully',
        (tester) async {
      setMobileView(tester);

      // Create a repository where syncProfile succeeds, but fetchProfileSnapshot throws
      final repo = _MockProfileRepository();
      repo.snapshotToReturn = null;
      // syncProfile succeeds normally

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider
              .overrideWithValue(const FlutterSecureStorage()),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Setup initial state
      const initialProfile = ProfileEntity(
        age: 25,
        height: 170,
        weight: 65,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
      );

      container.read(profileProvider.notifier).state = ProfileState(
        status: ProfileStatus.ready,
        profile: initialProfile,
      );

      // Now configure repo: subsequent fetchProfileSnapshot throws (simulating GET refresh failure)
      repo.fetchError = Exception('GET refresh network error');

      const newProfile = ProfileEntity(
        age: 26,
        height: 172,
        weight: 68,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      );

      // Call updateProfile: syncProfile succeeds, then loadProfile is called and catches the GET error
      await container.read(profileProvider.notifier).updateProfile(newProfile);

      // Verify syncProfile was called exactly once
      expect(repo.syncCount, equals(1));
      expect(repo.lastSyncedProfile?.age, equals(26));

      // In loadProfile, since error was caught and previous profile was valid, status becomes offline
      final endState = container.read(profileProvider);
      expect(endState.status, equals(ProfileStatus.offline));
      expect(endState.errorMessage, contains('GET refresh network error'));
    });
  });
}

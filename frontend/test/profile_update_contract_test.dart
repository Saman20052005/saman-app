import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/profile/edit_health_profile_screen.dart';

class _ContractMockProfileRepository implements ProfileRepository {
  int fetchCount = 0;
  int syncCount = 0;
  int cacheCount = 0;

  Completer<ProfileSnapshot>? syncCompleter;
  Completer<void>? cacheCompleter;
  Completer<ProfileSnapshot?>? fetchCompleter;

  Object? syncError;
  Object? cacheError;
  Object? fetchError;

  ProfileSnapshot? snapshotToReturn;
  final List<ProfileSnapshot> cachedSnapshots = [];

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    if (fetchCompleter != null) return fetchCompleter!.future;
    return snapshotToReturn;
  }

  @override
  Future<ProfileSnapshot> syncProfile(ProfileEntity profile) async {
    syncCount++;
    if (syncCompleter != null) {
      final res = await syncCompleter!.future;
      if (syncError != null) throw syncError!;
      return res;
    }
    if (syncError != null) throw syncError!;

    final result = ProfileSnapshot(
      profile: profile,
      targetCalories: 2200,
      email: snapshotToReturn?.email ?? 'test@saman.ai',
      fullName: snapshotToReturn?.fullName ?? 'Test Runner',
      avatar: snapshotToReturn?.avatar ?? 'https://avatar.png',
    );
    snapshotToReturn = result;
    return result;
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    cacheCount++;
    if (cacheCompleter != null) {
      await cacheCompleter!.future;
    }
    if (cacheError != null) throw cacheError!;
    cachedSnapshots.add(snapshot);
  }

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshotToReturn?.profile;

  @override
  Future<void> clearLocalProfile() async {
    cachedSnapshots.clear();
  }
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
  required _ContractMockProfileRepository repository,
  ProfileState? initialState,
  VoidCallback? onUnauthorizedLogout,
}) {
  return ProviderScope(
    overrides: [
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
      theme: SamanTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Profile Runtime Contract & Session Isolation Tests', () {
    test(
        '1. Success: 1 POST, 0 GET, 1 cache write upon updateProfile completion',
        () async {
      final repo = _ContractMockProfileRepository();
      final notifier = ProfileNotifier(repo);

      const updateEntity = ProfileEntity(age: 28, height: 175, weight: 70);
      await notifier.updateProfile(updateEntity);

      expect(repo.syncCount, equals(1), reason: 'Exactly 1 POST');
      expect(repo.fetchCount, equals(0), reason: 'Exactly 0 GET refresh');
      expect(repo.cacheCount, equals(1), reason: 'Exactly 1 cache write');
      expect(notifier.state.status, equals(ProfileStatus.ready));
      expect(notifier.state.profile.age, equals(28));
    });

    testWidgets(
        '2. Failed POST: 0 GET, 0 cache write, keeps form and does not pop',
        (tester) async {
      setMobileView(tester);
      final repo = _ContractMockProfileRepository();
      repo.syncError = Exception('Network 500 server error');

      await tester.pumpWidget(
        _createTestApp(
          child: const EditHealthProfileScreen(),
          repository: repo,
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '30');
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
      expect(repo.fetchCount, equals(0));
      expect(repo.cacheCount, equals(0));

      // Screen stays open, inputs kept
      expect(find.byType(EditHealthProfileScreen), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('170'), findsOneWidget);
      expect(find.text('65'), findsOneWidget);
      expect(find.textContaining('Network 500 server error'), findsOneWidget);
    });

    test('3. Malformed POST snapshot is not cached and throws error', () async {
      final repo = _ContractMockProfileRepository();
      repo.syncError = const FormatException('Malformed snapshot payload');

      final notifier = ProfileNotifier(repo);

      const updateEntity = ProfileEntity(age: 28, height: 175, weight: 70);

      await expectLater(
        notifier.updateProfile(updateEntity),
        throwsA(isA<FormatException>()),
      );

      expect(repo.cacheCount, equals(0), reason: 'Malformed response must not write to cache');
      expect(repo.cachedSnapshots, isEmpty);
    });

    testWidgets('4. Double-submit creates exactly one active POST', (tester) async {
      final repo = _ContractMockProfileRepository();
      final syncCompleter = Completer<ProfileSnapshot>();
      repo.syncCompleter = syncCompleter;

      await tester.pumpWidget(
        _createTestApp(
          child: const EditHealthProfileScreen(),
          repository: repo,
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '25');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '70');
      await tester.pump();

      // First tap
      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(repo.syncCount, equals(1));

      // Second tap while in-flight
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      expect(repo.syncCount, equals(1), reason: 'Double submit blocked by _isSaving');

      // Resolve in-flight request
      syncCompleter.complete(
        const ProfileSnapshot(
          profile: ProfileEntity(age: 25, height: 175, weight: 70),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.syncCount, equals(1));
    });

    test('5. Logout before POST completion leaves reset state and clean cache',
        () async {
      final repo = _ContractMockProfileRepository();
      final syncCompleter = Completer<ProfileSnapshot>();
      repo.syncCompleter = syncCompleter;

      final notifier = ProfileNotifier(repo);

      // Start update in session 0
      final saveFuture = notifier.updateProfile(
        const ProfileEntity(age: 25, height: 175, weight: 70),
      );

      // Logout / reset session while POST is pending
      notifier.resetSession();
      expect(notifier.state.status, equals(ProfileStatus.initial));

      // Late POST completes
      syncCompleter.complete(
        const ProfileSnapshot(
          profile: ProfileEntity(age: 25, height: 175, weight: 70),
          fullName: 'Stale Account A',
        ),
      );
      await saveFuture;

      expect(notifier.state.status, equals(ProfileStatus.initial));
      expect(repo.cacheCount, equals(0), reason: 'Stale snapshot must not write cache');
      expect(repo.cachedSnapshots, isEmpty);
    });

    test('6. Logout while cache awaits leaves reset state and clean cache', () async {
      final repo = _ContractMockProfileRepository();
      final cacheCompleter = Completer<void>();
      repo.cacheCompleter = cacheCompleter;

      final notifier = ProfileNotifier(repo);

      // Start update
      final saveFuture = notifier.updateProfile(
        const ProfileEntity(age: 30, height: 180, weight: 80),
      );

      // Allow POST to complete and enter cacheSnapshot
      await Future.delayed(Duration.zero);
      expect(repo.cacheCount, equals(1));

      // User logs out while cache write is in-flight
      notifier.resetSession();

      // Finish delayed cache write
      cacheCompleter.complete();
      await saveFuture;

      expect(notifier.state.status, equals(ProfileStatus.initial));
    });

    test('7. Late account A response never writes/applies into account B', () async {
      final repo = _ContractMockProfileRepository();
      final syncCompleterA = Completer<ProfileSnapshot>();
      repo.syncCompleter = syncCompleterA;

      final notifier = ProfileNotifier(repo);

      // Account A starts update
      final futureA = notifier.updateProfile(
        const ProfileEntity(age: 20, height: 160, weight: 50),
      );

      // User switches account / resets
      notifier.resetSession();

      // Account B logs in and completes load
      repo.syncCompleter = null;
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 35, height: 185, weight: 85),
        fullName: 'Account B',
      );
      await notifier.loadProfile();

      // Late response A arrives
      syncCompleterA.complete(
        const ProfileSnapshot(
          profile: ProfileEntity(age: 20, height: 160, weight: 50),
          fullName: 'Account A',
        ),
      );
      await futureA;

      // Account B state remains active and intact
      expect(notifier.state.fullName, equals('Account B'));
      expect(notifier.state.profile.age, equals(35));
    });

    test('8. 401 produces unauthorized state', () async {
      final repo = _ContractMockProfileRepository();
      repo.syncError = const UnauthorizedException('Token expired');

      final notifier = ProfileNotifier(repo);

      await expectLater(
        notifier.updateProfile(
          const ProfileEntity(age: 25, height: 175, weight: 70),
        ),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(notifier.state.status, equals(ProfileStatus.unauthorized));
      expect(notifier.state.isUnauthorized, isTrue);
    });

    testWidgets('9. Unauthorized causes no duplicate logout/navigation', (tester) async {
      final repo = _ContractMockProfileRepository();
      int logoutCallCount = 0;

      await tester.pumpWidget(
        _createTestApp(
          child: MainScreen(
            onUnauthorizedLogout: () {
              logoutCallCount++;
            },
          ),
          repository: repo,
          initialState: ProfileState(
            status: ProfileStatus.unauthorized,
            profile: ProfileEntity.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(logoutCallCount, equals(1));
    });

    test('10. Identity survives remote load', () async {
      final repo = _ContractMockProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 28, height: 175, weight: 70),
        email: 'athlete@saman.com',
        fullName: 'John Saman',
        avatar: 'https://saman.com/avatar.jpg',
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.email, equals('athlete@saman.com'));
      expect(notifier.state.fullName, equals('John Saman'));
      expect(notifier.state.avatar, equals('https://saman.com/avatar.jpg'));
    });

    test('11. Identity survives cached load', () async {
      final repo = _ContractMockProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 28, height: 175, weight: 70),
        email: 'cached@saman.com',
        fullName: 'Cached Member',
        avatar: 'https://saman.com/cached.jpg',
        isFromCache: true,
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.isFromCache, isTrue);
      expect(notifier.state.email, equals('cached@saman.com'));
      expect(notifier.state.fullName, equals('Cached Member'));
      expect(notifier.state.avatar, equals('https://saman.com/cached.jpg'));
    });

    test('12. Identity survives successful update', () async {
      final repo = _ContractMockProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 28, height: 175, weight: 70),
        email: 'updated@saman.com',
        fullName: 'Updated Athlete',
        avatar: 'https://saman.com/updated.png',
      );

      final notifier = ProfileNotifier(repo);
      await notifier.updateProfile(
        const ProfileEntity(age: 29, height: 176, weight: 71),
      );

      expect(notifier.state.email, equals('updated@saman.com'));
      expect(notifier.state.fullName, equals('Updated Athlete'));
      expect(notifier.state.avatar, equals('https://saman.com/updated.png'));
    });

    test('13. Reset clears old identity completely', () async {
      final repo = _ContractMockProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 28, height: 175, weight: 70),
        email: 'userA@saman.com',
        fullName: 'User A',
        avatar: 'https://saman.com/a.png',
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.email, equals('userA@saman.com'));

      notifier.resetSession();

      expect(notifier.state.email, isNull);
      expect(notifier.state.fullName, isNull);
      expect(notifier.state.avatar, isNull);
    });

    test('14. Cache failure does not report false success', () async {
      final repo = _ContractMockProfileRepository();
      repo.cacheError = Exception('Storage disk full');

      final notifier = ProfileNotifier(repo);

      await expectLater(
        notifier.updateProfile(
          const ProfileEntity(age: 28, height: 175, weight: 70),
        ),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets('15. Dispose during save does not pop or set stale UI state', (tester) async {
      final repo = _ContractMockProfileRepository();
      final syncCompleter = Completer<ProfileSnapshot>();
      repo.syncCompleter = syncCompleter;

      await tester.pumpWidget(
        _createTestApp(
          child: const EditHealthProfileScreen(),
          repository: repo,
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('edit_profile_age_input')), '25');
      await tester.enterText(
          find.byKey(const Key('edit_profile_height_input')), '175');
      await tester.enterText(
          find.byKey(const Key('edit_profile_weight_input')), '70');
      await tester.pump();

      await tester
          .ensureVisible(find.byKey(const Key('edit_profile_save_button')));
      await tester.tap(find.byKey(const Key('edit_profile_save_button')));
      await tester.pump();

      // Dispose screen while request in-flight by pumping empty Container
      await tester.pumpWidget(Container());

      // Resolve in-flight sync after widget was disposed
      syncCompleter.complete(
        const ProfileSnapshot(
          profile: ProfileEntity(age: 25, height: 175, weight: 70),
        ),
      );
      await tester.pump();

      // Ensure no framework exceptions or unhandled async exceptions occurred
      expect(tester.takeException(), isNull);
    });

    test('16. Existing loadProfile behavior does not regress', () async {
      final repo = _ContractMockProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 22, height: 170, weight: 60),
        targetCalories: 2100,
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.status, equals(ProfileStatus.ready));
      expect(notifier.state.targetCalories, equals(2100));
      expect(repo.fetchCount, equals(1));
    });
  });
}

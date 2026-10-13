import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileLocalDataSource - Cache Migration & Backward Compatibility',
      () {
    test(
        'migrates legacy flat cached_profile into ProfileSnapshot without fabricated health stats',
        () async {
      SharedPreferences.setMockInitialValues({
        'cached_profile': '''
        {
          "age": 29,
          "height": 180.0,
          "weight": 78.0,
          "gender": "male",
          "activity_level": "medium",
          "goal": "gain_muscle"
        }
        ''',
      });

      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      final snapshot = await dataSource.getLastSnapshot();

      expect(snapshot, isNotNull);
      expect(snapshot!.profile.age, equals(29));
      expect(snapshot.profile.height, equals(180.0));
      expect(snapshot.profile.weight, equals(78.0));
      expect(snapshot.profile.gender, equals(Gender.male));
      // No server-side health stats fabricated during migration
      expect(snapshot.targetCalories, equals(0));
      expect(snapshot.targetProtein, equals(0));
      expect(snapshot.targetCarbs, equals(0));
      expect(snapshot.targetFat, equals(0));
      expect(snapshot.isFromCache, isTrue);
    });

    test('prefers v2 snapshot cache over legacy v1 cache when both exist',
        () async {
      SharedPreferences.setMockInitialValues({
        'cached_profile': '''
        {
          "age": 20,
          "height": 160.0,
          "weight": 55.0
        }
        ''',
        'cached_profile_snapshot_v2': '''
        {
          "profile": {
            "age": 30,
            "height": 182.0,
            "weight": 80.0,
            "gender": "male",
            "activity_level": "high",
            "goal": "maintain_weight"
          },
          "health_stats": {
            "target_calories": 2650,
            "target_protein": 170,
            "target_carbs": 280,
            "target_fat": 75,
            "target_burned": 450,
            "water_target_ml": 3000
          }
        }
        ''',
      });

      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      final snapshot = await dataSource.getLastSnapshot();

      expect(snapshot, isNotNull);
      expect(snapshot!.profile.age, equals(30));
      expect(snapshot.profile.height, equals(182.0));
      expect(snapshot.targetCalories, equals(2650));
      expect(snapshot.targetProtein, equals(170));
      expect(snapshot.waterTargetMl, equals(3000));
      expect(snapshot.isFromCache, isTrue);
    });

    test('handles corrupted cache JSON gracefully without throwing', () async {
      SharedPreferences.setMockInitialValues({
        'cached_profile_snapshot_v2': '{{{ corrupted json content ...',
        'cached_profile': 'not a json',
      });

      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      final snapshot = await dataSource.getLastSnapshot();
      expect(snapshot, isNull);
    });

    test('handles missing or partial health_stats gracefully in snapshot',
        () async {
      SharedPreferences.setMockInitialValues({
        'cached_profile_snapshot_v2': '''
        {
          "profile": {
            "age": 25,
            "height": 170.0,
            "weight": 65.0
          }
        }
        ''',
      });

      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      final snapshot = await dataSource.getLastSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.profile.age, equals(25));
      expect(snapshot.targetCalories, equals(0));
      expect(snapshot.targetBurned, equals(300));
      expect(snapshot.waterTargetMl, equals(2000));
    });

    test('clearCache removes both v1 and v2 cache keys', () async {
      SharedPreferences.setMockInitialValues({
        'cached_profile': '{"age": 25}',
        'cached_profile_snapshot_v2': '{"profile": {"age": 25}}',
        'language_code': 'en',
      });

      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      await dataSource.clearCache();

      expect(prefs.containsKey('cached_profile'), isFalse);
      expect(prefs.containsKey('cached_profile_snapshot_v2'), isFalse);
      expect(prefs.getString('language_code'), equals('en'));
    });

    test('cacheSnapshot writes to v2 key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const snapshotModel = ProfileSnapshotModel(
        profile: ProfileEntity(
          age: 26,
          height: 172.0,
          weight: 68.0,
          gender: Gender.female,
          activityLevel: ActivityLevel.low,
          goal: Goal.lose_weight,
        ),
        targetCalories: 1800,
        targetProtein: 120,
        targetCarbs: 180,
        targetFat: 50,
      );

      await dataSource.cacheSnapshot(snapshotModel);

      expect(prefs.containsKey('cached_profile_snapshot_v2'), isTrue);
      final raw = prefs.getString('cached_profile_snapshot_v2');
      expect(raw, contains('"age":26'));
      expect(raw, contains('"daily_calories":1800'));
    });

    test(
        'serialized mutation queue: clearCache enqueued during in-flight cacheSnapshot executes after it and wipes cache',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const model = ProfileSnapshotModel(
        profile: ProfileEntity(age: 25, height: 175, weight: 70),
        targetCalories: 2000,
      );

      final writeFuture = dataSource.cacheSnapshot(model);
      final clearFuture = dataSource.clearCache();

      await Future.wait([writeFuture, clearFuture]);

      // Cache keys MUST be absent because clearCache ran in FIFO order after cacheSnapshot
      expect(prefs.containsKey('cached_profile'), isFalse);
      expect(prefs.containsKey('cached_profile_snapshot_v2'), isFalse);
    });
  });
}

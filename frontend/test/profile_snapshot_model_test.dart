import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

Map<String, dynamic> _payload() => {
  'user_id': 'server-user',
  'profile': {'age': 28, 'height': 178.25, 'weight': 72.5,
    'gender': 'male', 'activity_level': 'moderate', 'goal': 'maintain_weight'},
  'health_stats': <String, dynamic>{'daily_calories': 2400, 'target_protein': 145,
    'target_carbs': 290, 'target_fat': 65, 'water_target_ml': 2537},
};

void main() {
  group('CP04 raw server stats provenance', () {
    test('required numeric stats without target_burned keep exact profile decimals', () {
      final snapshot = ProfileSnapshotModel.fromJson(_payload());
      expect(snapshot.hasConfirmedServerHealthStats, isTrue);
      expect(snapshot.profile.height, 178.25);
      expect(snapshot.profile.weight, 72.5);
      expect(snapshot.targetBurned, 300);
    });
    test('daily_calorie_needs is a supported server alias', () {
      final payload = _payload();
      final stats = payload['health_stats'] as Map<String, dynamic>;
      stats['daily_calorie_needs'] = stats.remove('daily_calories');
      final snapshot = ProfileSnapshotModel.fromJson(payload);
      expect(snapshot.hasConfirmedServerHealthStats, isTrue);
      expect(snapshot.targetCalories, 2400);
    });
    test('server calorie alias takes precedence over legacy display target', () {
      final payload = _payload();
      final stats = payload['health_stats'] as Map<String, dynamic>;
      stats.remove('daily_calories');
      stats['daily_calorie_needs'] = 2400;
      stats['target_calories'] = 1000;
      final snapshot = ProfileSnapshotModel.fromJson(payload);
      expect(snapshot.hasConfirmedServerHealthStats, isTrue);
      expect(snapshot.targetCalories, 2400);
    });
    test('legacy target_calories and flat targets cannot prove server stats', () {
      final payload = _payload();
      final stats = payload['health_stats'] as Map<String, dynamic>;
      stats['target_calories'] = stats.remove('daily_calories');
      final legacy = ProfileSnapshotModel.fromJson(payload);
      expect(legacy.targetCalories, 2400);
      expect(legacy.hasConfirmedServerHealthStats, isFalse);
      payload.remove('health_stats');
      payload.addAll({'targetCalories':2400,'targetProtein':145,
        'targetCarbs':290,'targetFat':65,'waterTargetMl':2500});
      final snapshot = ProfileSnapshotModel.fromJson(payload);
      expect(snapshot.targetCalories, 2400);
      expect(snapshot.hasConfirmedServerHealthStats, isFalse);
    });
    for (final shape in [null, [], 'wrong', 4, true]) {
      test('invalid health_stats shape $shape loads without confirmation', () {
        final payload = _payload()..['health_stats'] = shape;
        final snapshot = ProfileSnapshotModel.fromJson(payload);
        expect(snapshot.hasConfirmedServerHealthStats, isFalse);
        expect(snapshot.waterTargetMl, 2000);
        expect(snapshot.targetBurned, 300);
      });
    }
    for (final field in ['daily_calories','target_protein','target_carbs',
      'target_fat','water_target_ml']) {
      for (final value in [null, '12', true, [], double.nan,
        double.infinity, double.negativeInfinity]) {
        test('$field raw $value cannot be hidden by defaults/coercion', () {
          final payload = _payload();
          (payload['health_stats'] as Map<String, dynamic>)[field] = value;
          expect(ProfileSnapshotModel.fromJson(payload).hasConfirmedServerHealthStats, isFalse);
        });
      }
      test('$field missing is unconfirmed', () {
        final payload = _payload();
        (payload['health_stats'] as Map<String, dynamic>).remove(field);
        expect(ProfileSnapshotModel.fromJson(payload).hasConfirmedServerHealthStats, isFalse);
      });
    }
    group('CP04B calorie alias selection', () {
      test('daily_calories wins over both other aliases', () {
        final payload = _payload();
        final stats = payload['health_stats'] as Map<String, dynamic>;
        stats['daily_calorie_needs'] = 2300;
        stats['target_calories'] = 1000;
        final snapshot = ProfileSnapshotModel.fromJson(payload);
        expect(snapshot.targetCalories, 2400);
        expect(snapshot.hasConfirmedServerHealthStats, isTrue);
      });
      test('null primary selects canonical needs before legacy target', () {
        final payload = _payload();
        final stats = payload['health_stats'] as Map<String, dynamic>;
        stats['daily_calories'] = null;
        stats['daily_calorie_needs'] = 2300;
        stats['target_calories'] = 1000;
        final snapshot = ProfileSnapshotModel.fromJson(payload);
        expect(snapshot.targetCalories, 2300);
        expect(snapshot.hasConfirmedServerHealthStats, isTrue);
      });
      for (final canonical in ['daily_calories', 'daily_calorie_needs']) {
        for (final invalid in ['2400', double.nan, double.infinity]) {
          test('$canonical invalid $invalid cannot be rescued by legacy', () {
            final payload = _payload();
            final stats = payload['health_stats'] as Map<String, dynamic>;
            if (canonical == 'daily_calorie_needs') {
              stats.remove('daily_calories');
            } else {
              // Even a valid secondary canonical value must not hide a bad
              // non-null primary value actually selected by the parser.
              stats['daily_calorie_needs'] = 2300;
            }
            stats[canonical] = invalid;
            stats['target_calories'] = 1000;
            final snapshot = ProfileSnapshotModel.fromJson(payload);
            expect(snapshot.hasConfirmedServerHealthStats, isFalse);
            expect(snapshot.targetCalories, invalid is String ? 2400 : 0);
          });
        }
      }
      test('complete raw cached JSON cannot confirm server stats', () {
        final snapshot = ProfileSnapshotModel.fromJson(
          _payload(), isFromCache: true,
        );
        expect(snapshot.targetCalories, 2400);
        expect(snapshot.hasConfirmedServerHealthStats, isFalse);
      });
    });
    test('finite zero/negative/decimal values add no new sign policy', () {
      final payload = _payload();
      (payload['health_stats'] as Map<String, dynamic>).addAll({
        'daily_calories': -1, 'target_protein': 0,
        'target_carbs': -2.5, 'target_fat': 0.25, 'water_target_ml': 0});
      expect(ProfileSnapshotModel.fromJson(payload).hasConfirmedServerHealthStats, isTrue);
    });
    test('default snapshots do not claim server confirmation', () {
      const snapshot = ProfileSnapshot(profile: ProfileEntity());
      expect(snapshot.hasConfirmedServerHealthStats, isFalse);
      expect(snapshot.copyWith().hasConfirmedServerHealthStats, isFalse);
      expect(ProfileSnapshotModel.fromSnapshot(snapshot).hasConfirmedServerHealthStats, isFalse);
    });
    test('copy/conversion retain provenance; cache cannot revive confirmation', () {
      final snapshot = ProfileSnapshotModel.fromJson(_payload());
      final copy = snapshot.copyWith();
      expect(copy.hasConfirmedServerHealthStats, isTrue);
      expect(ProfileSnapshotModel.fromSnapshot(copy).hasConfirmedServerHealthStats, isTrue);
      final cache = snapshot.copyWith(isFromCache: true);
      expect(cache.hasConfirmedServerHealthStats, isFalse);
      expect(cache.copyWith(isFromCache: false).hasConfirmedServerHealthStats, isFalse);
      expect(ProfileSnapshotModel.fromSnapshot(cache).hasConfirmedServerHealthStats, isFalse);
      final restored = ProfileSnapshotModel.fromJson(snapshot.toJson(), isFromCache: true);
      expect(restored.hasConfirmedServerHealthStats, isFalse);
      expect(restored.copyWith(isFromCache: false).hasConfirmedServerHealthStats, isFalse);
    });
  });
}

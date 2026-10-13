import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';

Map<String, dynamic> legacyJson() => {
      'exerciseId': 'plank',
      'exerciseSlug': 'plank',
      'setNumber': 1,
      'repsCompleted': 8,
      'weightKg': 26.0,
      'isCompleted': true,
      'restTakenSeconds': null,
      'cvDetected': false,
    };

Map<String, dynamic> timedJson() => {
      ...legacyJson(),
      'unit': 'seconds',
      'secondsCompleted': 50,
      'repsCompleted': 0,
      'weightKg': 0.0,
    };

void main() {
  test('Old Plank JSON retains reps, volume, and its exact JSON shape', () {
    final log = ExerciseSetLog.fromJson(legacyJson());
    expect(log.effectiveUnit, SetUnit.reps);
    expect(log.secondsCompleted, isNull);
    expect(log.repsCompleted, 8);
    expect(log.volumeKg, 208);
    expect(log.toJson(), legacyJson());
    expect(log.toJson().containsKey('unit'), false);
    expect(log.toJson().containsKey('secondsCompleted'), false);
    final permissive = ExerciseSetLog.fromJson({
      ...legacyJson(),
      'repsCompleted': -5,
      'weightKg': -1.0,
    });
    expect(permissive.repsCompleted, -5);
    expect(permissive.weightKg, -1);
  });

  test(
      'Timed JSON encode/decode and session round-trip keep authoritative seconds',
      () {
    final log = ExerciseSetLog.fromJson(timedJson());
    expect(log.effectiveUnit, SetUnit.seconds);
    expect(log.repsCompleted, 0);
    expect(log.secondsCompleted, 50);
    expect(log.volumeKg, 0);
    expect(log.toJson(), timedJson());
    expect(ExerciseSetLog.fromJson(jsonDecode(jsonEncode(log))), log);
    final session = WorkoutSession(
      id: 'mixed',
      planName: 'Mixed units',
      startedAt: DateTime.utc(2026, 10, 8),
      exerciseLogs: [ExerciseSetLog.fromJson(legacyJson()), log],
      totalVolumeKg: 208,
    );
    expect(WorkoutSession.fromJson(jsonDecode(jsonEncode(session))), session);
    // Unit is taken from the payload, independently of ID/slug/catalog.
    expect(
        log
            .copyWith(exerciseId: 'unknown', exerciseSlug: 'unknown')
            .effectiveUnit,
        SetUnit.seconds);
    expect(log.copyWith(weightKg: 26).volumeKg, 0);
  });

  for (final value in [null, 0, -1, 1000, 1.5, 50.0, '50', true, [], {}]) {
    test('Reject malformed timed seconds: $value (${value.runtimeType})', () {
      expect(
          () => ExerciseSetLog.fromJson(
              {...timedJson(), 'secondsCompleted': value}),
          throwsA(anything));
    });
  }
  test('Reject missing seconds and unsupported units without reps fallback',
      () {
    final missing = timedJson()..remove('secondsCompleted');
    expect(() => ExerciseSetLog.fromJson(missing), throwsFormatException);
    for (final value in ['minutes', '', 1, true]) {
      expect(() => ExerciseSetLog.fromJson({...timedJson(), 'unit': value}),
          throwsA(anything));
    }
    for (final reps in [-1, 1, 50, 0.5]) {
      expect(
          () =>
              ExerciseSetLog.fromJson({...timedJson(), 'repsCompleted': reps}),
          throwsA(anything));
    }
  });
  test('Constructor and copyWith enforce validation at runtime', () {
    for (final seconds in [null, 0, -1, 1000]) {
      expect(
          () => ExerciseSetLog(
                exerciseId: 'plank',
                exerciseSlug: 'plank',
                setNumber: 1,
                unit: SetUnit.seconds,
                secondsCompleted: seconds,
                repsCompleted: 0,
                weightKg: 0,
                isCompleted: true,
              ),
          throwsArgumentError);
    }
    final log = ExerciseSetLog.fromJson(timedJson());
    expect(() => log.copyWith(repsCompleted: 1), throwsArgumentError);
    expect(() => log.copyWith(secondsCompleted: null), throwsArgumentError);
    for (final seconds in [1, 999]) {
      expect(log.copyWith(secondsCompleted: seconds).secondsCompleted, seconds);
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';

void main() {
  group('CvFormSummaryCalculator', () {
    test('returns zero summary for an empty rep list', () {
      final summary = CvFormSummaryCalculator.compute(reps: const []);

      expect(summary.validReps, 0);
      expect(summary.totalReps, 0);
      expect(summary.fastReps, 0);
      expect(summary.avgElbowAngleDeg, 0.0);
      expect(summary.avgTempoSec, 0.0);
      expect(summary.abortCount, 0);
      expect(summary.toJson(), {
        'valid_reps': 0,
        'fast_reps': 0,
        'avg_elbow_angle_deg': 0.0,
        'avg_tempo_sec': 0.0,
        'abort_count': 0,
      });
    });

    test('summarizes standard, fast, and shallow reps with aborts', () {
      final summary = CvFormSummaryCalculator.compute(
        reps: [
          _rep(1, angle: 40, durationMs: 2500),
          _rep(2, angle: 42, durationMs: 1500),
          _rep(3, angle: 55, durationMs: 2400),
        ],
        abortCount: 2,
      );

      expect(summary.validReps, 1);
      expect(summary.totalReps, 3);
      expect(summary.fastReps, 1);
      expect(summary.avgElbowAngleDeg, 45.7);
      expect(summary.avgTempoSec, 2.13);
      expect(summary.abortCount, 2);
      expect(summary.toJson(), {
        'valid_reps': 1,
        'fast_reps': 1,
        'avg_elbow_angle_deg': 45.7,
        'avg_tempo_sec': 2.13,
        'abort_count': 2,
      });
    });
  });
}

LatPulldownRepEvent _rep(
  int number, {
  required double angle,
  required int durationMs,
}) {
  return LatPulldownRepEvent(
    repNumber: number,
    startTimestampMs: 0,
    bottomTimestampMs: durationMs ~/ 2,
    endTimestampMs: durationMs,
    durationMs: durationMs,
    minElbowAngleDeg: angle,
  );
}

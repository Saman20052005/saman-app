import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/bicep_curl_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/overhead_press_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';

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

    test('applies Squat criteria (knee <= 95 deg, 1.5-4.5s) instead of < 45 deg', () {
      final criteria = ExerciseFormCriteria.forModule(CvExerciseModule.squat);
      expect(criteria.angleMetricLabel, 'Góc gối');
      expect(criteria.criteriaDisplayText, 'Góc gối ≤ 95°');
      expect(criteria.tempoDisplayText, '1.5–4.5s');

      final summary = CvFormSummaryCalculator.compute(
        module: CvExerciseModule.squat,
        reps: [
          _rep(1, angle: 85.0, durationMs: 2500),
          _rep(2, angle: 95.0, durationMs: 1500), // inclusive boundary
          _rep(3, angle: 95.0, durationMs: 4500), // upper tempo boundary
          _rep(4, angle: 96.0, durationMs: 2200), // too shallow
          _rep(5, angle: 85.0, durationMs: 1200), // too fast
        ],
      );

      expect(summary.validReps, 3);
      expect(summary.totalReps, 5);
      expect(summary.fastReps, 1);
    });

    test('applies Pull-up criteria (<= 65 deg, 1.5-4s)', () {
      final criteria = ExerciseFormCriteria.forModule(CvExerciseModule.pullUp);
      expect(criteria.angleMetricLabel, 'Góc khuỷu tay');
      expect(criteria.criteriaDisplayText, 'Góc ≤ 65°');
      expect(criteria.tempoDisplayText, '1.5–4s');

      final summary = CvFormSummaryCalculator.compute(
        module: CvExerciseModule.pullUp,
        reps: [
          _rep(1, angle: 55.0, durationMs: 2000),
          _rep(2, angle: 65.0, durationMs: 4000), // inclusive boundary
          _rep(3, angle: 66.0, durationMs: 2000), // shallow
          _rep(4, angle: 50.0, durationMs: 1200), // fast
        ],
      );

      expect(summary.validReps, 2);
      expect(summary.totalReps, 4);
      expect(summary.fastReps, 1);
    });

    test('applies Push-up, Overhead Press, and Bicep Curl criteria', () {
      final pushUpCriteria =
          ExerciseFormCriteria.forModule(CvExerciseModule.pushUp);
      expect(pushUpCriteria.criteriaDisplayText, 'Góc ≤ 95°');
      expect(pushUpCriteria.tempoDisplayText, '1.2–4s');
      final pushUpSummary = CvFormSummaryCalculator.compute(
        module: CvExerciseModule.pushUp,
        reps: [
          _rep(1, angle: 95.0, durationMs: 1200),
          _rep(2, angle: 96.0, durationMs: 2000),
          _rep(3, angle: 85.0, durationMs: 1000),
        ],
      );
      expect(pushUpSummary.validReps, 1);
      expect(pushUpSummary.fastReps, 1);

      final ohpCriteria =
          ExerciseFormCriteria.forModule(CvExerciseModule.overheadPress);
      expect(ohpCriteria.isMinAngleCriteria, isTrue);
      expect(ohpCriteria.angleMetricLabel, 'Đỉnh duỗi');
      expect(ohpCriteria.criteriaDisplayText, 'Đỉnh duỗi ≥ 155°');
      expect(ohpCriteria.tempoDisplayText, '1.5–4s');
      final ohpSummary = CvFormSummaryCalculator.compute(
        module: CvExerciseModule.overheadPress,
        reps: [
          const OverheadPressRepEvent(
            repNumber: 1,
            startTimestampMs: 0,
            bottomTimestampMs: 900,
            endTimestampMs: 1800,
            durationMs: 1800,
            minElbowAngleDeg: 155.0,
            isBackVertical: true,
          ),
          const OverheadPressRepEvent(
            repNumber: 2,
            startTimestampMs: 2000,
            bottomTimestampMs: 3000,
            endTimestampMs: 4000,
            durationMs: 2000,
            minElbowAngleDeg: 154.0,
            isBackVertical: true,
          ),
          const OverheadPressRepEvent(
            repNumber: 3,
            startTimestampMs: 4200,
            bottomTimestampMs: 5200,
            endTimestampMs: 6200,
            durationMs: 2000,
            minElbowAngleDeg: 165.0,
            isBackVertical: false,
          ),
        ],
      );
      expect(ohpSummary.totalReps, 3);
      expect(ohpSummary.validReps, 1);

      final curlCriteria =
          ExerciseFormCriteria.forModule(CvExerciseModule.bicepCurl);
      expect(curlCriteria.criteriaDisplayText, 'Góc ≤ 60°');
      expect(curlCriteria.tempoDisplayText, '1.5–4s');
      final curlSummary = CvFormSummaryCalculator.compute(
        module: CvExerciseModule.bicepCurl,
        reps: [
          const BicepCurlRepEvent(
            repNumber: 1,
            startTimestampMs: 0,
            bottomTimestampMs: 900,
            endTimestampMs: 1800,
            durationMs: 1800,
            minElbowAngleDeg: 60.0,
            isElbowPinned: true,
            isTorsoStable: true,
          ),
          const BicepCurlRepEvent(
            repNumber: 2,
            startTimestampMs: 2000,
            bottomTimestampMs: 3000,
            endTimestampMs: 4000,
            durationMs: 2000,
            minElbowAngleDeg: 61.0,
            isElbowPinned: true,
            isTorsoStable: true,
          ),
          const BicepCurlRepEvent(
            repNumber: 3,
            startTimestampMs: 4200,
            bottomTimestampMs: 5200,
            endTimestampMs: 6200,
            durationMs: 2000,
            minElbowAngleDeg: 50.0,
            isElbowPinned: false,
            isTorsoStable: true,
          ),
          const BicepCurlRepEvent(
            repNumber: 4,
            startTimestampMs: 6400,
            bottomTimestampMs: 7400,
            endTimestampMs: 8400,
            durationMs: 2000,
            minElbowAngleDeg: 50.0,
            isElbowPinned: true,
            isTorsoStable: false,
          ),
        ],
      );
      expect(curlSummary.totalReps, 4);
      expect(curlSummary.validReps, 1);
    });

    test('explicit maxValidElbowAngleDeg override preserves strict < comparison', () {
      expect(
        CvFormSummaryCalculator.isRepStandardMet(
          _rep(1, angle: 49.9, durationMs: 2500),
          module: CvExerciseModule.squat,
          maxValidElbowAngleDeg: 50.0,
        ),
        isTrue,
      );
      expect(
        CvFormSummaryCalculator.isRepStandardMet(
          _rep(2, angle: 50.0, durationMs: 2500),
          module: CvExerciseModule.squat,
          maxValidElbowAngleDeg: 50.0,
        ),
        isFalse,
      );
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

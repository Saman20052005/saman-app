import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/hip_hinge_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lateral_raise_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/leg_machine_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/tricep_extension_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<Map<String, dynamic>> _baseLandmarkMaps({double visibility = 0.1}) {
  return List.generate(
    33,
    (i) => <String, dynamic>{
      'index': i,
      'x': 0.5,
      'y': 0.5,
      'z': 0.0,
      'visibility': visibility,
    },
  );
}

Map<String, dynamic> _lm(int index, double xPx, double yPx, double vis) => {
      'index': index,
      'x': (xPx / _imgW).clamp(0.0, 1.0),
      'y': (yPx / _imgH).clamp(0.0, 1.0),
      'z': 0.0,
      'visibility': vis,
    };

Map<String, dynamic> _wrapDetectingEvent({
  required int timestampMs,
  required List<Map<String, dynamic>> landmarks,
  int gen = 5,
}) {
  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

/// Builds a pose with exact 2D `Shoulder -> Hip -> Knee` and `Hip -> Knee -> Ankle` angles.
Map<String, dynamic> _hipHingePoseEvent({
  required int timestampMs,
  required double hipAngleDeg,
  double kneeAngleDeg = 172.0,
  bool wristAboveShoulder = false,
  bool includeWrist = true,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const hipX = 540.0;
  const hipY = 960.0;
  const seg = 260.0;

  final hipRad = hipAngleDeg * math.pi / 180.0;
  final kneeRad = kneeAngleDeg * math.pi / 180.0;

  const kneeX = hipX;
  const kneeY = hipY + seg;
  final shX = hipX + seg * math.sin(hipRad);
  final shY = hipY + seg * math.cos(hipRad);
  final ankleX = kneeX + seg * math.sin(kneeRad);
  final ankleY = kneeY - seg * math.cos(kneeRad);

  landmarks[PoseLandmark.rightShoulder] =
      _lm(PoseLandmark.rightShoulder, shX, shY, 0.95);
  landmarks[PoseLandmark.rightHip] =
      _lm(PoseLandmark.rightHip, hipX, hipY, 0.95);
  landmarks[PoseLandmark.rightKnee] =
      _lm(PoseLandmark.rightKnee, kneeX, kneeY, 0.95);
  landmarks[PoseLandmark.rightAnkle] =
      _lm(PoseLandmark.rightAnkle, ankleX, ankleY, 0.95);

  if (includeWrist) {
    final wristY = wristAboveShoulder ? shY - 150.0 : shY + 150.0;
    final elbowY = wristAboveShoulder ? shY - 75.0 : shY + 75.0;
    landmarks[PoseLandmark.rightElbow] =
        _lm(PoseLandmark.rightElbow, shX, elbowY, 0.95);
    landmarks[PoseLandmark.rightWrist] =
        _lm(PoseLandmark.rightWrist, shX, wristY, 0.95);
  }

  return _wrapDetectingEvent(
    timestampMs: timestampMs,
    landmarks: landmarks,
    gen: gen,
  );
}

/// Builds a pose with exact 2D `Shoulder -> Elbow -> Wrist` angles on left and right sides.
Map<String, dynamic> _tricepExtensionPoseEvent({
  required int timestampMs,
  required double leftElbowAngleDeg,
  required double rightElbowAngleDeg,
  double leftVis = 0.95,
  double rightVis = 0.95,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const seg = 180.0;

  const lShX = 420.0;
  const lShY = 600.0;
  const lElX = 420.0;
  const lElY = 800.0;
  final lRad = leftElbowAngleDeg * math.pi / 180.0;
  final lWrX = lElX - seg * math.sin(lRad);
  final lWrY = lElY - seg * math.cos(lRad);

  const rShX = 660.0;
  const rShY = 600.0;
  const rElX = 660.0;
  const rElY = 800.0;
  final rRad = rightElbowAngleDeg * math.pi / 180.0;
  final rWrX = rElX + seg * math.sin(rRad);
  final rWrY = rElY - seg * math.cos(rRad);

  landmarks[PoseLandmark.leftShoulder] =
      _lm(PoseLandmark.leftShoulder, lShX, lShY, leftVis);
  landmarks[PoseLandmark.leftElbow] =
      _lm(PoseLandmark.leftElbow, lElX, lElY, leftVis);
  landmarks[PoseLandmark.leftWrist] =
      _lm(PoseLandmark.leftWrist, lWrX, lWrY, leftVis);
  landmarks[PoseLandmark.leftHip] =
      _lm(PoseLandmark.leftHip, 440.0, 1100.0, 0.95);

  landmarks[PoseLandmark.rightShoulder] =
      _lm(PoseLandmark.rightShoulder, rShX, rShY, rightVis);
  landmarks[PoseLandmark.rightElbow] =
      _lm(PoseLandmark.rightElbow, rElX, rElY, rightVis);
  landmarks[PoseLandmark.rightWrist] =
      _lm(PoseLandmark.rightWrist, rWrX, rWrY, rightVis);
  landmarks[PoseLandmark.rightHip] =
      _lm(PoseLandmark.rightHip, 640.0, 1100.0, 0.95);

  return _wrapDetectingEvent(
    timestampMs: timestampMs,
    landmarks: landmarks,
    gen: gen,
  );
}

/// Builds a pose with exact 2D `Hip -> Shoulder -> Elbow` angles on left and right sides.
Map<String, dynamic> _lateralRaisePoseEvent({
  required int timestampMs,
  required double leftShoulderAngleDeg,
  required double rightShoulderAngleDeg,
  double leftVis = 0.95,
  double rightVis = 0.95,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const upperArmLen = 200.0;

  const lHipX = 460.0;
  const lHipY = 1100.0;
  const lShX = 460.0;
  const lShY = 750.0;
  final lRad = leftShoulderAngleDeg * math.pi / 180.0;
  final lElX = lShX - upperArmLen * math.sin(lRad);
  final lElY = lShY + upperArmLen * math.cos(lRad);

  const rHipX = 620.0;
  const rHipY = 1100.0;
  const rShX = 620.0;
  const rShY = 750.0;
  final rRad = rightShoulderAngleDeg * math.pi / 180.0;
  final rElX = rShX + upperArmLen * math.sin(rRad);
  final rElY = rShY + upperArmLen * math.cos(rRad);

  landmarks[PoseLandmark.leftHip] =
      _lm(PoseLandmark.leftHip, lHipX, lHipY, leftVis);
  landmarks[PoseLandmark.leftShoulder] =
      _lm(PoseLandmark.leftShoulder, lShX, lShY, leftVis);
  landmarks[PoseLandmark.leftElbow] =
      _lm(PoseLandmark.leftElbow, lElX, lElY, leftVis);

  landmarks[PoseLandmark.rightHip] =
      _lm(PoseLandmark.rightHip, rHipX, rHipY, rightVis);
  landmarks[PoseLandmark.rightShoulder] =
      _lm(PoseLandmark.rightShoulder, rShX, rShY, rightVis);
  landmarks[PoseLandmark.rightElbow] =
      _lm(PoseLandmark.rightElbow, rElX, rElY, rightVis);

  return _wrapDetectingEvent(
    timestampMs: timestampMs,
    landmarks: landmarks,
    gen: gen,
  );
}

/// Builds a pose with exact 2D `Hip -> Knee -> Ankle` angles on left and right sides.
Map<String, dynamic> _legPoseEvent({
  required int timestampMs,
  required double leftKneeAngleDeg,
  required double rightKneeAngleDeg,
  double leftVis = 0.95,
  double rightVis = 0.95,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const seg = 320.0;

  const lHipX = 440.0;
  const lHipY = 800.0;
  const lKneeX = 440.0;
  const lKneeY = 1150.0;
  final lRad = leftKneeAngleDeg * math.pi / 180.0;
  final lAnkX = lKneeX - seg * math.sin(lRad);
  final lAnkY = lKneeY - seg * math.cos(lRad);

  const rHipX = 640.0;
  const rHipY = 800.0;
  const rKneeX = 640.0;
  const rKneeY = 1150.0;
  final rRad = rightKneeAngleDeg * math.pi / 180.0;
  final rAnkX = rKneeX + seg * math.sin(rRad);
  final rAnkY = rKneeY - seg * math.cos(rRad);

  landmarks[PoseLandmark.leftHip] =
      _lm(PoseLandmark.leftHip, lHipX, lHipY, leftVis);
  landmarks[PoseLandmark.leftKnee] =
      _lm(PoseLandmark.leftKnee, lKneeX, lKneeY, leftVis);
  landmarks[PoseLandmark.leftAnkle] =
      _lm(PoseLandmark.leftAnkle, lAnkX, lAnkY, leftVis);

  landmarks[PoseLandmark.rightHip] =
      _lm(PoseLandmark.rightHip, rHipX, rHipY, rightVis);
  landmarks[PoseLandmark.rightKnee] =
      _lm(PoseLandmark.rightKnee, rKneeX, rKneeY, rightVis);
  landmarks[PoseLandmark.rightAnkle] =
      _lm(PoseLandmark.rightAnkle, rAnkX, rAnkY, rightVis);

  return _wrapDetectingEvent(
    timestampMs: timestampMs,
    landmarks: landmarks,
    gen: gen,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Extended Library Registry (Phase 6: +14 exercises)', () {
    test('maps all 14 new slugs and keeps bench press / seated cable row unsupported', () {
      const expected = <String, CvExerciseModule>{
        'romanian-deadlift': CvExerciseModule.hipHinge,
        'hanging-leg-raise': CvExerciseModule.hipHinge,
        'barbell-hip-thrust': CvExerciseModule.hipThrust,
        'glute-bridge': CvExerciseModule.hipThrust,
        'triceps-rope-pushdown': CvExerciseModule.tricepExtension,
        'overhead-triceps-extension': CvExerciseModule.tricepExtension,
        'lying-ez-bar-triceps-extension': CvExerciseModule.tricepExtension,
        'dumbbell-lateral-raise': CvExerciseModule.lateralRaise,
        'cable-lateral-raise': CvExerciseModule.lateralRaise,
        'leg-press': CvExerciseModule.legExtension,
        'leg-extension': CvExerciseModule.legExtension,
        'lying-leg-curl': CvExerciseModule.legCurl,
        'reverse-lunge': CvExerciseModule.legCurl,
        'bulgarian-split-squat': CvExerciseModule.legCurl,
      };

      expect(expected.length, 14);
      for (final entry in expected.entries) {
        expect(
          WorkoutCvExerciseRegistry.resolveModule(
            id: entry.key,
            slug: entry.key,
          ),
          entry.value,
          reason: '${entry.key} should map to ${entry.value}',
        );
        expect(
          WorkoutCvExerciseRegistry.isSupported(
            id: entry.key,
            slug: entry.key,
          ),
          isTrue,
        );
      }

      expect(
        WorkoutCvExerciseRegistry.resolveModule(
          id: 'db-bench-press',
          slug: 'dumbbell-bench-press',
        ),
        isNull,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
          id: 'seated-cable-row',
          slug: 'seated-cable-row',
        ),
        CvExerciseModule.row,
      );
      expect(
        WorkoutCvExerciseRegistry.isSupported(
          id: 'db-bench-press',
          slug: 'dumbbell-bench-press',
        ),
        isFalse,
      );
      expect(
        WorkoutCvExerciseRegistry.isSupported(
          id: 'seated-cable-row',
          slug: 'seated-cable-row',
        ),
        isTrue,
      );
    });
  });

  group('Extended Library ExerciseFormCriteria (6 new modules)', () {
    test('configures exact criteria and criteriaDisplayText for all 6 new modules', () {
      final hipHinge = ExerciseFormCriteria.forModule(CvExerciseModule.hipHinge);
      expect(hipHinge.maxValidAngleDeg, 105.0);
      expect(hipHinge.maxAngleInclusive, isTrue);
      expect(hipHinge.isMinAngleCriteria, isFalse);
      expect(hipHinge.minValidDurationMs, 1200);
      expect(hipHinge.maxValidDurationMs, 4500);
      expect(hipHinge.angleMetricLabel, 'Gập hông');
      expect(hipHinge.criteriaDisplayText, 'Gập hông ≤ 105°');

      final hipThrust =
          ExerciseFormCriteria.forModule(CvExerciseModule.hipThrust);
      expect(hipThrust.maxValidAngleDeg, 160.0);
      expect(hipThrust.maxAngleInclusive, isTrue);
      expect(hipThrust.isMinAngleCriteria, isTrue);
      expect(hipThrust.minValidDurationMs, 1200);
      expect(hipThrust.maxValidDurationMs, 4000);
      expect(hipThrust.angleMetricLabel, 'Khóa hông');
      expect(hipThrust.criteriaDisplayText, 'Khóa hông ≥ 160°');

      final tricep =
          ExerciseFormCriteria.forModule(CvExerciseModule.tricepExtension);
      expect(tricep.maxValidAngleDeg, 155.0);
      expect(tricep.maxAngleInclusive, isTrue);
      expect(tricep.isMinAngleCriteria, isTrue);
      expect(tricep.minValidDurationMs, 1200);
      expect(tricep.maxValidDurationMs, 4000);
      expect(tricep.angleMetricLabel, 'Đỉnh duỗi');
      expect(tricep.criteriaDisplayText, 'Đỉnh duỗi ≥ 155°');

      final lateral =
          ExerciseFormCriteria.forModule(CvExerciseModule.lateralRaise);
      expect(lateral.maxValidAngleDeg, 75.0);
      expect(lateral.maxAngleInclusive, isTrue);
      expect(lateral.isMinAngleCriteria, isTrue);
      expect(lateral.minValidDurationMs, 1200);
      expect(lateral.maxValidDurationMs, 4000);
      expect(lateral.angleMetricLabel, 'Dang vai');
      expect(lateral.criteriaDisplayText, 'Dang vai ≥ 75°');

      final legExt =
          ExerciseFormCriteria.forModule(CvExerciseModule.legExtension);
      expect(legExt.maxValidAngleDeg, 150.0);
      expect(legExt.maxAngleInclusive, isTrue);
      expect(legExt.isMinAngleCriteria, isTrue);
      expect(legExt.minValidDurationMs, 1200);
      expect(legExt.maxValidDurationMs, 4000);
      expect(legExt.angleMetricLabel, 'Đỉnh duỗi gối');
      expect(legExt.criteriaDisplayText, 'Đỉnh duỗi ≥ 150°');

      final legCurl = ExerciseFormCriteria.forModule(CvExerciseModule.legCurl);
      expect(legCurl.maxValidAngleDeg, 105.0);
      expect(legCurl.maxAngleInclusive, isTrue);
      expect(legCurl.isMinAngleCriteria, isFalse);
      expect(legCurl.minValidDurationMs, 1200);
      expect(legCurl.maxValidDurationMs, 4500);
      expect(legCurl.angleMetricLabel, 'Góc gối');
      expect(legCurl.criteriaDisplayText, 'Góc gối ≤ 105°');
    });
  });

  group('Extended Library WorkoutCvNotifier End-to-End Tests', () {
    Future<void> emitAndDrain(
      MockWorkoutCvNativeSource source,
      Map<String, dynamic> event,
    ) async {
      source.emitEvent(event);
      await Future<void>.delayed(Duration.zero);
    }

    test('Romanian Deadlift full cycle, squat-rejection when knee < 130°, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'romanian-deadlift',
        exerciseSlug: 'romanian-deadlift',
      );

      // 1. Valid RDL cycle (hip: 170 -> 95 -> 170 with knee = 168 >= 130)
      const rdlCycle = <(int, double, double)>[
        (0, 170, 168),
        (150, 170, 168),
        (250, 170, 168), // ready hold >= 200ms
        (500, 130, 166), // hinging (< 140)
        (950, 95, 165), // peak (<= 105 & knee >= 130)
        (1400, 132, 166), // returning (> 120)
        (1750, 165, 168), // >= 155
        (1950, 170, 168), // hold >= 150ms -> duration 1450ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, hip, knee) in rdlCycle) {
        await emitAndDrain(
          source,
          _hipHingePoseEvent(
            timestampMs: t,
            hipAngleDeg: hip,
            kneeAngleDeg: knee,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(95.0, 0.5));

      // 2. Squat-like cycle (hip = 90 but knee = 95 < 130) must NOT count as RDL rep
      const squatRejectedCycle = <(int, double, double)>[
        (2200, 130, 115),
        (2600, 90, 95),
        (3000, 130, 115),
        (3400, 170, 170),
        (3600, 170, 170),
      ];
      for (final (t, hip, knee) in squatRejectedCycle) {
        await emitAndDrain(
          source,
          _hipHingePoseEvent(
            timestampMs: t,
            hipAngleDeg: hip,
            kneeAngleDeg: knee,
          ),
        );
      }
      expect(controller.state.completedReps, 1);

      // 3. Gap > 500ms mid-rep aborts cycle
      await emitAndDrain(
        source,
        _hipHingePoseEvent(timestampMs: 3800, hipAngleDeg: 125, kneeAngleDeg: 165),
      );
      await emitAndDrain(
        source,
        _hipHingePoseEvent(timestampMs: 4450, hipAngleDeg: 170, kneeAngleDeg: 170),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.abortCount, greaterThanOrEqualTo(1));

      controller.dispose();
      source.dispose();
    });

    test('Barbell Hip Thrust full cycle, formSummary.validReps >= 1, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-hip-thrust',
        exerciseSlug: 'barbell-hip-thrust',
      );

      const thrustCycle = <(int, double)>[
        (0, 115),
        (150, 115),
        (250, 115), // ready (<= 130)
        (500, 148), // thrusting (> 140)
        (950, 172), // peak lockout (>= 160)
        (1400, 138), // returning (< 145)
        (1750, 120), // <= 130
        (1950, 118), // hold >= 150ms -> duration 1450ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, hip) in thrustCycle) {
        await emitAndDrain(
          source,
          _hipHingePoseEvent(timestampMs: t, hipAngleDeg: hip, kneeAngleDeg: 90),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(172.0, 0.5));

      // Gap > 500ms aborts mid-rep
      await emitAndDrain(
        source,
        _hipHingePoseEvent(timestampMs: 2150, hipAngleDeg: 150, kneeAngleDeg: 90),
      );
      await emitAndDrain(
        source,
        _hipHingePoseEvent(timestampMs: 2800, hipAngleDeg: 118, kneeAngleDeg: 90),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.abortCount, greaterThanOrEqualTo(1));

      controller.dispose();
      source.dispose();
    });

    test('Hanging Leg Raise requires wristAboveShoulder when wrists visible, completes cycle, and aborts on >500ms gap', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'hanging-leg-raise',
        exerciseSlug: 'hanging-leg-raise',
      );

      // Standing with wrists BELOW shoulder must NOT enter ready
      await emitAndDrain(
        source,
        _hipHingePoseEvent(
          timestampMs: 0,
          hipAngleDeg: 170,
          wristAboveShoulder: false,
        ),
      );
      await emitAndDrain(
        source,
        _hipHingePoseEvent(
          timestampMs: 250,
          hipAngleDeg: 170,
          wristAboveShoulder: false,
        ),
      );
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      // Hanging with wrists ABOVE shoulder completes rep
      const hlrCycle = <(int, double)>[
        (400, 165),
        (550, 165),
        (650, 165), // ready (>= 145)
        (900, 120), // hinging (< 130)
        (1350, 82), // peak (<= 95)
        (1800, 122), // returning (> 110)
        (2150, 158), // >= 145
        (2350, 162), // hold >= 150ms -> duration 1450ms -> rep 1
      ];

      for (final (t, hip) in hlrCycle) {
        await emitAndDrain(
          source,
          _hipHingePoseEvent(
            timestampMs: t,
            hipAngleDeg: hip,
            wristAboveShoulder: true,
          ),
        );
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(82.0, 0.5));

      // Gap > 500ms aborts
      await emitAndDrain(
        source,
        _hipHingePoseEvent(
          timestampMs: 2550,
          hipAngleDeg: 118,
          wristAboveShoulder: true,
        ),
      );
      await emitAndDrain(
        source,
        _hipHingePoseEvent(
          timestampMs: 3200,
          hipAngleDeg: 162,
          wristAboveShoulder: true,
        ),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Triceps Rope Pushdown enforces Side-Locking, grades lockout >= 155°, and aborts on >500ms gap', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'triceps-rope-pushdown',
        exerciseSlug: 'triceps-rope-pushdown',
      );

      // Left arm extends while right arm stays flexed at 85° with higher visibility (0.99 > 0.85).
      // Side-locking must lock onto LEFT and NOT jump to idle right arm.
      const tricepCycle = <(int, double, double)>[
        (0, 85, 85),
        (150, 85, 85),
        (250, 85, 85), // ready (<= 95)
        (500, 122, 85), // left extending (> 110) -> lock left
        (950, 165, 85), // left lockout (>= 155)
        (1400, 120, 85), // left returning (< 135)
        (1750, 90, 85), // <= 95
        (1950, 88, 85), // hold >= 150ms -> duration 1450ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, lAngle, rAngle) in tricepCycle) {
        await emitAndDrain(
          source,
          _tricepExtensionPoseEvent(
            timestampMs: t,
            leftElbowAngleDeg: lAngle,
            rightElbowAngleDeg: rAngle,
            leftVis: 0.85,
            rightVis: 0.99,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(165.0, 0.5));

      // Verify Side-Locking rejects occluded locked arm (> 500ms gap) instead of jumping to idle arm
      await emitAndDrain(
        source,
        _tricepExtensionPoseEvent(
          timestampMs: 2150,
          leftElbowAngleDeg: 122,
          rightElbowAngleDeg: 85,
          leftVis: 0.90,
          rightVis: 0.95,
        ),
      );
      await emitAndDrain(
        source,
        _tricepExtensionPoseEvent(
          timestampMs: 2350,
          leftElbowAngleDeg: 160,
          rightElbowAngleDeg: 165,
          leftVis: 0.10, // locked left occluded
          rightVis: 0.95,
        ),
      );
      await emitAndDrain(
        source,
        _tricepExtensionPoseEvent(
          timestampMs: 2950, // > 500ms since last valid left sample at 2150
          leftElbowAngleDeg: 160,
          rightElbowAngleDeg: 165,
          leftVis: 0.10,
          rightVis: 0.95,
        ),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.abortCount, greaterThanOrEqualTo(1));

      controller.dispose();
      source.dispose();
    });

    test('Dumbbell Lateral Raise full cycle with Side-Locking, validReps >= 1, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'dumbbell-lateral-raise',
        exerciseSlug: 'dumbbell-lateral-raise',
      );

      const raiseCycle = <(int, double, double)>[
        (0, 22, 22),
        (150, 22, 22),
        (250, 22, 22), // ready (<= 35)
        (500, 55, 22), // left raising (> 48) -> lock left
        (950, 86, 22), // peak (>= 75)
        (1400, 48, 22), // lowering (< 55)
        (1750, 28, 22), // <= 35
        (1950, 24, 22), // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, lShoulder, rShoulder) in raiseCycle) {
        await emitAndDrain(
          source,
          _lateralRaisePoseEvent(
            timestampMs: t,
            leftShoulderAngleDeg: lShoulder,
            rightShoulderAngleDeg: rShoulder,
            leftVis: 0.85,
            rightVis: 0.99,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(86.0, 0.5));

      // Gap > 500ms aborts
      await emitAndDrain(
        source,
        _lateralRaisePoseEvent(
          timestampMs: 2150,
          leftShoulderAngleDeg: 55,
          rightShoulderAngleDeg: 55,
        ),
      );
      await emitAndDrain(
        source,
        _lateralRaisePoseEvent(
          timestampMs: 2800,
          leftShoulderAngleDeg: 25,
          rightShoulderAngleDeg: 25,
        ),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Leg Press full cycle, validReps >= 1, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'leg-press',
        exerciseSlug: 'leg-press',
      );

      const legPressCycle = <(int, double)>[
        (0, 92),
        (150, 92),
        (250, 92), // ready (<= 105)
        (500, 128), // active (> 120)
        (950, 162), // peak (>= 150)
        (1400, 120), // returning (< 130)
        (1750, 96), // <= 105
        (1950, 92), // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, knee) in legPressCycle) {
        await emitAndDrain(
          source,
          _legPoseEvent(
            timestampMs: t,
            leftKneeAngleDeg: knee,
            rightKneeAngleDeg: knee,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(162.0, 0.5));

      // Gap > 500ms aborts
      await emitAndDrain(
        source,
        _legPoseEvent(timestampMs: 2150, leftKneeAngleDeg: 128, rightKneeAngleDeg: 128),
      );
      await emitAndDrain(
        source,
        _legPoseEvent(timestampMs: 2800, leftKneeAngleDeg: 95, rightKneeAngleDeg: 95),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Lying Leg Curl full cycle, validReps >= 1, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'lying-leg-curl',
        exerciseSlug: 'lying-leg-curl',
      );

      const legCurlCycle = <(int, double)>[
        (0, 165),
        (150, 165),
        (250, 165), // ready (>= 150)
        (500, 125), // active (< 135)
        (950, 75), // peak (<= 85)
        (1400, 115), // returning (> 105)
        (1750, 158), // >= 150
        (1950, 165), // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, knee) in legCurlCycle) {
        await emitAndDrain(
          source,
          _legPoseEvent(
            timestampMs: t,
            leftKneeAngleDeg: knee,
            rightKneeAngleDeg: knee,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(75.0, 0.5));

      // Gap > 500ms aborts
      await emitAndDrain(
        source,
        _legPoseEvent(timestampMs: 2150, leftKneeAngleDeg: 125, rightKneeAngleDeg: 125),
      );
      await emitAndDrain(
        source,
        _legPoseEvent(timestampMs: 2800, leftKneeAngleDeg: 165, rightKneeAngleDeg: 165),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Reverse Lunge tracks alternating legs via minValidKneeAngleDeg, grades validReps >= 2, and aborts on >500ms gap', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'reverse-lunge',
        exerciseSlug: 'reverse-lunge',
      );

      // Rep 1: Left leg bends deeply (90°), right stays higher vis & straighter (140°)
      // Rep 2: Right leg bends deeply (92°), left stays higher vis & straighter (142°)
      const alternatingLungeCycles = <(int, double, double, double, double)>[
        (0, 170, 170, 0.95, 0.95),
        (150, 170, 170, 0.95, 0.95),
        (250, 170, 170, 0.95, 0.95), // ready (>= 150)
        // Rep 1
        (500, 128, 155, 0.85, 0.99),
        (950, 90, 140, 0.85, 0.99), // minValidKnee = 90 <= 105
        (1400, 130, 158, 0.85, 0.99),
        (1750, 162, 168, 0.85, 0.99),
        (1950, 168, 170, 0.85, 0.99), // rep 1 complete
        // Rep 2 (alternated side)
        (2200, 155, 125, 0.99, 0.85),
        (2650, 142, 92, 0.99, 0.85), // minValidKnee = 92 <= 105
        (3100, 158, 130, 0.99, 0.85),
        (3450, 168, 162, 0.99, 0.85),
        (3650, 170, 168, 0.99, 0.85), // rep 2 complete
      ];

      for (final (t, lKnee, rKnee, lVis, rVis) in alternatingLungeCycles) {
        await emitAndDrain(
          source,
          _legPoseEvent(
            timestampMs: t,
            leftKneeAngleDeg: lKnee,
            rightKneeAngleDeg: rKnee,
            leftVis: lVis,
            rightVis: rVis,
          ),
        );
      }

      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.validReps, 2);
      expect(controller.state.replayRepEvents[0].minElbowAngleDeg, closeTo(90.0, 0.5));
      expect(controller.state.replayRepEvents[1].minElbowAngleDeg, closeTo(92.0, 0.5));

      // Gap > 500ms aborts
      await emitAndDrain(
        source,
        _legPoseEvent(timestampMs: 3850, leftKneeAngleDeg: 120, rightKneeAngleDeg: 145),
      );
      await emitAndDrain(
        source,
        _legPoseEvent(timestampMs: 4500, leftKneeAngleDeg: 170, rightKneeAngleDeg: 170),
      );
      expect(controller.state.completedReps, 2);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.abortCount, greaterThanOrEqualTo(1));

      controller.dispose();
      source.dispose();
    });
  });

  group('Extended Library Direct Baseline Unit Guards', () {
    test('rejects non-monotonic timestamps and supports reset across all 4 new evaluators', () {
      final hip = HipHingeBaseline.forSlug('romanian-deadlift');
      final tricep = TricepExtensionBaseline();
      final lateral = LateralRaiseBaseline();
      final leg = LegMachineBaseline.forSlug('bulgarian-split-squat');

      hip.processSample(frameIndex: 0, timestampMs: 100, hipAngleDeg: 170, isSampleValid: true);
      final hipDrop = hip.processSample(frameIndex: 1, timestampMs: 100, hipAngleDeg: 170, isSampleValid: true);
      expect(hipDrop.resetReason, 'droppedNonMonotonicTimestamp');
      expect(hip.droppedNonMonotonicFrames, 1);
      hip.reset();
      expect(hip.phase, HipHingePhase.notReady);
      expect(hip.completedReps, 0);

      tricep.processSample(frameIndex: 0, timestampMs: 100, elbowAngleDeg: 85, isSampleValid: true);
      final tricepDrop = tricep.processSample(frameIndex: 1, timestampMs: 90, elbowAngleDeg: 85, isSampleValid: true);
      expect(tricepDrop.resetReason, 'droppedNonMonotonicTimestamp');
      tricep.reset();
      expect(tricep.phase, TricepExtensionPhase.notReady);

      lateral.processSample(frameIndex: 0, timestampMs: 100, shoulderAngleDeg: 25, isSampleValid: true);
      final latDrop = lateral.processSample(frameIndex: 1, timestampMs: 50, shoulderAngleDeg: 25, isSampleValid: true);
      expect(latDrop.resetReason, 'droppedNonMonotonicTimestamp');
      lateral.reset();
      expect(lateral.phase, LateralRaisePhase.notReady);

      leg.processSample(frameIndex: 0, timestampMs: 100, kneeAngleDeg: 170, isSampleValid: true);
      final legDrop = leg.processSample(frameIndex: 1, timestampMs: 100, kneeAngleDeg: 170, isSampleValid: true);
      expect(legDrop.resetReason, 'droppedNonMonotonicTimestamp');
      leg.reset();
      expect(leg.phase, LegMachinePhase.notReady);
    });

    testWidgets('WorkoutCvScreen renders camera angle hints for all 6 extended modules', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final source = MockWorkoutCvNativeSource();

      final samples = <(String, String, String)>[
        ('romanian-deadlift', 'Romanian Deadlift', 'through the hinge'),
        ('barbell-hip-thrust', 'Barbell Hip Thrust', 'bench/floor height'),
        ('triceps-rope-pushdown', 'Triceps Rope Pushdown', 'wrist extension'),
        ('dumbbell-lateral-raise', 'Dumbbell Lateral Raise', 'both elbows clearly'),
        ('leg-press', 'Leg Press', 'next to the machine'),
        ('lying-leg-curl', 'Lying Leg Curl', 'framing hips, knees, and ankles'),
      ];

      for (final (slug, name, hintSnippet) in samples) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('ext_scope_$slug'),
            overrides: [
              workoutCvNativeSourceProvider.overrideWithValue(source),
            ],
            child: MaterialApp(
              home: WorkoutCvScreen(
                exerciseId: slug,
                exerciseSlug: slug,
                exerciseName: name,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(hintSnippet), findsOneWidget,
            reason: '$slug should display its camera angle hint');
      }

      // Verify extractExtendedLibraryFeatures handles gateNotDetecting safely
      final gated = WorkoutCvMotionFeatures.extractExtendedLibraryFeatures(
        frameIndex: 0,
        timestampMs: 0,
        landmarks: const [],
        imageWidth: _imgW,
        imageHeight: _imgH,
        isGateDetecting: false,
      );
      expect(gated.bestHipAngleDeg.isValid, isFalse);
      expect(gated.minValidKneeAngleDeg.isValid, isFalse);
      expect(gated.hasWristSignal, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

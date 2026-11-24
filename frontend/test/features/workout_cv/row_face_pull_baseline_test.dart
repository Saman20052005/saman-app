import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/face_pull_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/row_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildRowLandmarks({
  required double leftElbowAngleDeg,
  required double rightElbowAngleDeg,
  required double torsoLeanDeg,
  double leftVis = 0.95,
  double rightVis = 0.95,
}) {
  const hipX = 540.0;
  const hipY = 1050.0;
  const torsoLen = 260.0;
  const upperArmLen = 140.0;
  const forearmLen = 140.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);

  (double, double, double, double) solveArm(double elbowDeg) {
    final elX = shX;
    final elY = shY + upperArmLen;
    final elbowRad = elbowDeg * math.pi / 180.0;
    final wrX = elX + forearmLen * math.sin(elbowRad);
    final wrY = elY - forearmLen * math.cos(elbowRad);
    return (elX, elY, wrX, wrY);
  }

  final (lElX, lElY, lWrX, lWrY) = solveArm(leftElbowAngleDeg);
  final (rElX, rElY, rWrX, rWrY) = solveArm(rightElbowAngleDeg);

  final landmarks = List.generate(
    33,
    (i) => PoseLandmark(
      index: i,
      x: 0.5,
      y: 0.5,
      z: 0.0,
      visibility: 0.1,
    ),
  );

  PoseLandmark px(int index, double xPx, double yPx, double vis) {
    return PoseLandmark(
      index: index,
      x: (xPx / _imgW).clamp(0.0, 1.0),
      y: (yPx / _imgH).clamp(0.0, 1.0),
      z: 0.0,
      visibility: vis,
    );
  }

  landmarks[PoseLandmark.leftShoulder] =
      px(PoseLandmark.leftShoulder, shX - 40, shY, leftVis);
  landmarks[PoseLandmark.leftElbow] =
      px(PoseLandmark.leftElbow, lElX - 40, lElY, leftVis);
  landmarks[PoseLandmark.leftWrist] =
      px(PoseLandmark.leftWrist, lWrX - 40, lWrY, leftVis);
  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, hipX - 40, hipY, leftVis);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, shX + 40, shY, rightVis);
  landmarks[PoseLandmark.rightElbow] =
      px(PoseLandmark.rightElbow, rElX + 40, rElY, rightVis);
  landmarks[PoseLandmark.rightWrist] =
      px(PoseLandmark.rightWrist, rWrX + 40, rWrY, rightVis);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, hipX + 40, hipY, rightVis);

  return landmarks;
}

List<PoseLandmark> _buildFacePullLandmarks({
  required double elbowAngleDeg,
  required bool elbowAtShoulderHeight,
  double visibility = 0.95,
}) {
  const shX = 540.0;
  const shY = 580.0;
  const upperArmLen = 150.0;
  const forearmLen = 140.0;

  // Upper arm horizontal (0 deg drop) vs dropped steeply downward (80 deg drop)
  final dropRad = (elbowAtShoulderHeight ? 0.0 : 80.0) * math.pi / 180.0;
  final elDirX = -math.cos(dropRad);
  final elDirY = math.sin(dropRad);
  final elX = shX + upperArmLen * elDirX;
  final elY = shY + upperArmLen * elDirY;

  final backX = -elDirX;
  final backY = -elDirY;
  final elbowRad = elbowAngleDeg * math.pi / 180.0;
  // Bend forearm upward (-y) from elbow toward face
  final wrDirX = backX * math.cos(elbowRad) + backY * math.sin(elbowRad);
  final wrDirY = backY * math.cos(elbowRad) - backX * math.sin(elbowRad);
  final wrX = elX + forearmLen * wrDirX;
  final wrY = elY + forearmLen * wrDirY;

  final landmarks = List.generate(
    33,
    (i) => PoseLandmark(
      index: i,
      x: 0.5,
      y: 0.5,
      z: 0.0,
      visibility: 0.1,
    ),
  );

  PoseLandmark px(int index, double xPx, double yPx, double vis) {
    return PoseLandmark(
      index: index,
      x: (xPx / _imgW).clamp(0.0, 1.0),
      y: (yPx / _imgH).clamp(0.0, 1.0),
      z: 0.0,
      visibility: vis,
    );
  }

  landmarks[PoseLandmark.leftShoulder] =
      px(PoseLandmark.leftShoulder, shX, shY, visibility);
  landmarks[PoseLandmark.leftElbow] =
      px(PoseLandmark.leftElbow, elX, elY, visibility);
  landmarks[PoseLandmark.leftWrist] =
      px(PoseLandmark.leftWrist, wrX, wrY, visibility);
  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, shX, shY + 300, visibility);

  return landmarks;
}

Map<String, dynamic> _wrapDetecting(
    int timestampMs, List<PoseLandmark> landmarks) {
  return {
    'status': 'detecting',
    'timestamp': timestampMs,
    'latencyMs': 12,
    'numPoses': 1,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
    'landmarks': landmarks
        .map((l) => {
              'index': l.index,
              'x': l.x,
              'y': l.y,
              'z': l.z,
              'visibility': l.visibility,
            })
        .toList(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Registry Resolution (6 New Slugs + Deferred Bench Press)', () {
    test('resolves all 6 new slugs and keeps supine bench press / flyes unsupported', () {
      const expectedNew = <String, CvExerciseModule>{
        'plank': CvExerciseModule.plankHold,
        'side-plank': CvExerciseModule.plankHold,
        'bent-over-barbell-row': CvExerciseModule.row,
        'seated-cable-row': CvExerciseModule.row,
        'one-arm-dumbbell-row': CvExerciseModule.row,
        'face-pulls': CvExerciseModule.facePull,
      };

      for (final entry in expectedNew.entries) {
        expect(
          WorkoutCvExerciseRegistry.resolveModule(
            id: entry.key,
            slug: entry.key,
          ),
          entry.value,
        );
        expect(
          WorkoutCvExerciseRegistry.isSupported(
            id: entry.key,
            slug: entry.key,
          ),
          isTrue,
        );
      }

      const deferredBenchAndFlyes = [
        'db-bench-press',
        'dumbbell-bench-press',
        'barbell-bench-press',
        'incline-dumbbell-flyes',
        'chest-fly',
      ];
      for (final slug in deferredBenchAndFlyes) {
        expect(
          WorkoutCvExerciseRegistry.resolveModule(id: slug, slug: slug),
          isNull,
          reason: '$slug must remain Deferred',
        );
        expect(
          WorkoutCvExerciseRegistry.isSupported(id: slug, slug: slug),
          isFalse,
          reason: '$slug must remain unsupported',
        );
      }

      final plankCriteria =
          ExerciseFormCriteria.forModule(CvExerciseModule.plankHold);
      expect(plankCriteria.maxValidAngleDeg, 165.0);
      expect(plankCriteria.isMinAngleCriteria, isTrue);
      expect(plankCriteria.criteriaDisplayText, 'Trục thân ≥ 165°');

      final rowCriteria = ExerciseFormCriteria.forModule(CvExerciseModule.row);
      expect(rowCriteria.maxValidAngleDeg, 80.0);
      expect(rowCriteria.criteriaDisplayText, 'Góc ≤ 80°');

      final facePullCriteria =
          ExerciseFormCriteria.forModule(CvExerciseModule.facePull);
      expect(facePullCriteria.maxValidAngleDeg, 85.0);
      expect(facePullCriteria.criteriaDisplayText, 'Góc ≤ 85°');
    });
  });

  group('RowBaseline & FacePullBaseline Unit + Controller Integration', () {
    Future<void> emitAndDrain(
      MockWorkoutCvNativeSource source,
      Map<String, dynamic> event,
    ) async {
      source.emitEvent(event);
      await Future<void>.delayed(Duration.zero);
    }

    test('Row grades standard rep as validReps == 1 and back-swing > 25 deg as invalid (validReps stays 1)', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'bent-over-barbell-row',
        exerciseSlug: 'bent-over-barbell-row',
      );

      // Rep 1: stable bent-over back (torsoLean ~ 60 deg), elbow 155 -> 70 -> 155, duration 1500ms
      const cleanRow = <(int, double, double)>[
        (0, 155, 60),
        (150, 155, 60),
        (250, 155, 60), // ready
        (500, 118, 60), // pulling (< 130)
        (1000, 70, 62), // flexed (<= 75)
        (1500, 110, 60), // returning (> 95)
        (1850, 150, 60), // >= 145
        (2050, 155, 60), // rep 1 (duration 1550ms)
      ];

      for (final (t, elbow, lean) in cleanRow) {
        await emitAndDrain(
          source,
          _wrapDetecting(
            t,
            _buildRowLandmarks(
              leftElbowAngleDeg: elbow,
              rightElbowAngleDeg: elbow,
              torsoLeanDeg: lean,
            ),
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      final rep1 = controller.state.replayRepEvents.first as RowRepEvent;
      expect(rep1.isBackStable, isTrue);

      // Rep 2: excessive back jerk (60 -> 20 deg = 40 deg swing > 25 deg)
      const jerkyRow = <(int, double, double)>[
        (2400, 118, 60), // pulling starts at 60 deg
        (2900, 70, 20),  // jerked upright by 40 deg!
        (3400, 110, 48),
        (3750, 150, 58),
        (3950, 155, 60), // rep 2 (duration 1550ms)
      ];

      for (final (t, elbow, lean) in jerkyRow) {
        await emitAndDrain(
          source,
          _wrapDetecting(
            t,
            _buildRowLandmarks(
              leftElbowAngleDeg: elbow,
              rightElbowAngleDeg: elbow,
              torsoLeanDeg: lean,
            ),
          ),
        );
      }

      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.totalReps, 2);
      expect(controller.state.formSummary.validReps, 1);
      final rep2 = controller.state.replayRepEvents[1] as RowRepEvent;
      expect(rep2.isBackStable, isFalse);

      controller.dispose();
      source.dispose();
    });

    test('One-Arm Dumbbell Row keeps side-lock on pulling arm even when support arm has higher visibility', () {
      final baseline = RowBaseline.forSlug('one-arm-dumbbell-row');
      const oneArmCycle = <(int, double, double)>[
        (0, 160, 165),
        (250, 160, 165), // ready
        (500, 118, 165), // left pulls while right supports
        (1000, 70, 165), // left flexed <= 75
        (1500, 110, 165),
        (1850, 152, 165),
        (2050, 158, 165),
      ];

      for (final (t, lElbow, rElbow) in oneArmCycle) {
        final features = WorkoutCvMotionFeatures.extractRowFeatures(
          frameIndex: t,
          timestampMs: t,
          landmarks: _buildRowLandmarks(
            leftElbowAngleDeg: lElbow,
            rightElbowAngleDeg: rElbow,
            torsoLeanDeg: 55.0,
            leftVis: 0.85,
            rightVis: 0.99,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        baseline.processRowFeatures(features);
      }

      expect(baseline.completedReps, 1);
      final rep = baseline.repHistory.single as RowRepEvent;
      expect(rep.activeSide, 'left');
      expect(rep.minElbowAngleDeg, closeTo(70.0, 0.5));
      expect(rep.isBackStable, isTrue);
    });

    test('Face Pull grades elbows at shoulder height as validReps == 1 and dropped elbows as invalid', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'face-pulls',
        exerciseSlug: 'face-pulls',
      );

      // Rep 1: elbows high at shoulder height, elbow 155 -> 78 -> 155, duration 1550ms
      const cleanFacePull = <(int, double, bool)>[
        (0, 155, true),
        (150, 155, true),
        (250, 155, true),
        (500, 118, true),
        (1000, 78, true), // <= 85
        (1500, 115, true),
        (1850, 152, true),
        (2050, 155, true),
      ];

      for (final (t, elbow, high) in cleanFacePull) {
        await emitAndDrain(
          source,
          _wrapDetecting(
            t,
            _buildFacePullLandmarks(
              elbowAngleDeg: elbow,
              elbowAtShoulderHeight: high,
            ),
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      final rep1 = controller.state.replayRepEvents.first as FacePullRepEvent;
      expect(rep1.isElbowHigh, isTrue);

      // Rep 2: elbows dropped low during pull/peak -> isElbowHigh == false, validReps stays 1
      const lowElbowFacePull = <(int, double, bool)>[
        (2400, 118, false),
        (2900, 78, false),
        (3400, 115, false),
        (3750, 152, true),
        (3950, 155, true),
      ];

      for (final (t, elbow, high) in lowElbowFacePull) {
        await emitAndDrain(
          source,
          _wrapDetecting(
            t,
            _buildFacePullLandmarks(
              elbowAngleDeg: elbow,
              elbowAtShoulderHeight: high,
            ),
          ),
        );
      }

      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.totalReps, 2);
      expect(controller.state.formSummary.validReps, 1);
      final rep2 = controller.state.replayRepEvents[1] as FacePullRepEvent;
      expect(rep2.isElbowHigh, isFalse);

      // Direct FacePullBaseline non-monotonic + reset check
      final direct = FacePullBaseline();
      direct.processSample(
        frameIndex: 0,
        timestampMs: 100,
        elbowAngleDeg: 155,
        isSampleValid: true,
      );
      final dropped = direct.processSample(
        frameIndex: 1,
        timestampMs: 100,
        elbowAngleDeg: 155,
        isSampleValid: true,
      );
      expect(dropped.resetReason, 'droppedNonMonotonicTimestamp');
      direct.reset();
      expect(direct.phase, FacePullPhase.notReady);

      controller.dispose();
      source.dispose();
    });
  });
}

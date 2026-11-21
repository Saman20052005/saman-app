import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/bicep_curl_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/overhead_press_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/push_up_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/squat_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<Map<String, dynamic>> _baseLandmarkMaps({double visibility = 0.95}) {
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

/// Builds a pose event with an exact 2D angle at [vertexIdx] in pixel space.
/// [p1Idx] is placed directly above [vertexIdx] (or below if [p1OffsetY] > 0),
/// and [p2Idx] is rotated by [angleDeg] from the segment (vertex -> p1).
Map<String, dynamic> _armSidePoseEvent({
  required int timestampMs,
  required double elbowAngleDeg,
  bool useRightSideOnly = true,
  bool wristAboveShoulder = false,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: useRightSideOnly ? 0.1 : 0.92);
  final shoulderIdx =
      useRightSideOnly ? PoseLandmark.rightShoulder : PoseLandmark.leftShoulder;
  final elbowIdx =
      useRightSideOnly ? PoseLandmark.rightElbow : PoseLandmark.leftElbow;
  final wristIdx =
      useRightSideOnly ? PoseLandmark.rightWrist : PoseLandmark.leftWrist;

  // Center elbow at (540, 960) px -> (0.5, 0.5)
  const ex = 540.0;
  const ey = 960.0;
  const seg = 180.0;
  final rad = elbowAngleDeg * math.pi / 180.0;

  if (wristAboveShoulder) {
    // Shoulder below elbow? No: for overhead press, shoulder at (540, 1080),
    // elbow moves around shoulder/above, and wrist goes above shoulder as angle opens.
    // Place elbow at (540, 960), shoulder below-left or straight down?
    // Wait: if shoulder is at (540, 960 + seg*cos(rad/2)) etc., simpler:
    // Upper arm goes downward-outward from elbow? Let's place:
    // Shoulder = (540, 1140) -> vector elbow->shoulder = (0, +180) (downward).
    // Wrist = rotated by angleDeg from downward vector:
    //   at angle=80 deg: wrist is slightly above elbow / near shoulder level.
    //   at angle=165 deg: vector elbow->wrist points almost straight UP (y < shoulder.y)!
    landmarks[shoulderIdx] = {
      'index': shoulderIdx,
      'x': ex / _imgW,
      'y': (ey + seg) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[elbowIdx] = {
      'index': elbowIdx,
      'x': ex / _imgW,
      'y': ey / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[wristIdx] = {
      'index': wristIdx,
      'x': (ex + seg * math.sin(rad)) / _imgW,
      'y': (ey + seg * math.cos(rad)) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
  } else {
    // Standard arm pose: Shoulder directly above elbow: (540, 780) -> vec = (0, -180)
    // Wrist rotated by angleDeg from upward vector:
    //   at 180 deg -> straight down (540, 1140)
    //   at 45 deg -> curled upward (above/near shoulder)
    landmarks[shoulderIdx] = {
      'index': shoulderIdx,
      'x': ex / _imgW,
      'y': (ey - seg) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[elbowIdx] = {
      'index': elbowIdx,
      'x': ex / _imgW,
      'y': ey / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[wristIdx] = {
      'index': wristIdx,
      'x': (ex + seg * math.sin(rad)) / _imgW,
      'y': (ey - seg * math.cos(rad)) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
  }

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

Map<String, dynamic> _pullUpPoseEvent({
  required int timestampMs,
  required double elbowAngleDeg,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.95);
  const ex = 540.0;
  const ey = 960.0;
  const seg = 180.0;
  final rad = elbowAngleDeg * math.pi / 180.0;

  landmarks[PoseLandmark.leftShoulder] = {
    'index': PoseLandmark.leftShoulder,
    'x': ex / _imgW,
    'y': (ey - seg) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.rightShoulder] = {
    'index': PoseLandmark.rightShoulder,
    'x': (ex + 160.0) / _imgW,
    'y': (ey - seg) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.leftElbow] = {
    'index': PoseLandmark.leftElbow,
    'x': ex / _imgW,
    'y': ey / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.leftWrist] = {
    'index': PoseLandmark.leftWrist,
    'x': (ex + seg * math.sin(rad)) / _imgW,
    'y': (ey - seg * math.cos(rad)) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };

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

Map<String, dynamic> _squatSidePoseEvent({
  required int timestampMs,
  required double kneeAngleDeg,
  int gen = 5,
}) {
  // Side view: only right leg (24-26-28) has high visibility; upper body occluded.
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const kx = 540.0;
  const ky = 1100.0;
  const seg = 220.0;
  final rad = kneeAngleDeg * math.pi / 180.0;

  landmarks[PoseLandmark.rightHip] = {
    'index': PoseLandmark.rightHip,
    'x': kx / _imgW,
    'y': (ky - seg) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.rightKnee] = {
    'index': PoseLandmark.rightKnee,
    'x': kx / _imgW,
    'y': ky / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.rightAnkle] = {
    'index': PoseLandmark.rightAnkle,
    'x': (kx + seg * math.sin(rad)) / _imgW,
    'y': (ky - seg * math.cos(rad)) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };

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

Exercise _exercise({
  required String id,
  required String slug,
  required String name,
}) {
  return Exercise(
    id: id,
    slug: slug,
    name: name,
    nameVi: name,
    muscleGroup: 'Full Body',
    targetMuscles: const ['Primary'],
    secondaryMuscles: const [],
    equipment: const ['Bodyweight'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-12',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: const [],
    commonMistakes: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutCvExerciseRegistry', () {
    test('maps all supported exercise slugs and rejects unsupported ones', () {
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'lat-pulldown', slug: 'lat-pulldown'),
        CvExerciseModule.latPulldown,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'pull-up', slug: 'pull-up'),
        CvExerciseModule.pullUp,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'barbell-back-squat', slug: 'barbell-back-squat'),
        CvExerciseModule.squat,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'goblet-squat', slug: 'goblet-squat'),
        CvExerciseModule.squat,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'push-up', slug: 'push-up'),
        CvExerciseModule.pushUp,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'barbell-overhead-press', slug: 'barbell-overhead-press'),
        CvExerciseModule.overheadPress,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'db-shoulder-press', slug: 'dumbbell-shoulder-press'),
        CvExerciseModule.overheadPress,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'db-bicep-curl', slug: 'dumbbell-bicep-curl'),
        CvExerciseModule.bicepCurl,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'ez-bar-curl', slug: 'ez-bar-curl'),
        CvExerciseModule.bicepCurl,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'hammer-curl', slug: 'hammer-curl'),
        CvExerciseModule.bicepCurl,
      );

      expect(
        WorkoutCvExerciseRegistry.isSupported(
            id: 'db-bench-press', slug: 'dumbbell-bench-press'),
        isFalse,
      );
      expect(
        WorkoutCvExerciseRegistry.isSupported(
            id: 'seated-cable-row', slug: 'seated-cable-row'),
        isFalse,
      );
    });
  });

  group('WorkoutCvMotionFeatures.extractMultiExerciseAngles', () {
    test('selects higher-visibility side and computes wristAboveShoulder in pixel space', () {
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

      // Left arm: valid 180 deg, lower visibility (0.55)
      landmarks[PoseLandmark.leftShoulder] = const PoseLandmark(
          index: PoseLandmark.leftShoulder, x: 0.3, y: 0.3, z: 0, visibility: 0.55);
      landmarks[PoseLandmark.leftElbow] = const PoseLandmark(
          index: PoseLandmark.leftElbow, x: 0.3, y: 0.5, z: 0, visibility: 0.55);
      landmarks[PoseLandmark.leftWrist] = const PoseLandmark(
          index: PoseLandmark.leftWrist, x: 0.3, y: 0.7, z: 0, visibility: 0.55);

      // Right arm: exact 90 deg in 1080x1920 pixel space, higher visibility (0.95)
      // Elbow at (540, 960), shoulder at (540, 576) -> y = 0.3,
      // wrist at (924, 960) -> x = 924/1080, y = 0.5
      landmarks[PoseLandmark.rightShoulder] = const PoseLandmark(
          index: PoseLandmark.rightShoulder, x: 0.5, y: 0.3, z: 0, visibility: 0.95);
      landmarks[PoseLandmark.rightElbow] = const PoseLandmark(
          index: PoseLandmark.rightElbow, x: 0.5, y: 0.5, z: 0, visibility: 0.95);
      landmarks[PoseLandmark.rightWrist] = const PoseLandmark(
          index: PoseLandmark.rightWrist, x: 924.0 / 1080.0, y: 0.5, z: 0, visibility: 0.95);

      // Right knee: 180 deg
      landmarks[PoseLandmark.rightHip] = const PoseLandmark(
          index: PoseLandmark.rightHip, x: 0.5, y: 0.5, z: 0, visibility: 0.9);
      landmarks[PoseLandmark.rightKnee] = const PoseLandmark(
          index: PoseLandmark.rightKnee, x: 0.5, y: 0.7, z: 0, visibility: 0.9);
      landmarks[PoseLandmark.rightAnkle] = const PoseLandmark(
          index: PoseLandmark.rightAnkle, x: 0.5, y: 0.9, z: 0, visibility: 0.9);

      final features = WorkoutCvMotionFeatures.extractMultiExerciseAngles(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(features.bestElbowAngleDeg.isValid, isTrue);
      expect(features.bestElbowAngleDeg.value, closeTo(90.0, 1e-4));
      expect(features.bestKneeAngleDeg.isValid, isTrue);
      expect(features.bestKneeAngleDeg.value, closeTo(180.0, 1e-4));
      expect(features.isWristAboveShoulder, isFalse);

      // Move right wrist above right shoulder (y = 0.2 < 0.3)
      landmarks[PoseLandmark.rightWrist] = const PoseLandmark(
          index: PoseLandmark.rightWrist, x: 0.5, y: 0.2, z: 0, visibility: 0.95);
      final overheadFeatures = WorkoutCvMotionFeatures.extractMultiExerciseAngles(
        frameIndex: 1,
        timestampMs: 200,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );
      expect(overheadFeatures.isWristAboveShoulder, isTrue);

      // Gate not detecting never fabricates 0.0
      final gatedFeatures = WorkoutCvMotionFeatures.extractMultiExerciseAngles(
        frameIndex: 2,
        timestampMs: 300,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
        isGateDetecting: false,
      );
      expect(gatedFeatures.bestElbowAngleDeg.isValid, isFalse);
      expect(gatedFeatures.bestElbowAngleDeg.value, isNull);
      expect(gatedFeatures.bestKneeAngleDeg.isValid, isFalse);
      expect(gatedFeatures.bestKneeAngleDeg.value, isNull);
      expect(gatedFeatures.isWristAboveShoulder, isFalse);
    });
  });

  group('Multi-Exercise Ground-Truth Kinematic & Gap Loss Tests', () {
    Future<void> emitAndDrain(
      MockWorkoutCvNativeSource source,
      Map<String, dynamic> event,
    ) async {
      source.emitEvent(event);
      await Future<void>.delayed(Duration.zero);
    }

    test('Pull-up full cycle, gap loss > 500ms abort, and summary compatibility', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      const pullUpCycle = <(int, double)>[
        (0, 165),
        (150, 165),
        (250, 165),
        (400, 90),
        (700, 50),
        (900, 52),
        (1100, 85),
        (1350, 165),
        (1550, 165),
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in pullUpCycle) {
        await emitAndDrain(source, _pullUpPoseEvent(timestampMs: t, elbowAngleDeg: angle));
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số lần kéo: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(50.0, 0.5));
      expect(CvFormSummaryCalculator.compute(reps: controller.state.replayRepEvents).totalReps, 1);

      // Start second rep, then inject >500ms gap
      await emitAndDrain(source, _pullUpPoseEvent(timestampMs: 1700, elbowAngleDeg: 90));
      await emitAndDrain(source, _pullUpPoseEvent(timestampMs: 1850, elbowAngleDeg: 50));
      await emitAndDrain(source, _pullUpPoseEvent(timestampMs: 2500, elbowAngleDeg: 165)); // 650ms gap
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Squat (side-view leg only) full cycle, label, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-back-squat',
        exerciseSlug: 'barbell-back-squat',
      );

      const squatCycle = <(int, double)>[
        (0, 170),
        (150, 170),
        (250, 170), // standing hold satisfied
        (400, 130), // descending
        (700, 85),  // bottom (<= 95)
        (950, 120), // ascending (> 110)
        (1250, 165), // return to standing (>= 155)
        (1450, 168), // extended hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, knee) in squatCycle) {
        await emitAndDrain(source, _squatSidePoseEvent(timestampMs: t, kneeAngleDeg: knee));
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(85.0, 0.5));
      expect(controller.state.replayRepEvents.single.durationMs, 1050);

      // Gap loss > 500ms during descent aborts incomplete cycle
      await emitAndDrain(source, _squatSidePoseEvent(timestampMs: 1600, kneeAngleDeg: 130));
      await emitAndDrain(source, _squatSidePoseEvent(timestampMs: 1750, kneeAngleDeg: 88));
      await emitAndDrain(source, _squatSidePoseEvent(timestampMs: 2400, kneeAngleDeg: 170)); // 650ms gap
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.abortCount, greaterThanOrEqualTo(1));

      // Direct SquatBaseline unit test sanity
      final direct = SquatBaseline();
      for (final (t, knee) in squatCycle) {
        direct.processSample(frameIndex: t, timestampMs: t, kneeAngleDeg: knee, isSampleValid: true);
      }
      expect(direct.completedReps, 1);

      controller.dispose();
      source.dispose();
    });

    test('Push-up (side-view arm only) full cycle, label, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(exerciseId: 'push-up', exerciseSlug: 'push-up');

      const pushUpCycle = <(int, double)>[
        (0, 165),
        (150, 165),
        (250, 165), // extended
        (400, 125), // lowering (< 135)
        (700, 85),  // bottom (<= 95)
        (950, 120), // pushing (> 110)
        (1250, 160), // >= 150
        (1450, 162), // rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in pushUpCycle) {
        await emitAndDrain(source, _armSidePoseEvent(timestampMs: t, elbowAngleDeg: angle));
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(85.0, 0.5));

      // Gap loss > 500ms aborts mid-rep
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 1600, elbowAngleDeg: 120));
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 2250, elbowAngleDeg: 160));
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      final direct = PushUpBaseline();
      for (final (t, angle) in pushUpCycle) {
        direct.processSample(frameIndex: t, timestampMs: t, elbowAngleDeg: angle, isSampleValid: true);
      }
      expect(direct.completedReps, 1);

      controller.dispose();
      source.dispose();
    });

    test('Overhead Press enforces wristAboveShoulder, completes cycle, and aborts on >500ms gap', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-overhead-press',
        exerciseSlug: 'barbell-overhead-press',
      );

      // Verify OverheadPressBaseline rejects >=150 deg when wrist is NOT above shoulder
      final ohp = OverheadPressBaseline();
      ohp.processSample(frameIndex: 0, timestampMs: 0, elbowAngleDeg: 85, isWristAboveShoulder: false, isSampleValid: true);
      ohp.processSample(frameIndex: 1, timestampMs: 250, elbowAngleDeg: 85, isWristAboveShoulder: false, isSampleValid: true);
      ohp.processSample(frameIndex: 2, timestampMs: 400, elbowAngleDeg: 120, isWristAboveShoulder: false, isSampleValid: true);
      final noOverhead = ohp.processSample(frameIndex: 3, timestampMs: 700, elbowAngleDeg: 165, isWristAboveShoulder: false, isSampleValid: true);
      expect(noOverhead.phase, OverheadPressPhase.pressing); // Must NOT reach lockout!

      // Full valid OHP cycle through controller
      const ohpCycle = <(int, double)>[
        (0, 80),
        (150, 80),
        (250, 80),   // ready (<= 95)
        (450, 125),  // pressing (> 110)
        (750, 165),  // lockout (>= 150 & wrist above shoulder)
        (1000, 125), // lowering (< 135)
        (1250, 85),  // rack (<= 95)
        (1450, 82),  // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in ohpCycle) {
        await emitAndDrain(
          source,
          _armSidePoseEvent(
            timestampMs: t,
            elbowAngleDeg: angle,
            wristAboveShoulder: true,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.durationMs, 1000);

      // Gap loss > 500ms aborts mid-rep
      await emitAndDrain(
        source,
        _armSidePoseEvent(timestampMs: 1600, elbowAngleDeg: 125, wristAboveShoulder: true),
      );
      await emitAndDrain(
        source,
        _armSidePoseEvent(timestampMs: 2250, elbowAngleDeg: 85, wristAboveShoulder: true),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Bicep Curl full cycle, label, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'db-bicep-curl',
        exerciseSlug: 'dumbbell-bicep-curl',
      );

      const curlCycle = <(int, double)>[
        (0, 160),
        (150, 160),
        (250, 160), // extended (>= 145)
        (450, 115), // curling (< 130)
        (750, 50),  // flexed (<= 60)
        (1000, 95), // lowering (> 80)
        (1250, 155), // >= 145
        (1450, 160), // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in curlCycle) {
        await emitAndDrain(source, _armSidePoseEvent(timestampMs: t, elbowAngleDeg: angle));
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(50.0, 0.5));

      // Gap loss > 500ms aborts mid-rep
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 1600, elbowAngleDeg: 110));
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 2250, elbowAngleDeg: 160));
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      final direct = BicepCurlBaseline();
      for (final (t, angle) in curlCycle) {
        direct.processSample(frameIndex: t, timestampMs: t, elbowAngleDeg: angle, isSampleValid: true);
      }
      expect(direct.completedReps, 1);

      controller.dispose();
      source.dispose();
    });
  });

  group('ActiveWorkoutScreen & WorkoutCvScreen Multi-Exercise Integration', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'ActiveWorkoutScreen opens WorkoutCvScreen for Squat, Push-up, OHP, Bicep Curl, and keeps Dumbbell Bench Press Deferred',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final source = MockWorkoutCvNativeSource();

        final supportedExercises = [
          _exercise(
              id: 'barbell-back-squat',
              slug: 'barbell-back-squat',
              name: 'Barbell Back Squat'),
          _exercise(id: 'push-up', slug: 'push-up', name: 'Push-up'),
          _exercise(
              id: 'barbell-overhead-press',
              slug: 'barbell-overhead-press',
              name: 'Overhead Press'),
          _exercise(
              id: 'db-bicep-curl',
              slug: 'dumbbell-bicep-curl',
              name: 'Dumbbell Bicep Curl'),
        ];

        for (final ex in supportedExercises) {
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('scope_${ex.slug}'),
              overrides: [
                workoutCvNativeSourceProvider.overrideWithValue(source),
              ],
              child: MaterialApp(
                home: ActiveWorkoutScreen(
                  exercises: [ex],
                  autoTick: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
              find.byKey(const ValueKey('active_workout_form_check_badge')));
          await tester.pumpAndSettle();

          // Source sheet opens for supported Android exercise; choose real-time camera
          await tester
              .tap(find.byKey(const ValueKey('form_check_mode_realtime')));
          await tester.pumpAndSettle();

          expect(find.byType(WorkoutCvScreen), findsOneWidget,
              reason: '${ex.slug} should open WorkoutCvScreen');
          expect(find.text(ex.name), findsOneWidget);
          expect(find.byKey(const ValueKey('workout_cv_replay_rep_count')),
              findsOneWidget);
          expect(find.text('Số rep: 0'), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
          await tester.pumpAndSettle();
          expect(find.byType(WorkoutCvScreen), findsNothing);
        }

        // Unsupported exercise (Dumbbell Bench Press) must show Deferred modal directly
        final benchPress = _exercise(
          id: 'db-bench-press',
          slug: 'dumbbell-bench-press',
          name: 'Dumbbell Bench Press',
        );
        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey('scope_bench_press'),
            overrides: [
              workoutCvNativeSourceProvider.overrideWithValue(source),
            ],
            child: MaterialApp(
              home: ActiveWorkoutScreen(
                exercises: [benchPress],
                autoTick: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
            find.byKey(const ValueKey('active_workout_form_check_badge')));
        await tester.pumpAndSettle();

        expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
        expect(find.byType(WorkoutCvScreen), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        source.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });
}

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/push_up_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildPushUpLandmarks({
  required double elbowAngleDeg,
  required double torsoLeanDeg,
  required double bodyAlignmentDeg,
  double leftArmVisibility = 0.95,
  double rightArmVisibility = 0.95,
  double leftBodyVisibility = 0.95,
  double rightBodyVisibility = 0.95,
}) {
  const hipX = 540.0;
  const hipY = 960.0;
  const torsoLen = 220.0;
  const legLen = 240.0;
  const armSeg = 120.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final alignRad = bodyAlignmentDeg * math.pi / 180.0;
  final elbowRad = elbowAngleDeg * math.pi / 180.0;

  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);

  final legAzimuth = leanRad + alignRad;
  final ankX = hipX + legLen * math.sin(legAzimuth);
  final ankY = hipY - legLen * math.cos(legAzimuth);

  final elX = shX;
  final elY = shY + armSeg;
  final wrX = elX + armSeg * math.sin(elbowRad);
  final wrY = elY - armSeg * math.cos(elbowRad);

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
      px(PoseLandmark.leftShoulder, shX, shY, leftArmVisibility);
  landmarks[PoseLandmark.leftElbow] =
      px(PoseLandmark.leftElbow, elX, elY, leftArmVisibility);
  landmarks[PoseLandmark.leftWrist] =
      px(PoseLandmark.leftWrist, wrX, wrY, leftArmVisibility);
  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, hipX, hipY, leftBodyVisibility);
  landmarks[PoseLandmark.leftAnkle] =
      px(PoseLandmark.leftAnkle, ankX, ankY, leftBodyVisibility);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, shX, shY, rightArmVisibility);
  landmarks[PoseLandmark.rightElbow] =
      px(PoseLandmark.rightElbow, elX, elY, rightArmVisibility);
  landmarks[PoseLandmark.rightWrist] =
      px(PoseLandmark.rightWrist, wrX, wrY, rightArmVisibility);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, hipX, hipY, rightBodyVisibility);
  landmarks[PoseLandmark.rightAnkle] =
      px(PoseLandmark.rightAnkle, ankX, ankY, rightBodyVisibility);

  return landmarks;
}

Map<String, dynamic> _landmarksToDetectingEvent({
  required int timestampMs,
  required List<PoseLandmark> landmarks,
}) {
  return {
    'status': 'detecting',
    'sessionGen': 1,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks
        .map((lm) => {
              'index': lm.index,
              'x': lm.x,
              'y': lm.y,
              'z': lm.z,
              'visibility': lm.visibility,
            })
        .toList(),
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

void main() {
  group('WorkoutCvMotionFeatures.extractPushUpFeatures & PushUpBaseline', () {
    test(
        '1. Standard Push-up cycle (torsoLean=82, bodyAlignment=174, elbow=85) counts 1 rep with isPlankAligned == true and validReps == 1',
        () {
      final tracker = PushUpBaseline();
      const cycle = <(int, double, double, double)>[
        (0, 168.0, 82.0, 174.0),
        (120, 168.0, 82.0, 174.0),
        (250, 168.0, 82.0, 174.0), // extended hold satisfied
        (500, 128.0, 82.0, 174.0), // lowering (< 135)
        (850, 102.0, 82.0, 174.0),
        (1150, 85.0, 82.0, 174.0), // bottom (<= 100)
        (1450, 122.0, 82.0, 174.0), // pushing (> 115)
        (1750, 162.0, 82.0, 174.0),
        (1950, 168.0, 82.0, 174.0), // duration = 1450ms (within 1.2-4s)
      ];

      final phases = <PushUpPhase>{};
      for (var i = 0; i < cycle.length; i++) {
        final (t, elbow, lean, alignment) = cycle[i];
        final features = WorkoutCvMotionFeatures.extractPushUpFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildPushUpLandmarks(
            elbowAngleDeg: elbow,
            torsoLeanDeg: lean,
            bodyAlignmentDeg: alignment,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.bestElbowAngleDeg.value, closeTo(elbow, 0.5));
        expect(features.torsoLeanDeg.value, closeTo(lean, 0.5));
        expect(features.bodyAlignmentDeg.value, closeTo(alignment, 0.5));
        final res = tracker.processPushUpFeatures(features);
        phases.add(res.phase);
      }

      expect(phases, containsAll(PushUpPhase.values));
      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.minElbowAngleDeg, closeTo(85.0, 0.5));
      expect(rep.minBodyAlignmentDeg, closeTo(174.0, 0.5));
      expect(rep.isPlankAligned, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.pushUp,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 1);
    });

    test(
        '2. Bottom visibility drop to 0.38 (< 0.45 but >= 0.35) keeps framing detecting and counts Push-up rep without loss',
        () async {
      final lowVisBottom = WorkoutCvMotionFeatures.extractPushUpFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: _buildPushUpLandmarks(
          elbowAngleDeg: 85.0,
          torsoLeanDeg: 82.0,
          bodyAlignmentDeg: 174.0,
          leftArmVisibility: 0.1,
          rightArmVisibility: 0.38,
          leftBodyVisibility: 0.1,
          rightBodyVisibility: 0.38,
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(lowVisBottom.bestElbowAngleDeg.isValid, isTrue);
      expect(lowVisBottom.bestElbowAngleDeg.value, closeTo(85.0, 0.5));
      expect(lowVisBottom.bestSideKey, 'model_right_12_14_16');

      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'push-up',
        exerciseSlug: 'push-up',
      );

      const cycle = <(int, double, double)>[
        (0, 168.0, 0.90),
        (250, 168.0, 0.90),
        (550, 125.0, 0.70),
        (900, 95.0, 0.38),
        (1150, 85.0, 0.38),
        (1450, 122.0, 0.70),
        (1800, 164.0, 0.90),
        (2000, 168.0, 0.90),
      ];

      for (final (t, elbow, vis) in cycle) {
        final lms = _buildPushUpLandmarks(
          elbowAngleDeg: elbow,
          torsoLeanDeg: 82.0,
          bodyAlignmentDeg: 174.0,
          leftArmVisibility: 0.1,
          rightArmVisibility: vis,
          leftBodyVisibility: 0.1,
          rightBodyVisibility: vis,
        );
        source.emitEvent(_landmarksToDetectingEvent(timestampMs: t, landmarks: lms));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.abortCount, 0);

      controller.dispose();
      source.dispose();
    });

    test(
        '3. Sagging hips / pike (bodyAlignment=142 < 155) counts totalReps == 1 with isPlankAligned == false and validReps == 0',
        () {
      final tracker = PushUpBaseline();
      const cycle = <(int, double, double, double)>[
        (0, 168.0, 80.0, 168.0),
        (250, 168.0, 80.0, 168.0),
        (500, 128.0, 78.0, 152.0),
        (900, 88.0, 76.0, 142.0),
        (1350, 122.0, 78.0, 150.0),
        (1750, 164.0, 80.0, 166.0),
        (1950, 168.0, 80.0, 168.0),
      ];

      for (var i = 0; i < cycle.length; i++) {
        final (t, elbow, lean, alignment) = cycle[i];
        tracker.processPushUpFeatures(
          WorkoutCvMotionFeatures.extractPushUpFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildPushUpLandmarks(
              elbowAngleDeg: elbow,
              torsoLeanDeg: lean,
              bodyAlignmentDeg: alignment,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.minBodyAlignmentDeg, closeTo(142.0, 0.5));
      expect(rep.isPlankAligned, isFalse);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.pushUp,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '4. Standing upright arm bends (torsoLean=12 < 45) never enter extended and produce completedReps == 0',
        () {
      final tracker = PushUpBaseline();
      const standingFrames = <(int, double, double, double)>[
        (0, 170.0, 12.0, 175.0),
        (250, 170.0, 12.0, 175.0),
        (500, 120.0, 12.0, 175.0),
        (900, 82.0, 12.0, 175.0),
        (1300, 122.0, 12.0, 175.0),
        (1700, 170.0, 12.0, 175.0),
        (1950, 170.0, 12.0, 175.0),
      ];

      for (var i = 0; i < standingFrames.length; i++) {
        final (t, elbow, lean, alignment) = standingFrames[i];
        final res = tracker.processPushUpFeatures(
          WorkoutCvMotionFeatures.extractPushUpFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildPushUpLandmarks(
              elbowAngleDeg: elbow,
              torsoLeanDeg: lean,
              bodyAlignmentDeg: alignment,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
        expect(res.phase, PushUpPhase.notReady);
      }

      expect(tracker.completedReps, 0);
    });

    test(
        '5. Higher-visibility arm selection, shallow rep (98 deg <= 100 but > 95 -> validReps == 0), >500ms gap abort, and 50/25/10 FPS invariance',
        () {
      // 5a: Higher-visibility arm selection
      final features = WorkoutCvMotionFeatures.extractPushUpFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: _buildPushUpLandmarks(
          elbowAngleDeg: 88.0,
          torsoLeanDeg: 82.0,
          bodyAlignmentDeg: 172.0,
          leftArmVisibility: 0.42,
          rightArmVisibility: 0.91,
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(features.bestSideKey, 'model_right_12_14_16');
      expect(features.bestElbowAngleDeg.isValid, isTrue);

      // 5b: Shallow rep at 98 deg (counts total rep via bottomEnterDeg=100, fails validReps <= 95)
      final shallowTracker = PushUpBaseline();
      const shallowCycle = <(int, double)>[
        (0, 168.0),
        (250, 168.0),
        (500, 125.0),
        (900, 98.0),
        (1300, 122.0),
        (1750, 165.0),
        (1950, 168.0),
      ];
      for (var i = 0; i < shallowCycle.length; i++) {
        final (t, elbow) = shallowCycle[i];
        shallowTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 82.0,
          bodyAlignmentDeg: 174.0,
          isSampleValid: true,
        );
      }
      expect(shallowTracker.completedReps, 1);
      final shallowSummary = CvFormSummaryCalculator.compute(
        reps: shallowTracker.repHistory,
        module: CvExerciseModule.pushUp,
      );
      expect(shallowSummary.totalReps, 1);
      expect(shallowSummary.validReps, 0);

      // 5c: Gap loss > 500ms aborts mid-rep
      final gapTracker = PushUpBaseline();
      gapTracker.processSample(
        frameIndex: 0,
        timestampMs: 0,
        elbowAngleDeg: 168.0,
        torsoLeanDeg: 82.0,
        bodyAlignmentDeg: 174.0,
        isSampleValid: true,
      );
      gapTracker.processSample(
        frameIndex: 1,
        timestampMs: 250,
        elbowAngleDeg: 168.0,
        torsoLeanDeg: 82.0,
        bodyAlignmentDeg: 174.0,
        isSampleValid: true,
      );
      gapTracker.processSample(
        frameIndex: 2,
        timestampMs: 500,
        elbowAngleDeg: 120.0,
        torsoLeanDeg: 82.0,
        bodyAlignmentDeg: 174.0,
        isSampleValid: true,
      );
      gapTracker.processSample(
        frameIndex: 3,
        timestampMs: 800,
        elbowAngleDeg: 88.0,
        torsoLeanDeg: 82.0,
        bodyAlignmentDeg: 174.0,
        isSampleValid: true,
      );
      expect(gapTracker.phase, PushUpPhase.bottom);
      final afterGap = gapTracker.processSample(
        frameIndex: 4,
        timestampMs: 1450,
        elbowAngleDeg: 168.0,
        torsoLeanDeg: 82.0,
        bodyAlignmentDeg: 174.0,
        isSampleValid: true,
      );
      expect(afterGap.resetReason, 'dataLossGapBeforeValidSample');
      expect(gapTracker.phase, PushUpPhase.notReady);
      expect(gapTracker.completedReps, 0);

      // 5d: Sampling-rate invariance across 50 / 25 / 10 FPS
      double synthElbow(double sec) =>
          128.0 + 44.0 * math.cos(2 * math.pi * sec / 2.6);

      int runSim(int stepMs) {
        final sim = PushUpBaseline();
        var fIdx = 0;
        for (var t = 0; t <= 5800; t += stepMs) {
          sim.processSample(
            frameIndex: fIdx++,
            timestampMs: t,
            elbowAngleDeg: synthElbow(t / 1000.0),
            torsoLeanDeg: 82.0,
            bodyAlignmentDeg: 174.0,
            isSampleValid: true,
          );
        }
        return sim.completedReps;
      }

      expect(runSim(20), 2); // 50 FPS
      expect(runSim(40), 2); // 25 FPS
      expect(runSim(100), 2); // 10 FPS
    });
  });
}

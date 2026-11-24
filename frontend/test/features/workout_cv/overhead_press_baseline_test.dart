import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/overhead_press_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildOhpLandmarks({
  required double elbowAngleDeg,
  required double torsoLeanDeg,
  required bool wristAboveShoulder,
  double leftArmVisibility = 0.95,
  double rightArmVisibility = 0.95,
  double hipVisibility = 0.95,
}) {
  const hipX = 540.0;
  const hipY = 1150.0;
  const torsoLen = 250.0;
  const upperArmLen = 140.0;
  const forearmLen = 140.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final elbowRad = elbowAngleDeg * math.pi / 180.0;

  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);

  final double ux;
  final double uy;
  if (wristAboveShoulder) {
    // Upper arm angled upward/outward so forearm stays above shoulder at all angles.
    ux = 120.0;
    uy = -70.0;
  } else {
    // Upper arm hanging downward so wrist stays below shoulder even when extended.
    ux = 0.0;
    uy = upperArmLen;
  }

  final elX = shX + ux;
  final elY = shY + uy;
  final thetaElToSh = math.atan2(shY - elY, shX - elX);
  final thetaElToWr = thetaElToSh + elbowRad;
  final wrX = elX + forearmLen * math.cos(thetaElToWr);
  final wrY = elY + forearmLen * math.sin(thetaElToWr);

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
      px(PoseLandmark.leftHip, hipX, hipY, hipVisibility);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, shX, shY, rightArmVisibility);
  landmarks[PoseLandmark.rightElbow] =
      px(PoseLandmark.rightElbow, elX, elY, rightArmVisibility);
  landmarks[PoseLandmark.rightWrist] =
      px(PoseLandmark.rightWrist, wrX, wrY, rightArmVisibility);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, hipX, hipY, hipVisibility);

  return landmarks;
}

void main() {
  group('WorkoutCvMotionFeatures.extractOverheadPressFeatures & OverheadPressBaseline', () {
    test(
        '1. Standard OHP cycle (rack 85 -> lockout 165 + wristAboveShoulder + torsoLean=12) counts 1 rep with validReps == 1 and minElbowAngleDeg ~ 165',
        () {
      final tracker = OverheadPressBaseline();
      const cycle = <(int, double, double)>[
        (0, 85.0, 12.0),
        (120, 85.0, 12.0),
        (250, 85.0, 12.0), // ready hold satisfied (<= 100)
        (500, 118.0, 12.0), // pressing (> 112)
        (900, 152.0, 12.0), // lockout (>= 150)
        (1150, 165.0, 12.0), // peak lockout
        (1450, 130.0, 12.0), // lowering (< 135)
        (1850, 88.0, 12.0), // back to rack (<= 100)
        (2050, 85.0, 12.0), // duration = 1550ms (within 1.5-4s)
      ];

      final phases = <OverheadPressPhase>{};
      for (var i = 0; i < cycle.length; i++) {
        final (t, elbow, lean) = cycle[i];
        final features = WorkoutCvMotionFeatures.extractOverheadPressFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildOhpLandmarks(
            elbowAngleDeg: elbow,
            torsoLeanDeg: lean,
            wristAboveShoulder: true,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.bestElbowAngleDeg.value, closeTo(elbow, 0.5));
        expect(features.torsoLeanDeg.value, closeTo(lean, 0.5));
        expect(features.isWristAboveShoulder, isTrue);

        final res = tracker.processOverheadPressFeatures(features);
        phases.add(res.phase);
      }

      expect(phases, containsAll(OverheadPressPhase.values));
      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.minElbowAngleDeg, closeTo(165.0, 0.5));
      expect(rep.peakLockoutAngleDeg, closeTo(165.0, 0.5));
      expect(rep.minRackElbowAngleDeg, closeTo(85.0, 0.5));
      expect(rep.maxTorsoLeanDeg, closeTo(12.0, 0.5));
      expect(rep.isBackVertical, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.overheadPress,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 1);
      expect(summary.avgElbowAngleDeg, closeTo(165.0, 0.5));
    });

    test('2. Blocks lockout transition when !isWristAboveShoulder', () {
      final tracker = OverheadPressBaseline();
      const frames = <(int, double)>[
        (0, 85.0),
        (250, 85.0), // ready
        (500, 120.0), // pressing
        (900, 165.0), // >= 150 but wrist below shoulder -> must stay pressing
        (1300, 125.0),
        (1700, 85.0),
        (1950, 85.0),
      ];

      for (var i = 0; i < frames.length; i++) {
        final (t, elbow) = frames[i];
        final features = WorkoutCvMotionFeatures.extractOverheadPressFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildOhpLandmarks(
            elbowAngleDeg: elbow,
            torsoLeanDeg: 10.0,
            wristAboveShoulder: false,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.isWristAboveShoulder, isFalse);
        final res = tracker.processOverheadPressFeatures(features);
        expect(res.phase, isNot(OverheadPressPhase.lockout));
      }

      expect(tracker.completedReps, 0);
    });

    test(
        '3. Shallow lockout at 151 deg (>= 150 but < 155) counts totalReps == 1 with validReps == 0',
        () {
      final tracker = OverheadPressBaseline();
      const shallowCycle = <(int, double)>[
        (0, 88.0),
        (250, 88.0),
        (500, 120.0),
        (1000, 151.0), // reaches lockout >= 150, fails >= 155 standard
        (1450, 125.0),
        (1850, 88.0),
        (2050, 88.0), // duration = 1550ms
      ];

      for (var i = 0; i < shallowCycle.length; i++) {
        final (t, elbow) = shallowCycle[i];
        tracker.processOverheadPressFeatures(
          WorkoutCvMotionFeatures.extractOverheadPressFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildOhpLandmarks(
              elbowAngleDeg: elbow,
              torsoLeanDeg: 10.0,
              wristAboveShoulder: true,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.single.minElbowAngleDeg, closeTo(151.0, 0.5));
      expect(tracker.repHistory.single.isBackVertical, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.overheadPress,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '4. Excessive back hyperextension (torsoLean = 32 > 25) marks isBackVertical == false and validReps == 0',
        () {
      final tracker = OverheadPressBaseline();
      const archCycle = <(int, double, double)>[
        (0, 85.0, 10.0),
        (250, 85.0, 10.0),
        (500, 120.0, 22.0),
        (950, 165.0, 32.0), // lean > 25 deg
        (1400, 125.0, 20.0),
        (1850, 85.0, 10.0),
        (2050, 85.0, 10.0),
      ];

      for (var i = 0; i < archCycle.length; i++) {
        final (t, elbow, lean) = archCycle[i];
        tracker.processOverheadPressFeatures(
          WorkoutCvMotionFeatures.extractOverheadPressFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildOhpLandmarks(
              elbowAngleDeg: elbow,
              torsoLeanDeg: lean,
              wristAboveShoulder: true,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.minElbowAngleDeg, closeTo(165.0, 0.5));
      expect(rep.maxTorsoLeanDeg, closeTo(32.0, 0.5));
      expect(rep.isBackVertical, isFalse);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.overheadPress,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '5. Horizontal posture (torsoLean = 75 > 50) never enters ready, >500ms gap aborts cycle, and 50/25/10 FPS invariance',
        () {
      // 5a: Horizontal torso (e.g., bench press / lying down) stays notReady
      final horizontalTracker = OverheadPressBaseline();
      const horizontalFrames = <(int, double)>[
        (0, 85.0),
        (250, 85.0),
        (500, 125.0),
        (900, 165.0),
        (1400, 125.0),
        (1850, 85.0),
        (2050, 85.0),
      ];
      for (var i = 0; i < horizontalFrames.length; i++) {
        final (t, elbow) = horizontalFrames[i];
        final res = horizontalTracker.processOverheadPressFeatures(
          WorkoutCvMotionFeatures.extractOverheadPressFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildOhpLandmarks(
              elbowAngleDeg: elbow,
              torsoLeanDeg: 75.0,
              wristAboveShoulder: true,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
        expect(res.phase, OverheadPressPhase.notReady);
      }
      expect(horizontalTracker.completedReps, 0);

      // 5b: >500ms gap aborts mid-rep
      final gapTracker = OverheadPressBaseline();
      gapTracker.processSample(
        frameIndex: 0,
        timestampMs: 0,
        elbowAngleDeg: 85.0,
        isWristAboveShoulder: true,
        torsoLeanDeg: 10.0,
        isSampleValid: true,
      );
      gapTracker.processSample(
        frameIndex: 1,
        timestampMs: 250,
        elbowAngleDeg: 85.0,
        isWristAboveShoulder: true,
        torsoLeanDeg: 10.0,
        isSampleValid: true,
      );
      gapTracker.processSample(
        frameIndex: 2,
        timestampMs: 500,
        elbowAngleDeg: 120.0,
        isWristAboveShoulder: true,
        torsoLeanDeg: 10.0,
        isSampleValid: true,
      );
      gapTracker.processSample(
        frameIndex: 3,
        timestampMs: 850,
        elbowAngleDeg: 162.0,
        isWristAboveShoulder: true,
        torsoLeanDeg: 10.0,
        isSampleValid: true,
      );
      expect(gapTracker.phase, OverheadPressPhase.lockout);

      final afterGap = gapTracker.processSample(
        frameIndex: 4,
        timestampMs: 1500, // 650ms gap
        elbowAngleDeg: 85.0,
        isWristAboveShoulder: true,
        torsoLeanDeg: 10.0,
        isSampleValid: true,
      );
      expect(afterGap.resetReason, 'dataLossGapBeforeValidSample');
      expect(gapTracker.phase, OverheadPressPhase.notReady);
      expect(gapTracker.completedReps, 0);

      // 5c: Sampling-rate invariance across 50 / 25 / 10 FPS
      double synthElbow(double sec) =>
          125.0 - 45.0 * math.cos(2 * math.pi * sec / 2.6);

      int runSim(int stepMs) {
        final sim = OverheadPressBaseline();
        var fIdx = 0;
        for (var t = 0; t <= 5800; t += stepMs) {
          sim.processSample(
            frameIndex: fIdx++,
            timestampMs: t,
            elbowAngleDeg: synthElbow(t / 1000.0),
            isWristAboveShoulder: true,
            torsoLeanDeg: 12.0,
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

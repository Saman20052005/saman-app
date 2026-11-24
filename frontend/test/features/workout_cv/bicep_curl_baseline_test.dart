import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/bicep_curl_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildBicepCurlLandmarks({
  required double leftElbowAngleDeg,
  required double rightElbowAngleDeg,
  double leftUpperArmSwingDeg = 8.0,
  double rightUpperArmSwingDeg = 8.0,
  double torsoLeanDeg = 6.0,
  double leftArmVisibility = 0.95,
  double rightArmVisibility = 0.95,
  double hipVisibility = 0.95,
}) {
  const lHipX = 460.0;
  const rHipX = 620.0;
  const hipY = 1050.0;
  const torsoLen = 260.0;
  const upperArmLen = 140.0;
  const forearmLen = 140.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final lShX = lHipX + torsoLen * math.sin(leanRad);
  final lShY = hipY - torsoLen * math.cos(leanRad);
  final rShX = rHipX + torsoLen * math.sin(leanRad);
  final rShY = hipY - torsoLen * math.cos(leanRad);

  (double, double, double, double) solveArm({
    required double shX,
    required double shY,
    required double hipX,
    required double swingDeg,
    required double elbowDeg,
  }) {
    final dxSH = hipX - shX;
    final dySH = hipY - shY;
    final lenSH = math.sqrt(dxSH * dxSH + dySH * dySH);
    final u = dxSH / lenSH;
    final v = dySH / lenSH;
    final swingRad = swingDeg * math.pi / 180.0;
    final elDirX = u * math.cos(swingRad) - v * math.sin(swingRad);
    final elDirY = u * math.sin(swingRad) + v * math.cos(swingRad);

    final elX = shX + upperArmLen * elDirX;
    final elY = shY + upperArmLen * elDirY;

    final elbowRad = elbowDeg * math.pi / 180.0;
    final backX = -elDirX;
    final backY = -elDirY;
    final wrDirX = backX * math.cos(elbowRad) - backY * math.sin(elbowRad);
    final wrDirY = backX * math.sin(elbowRad) + backY * math.cos(elbowRad);

    final wrX = elX + forearmLen * wrDirX;
    final wrY = elY + forearmLen * wrDirY;
    return (elX, elY, wrX, wrY);
  }

  final (lElX, lElY, lWrX, lWrY) = solveArm(
    shX: lShX,
    shY: lShY,
    hipX: lHipX,
    swingDeg: leftUpperArmSwingDeg,
    elbowDeg: leftElbowAngleDeg,
  );
  final (rElX, rElY, rWrX, rWrY) = solveArm(
    shX: rShX,
    shY: rShY,
    hipX: rHipX,
    swingDeg: rightUpperArmSwingDeg,
    elbowDeg: rightElbowAngleDeg,
  );

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
      px(PoseLandmark.leftShoulder, lShX, lShY, leftArmVisibility);
  landmarks[PoseLandmark.leftElbow] =
      px(PoseLandmark.leftElbow, lElX, lElY, leftArmVisibility);
  landmarks[PoseLandmark.leftWrist] =
      px(PoseLandmark.leftWrist, lWrX, lWrY, leftArmVisibility);
  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, lHipX, hipY, hipVisibility);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, rShX, rShY, rightArmVisibility);
  landmarks[PoseLandmark.rightElbow] =
      px(PoseLandmark.rightElbow, rElX, rElY, rightArmVisibility);
  landmarks[PoseLandmark.rightWrist] =
      px(PoseLandmark.rightWrist, rWrX, rWrY, rightArmVisibility);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, rHipX, hipY, hipVisibility);

  return landmarks;
}

void main() {
  group('WorkoutCvMotionFeatures.extractBicepCurlFeatures & BicepCurlBaseline', () {
    test(
        '1. Alternating 2-arm curls keep side-lock on curling arm even when idle arm has higher visibility (0.99 > 0.85), counting 2 clean reps',
        () {
      final tracker = BicepCurlBaseline();
      const alternatingCycle = <(int, double, double)>[
        // Setup in extended
        (0, 162.0, 165.0),
        (120, 162.0, 165.0),
        (250, 162.0, 165.0),
        // Rep 1: Left arm curls while Right arm stays extended with vis 0.99 > 0.85
        (500, 118.0, 165.0),
        (850, 75.0, 166.0),
        (1200, 48.0, 165.0),
        (1600, 92.0, 165.0),
        (1950, 155.0, 165.0),
        (2150, 162.0, 165.0), // duration = 1650ms -> rep 1 (left)
        // Rep 2: Right arm curls while Left arm stays extended
        (2400, 162.0, 120.0),
        (2750, 164.0, 78.0),
        (3100, 162.0, 50.0),
        (3500, 162.0, 95.0),
        (3850, 162.0, 155.0),
        (4050, 162.0, 165.0), // duration = 1650ms -> rep 2 (right)
      ];

      final phases = <BicepCurlPhase>{};
      for (var i = 0; i < alternatingCycle.length; i++) {
        final (t, leftDeg, rightDeg) = alternatingCycle[i];
        final isRep1Window = t >= 500 && t <= 2150;
        final features = WorkoutCvMotionFeatures.extractBicepCurlFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildBicepCurlLandmarks(
            leftElbowAngleDeg: leftDeg,
            rightElbowAngleDeg: rightDeg,
            leftArmVisibility: isRep1Window ? 0.85 : 0.99,
            rightArmVisibility: isRep1Window ? 0.99 : 0.85,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        final res = tracker.processBicepCurlFeatures(features);
        phases.add(res.phase);

        if (t >= 500 && t <= 1950) {
          expect(tracker.lockedSide, 'left');
        } else if (t >= 2400 && t <= 3850) {
          expect(tracker.lockedSide, 'right');
        }
      }

      expect(phases, containsAll(BicepCurlPhase.values));
      expect(tracker.lockedSide, isNull);
      expect(tracker.completedReps, 2);

      final rep1 = tracker.repHistory[0];
      expect(rep1.activeSide, 'left');
      expect(rep1.minElbowAngleDeg, closeTo(48.0, 0.5));
      expect(rep1.isElbowPinned, isTrue);
      expect(rep1.isTorsoStable, isTrue);

      final rep2 = tracker.repHistory[1];
      expect(rep2.activeSide, 'right');
      expect(rep2.minElbowAngleDeg, closeTo(50.0, 0.5));
      expect(rep2.isElbowPinned, isTrue);
      expect(rep2.isTorsoStable, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.bicepCurl,
      );
      expect(summary.totalReps, 2);
      expect(summary.validReps, 2);
    });

    test(
        '2. Penalizes elbow swing (upperArmSwing = 48 > 35): isElbowPinned == false, validReps == 0',
        () {
      final tracker = BicepCurlBaseline();
      const swingCycle = <(int, double, double)>[
        (0, 162.0, 10.0),
        (250, 162.0, 10.0),
        (500, 120.0, 28.0),
        (800, 80.0, 38.0),
        (1100, 50.0, 48.0), // > 35 deg
        (1450, 95.0, 30.0),
        (1850, 155.0, 12.0),
        (2050, 162.0, 10.0),
      ];

      for (var i = 0; i < swingCycle.length; i++) {
        final (t, elbow, swing) = swingCycle[i];
        tracker.processBicepCurlFeatures(
          WorkoutCvMotionFeatures.extractBicepCurlFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildBicepCurlLandmarks(
              leftElbowAngleDeg: elbow,
              rightElbowAngleDeg: elbow,
              leftUpperArmSwingDeg: swing,
              rightUpperArmSwingDeg: swing,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.maxUpperArmSwingDeg, closeTo(48.0, 0.5));
      expect(rep.isElbowPinned, isFalse);
      expect(rep.isTorsoStable, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.bicepCurl,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '3. Penalizes torso sway (torsoLean = 32 > 25): isTorsoStable == false, validReps == 0',
        () {
      final tracker = BicepCurlBaseline();
      const swayCycle = <(int, double, double)>[
        (0, 162.0, 6.0),
        (250, 162.0, 6.0),
        (500, 120.0, 18.0),
        (800, 80.0, 26.0),
        (1100, 50.0, 32.0), // > 25 deg
        (1450, 95.0, 16.0),
        (1850, 155.0, 6.0),
        (2050, 162.0, 6.0),
      ];

      for (var i = 0; i < swayCycle.length; i++) {
        final (t, elbow, lean) = swayCycle[i];
        tracker.processBicepCurlFeatures(
          WorkoutCvMotionFeatures.extractBicepCurlFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildBicepCurlLandmarks(
              leftElbowAngleDeg: elbow,
              rightElbowAngleDeg: elbow,
              torsoLeanDeg: lean,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.maxTorsoLeanDeg, closeTo(32.0, 0.5));
      expect(rep.isElbowPinned, isTrue);
      expect(rep.isTorsoStable, isFalse);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.bicepCurl,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '4. Preacher curl mode (maxValidUpperArmSwingDeg = 75) allows 50-deg bench-braced arm and grades validReps == 1',
        () {
      final tracker = BicepCurlBaseline(maxValidUpperArmSwingDeg: 75.0);
      const preacherCycle = <(int, double)>[
        (0, 160.0),
        (250, 160.0),
        (500, 118.0),
        (800, 80.0),
        (1100, 50.0),
        (1450, 95.0),
        (1850, 155.0),
        (2050, 160.0),
      ];

      for (var i = 0; i < preacherCycle.length; i++) {
        final (t, elbow) = preacherCycle[i];
        tracker.processBicepCurlFeatures(
          WorkoutCvMotionFeatures.extractBicepCurlFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildBicepCurlLandmarks(
              leftElbowAngleDeg: elbow,
              rightElbowAngleDeg: elbow,
              leftUpperArmSwingDeg: 50.0,
              rightUpperArmSwingDeg: 50.0,
              torsoLeanDeg: 14.0,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.maxUpperArmSwingDeg, closeTo(50.0, 0.5));
      expect(rep.isElbowPinned, isTrue);
      expect(rep.isTorsoStable, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.bicepCurl,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 1);
    });

    test(
        '5. >500ms gap aborts cycle and releases side-lock, plus 50/25/10 FPS invariance',
        () {
      // 5a: Gap loss > 500ms aborts and releases _lockedSide
      final gapTracker = BicepCurlBaseline();
      const setupFrames = <(int, double, double)>[
        (0, 162.0, 162.0),
        (250, 162.0, 162.0),
        (500, 115.0, 162.0),
        (800, 55.0, 162.0),
      ];
      for (var i = 0; i < setupFrames.length; i++) {
        final (t, lElbow, rElbow) = setupFrames[i];
        gapTracker.processBicepCurlFeatures(
          WorkoutCvMotionFeatures.extractBicepCurlFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildBicepCurlLandmarks(
              leftElbowAngleDeg: lElbow,
              rightElbowAngleDeg: rElbow,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }
      expect(gapTracker.phase, BicepCurlPhase.flexed);
      expect(gapTracker.lockedSide, 'left');

      final afterGap = gapTracker.processBicepCurlFeatures(
        WorkoutCvMotionFeatures.extractBicepCurlFeatures(
          frameIndex: 4,
          timestampMs: 1450, // 650ms gap
          landmarks: _buildBicepCurlLandmarks(
            leftElbowAngleDeg: 162.0,
            rightElbowAngleDeg: 162.0,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        ),
      );
      expect(afterGap.resetReason, 'dataLossGapBeforeValidSample');
      expect(gapTracker.phase, BicepCurlPhase.notReady);
      expect(gapTracker.lockedSide, isNull);
      expect(gapTracker.completedReps, 0);

      // 5b: Sampling-rate invariance across 50 / 25 / 10 FPS
      double synthElbow(double sec) =>
          110.0 + 55.0 * math.cos(2 * math.pi * sec / 2.6);

      int runSim(int stepMs) {
        final sim = BicepCurlBaseline();
        var fIdx = 0;
        for (var t = 0; t <= 5800; t += stepMs) {
          sim.processSample(
            frameIndex: fIdx++,
            timestampMs: t,
            elbowAngleDeg: synthElbow(t / 1000.0),
            upperArmSwingDeg: 10.0,
            torsoLeanDeg: 8.0,
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

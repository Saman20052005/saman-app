import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/pull_up_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildPullUpLandmarks({
  required double elbowAngleDeg,
  double barY = 400.0,
  double mouthOffsetAboveShoulder = 130.0,
  bool wristsBelowShoulders = false,
  double leftArmVisibility = 0.95,
  double rightArmVisibility = 0.95,
  bool includeMouth = true,
  bool includeNose = true,
  bool includeEars = true,
  double? customMouthY,
  double? customNoseY,
  double? customEarY,
  double? customShoulderY,
}) {
  const seg = 150.0;
  const leftX = 420.0;
  const rightX = 660.0;
  final rad = elbowAngleDeg * math.pi / 180.0;
  final halfCos = math.cos(rad / 2.0);
  final halfSin = math.sin(rad / 2.0);
  final wristShoulderDist = 2.0 * seg * halfSin;

  final double lShoulderY;
  final double rShoulderY;
  final double lElbowY;
  final double rElbowY;
  final double lWristY;
  final double rWristY;

  if (wristsBelowShoulders) {
    // Standing/resting on ground: shoulders above elbows/wrists
    lShoulderY = customShoulderY ?? 600.0;
    rShoulderY = customShoulderY ?? 600.0;
    lElbowY = lShoulderY + seg;
    rElbowY = rShoulderY + seg;
    lWristY = lElbowY - seg * math.cos(rad);
    rWristY = rElbowY - seg * math.cos(rad);
  } else {
    // Hanging from bar: wrists at barY, shoulders below wrists
    lWristY = barY;
    rWristY = barY;
    lShoulderY = customShoulderY ?? (barY + wristShoulderDist);
    rShoulderY = customShoulderY ?? (barY + wristShoulderDist);
    lElbowY = barY + wristShoulderDist / 2.0;
    rElbowY = barY + wristShoulderDist / 2.0;
  }

  final lElbowX = wristsBelowShoulders ? leftX : (leftX - seg * halfCos);
  final rElbowX = wristsBelowShoulders ? rightX : (rightX + seg * halfCos);
  final lWristX =
      wristsBelowShoulders ? (leftX + seg * math.sin(rad)) : leftX;
  final rWristX =
      wristsBelowShoulders ? (rightX + seg * math.sin(rad)) : rightX;

  final avgShoulderY = (lShoulderY + rShoulderY) / 2.0;
  final mouthY = customMouthY ?? (avgShoulderY - mouthOffsetAboveShoulder);
  final noseY = customNoseY ?? (mouthY - 35.0);
  final earY = customEarY ?? (mouthY - 40.0);

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
      px(PoseLandmark.leftShoulder, leftX, lShoulderY, leftArmVisibility);
  landmarks[PoseLandmark.leftElbow] =
      px(PoseLandmark.leftElbow, lElbowX, lElbowY, leftArmVisibility);
  landmarks[PoseLandmark.leftWrist] =
      px(PoseLandmark.leftWrist, lWristX, lWristY, leftArmVisibility);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, rightX, rShoulderY, rightArmVisibility);
  landmarks[PoseLandmark.rightElbow] =
      px(PoseLandmark.rightElbow, rElbowX, rElbowY, rightArmVisibility);
  landmarks[PoseLandmark.rightWrist] =
      px(PoseLandmark.rightWrist, rWristX, rWristY, rightArmVisibility);

  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, 440.0, avgShoulderY + 320.0, 0.95);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, 640.0, avgShoulderY + 320.0, 0.95);

  landmarks[PoseLandmark.mouthLeft] = px(
      PoseLandmark.mouthLeft, 520.0, mouthY, includeMouth ? 0.95 : 0.1);
  landmarks[PoseLandmark.mouthRight] = px(
      PoseLandmark.mouthRight, 560.0, mouthY, includeMouth ? 0.95 : 0.1);
  landmarks[PoseLandmark.nose] =
      px(PoseLandmark.nose, 540.0, noseY, includeNose ? 0.95 : 0.1);
  landmarks[PoseLandmark.leftEar] =
      px(PoseLandmark.leftEar, 490.0, earY, includeEars ? 0.95 : 0.1);
  landmarks[PoseLandmark.rightEar] =
      px(PoseLandmark.rightEar, 590.0, earY, includeEars ? 0.95 : 0.1);

  return landmarks;
}

void main() {
  group('WorkoutCvMotionFeatures.extractPullUpFeatures & PullUpBaseline', () {
    test(
        '1. Standard pull-up cycle with real geometry counts 1 rep, isChinCleared == true, validReps == 1',
        () {
      final tracker = PullUpBaseline();
      const cycle = <(int, double)>[
        (0, 165.0),
        (120, 165.0),
        (250, 165.0), // readyHoldSatisfied -> extended
        (500, 95.0), // pullingStarted
        (850, 70.0),
        (1200, 52.0), // flexed + chin cleared
        (1550, 88.0), // returnStarted
        (1900, 160.0),
        (2100, 165.0), // repCompleted (duration = 1600ms)
      ];

      final phases = <PullUpPhase>{};
      for (var i = 0; i < cycle.length; i++) {
        final (t, angle) = cycle[i];
        final features = WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildPullUpLandmarks(elbowAngleDeg: angle),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.isWristAboveShoulder, isTrue);
        final res = tracker.processPullUpFeatures(features);
        phases.add(res.phase);
      }

      expect(phases, containsAll(PullUpPhase.values));
      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.single.isChinCleared, isTrue);
      expect(tracker.repHistory.single.minElbowAngleDeg, closeTo(52.0, 0.5));

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.pullUp,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 1);
    });

    test(
        '2. Selects higher-visibility arm automatically (occluded left -> uses right side)',
        () {
      final features = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: _buildPullUpLandmarks(
          elbowAngleDeg: 52.0,
          leftArmVisibility: 0.2,
          rightArmVisibility: 0.92,
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );

      expect(features.bestElbowAngleDeg.isValid, isTrue);
      expect(features.bestElbowAngleDeg.value, closeTo(52.0, 0.5));
      expect(features.bestSideKey, 'model_right_12_14_16');
      expect(features.isWristAboveShoulder, isTrue);
      expect(features.isChinCleared, isTrue);

      final tiePreferRight = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 1,
        timestampMs: 200,
        landmarks: _buildPullUpLandmarks(
          elbowAngleDeg: 90.0,
          leftArmVisibility: 0.55,
          rightArmVisibility: 0.95,
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(tiePreferRight.bestSideKey, 'model_right_12_14_16');
    });

    test(
        '3. Standing on ground / arms down (wristY > shoulderY) cannot enter extended and dropping from bar resets without abortCount',
        () {
      final tracker = PullUpBaseline();

      // Standing with arms down (165 -> 50 -> 165) must stay in notReady
      const standingFrames = <(int, double)>[
        (0, 165.0),
        (250, 165.0),
        (500, 90.0),
        (900, 50.0),
        (1300, 90.0),
        (1700, 165.0),
        (1950, 165.0),
      ];
      for (var i = 0; i < standingFrames.length; i++) {
        final (t, angle) = standingFrames[i];
        final features = WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildPullUpLandmarks(
            elbowAngleDeg: angle,
            wristsBelowShoulders: true,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.isWristAboveShoulder, isFalse);
        final res = tracker.processPullUpFeatures(features);
        expect(res.phase, PullUpPhase.notReady);
      }
      expect(tracker.completedReps, 0);

      // Hang on bar -> enter extended -> drop hands below shoulders
      tracker.processPullUpFeatures(
        WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: 10,
          timestampMs: 2100,
          landmarks: _buildPullUpLandmarks(elbowAngleDeg: 165.0),
          imageWidth: _imgW,
          imageHeight: _imgH,
        ),
      );
      final readyRes = tracker.processPullUpFeatures(
        WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: 11,
          timestampMs: 2350,
          landmarks: _buildPullUpLandmarks(elbowAngleDeg: 165.0),
          imageWidth: _imgW,
          imageHeight: _imgH,
        ),
      );
      expect(readyRes.phase, PullUpPhase.extended);

      final dropRes = tracker.processPullUpFeatures(
        WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: 12,
          timestampMs: 2500,
          landmarks: _buildPullUpLandmarks(
            elbowAngleDeg: 165.0,
            wristsBelowShoulders: true,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        ),
      );
      expect(dropRes.phase, PullUpPhase.notReady);
      expect(dropRes.transitionReason, 'droppedFromBar');
      expect(dropRes.resetReason, isNull);
    });

    test(
        '4. Blocks half-rep phantom counts when elbow flexes <= 65 deg but mouth remains far below bar',
        () {
      final tracker = PullUpBaseline();

      // Establish extended hang
      for (final (i, t) in [(0, 0), (1, 250)]) {
        tracker.processPullUpFeatures(
          WorkoutCvMotionFeatures.extractPullUpFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildPullUpLandmarks(elbowAngleDeg: 165.0),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }
      expect(tracker.phase, PullUpPhase.extended);

      // Pull to 58 deg elbow angle while keeping mouth far below bar (headToBarNorm > 0.25)
      final pullingStart = tracker.processPullUpFeatures(
        WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: 2,
          timestampMs: 450,
          landmarks: _buildPullUpLandmarks(elbowAngleDeg: 90.0),
          imageWidth: _imgW,
          imageHeight: _imgH,
        ),
      );
      expect(pullingStart.phase, PullUpPhase.pulling);

      final halfRepFeatures = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 3,
        timestampMs: 900,
        landmarks: _buildPullUpLandmarks(
          elbowAngleDeg: 58.0,
          customMouthY: 480.0, // (480 - 400) / 240 = +0.333 > 0.25
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(halfRepFeatures.headToBarNorm.value, greaterThan(0.25));
      expect(halfRepFeatures.isTopPositionReached, isFalse);
      expect(halfRepFeatures.isChinCleared, isFalse);

      final halfRepRes = tracker.processPullUpFeatures(halfRepFeatures);
      expect(halfRepRes.phase, PullUpPhase.pulling);

      // Extend arms back down -> returns to extended with incompletePullChinNotCleared
      final abortRes = tracker.processPullUpFeatures(
        WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: 4,
          timestampMs: 1400,
          landmarks: _buildPullUpLandmarks(elbowAngleDeg: 165.0),
          imageWidth: _imgW,
          imageHeight: _imgH,
        ),
      );
      expect(abortRes.phase, PullUpPhase.extended);
      expect(abortRes.transitionReason, 'incompletePullChinNotCleared');
      expect(tracker.completedReps, 0);
    });

    test(
        '5. Rear/back-view fallback (no mouth/nose/ears, shoulderToBarNorm <= 0.55) counts rep with isChinCleared == null',
        () {
      final tracker = PullUpBaseline();

      // Priority 2 (nose) & Priority 3 (ears) extraction checks
      final noseFallback = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 0,
        timestampMs: 0,
        landmarks: _buildPullUpLandmarks(
          elbowAngleDeg: 52.0,
          includeMouth: false,
          includeNose: true,
          customNoseY: 380.0, // (380 - 400) / 240 = -0.083 <= -0.03
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(noseFallback.isChinCleared, isTrue);
      expect(noseFallback.isTopPositionReached, isTrue);

      final earFallback = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 1,
        timestampMs: 0,
        landmarks: _buildPullUpLandmarks(
          elbowAngleDeg: 52.0,
          includeMouth: false,
          includeNose: false,
          includeEars: true,
          customEarY: 410.0, // (410 - 400) / 240 = +0.041 <= 0.08
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(earFallback.isChinCleared, isNull);
      expect(earFallback.isTopPositionReached, isTrue);

      // Priority 4 (back of neck: shoulders + arms only) full rep cycle
      const rearCycle = <(int, double, double?)>[
        (0, 165.0, null),
        (250, 165.0, null),
        (500, 92.0, null),
        (800, 72.0, null),
        (1100, 52.0, 520.0), // (520 - 400) / 240 = 0.50 <= 0.55
        (1450, 88.0, null),
        (1850, 165.0, null),
        (2100, 165.0, null), // duration = 1600ms
      ];
      for (var i = 0; i < rearCycle.length; i++) {
        final (t, angle, customShoulderY) = rearCycle[i];
        final features = WorkoutCvMotionFeatures.extractPullUpFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildPullUpLandmarks(
            elbowAngleDeg: angle,
            includeMouth: false,
            includeNose: false,
            includeEars: false,
            customShoulderY: customShoulderY,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.isChinCleared, isNull);
        tracker.processPullUpFeatures(features);
      }

      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.single.isChinCleared, isNull);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.pullUp,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 1);
    });

    test(
        '6. CvFormSummaryCalculator gives validReps == 0 when PullUpRepEvent has isChinCleared == false',
        () {
      const unclearRep = PullUpRepEvent(
        repNumber: 1,
        startTimestampMs: 500,
        bottomTimestampMs: 1200,
        endTimestampMs: 2200,
        durationMs: 1700,
        minElbowAngleDeg: 55.0,
        isChinCleared: false,
      );

      final summary = CvFormSummaryCalculator.compute(
        reps: const [unclearRep],
        module: CvExerciseModule.pullUp,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);

      // Also verify geometric case where mouth is in tolerance zone (0.05 < norm <= 0.12)
      final tracker = PullUpBaseline();
      const marginalCycle = <(int, double, double)>[
        (0, 165.0, 560.0),
        (250, 165.0, 560.0),
        (500, 90.0, 480.0),
        (800, 68.0, 450.0),
        (1100, 55.0, 420.0), // (420 - 400) / 240 = +0.0833 (top reached, chin not cleared)
        (1450, 88.0, 470.0),
        (1850, 165.0, 560.0),
        (2100, 165.0, 560.0),
      ];
      for (var i = 0; i < marginalCycle.length; i++) {
        final (t, angle, mouthY) = marginalCycle[i];
        tracker.processPullUpFeatures(
          WorkoutCvMotionFeatures.extractPullUpFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildPullUpLandmarks(
              elbowAngleDeg: angle,
              customMouthY: mouthY,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }
      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.single.isChinCleared, isFalse);
      final marginalSummary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.pullUp,
      );
      expect(marginalSummary.totalReps, 1);
      expect(marginalSummary.validReps, 0);
    });

    test(
        '7. Sampling-rate invariance (50/25/10 FPS) & >500ms gap loss aborts incomplete rep',
        () {
      double syntheticAngle(double sec) =>
          115.0 + 55.0 * math.cos(2 * math.pi * sec / 3.0);

      int runSim(int stepMs) {
        final simTracker = PullUpBaseline();
        var fIdx = 0;
        for (var t = 0; t <= 6500; t += stepMs) {
          final angle = syntheticAngle(t / 1000.0);
          simTracker.processSample(
            frameIndex: fIdx++,
            timestampMs: t,
            elbowAngleDeg: angle,
            isSampleValid: true,
            isWristAboveShoulder: true,
            isTopPositionReached: angle <= 65.0,
            isChinCleared: angle <= 65.0,
          );
        }
        return simTracker.completedReps;
      }

      expect(runSim(20), 2); // 50 FPS
      expect(runSim(40), 2); // 25 FPS
      expect(runSim(100), 2); // 10 FPS

      // Gap loss > 500ms aborts mid-rep
      final gapTracker = PullUpBaseline();
      gapTracker.processSample(
          frameIndex: 0, timestampMs: 0, elbowAngleDeg: 165.0, isSampleValid: true);
      gapTracker.processSample(
          frameIndex: 1, timestampMs: 250, elbowAngleDeg: 165.0, isSampleValid: true);
      gapTracker.processSample(
          frameIndex: 2, timestampMs: 450, elbowAngleDeg: 90.0, isSampleValid: true);
      gapTracker.processSample(
          frameIndex: 3, timestampMs: 750, elbowAngleDeg: 55.0, isSampleValid: true);
      expect(gapTracker.phase, PullUpPhase.flexed);

      // 650ms gap (> maxAllowedGapMs = 500ms)
      final afterGap = gapTracker.processSample(
          frameIndex: 4, timestampMs: 1400, elbowAngleDeg: 165.0, isSampleValid: true);
      expect(afterGap.resetReason, 'dataLossGapBeforeValidSample');
      expect(gapTracker.phase, PullUpPhase.notReady);
      expect(gapTracker.completedReps, 0);
    });

    test(
        '8. Gate not detecting and invalid image dimensions return invalid features safely',
        () {
      final landmarks = _buildPullUpLandmarks(elbowAngleDeg: 165.0);

      final gated = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: _imgW,
        imageHeight: _imgH,
        isGateDetecting: false,
      );
      expect(gated.bestElbowAngleDeg.isValid, isFalse);
      expect(gated.bestElbowAngleDeg.failure, MotionMetricFailure.gateNotDetecting);
      expect(gated.isWristAboveShoulder, isFalse);
      expect(gated.isTopPositionReached, isFalse);
      expect(gated.isChinCleared, isNull);

      final badDim = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 1,
        timestampMs: 200,
        landmarks: landmarks,
        imageWidth: 0.0,
        imageHeight: _imgH,
      );
      expect(badDim.bestElbowAngleDeg.isValid, isFalse);
      expect(
        badDim.bestElbowAngleDeg.failure,
        MotionMetricFailure.invalidImageDimensions,
      );
    });
  });
}

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/squat_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildSquatLandmarks({
  required double kneeAngleDeg,
  required double hipAngleDeg,
  required double torsoLeanDeg,
  double leftLegVisibility = 0.95,
  double rightLegVisibility = 0.95,
  double leftShoulderVisibility = 0.95,
  double rightShoulderVisibility = 0.95,
}) {
  const hipX = 540.0;
  const hipY = 900.0;
  const torsoLen = 280.0;
  const thighLen = 220.0;
  const shinLen = 220.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final hipRad = hipAngleDeg * math.pi / 180.0;
  final kneeRad = kneeAngleDeg * math.pi / 180.0;

  // Shoulder at clockwise angle `leanRad` from upward vertical (0, -1)
  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);

  // Thigh at clockwise angle `leanRad + hipRad` from upward vertical
  final thighAzimuth = leanRad + hipRad;
  final kneeX = hipX + thighLen * math.sin(thighAzimuth);
  final kneeY = hipY - thighLen * math.cos(thighAzimuth);

  // Shin rotated counter-clockwise by `kneeRad` from (Knee -> Hip)
  final shinAzimuth = thighAzimuth + math.pi - kneeRad;
  final ankleX = kneeX + shinLen * math.sin(shinAzimuth);
  final ankleY = kneeY - shinLen * math.cos(shinAzimuth);

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
      px(PoseLandmark.leftShoulder, shX, shY, leftShoulderVisibility);
  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, hipX, hipY, leftLegVisibility);
  landmarks[PoseLandmark.leftKnee] =
      px(PoseLandmark.leftKnee, kneeX, kneeY, leftLegVisibility);
  landmarks[PoseLandmark.leftAnkle] =
      px(PoseLandmark.leftAnkle, ankleX, ankleY, leftLegVisibility);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, shX, shY, rightShoulderVisibility);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, hipX, hipY, rightLegVisibility);
  landmarks[PoseLandmark.rightKnee] =
      px(PoseLandmark.rightKnee, kneeX, kneeY, rightLegVisibility);
  landmarks[PoseLandmark.rightAnkle] =
      px(PoseLandmark.rightAnkle, ankleX, ankleY, rightLegVisibility);

  return landmarks;
}

void main() {
  group('WorkoutCvMotionFeatures.extractSquatFeatures & SquatBaseline', () {
    test(
        '1. Standard Squat cycle (shoulder+hip+knee+ankle, knee=85, torsoLean=28, hipAngle=80) counts 1 rep, isBackStraight == true, validReps == 1',
        () {
      final tracker = SquatBaseline();
      const cycle = <(int, double, double, double)>[
        (0, 172.0, 172.0, 8.0),
        (120, 172.0, 172.0, 8.0),
        (250, 172.0, 172.0, 8.0), // standing
        (500, 132.0, 125.0, 18.0), // descending
        (850, 108.0, 98.0, 24.0),
        (1200, 85.0, 80.0, 28.0), // bottom
        (1550, 120.0, 112.0, 22.0), // ascending
        (1950, 165.0, 165.0, 10.0),
        (2200, 170.0, 170.0, 8.0), // duration = 1700ms (1.5-4.5s)
      ];

      final phases = <SquatPhase>{};
      for (var i = 0; i < cycle.length; i++) {
        final (t, knee, hip, lean) = cycle[i];
        final features = WorkoutCvMotionFeatures.extractSquatFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildSquatLandmarks(
            kneeAngleDeg: knee,
            hipAngleDeg: hip,
            torsoLeanDeg: lean,
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.bestKneeAngleDeg.value, closeTo(knee, 0.5));
        expect(features.bestHipAngleDeg.value, closeTo(hip, 0.5));
        expect(features.torsoLeanDeg.value, closeTo(lean, 0.5));
        final res = tracker.processSquatFeatures(features);
        phases.add(res.phase);
      }

      expect(phases, containsAll(SquatPhase.values));
      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.minElbowAngleDeg, closeTo(85.0, 0.5));
      expect(rep.maxTorsoLeanDeg, closeTo(28.0, 0.5));
      expect(rep.minHipAngleDeg, closeTo(80.0, 0.5));
      expect(rep.isBackStraight, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.squat,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 1);
    });

    test(
        '2. Parallel Squat (knee=98, torsoLean=30, hipAngle=90) counts rep (completedReps == 1) but validReps == 0 (> 95 deg)',
        () {
      final tracker = SquatBaseline();
      const parallelCycle = <(int, double, double, double)>[
        (0, 170.0, 170.0, 8.0),
        (250, 170.0, 170.0, 8.0),
        (500, 130.0, 125.0, 20.0),
        (900, 105.0, 98.0, 26.0),
        (1200, 98.0, 90.0, 30.0), // bottom <= 100, shallower than 95
        (1550, 122.0, 118.0, 22.0),
        (1950, 165.0, 165.0, 10.0),
        (2150, 170.0, 170.0, 8.0),
      ];

      for (var i = 0; i < parallelCycle.length; i++) {
        final (t, knee, hip, lean) = parallelCycle[i];
        tracker.processSquatFeatures(
          WorkoutCvMotionFeatures.extractSquatFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildSquatLandmarks(
              kneeAngleDeg: knee,
              hipAngleDeg: hip,
              torsoLeanDeg: lean,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.single.minElbowAngleDeg, closeTo(98.0, 0.5));
      expect(tracker.repHistory.single.isBackStraight, isTrue);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.squat,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '3. Excessive torso lean / rounded back (knee=88, torsoLean=62) counts totalReps == 1 with isBackStraight == false and validReps == 0',
        () {
      final tracker = SquatBaseline();
      const badBackCycle = <(int, double, double, double)>[
        (0, 170.0, 170.0, 10.0),
        (250, 170.0, 170.0, 10.0),
        (500, 130.0, 115.0, 40.0),
        (900, 95.0, 75.0, 58.0),
        (1200, 88.0, 70.0, 62.0), // torsoLean > 55 (<= 75 plausible)
        (1550, 120.0, 110.0, 42.0),
        (1950, 165.0, 165.0, 12.0),
        (2200, 170.0, 170.0, 10.0),
      ];

      for (var i = 0; i < badBackCycle.length; i++) {
        final (t, knee, hip, lean) = badBackCycle[i];
        tracker.processSquatFeatures(
          WorkoutCvMotionFeatures.extractSquatFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildSquatLandmarks(
              kneeAngleDeg: knee,
              hipAngleDeg: hip,
              torsoLeanDeg: lean,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
      }

      expect(tracker.completedReps, 1);
      final rep = tracker.repHistory.single;
      expect(rep.minElbowAngleDeg, closeTo(88.0, 0.5));
      expect(rep.maxTorsoLeanDeg, closeTo(62.0, 0.5));
      expect(rep.isBackStraight, isFalse);

      final summary = CvFormSummaryCalculator.compute(
        reps: tracker.repHistory,
        module: CvExerciseModule.squat,
      );
      expect(summary.totalReps, 1);
      expect(summary.validReps, 0);
    });

    test(
        '4. Blocks phantom reps from standing leg curl (knee=85, hipAngle=170) and pre-bent forward posture (torsoLean=50)',
        () {
      // 4a: Standing leg curl (hip remains extended at 170 deg)
      final curlTracker = SquatBaseline();
      const legCurlFrames = <(int, double, double, double)>[
        (0, 172.0, 172.0, 8.0),
        (250, 172.0, 172.0, 8.0), // standing
        (500, 125.0, 170.0, 10.0), // descending
        (900, 85.0, 170.0, 10.0), // knee <= 100 but hipAngle 170 > 145
        (1300, 125.0, 170.0, 10.0),
        (1700, 172.0, 172.0, 8.0),
        (1950, 172.0, 172.0, 8.0),
      ];

      for (var i = 0; i < legCurlFrames.length; i++) {
        final (t, knee, hip, lean) = legCurlFrames[i];
        final res = curlTracker.processSquatFeatures(
          WorkoutCvMotionFeatures.extractSquatFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildSquatLandmarks(
              kneeAngleDeg: knee,
              hipAngleDeg: hip,
              torsoLeanDeg: lean,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
        expect(res.phase, isNot(SquatPhase.bottom));
      }
      expect(curlTracker.completedReps, 0);

      // 4b: Pre-bent forward posture (torsoLean=50 > 35) cannot enter standing
      final bentTracker = SquatBaseline();
      const bentFrames = <(int, double, double, double)>[
        (0, 168.0, 125.0, 50.0),
        (250, 168.0, 125.0, 50.0),
        (500, 130.0, 100.0, 52.0),
        (900, 88.0, 75.0, 55.0),
        (1300, 125.0, 100.0, 52.0),
        (1700, 168.0, 125.0, 50.0),
        (1950, 168.0, 125.0, 50.0),
      ];

      for (var i = 0; i < bentFrames.length; i++) {
        final (t, knee, hip, lean) = bentFrames[i];
        final res = bentTracker.processSquatFeatures(
          WorkoutCvMotionFeatures.extractSquatFeatures(
            frameIndex: i,
            timestampMs: t,
            landmarks: _buildSquatLandmarks(
              kneeAngleDeg: knee,
              hipAngleDeg: hip,
              torsoLeanDeg: lean,
            ),
            imageWidth: _imgW,
            imageHeight: _imgH,
          ),
        );
        expect(res.phase, SquatPhase.notReady);
      }
      expect(bentTracker.completedReps, 0);
    });

    test('5. Blocks phantom rep when sitting at bottom for > 12s (maxRepDurationMs)',
        () {
      final tracker = SquatBaseline();
      tracker.processSample(
        frameIndex: 0,
        timestampMs: 0,
        kneeAngleDeg: 170.0,
        hipAngleDeg: 170.0,
        torsoLeanDeg: 8.0,
        isSampleValid: true,
      );
      tracker.processSample(
        frameIndex: 1,
        timestampMs: 250,
        kneeAngleDeg: 170.0,
        hipAngleDeg: 170.0,
        torsoLeanDeg: 8.0,
        isSampleValid: true,
      );
      expect(tracker.phase, SquatPhase.standing);

      // Descend and hold at bottom (90 deg) for > 12000ms without gap > 500ms
      var fIdx = 2;
      tracker.processSample(
        frameIndex: fIdx++,
        timestampMs: 500,
        kneeAngleDeg: 130.0,
        hipAngleDeg: 120.0,
        torsoLeanDeg: 20.0,
        isSampleValid: true,
      );
      for (var t = 800; t <= 12800; t += 300) {
        tracker.processSample(
          frameIndex: fIdx++,
          timestampMs: t,
          kneeAngleDeg: 90.0,
          hipAngleDeg: 85.0,
          torsoLeanDeg: 25.0,
          isSampleValid: true,
        );
      }
      expect(tracker.phase, SquatPhase.bottom);

      // Stand up at t = 13100 -> 13400 (duration = 12900ms > 12000ms)
      tracker.processSample(
        frameIndex: fIdx++,
        timestampMs: 13100,
        kneeAngleDeg: 125.0,
        hipAngleDeg: 120.0,
        torsoLeanDeg: 18.0,
        isSampleValid: true,
      );
      tracker.processSample(
        frameIndex: fIdx++,
        timestampMs: 13400,
        kneeAngleDeg: 170.0,
        hipAngleDeg: 170.0,
        torsoLeanDeg: 8.0,
        isSampleValid: true,
      );
      final endRes = tracker.processSample(
        frameIndex: fIdx++,
        timestampMs: 13650,
        kneeAngleDeg: 170.0,
        hipAngleDeg: 170.0,
        torsoLeanDeg: 8.0,
        isSampleValid: true,
      );

      expect(endRes.transitionReason, 'repTooLongIgnored');
      expect(tracker.completedReps, 0);
      expect(tracker.phase, SquatPhase.standing);
    });

    test(
        '6. Higher-visibility leg selection, >500ms gap loss abort, and sampling-rate invariance (50/25/10 FPS)',
        () {
      // Left leg occluded -> chooses right leg ('model_right_24_26_28')
      final features = WorkoutCvMotionFeatures.extractSquatFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: _buildSquatLandmarks(
          kneeAngleDeg: 88.0,
          hipAngleDeg: 82.0,
          torsoLeanDeg: 26.0,
          leftLegVisibility: 0.15,
          rightLegVisibility: 0.94,
          leftShoulderVisibility: 0.15,
          rightShoulderVisibility: 0.94,
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(features.bestSideKey, 'model_right_24_26_28');
      expect(features.bestKneeAngleDeg.isValid, isTrue);
      expect(features.bestKneeAngleDeg.value, closeTo(88.0, 0.5));
      expect(features.bestHipAngleDeg.value, closeTo(82.0, 0.5));
      expect(features.torsoLeanDeg.value, closeTo(26.0, 0.5));

      // Gap loss > 500ms aborts mid-rep
      final gapTracker = SquatBaseline();
      gapTracker.processSample(
          frameIndex: 0, timestampMs: 0, kneeAngleDeg: 170.0, isSampleValid: true);
      gapTracker.processSample(
          frameIndex: 1, timestampMs: 250, kneeAngleDeg: 170.0, isSampleValid: true);
      gapTracker.processSample(
          frameIndex: 2, timestampMs: 500, kneeAngleDeg: 125.0, isSampleValid: true);
      gapTracker.processSample(
          frameIndex: 3, timestampMs: 800, kneeAngleDeg: 90.0, isSampleValid: true);
      expect(gapTracker.phase, SquatPhase.bottom);

      final afterGap = gapTracker.processSample(
          frameIndex: 4, timestampMs: 1450, kneeAngleDeg: 170.0, isSampleValid: true);
      expect(afterGap.resetReason, 'dataLossGapBeforeValidSample');
      expect(gapTracker.phase, SquatPhase.notReady);
      expect(gapTracker.completedReps, 0);

      // Sampling-rate invariance across 50 / 25 / 10 FPS (period = 3.0s)
      double synthKnee(double sec) =>
          130.0 + 45.0 * math.cos(2 * math.pi * sec / 3.0);
      double synthHip(double sec) =>
          125.0 + 48.0 * math.cos(2 * math.pi * sec / 3.0);
      double synthLean(double sec) =>
          18.0 - 12.0 * math.cos(2 * math.pi * sec / 3.0);

      int runSim(int stepMs) {
        final sim = SquatBaseline();
        var fIdx = 0;
        for (var t = 0; t <= 6500; t += stepMs) {
          final sec = t / 1000.0;
          sim.processSample(
            frameIndex: fIdx++,
            timestampMs: t,
            kneeAngleDeg: synthKnee(sec),
            hipAngleDeg: synthHip(sec),
            torsoLeanDeg: synthLean(sec),
            isSampleValid: true,
          );
        }
        return sim.completedReps;
      }

      expect(runSim(20), 2); // 50 FPS
      expect(runSim(40), 2); // 25 FPS
      expect(runSim(100), 2); // 10 FPS
    });

    test(
        '7. Gate/dimension failures and shoulder-occluded fallback behave safely',
        () {
      final landmarks = _buildSquatLandmarks(
        kneeAngleDeg: 90.0,
        hipAngleDeg: 85.0,
        torsoLeanDeg: 25.0,
      );

      final gated = WorkoutCvMotionFeatures.extractSquatFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: _imgW,
        imageHeight: _imgH,
        isGateDetecting: false,
      );
      expect(gated.bestSideKey, 'none');
      expect(gated.bestKneeAngleDeg.failure, MotionMetricFailure.gateNotDetecting);
      expect(gated.bestHipAngleDeg.failure, MotionMetricFailure.gateNotDetecting);
      expect(gated.torsoLeanDeg.failure, MotionMetricFailure.gateNotDetecting);

      final badDim = WorkoutCvMotionFeatures.extractSquatFeatures(
        frameIndex: 1,
        timestampMs: 200,
        landmarks: landmarks,
        imageWidth: 0.0,
        imageHeight: _imgH,
      );
      expect(
        badDim.bestKneeAngleDeg.failure,
        MotionMetricFailure.invalidImageDimensions,
      );

      // Shoulder occluded -> bestKneeAngleDeg valid, hip/torso invalid, SquatBaseline falls back safely
      final noShoulder = WorkoutCvMotionFeatures.extractSquatFeatures(
        frameIndex: 2,
        timestampMs: 300,
        landmarks: _buildSquatLandmarks(
          kneeAngleDeg: 88.0,
          hipAngleDeg: 85.0,
          torsoLeanDeg: 25.0,
          leftShoulderVisibility: 0.1,
          rightShoulderVisibility: 0.1,
        ),
        imageWidth: _imgW,
        imageHeight: _imgH,
      );
      expect(noShoulder.bestKneeAngleDeg.isValid, isTrue);
      expect(noShoulder.bestHipAngleDeg.isValid, isFalse);
      expect(noShoulder.torsoLeanDeg.isValid, isFalse);
    });
  });
}

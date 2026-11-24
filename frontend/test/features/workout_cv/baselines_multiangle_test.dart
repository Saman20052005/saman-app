import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/bicep_curl_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/pull_up_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/push_up_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/squat_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildSquatPoseLandmarks({
  required double shoulderWidthNorm,
  required double kneeAngleDeg,
  required double hipAngleDeg,
  required double torsoLeanDeg,
  double kneeWidthFactor = 1.0,
  double? overrideHipYNorm,
  double? overrideKneeYNorm,
}) {
  const hipCenterX = 540.0;
  final hipY = (overrideHipYNorm ?? 0.50) * _imgH;
  const torsoLen = 300.0;
  const thighLen = 220.0;
  const shinLen = 220.0;

  final halfShoulderPx = (shoulderWidthNorm * _imgW) / 2.0;
  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final hipRad = hipAngleDeg * math.pi / 180.0;
  final kneeRad = kneeAngleDeg * math.pi / 180.0;

  final midShX = hipCenterX + torsoLen * math.sin(leanRad);
  final midShY = hipY - torsoLen * math.cos(leanRad);

  final thighAzimuth = leanRad + hipRad;
  final baseKneeX = hipCenterX + thighLen * math.sin(thighAzimuth);
  final kneeY = overrideKneeYNorm != null
      ? overrideKneeYNorm * _imgH
      : (hipY - thighLen * math.cos(thighAzimuth));

  final shinAzimuth = thighAzimuth + math.pi - kneeRad;
  final baseAnkleX = baseKneeX + shinLen * math.sin(shinAzimuth);
  final ankleY = kneeY - shinLen * math.cos(shinAzimuth);

  const ankleSpreadHalfPx = 120.0;
  final kneeSpreadHalfPx = ankleSpreadHalfPx * kneeWidthFactor;

  PoseLandmark px(int index, double xPx, double yPx, {double vis = 0.95}) {
    return PoseLandmark(
      index: index,
      x: (xPx / _imgW).clamp(0.0, 1.0),
      y: (yPx / _imgH).clamp(0.0, 1.0),
      z: 0.0,
      visibility: vis,
    );
  }

  final lms = List.generate(
    33,
    (i) => PoseLandmark(index: i, x: 0.5, y: 0.5, z: 0.0, visibility: 0.1),
  );

  lms[PoseLandmark.leftShoulder] =
      px(PoseLandmark.leftShoulder, midShX - halfShoulderPx, midShY);
  lms[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, midShX + halfShoulderPx, midShY);
  lms[PoseLandmark.leftHip] = px(PoseLandmark.leftHip, hipCenterX - 70, hipY);
  lms[PoseLandmark.rightHip] = px(PoseLandmark.rightHip, hipCenterX + 70, hipY);
  lms[PoseLandmark.leftKnee] =
      px(PoseLandmark.leftKnee, baseKneeX - kneeSpreadHalfPx, kneeY);
  lms[PoseLandmark.rightKnee] =
      px(PoseLandmark.rightKnee, baseKneeX + kneeSpreadHalfPx, kneeY);
  lms[PoseLandmark.leftAnkle] =
      px(PoseLandmark.leftAnkle, baseAnkleX - ankleSpreadHalfPx, ankleY);
  lms[PoseLandmark.rightAnkle] =
      px(PoseLandmark.rightAnkle, baseAnkleX + ankleSpreadHalfPx, ankleY);
  return lms;
}

List<Map<String, dynamic>> _buildFrontalPushUpLandmarkMaps({
  required double elbowAngleDeg,
}) {
  // Low frontal camera viewing plank:
  // midShoulder = (540, 600), midHip = (540, 660) => torsoHeightPx = 60px,
  // shoulderWidthPx = 280px => ratio = 4.67 >= 0.58 (frontal).
  // Per-side hip shifted outward vs shoulder => torsoLeanDeg ~ 65 deg (>= 45),
  // shoulder->hip->ankle nearly collinear (~180 deg >= 155).
  const shY = 600.0;
  const hipY = 660.0;
  const ankY = 720.0;
  const seg = 110.0;
  final rad = elbowAngleDeg * math.pi / 180.0;

  Map<String, dynamic> lm(int index, double xPx, double yPx) => {
        'index': index,
        'x': (xPx / _imgW).clamp(0.0, 1.0),
        'y': (yPx / _imgH).clamp(0.0, 1.0),
        'z': 0.0,
        'visibility': 0.95,
      };

  final list = List.generate(
    33,
    (i) => <String, dynamic>{
      'index': i,
      'x': 0.5,
      'y': 0.5,
      'z': 0.0,
      'visibility': 0.1,
    },
  );
  list[PoseLandmark.leftShoulder] = lm(PoseLandmark.leftShoulder, 400.0, shY);
  list[PoseLandmark.rightShoulder] = lm(PoseLandmark.rightShoulder, 680.0, shY);
  list[PoseLandmark.leftHip] = lm(PoseLandmark.leftHip, 520.0, hipY);
  list[PoseLandmark.rightHip] = lm(PoseLandmark.rightHip, 560.0, hipY);
  list[PoseLandmark.leftAnkle] = lm(PoseLandmark.leftAnkle, 640.0, ankY);
  list[PoseLandmark.rightAnkle] = lm(PoseLandmark.rightAnkle, 440.0, ankY);

  list[PoseLandmark.leftElbow] =
      lm(PoseLandmark.leftElbow, 400.0, shY + seg);
  list[PoseLandmark.leftWrist] = lm(
    PoseLandmark.leftWrist,
    400.0 - seg * math.sin(rad),
    shY + seg - seg * math.cos(rad),
  );
  list[PoseLandmark.rightElbow] =
      lm(PoseLandmark.rightElbow, 680.0, shY + seg);
  list[PoseLandmark.rightWrist] = lm(
    PoseLandmark.rightWrist,
    680.0 + seg * math.sin(rad),
    shY + seg - seg * math.cos(rad),
  );
  return list;
}

void main() {
  group('1. PullUpBaseline Multi-Angle (0 / 45 / 90 deg)', () {
    test('counts clean rep at frontal (0°), oblique45 (45°), and side90 (90°) with 2D compensation', () {
      // Frontal (0°): flexion offset = +12 (flexed <= 77), extension offset = -8 (extended >= 107)
      final frontalTracker = PullUpBaseline();
      const frontalCycle = <(int, double)>[
        (0, 110.0),
        (250, 110.0),
        (500, 92.0),
        (850, 72.0),
        (1200, 92.0),
        (1550, 102.0),
        (1850, 110.0),
        (2050, 110.0), // duration 1550ms >= 1500ms
      ];
      for (var i = 0; i < frontalCycle.length; i++) {
        final (t, angle) = frontalCycle[i];
        frontalTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isChinCleared: true,
          viewAngle: CameraViewAngle.frontal,
        );
      }
      expect(frontalTracker.completedReps, 1);
      expect(frontalTracker.repHistory.single.viewAngle, CameraViewAngle.frontal);
      expect(frontalTracker.repHistory.single.issueCode, isNull);

      // Oblique45 (45°): flexion offset = +6 (flexed <= 71), extension offset = -4 (extended >= 111)
      final obliqueTracker = PullUpBaseline();
      const obliqueCycle = <(int, double)>[
        (0, 114.0),
        (250, 114.0),
        (500, 90.0),
        (900, 68.0),
        (1300, 92.0),
        (1650, 105.0),
        (1850, 114.0),
        (2050, 114.0),
      ];
      for (var i = 0; i < obliqueCycle.length; i++) {
        final (t, angle) = obliqueCycle[i];
        obliqueTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isChinCleared: true,
          viewAngle: CameraViewAngle.oblique45,
        );
      }
      expect(obliqueTracker.completedReps, 1);
      expect(obliqueTracker.repHistory.single.viewAngle, CameraViewAngle.oblique45);
      expect(obliqueTracker.repHistory.single.issueCode, isNull);

      // Side90 (90°): exact angles (flexed <= 65, extended >= 115)
      final sideTracker = PullUpBaseline();
      const sideCycle = <(int, double)>[
        (0, 165.0),
        (250, 165.0),
        (500, 95.0),
        (900, 58.0),
        (1300, 95.0),
        (1650, 112.0),
        (1900, 160.0),
        (2100, 165.0),
      ];
      for (var i = 0; i < sideCycle.length; i++) {
        final (t, angle) = sideCycle[i];
        sideTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isChinCleared: true,
          viewAngle: CameraViewAngle.side90,
        );
      }
      expect(sideTracker.completedReps, 1);
      expect(sideTracker.repHistory.single.viewAngle, CameraViewAngle.side90);
      expect(sideTracker.repHistory.single.issueCode, isNull);
    });

    test('detects chinNotCleared, tooFast, and incompleteLockout in side90', () {
      // chinNotCleared
      final chinTracker = PullUpBaseline();
      const chinFailCycle = <(int, double)>[
        (0, 165.0),
        (250, 165.0),
        (500, 95.0),
        (900, 60.0),
        (1300, 95.0),
        (1650, 140.0),
        (1900, 165.0),
        (2100, 165.0),
      ];
      for (var i = 0; i < chinFailCycle.length; i++) {
        final (t, angle) = chinFailCycle[i];
        chinTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isChinCleared: false,
          viewAngle: CameraViewAngle.oblique45,
        );
      }
      expect(chinTracker.completedReps, 1);
      expect(chinTracker.repHistory.single.issueCode, 'chinNotCleared');

      // tooFast (< 1500ms, >= 900ms minRepDurationMs)
      final fastTracker = PullUpBaseline();
      const fastCycle = <(int, double)>[
        (0, 165.0),
        (250, 165.0),
        (500, 95.0),
        (800, 58.0),
        (1100, 95.0),
        (1450, 165.0),
        (1650, 165.0), // duration = 1150ms < 1500ms
      ];
      for (var i = 0; i < fastCycle.length; i++) {
        final (t, angle) = fastCycle[i];
        fastTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isChinCleared: true,
          viewAngle: CameraViewAngle.frontal,
        );
      }
      expect(fastTracker.completedReps, 1);
      expect(fastTracker.repHistory.single.issueCode, 'tooFast');

      // incompleteLockout in side90 (returns to 122° >= 115° but < 130°)
      final lockoutTracker = PullUpBaseline();
      const incompleteLockoutCycle = <(int, double)>[
        (0, 165.0),
        (250, 165.0),
        (500, 95.0),
        (900, 55.0),
        (1300, 95.0),
        (1650, 112.0),
        (1900, 122.0),
        (2100, 122.0), // duration = 1600ms, minAngle = 55°, maxReturn = 122° < 130°
      ];
      for (var i = 0; i < incompleteLockoutCycle.length; i++) {
        final (t, angle) = incompleteLockoutCycle[i];
        lockoutTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isChinCleared: true,
          viewAngle: CameraViewAngle.side90,
        );
      }
      expect(lockoutTracker.completedReps, 1);
      expect(lockoutTracker.repHistory.single.issueCode, 'incompleteLockout');
    });
  });

  group('2. LatPulldownBaseline Multi-Angle (0 / 45 / 90 deg)', () {
    test('counts clean rep across frontal, oblique45, and side90 with 2D compensation & side-locking', () {
      for (final entry in <(CameraViewAngle, double, double)>[
        // (viewAngle, extendedAngle, bottomAngle)
        (CameraViewAngle.frontal, 100.0, 48.0), // effectiveFlexed=67, <45+12=57
        (CameraViewAngle.oblique45, 103.0, 46.0), // effectiveFlexed=61, <45+6=51
        (CameraViewAngle.side90, 115.0, 42.0), // effectiveFlexed=55, <45
      ]) {
        final (angleMode, extDeg, botDeg) = entry;
        final tracker = LatPulldownBaseline();
        final cycle = <(int, double)>[
          (0, extDeg),
          (250, extDeg),
          (500, 85.0),
          (900, 62.0),
          (1200, botDeg),
          (1550, 75.0),
          (1950, 92.0),
          (2350, extDeg),
          (2550, extDeg), // duration = 2050ms >= 2000ms
        ];
        for (var i = 0; i < cycle.length; i++) {
          final (t, elbow) = cycle[i];
          tracker.processSample(
            frameIndex: i,
            timestampMs: t,
            elbowAngleDeg: elbow,
            torsoLeanDeg: 15.0,
            viewAngle: angleMode,
            isSampleValid: true,
          );
        }
        expect(tracker.completedReps, 1, reason: 'Failed for $angleMode');
        expect(tracker.repHistory.single.viewAngle, angleMode);
        expect(tracker.repHistory.single.issueCode, isNull);
      }

      // Side-locking in oblique45 via LatPulldownFrameFeatures: keeps left side until right exceeds by >= 0.12
      final lockTracker = LatPulldownBaseline();
      LatPulldownFrameFeatures makeFrame(
        int idx,
        int t,
        double leftAngle,
        double rightAngle,
        double leftVis,
        double rightVis,
      ) {
        return LatPulldownFrameFeatures(
          frameIndex: idx,
          timestampMs: t,
          isGateDetecting: true,
          shoulderWidthPx: const MotionMeasurement.valid(200.0),
          viewAngle: CameraViewAngle.oblique45,
          torsoLeanDeg: const MotionMeasurement.valid(12.0),
          leftSide: LatPulldownSideFeatures(
            sideKey: 'model_left_11_13_15',
            shoulderId: 11,
            elbowId: 13,
            wristId: 15,
            elbowAngleDeg: MotionMeasurement.valid(leftAngle),
            elbowVisibilityScore: leftVis,
            wristRelY: const MotionMeasurement.valid(-0.2),
            wristRelX: const MotionMeasurement.valid(0.0),
            wristDistance: const MotionMeasurement.valid(1.0),
          ),
          rightSide: LatPulldownSideFeatures(
            sideKey: 'model_right_12_14_16',
            shoulderId: 12,
            elbowId: 14,
            wristId: 16,
            elbowAngleDeg: MotionMeasurement.valid(rightAngle),
            elbowVisibilityScore: rightVis,
            wristRelY: const MotionMeasurement.valid(-0.2),
            wristRelX: const MotionMeasurement.valid(0.0),
            wristDistance: const MotionMeasurement.valid(1.0),
          ),
        );
      }

      // Initial frame picks left (0.85 > 0.70)
      final r0 = lockTracker.processFrameFeatures(
        makeFrame(0, 0, 115.0, 170.0, 0.85, 0.70),
      );
      expect(r0.elbowAngleDeg, 115.0);
      // Right momentarily slightly higher (+0.08 < 0.12) -> remains locked on left (115.0)
      final r1 = lockTracker.processFrameFeatures(
        makeFrame(1, 50, 115.0, 170.0, 0.72, 0.80),
      );
      expect(r1.elbowAngleDeg, 115.0);
    });

    test('flags torsoLean (> 35°) and tooFast (< 2000ms)', () {
      final leanTracker = LatPulldownBaseline();
      const leanCycle = <(int, double, double)>[
        (0, 115.0, 10.0),
        (250, 115.0, 10.0),
        (500, 85.0, 28.0),
        (900, 60.0, 36.0),
        (1200, 42.0, 42.0), // > 35° lean
        (1600, 75.0, 25.0),
        (2000, 95.0, 15.0),
        (2350, 115.0, 10.0),
        (2550, 115.0, 10.0),
      ];
      for (var i = 0; i < leanCycle.length; i++) {
        final (t, elbow, lean) = leanCycle[i];
        leanTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: lean,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(leanTracker.completedReps, 1);
      expect(leanTracker.repHistory.single.issueCode, 'torsoLean');

      final fastTracker = LatPulldownBaseline();
      const fastCycle = <(int, double)>[
        (0, 115.0),
        (250, 115.0),
        (500, 80.0),
        (900, 42.0),
        (1300, 85.0),
        (1700, 115.0),
        (1900, 115.0), // duration = 1400ms < 2000ms
      ];
      for (var i = 0; i < fastCycle.length; i++) {
        final (t, elbow) = fastCycle[i];
        fastTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 10.0,
          viewAngle: CameraViewAngle.oblique45,
          isSampleValid: true,
        );
      }
      expect(fastTracker.completedReps, 1);
      expect(fastTracker.repHistory.single.issueCode, 'tooFast');
    });
  });

  group('3. SquatBaseline Multi-Angle (0 / 45 / 90 deg)', () {
    test('frontal (0°) reaches bottom via hipBelowKneeNorm even with compressed 2D knee angle (120°) and catches kneeValgus', () {
      // Good frontal squat using hipBelowKneeNorm >= -0.08 with kneeAngleDeg = 120°
      final frontalClean = SquatBaseline();
      const frontalCycle = <(int, double, double, double, double)>[
        // (t, knee, hip, lean, hipBelowKneeNorm)
        (0, 170.0, 170.0, 6.0, -0.85),
        (250, 170.0, 170.0, 6.0, -0.85),
        (500, 134.0, 128.0, 14.0, -0.35),
        (900, 122.0, 110.0, 18.0, 0.04), // bottom via hipBelowKneeNorm >= -0.08 & knee <= 135
        (1250, 120.0, 108.0, 18.0, 0.08),
        (1650, 138.0, 140.0, 12.0, -0.30),
        (2050, 165.0, 165.0, 6.0, -0.80),
        (2250, 170.0, 170.0, 6.0, -0.85),
      ];
      for (var i = 0; i < frontalCycle.length; i++) {
        final (t, knee, hip, lean, hipBelow) = frontalCycle[i];
        frontalClean.processSample(
          frameIndex: i,
          timestampMs: t,
          kneeAngleDeg: knee,
          hipAngleDeg: hip,
          torsoLeanDeg: lean,
          kneeValgusRatio: 0.92,
          hipBelowKneeNorm: hipBelow,
          viewAngle: CameraViewAngle.frontal,
          isSampleValid: true,
        );
      }
      expect(frontalClean.completedReps, 1);
      expect(frontalClean.repHistory.single.viewAngle, CameraViewAngle.frontal);
      expect(frontalClean.repHistory.single.isKneeValgus, isFalse);
      expect(frontalClean.repHistory.single.issueCode, isNull);

      // Knee valgus at frontal (0°): kneeWidth / ankleWidth < 0.78 via extractSquatFeatures
      final valgusTracker = SquatBaseline();
      final valgusFrames = <(int, double, double, double, double, double?, double?)>[
        (0, 170.0, 170.0, 6.0, 1.0, null, null),
        (250, 170.0, 170.0, 6.0, 1.0, null, null),
        (500, 130.0, 120.0, 15.0, 0.82, null, null),
        (900, 105.0, 95.0, 20.0, 0.55, 0.58, 0.54), // valgus ratio ~0.55 < 0.78, hip below knee
        (1350, 132.0, 125.0, 14.0, 0.80, null, null),
        (1750, 158.0, 158.0, 8.0, 1.0, null, null),
        (1950, 170.0, 170.0, 6.0, 1.0, null, null),
      ];
      for (var i = 0; i < valgusFrames.length; i++) {
        final (t, knee, hip, lean, kneeFactor, hipY, kneeY) = valgusFrames[i];
        final lms = _buildSquatPoseLandmarks(
          shoulderWidthNorm: 0.28,
          kneeAngleDeg: knee,
          hipAngleDeg: hip,
          torsoLeanDeg: lean,
          kneeWidthFactor: kneeFactor,
          overrideHipYNorm: hipY,
          overrideKneeYNorm: kneeY,
        );
        final feat = WorkoutCvMotionFeatures.extractSquatFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: lms,
          imageWidth: _imgW,
          imageHeight: _imgH,
          viewAngle: CameraViewAngle.frontal,
        );
        valgusTracker.processSquatFeatures(feat);
      }
      expect(valgusTracker.completedReps, 1);
      expect(valgusTracker.repHistory.single.isKneeValgus, isTrue);
      expect(valgusTracker.repHistory.single.issueCode, 'kneeValgus');
    });

    test('oblique45 (45°) & side90 (90°) count valid reps and flag torsoLean / shallowDepth', () {
      // Oblique45 clean rep with 99° knee angle (valid with +6° offset => <= 101°)
      final obliqueClean = SquatBaseline();
      const obliqueCycle = <(int, double, double, double)>[
        (0, 170.0, 170.0, 8.0),
        (250, 170.0, 170.0, 8.0),
        (500, 130.0, 125.0, 18.0),
        (900, 112.0, 108.0, 22.0),
        (1200, 99.0, 92.0, 26.0),
        (1600, 130.0, 125.0, 18.0),
        (2000, 165.0, 165.0, 8.0),
        (2200, 170.0, 170.0, 8.0),
      ];
      for (var i = 0; i < obliqueCycle.length; i++) {
        final (t, knee, hip, lean) = obliqueCycle[i];
        obliqueClean.processSample(
          frameIndex: i,
          timestampMs: t,
          kneeAngleDeg: knee,
          hipAngleDeg: hip,
          torsoLeanDeg: lean,
          viewAngle: CameraViewAngle.oblique45,
          isSampleValid: true,
        );
      }
      expect(obliqueClean.completedReps, 1);
      expect(obliqueClean.repHistory.single.issueCode, isNull);

      // Side90 clean rep
      final sideClean = SquatBaseline();
      const sideCycle = <(int, double, double, double)>[
        (0, 170.0, 170.0, 8.0),
        (250, 170.0, 170.0, 8.0),
        (500, 130.0, 125.0, 18.0),
        (900, 105.0, 98.0, 22.0),
        (1200, 86.0, 82.0, 26.0),
        (1600, 128.0, 120.0, 18.0),
        (2000, 165.0, 165.0, 8.0),
        (2200, 170.0, 170.0, 8.0),
      ];
      for (var i = 0; i < sideCycle.length; i++) {
        final (t, knee, hip, lean) = sideCycle[i];
        sideClean.processSample(
          frameIndex: i,
          timestampMs: t,
          kneeAngleDeg: knee,
          hipAngleDeg: hip,
          torsoLeanDeg: lean,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(sideClean.completedReps, 1);
      expect(sideClean.repHistory.single.issueCode, isNull);

      // Side90 torsoLean (> 55°)
      final leanTracker = SquatBaseline();
      const leanCycle = <(int, double, double, double)>[
        (0, 170.0, 170.0, 10.0),
        (250, 170.0, 170.0, 10.0),
        (500, 128.0, 115.0, 42.0),
        (900, 100.0, 85.0, 56.0),
        (1200, 88.0, 75.0, 62.0),
        (1600, 125.0, 115.0, 40.0),
        (2000, 165.0, 165.0, 10.0),
        (2200, 170.0, 170.0, 10.0),
      ];
      for (var i = 0; i < leanCycle.length; i++) {
        final (t, knee, hip, lean) = leanCycle[i];
        leanTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          kneeAngleDeg: knee,
          hipAngleDeg: hip,
          torsoLeanDeg: lean,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(leanTracker.completedReps, 1);
      expect(leanTracker.repHistory.single.issueCode, 'torsoLean');

      // Side90 shallowDepth (98° <= 100° bottomEnterDeg, > 95° standard)
      final shallowTracker = SquatBaseline();
      const shallowCycle = <(int, double, double, double)>[
        (0, 170.0, 170.0, 10.0),
        (250, 170.0, 170.0, 10.0),
        (500, 128.0, 120.0, 22.0),
        (900, 105.0, 100.0, 26.0),
        (1200, 98.0, 95.0, 28.0),
        (1600, 125.0, 120.0, 20.0),
        (2000, 165.0, 165.0, 10.0),
        (2200, 170.0, 170.0, 10.0),
      ];
      for (var i = 0; i < shallowCycle.length; i++) {
        final (t, knee, hip, lean) = shallowCycle[i];
        shallowTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          kneeAngleDeg: knee,
          hipAngleDeg: hip,
          torsoLeanDeg: lean,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(shallowTracker.completedReps, 1);
      expect(shallowTracker.repHistory.single.issueCode, 'shallowDepth');
    });
  });

  group('4. PushUpBaseline Multi-Angle (45 / 90 deg + 0 deg warning)', () {
    test('counts clean rep at oblique45 and side90, and flags hipSag / tooFast', () {
      // Oblique45 clean rep with 98° elbow angle (valid with +6° => <= 101°)
      final obliqueTracker = PushUpBaseline();
      const obliqueCycle = <(int, double)>[
        (0, 160.0),
        (250, 160.0),
        (500, 125.0),
        (900, 98.0),
        (1350, 128.0),
        (1750, 155.0),
        (1950, 160.0),
      ];
      for (var i = 0; i < obliqueCycle.length; i++) {
        final (t, elbow) = obliqueCycle[i];
        final res = obliqueTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 80.0,
          bodyAlignmentDeg: 172.0,
          viewAngle: CameraViewAngle.oblique45,
          isSampleValid: true,
        );
        expect(res.isFrontalAngleWarning, isFalse);
      }
      expect(obliqueTracker.completedReps, 1);
      expect(obliqueTracker.repHistory.single.viewAngle, CameraViewAngle.oblique45);
      expect(obliqueTracker.repHistory.single.issueCode, isNull);

      // Side90 clean rep
      final sideTracker = PushUpBaseline();
      const sideCycle = <(int, double)>[
        (0, 168.0),
        (250, 168.0),
        (500, 125.0),
        (950, 86.0),
        (1400, 125.0),
        (1800, 162.0),
        (2000, 168.0),
      ];
      for (var i = 0; i < sideCycle.length; i++) {
        final (t, elbow) = sideCycle[i];
        sideTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 82.0,
          bodyAlignmentDeg: 174.0,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(sideTracker.completedReps, 1);
      expect(sideTracker.repHistory.single.issueCode, isNull);

      // hipSag (bodyAlignment < 155°)
      final sagTracker = PushUpBaseline();
      const sagCycle = <(int, double, double)>[
        (0, 168.0, 168.0),
        (250, 168.0, 168.0),
        (500, 125.0, 152.0),
        (950, 88.0, 140.0),
        (1400, 125.0, 150.0),
        (1800, 162.0, 166.0),
        (2000, 168.0, 168.0),
      ];
      for (var i = 0; i < sagCycle.length; i++) {
        final (t, elbow, align) = sagCycle[i];
        sagTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 80.0,
          bodyAlignmentDeg: align,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(sagTracker.completedReps, 1);
      expect(sagTracker.repHistory.single.issueCode, 'hipSag');

      // tooFast (< 1200ms, >= 800ms minRepDurationMs)
      final fastTracker = PushUpBaseline();
      const fastCycle = <(int, double)>[
        (0, 168.0),
        (250, 168.0),
        (500, 120.0),
        (750, 88.0),
        (1000, 128.0),
        (1250, 162.0),
        (1450, 168.0), // duration = 950ms < 1200ms
      ];
      for (var i = 0; i < fastCycle.length; i++) {
        final (t, elbow) = fastCycle[i];
        fastTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 82.0,
          bodyAlignmentDeg: 174.0,
          viewAngle: CameraViewAngle.oblique45,
          isSampleValid: true,
        );
      }
      expect(fastTracker.completedReps, 1);
      expect(fastTracker.repHistory.single.issueCode, 'tooFast');
    });

    test('sets isFrontalAngleWarning == true at frontal (0°) and tags completed rep with frontalAngleWarning', () {
      final frontalTracker = PushUpBaseline();
      const frontalCycle = <(int, double)>[
        (0, 155.0),
        (250, 155.0),
        (500, 125.0),
        (950, 102.0), // reaches bottomEnterDeg + 12 = 112
        (1400, 132.0),
        (1800, 150.0),
        (2000, 155.0),
      ];
      for (var i = 0; i < frontalCycle.length; i++) {
        final (t, elbow) = frontalCycle[i];
        final res = frontalTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          torsoLeanDeg: 80.0,
          bodyAlignmentDeg: 174.0,
          viewAngle: CameraViewAngle.frontal,
          isSampleValid: true,
        );
        expect(res.isFrontalAngleWarning, isTrue);
      }
      expect(frontalTracker.completedReps, 1);
      expect(frontalTracker.repHistory.single.issueCode, 'frontalAngleWarning');
    });
  });

  group('5. BicepCurlBaseline Multi-Angle (0 / 45 / 90 deg)', () {
    test('counts clean rep at frontal, oblique45, and side90 and flags elbowSwing / torsoLean', () {
      for (final entry in <(CameraViewAngle, double, double)>[
        (CameraViewAngle.frontal, 140.0, 68.0), // flexed<=72, <60+12=72
        (CameraViewAngle.oblique45, 144.0, 63.0), // flexed<=66, <60+6=66
        (CameraViewAngle.side90, 160.0, 50.0), // flexed<=60, <60
      ]) {
        final (angleMode, extDeg, peakDeg) = entry;
        final tracker = BicepCurlBaseline();
        final cycle = <(int, double)>[
          (0, extDeg),
          (250, extDeg),
          (500, 118.0),
          (900, 82.0),
          (1200, peakDeg),
          (1600, 118.0),
          (2000, extDeg),
          (2200, extDeg), // duration = 1700ms >= 1500ms
        ];
        for (var i = 0; i < cycle.length; i++) {
          final (t, elbow) = cycle[i];
          tracker.processSample(
            frameIndex: i,
            timestampMs: t,
            elbowAngleDeg: elbow,
            upperArmSwingDeg: 10.0,
            torsoLeanDeg: 8.0,
            viewAngle: angleMode,
            isSampleValid: true,
          );
        }
        expect(tracker.completedReps, 1, reason: 'Failed for $angleMode');
        expect(tracker.repHistory.single.viewAngle, angleMode);
        expect(tracker.repHistory.single.issueCode, isNull);
      }

      // elbowSwing (> 35°)
      final swingTracker = BicepCurlBaseline();
      const swingCycle = <(int, double, double)>[
        (0, 160.0, 10.0),
        (250, 160.0, 10.0),
        (500, 118.0, 30.0),
        (900, 80.0, 40.0),
        (1200, 52.0, 48.0),
        (1600, 118.0, 25.0),
        (2000, 160.0, 10.0),
        (2200, 160.0, 10.0),
      ];
      for (var i = 0; i < swingCycle.length; i++) {
        final (t, elbow, swing) = swingCycle[i];
        swingTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          upperArmSwingDeg: swing,
          torsoLeanDeg: 8.0,
          viewAngle: CameraViewAngle.side90,
          isSampleValid: true,
        );
      }
      expect(swingTracker.completedReps, 1);
      expect(swingTracker.repHistory.single.issueCode, 'elbowSwing');

      // torsoLean (> 25°)
      final leanTracker = BicepCurlBaseline();
      const leanCycle = <(int, double, double)>[
        (0, 160.0, 6.0),
        (250, 160.0, 6.0),
        (500, 118.0, 18.0),
        (900, 80.0, 26.0),
        (1200, 52.0, 32.0),
        (1600, 118.0, 16.0),
        (2000, 160.0, 6.0),
        (2200, 160.0, 6.0),
      ];
      for (var i = 0; i < leanCycle.length; i++) {
        final (t, elbow, lean) = leanCycle[i];
        leanTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: elbow,
          upperArmSwingDeg: 10.0,
          torsoLeanDeg: lean,
          viewAngle: CameraViewAngle.oblique45,
          isSampleValid: true,
        );
      }
      expect(leanTracker.completedReps, 1);
      expect(leanTracker.repHistory.single.issueCode, 'torsoLean');
    });
  });

  group('6. AngleSmoother Spike Suppression & Controller Multi-Angle Integration', () {
    test('enableAngleSmoothing: true suppresses 1-frame jitter spike and still counts exact rep', () {
      final smoothedTracker = LatPulldownBaseline(
        config: const LatPulldownBaselineConfig(
          enableAngleSmoothing: true,
          smoothingAlpha: 0.50,
        ),
      );
      final strictSpikeTracker = LatPulldownBaseline(
        config: const LatPulldownBaselineConfig(
          enableAngleSmoothing: true,
          smoothingAlpha: 0.35,
        ),
      );

      final samples = <(int, double)>[
        (0, 115.0),
        (100, 115.0),
        (220, 115.0), // readyHoldSatisfied -> extended
        (260, 75.0), // 1-frame spike! 0.35*75 + 0.65*115 = 101.0 >= 95 -> suppressed!
        (300, 115.0),
        (400, 115.0),
      ];
      for (var i = 0; i < samples.length; i++) {
        final (t, angle) = samples[i];
        final res = strictSpikeTracker.processSample(
          frameIndex: i,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
        );
        if (i >= 2) {
          expect(res.phase, LatPulldownPhase.extended);
        }
      }
      expect(strictSpikeTracker.completedReps, 0);

      // Smooth 25Hz rep with a 1-frame noisy spike mid-bottom
      var fIdx = 0;
      for (var t = 0; t <= 300; t += 40) {
        smoothedTracker.processSample(
          frameIndex: fIdx++,
          timestampMs: t,
          elbowAngleDeg: 118.0,
          isSampleValid: true,
        );
      }
      expect(smoothedTracker.phase, LatPulldownPhase.extended);

      for (var t = 340; t <= 1220; t += 40) {
        final frac = (t - 340) / 880.0;
        var angle = 118.0 - 78.0 * frac;
        if (t == 1140) angle = 85.0; // single noisy spike at bottom!
        smoothedTracker.processSample(
          frameIndex: fIdx++,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
        );
      }
      expect(smoothedTracker.phase, LatPulldownPhase.flexed);

      for (var t = 1260; t <= 2600; t += 40) {
        final frac = ((t - 1260) / 1000.0).clamp(0.0, 1.0);
        final angle = 40.0 + 78.0 * frac;
        smoothedTracker.processSample(
          frameIndex: fIdx++,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
        );
      }
      expect(smoothedTracker.completedReps, 1);
    });

    test('WorkoutCvNotifier updates detectedViewAngle, repRecords, and frontal Push-up warning', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'push-up',
        exerciseSlug: 'push-up',
      );

      const cycle = <(int, double)>[
        (0, 158.0),
        (120, 158.0),
        (240, 158.0), // 3rd consecutive frontal frame confirms CameraViewAngle.frontal
        (500, 125.0),
        (900, 102.0),
        (1350, 130.0),
        (1750, 152.0),
        (1950, 158.0),
      ];

      for (final (t, elbow) in cycle) {
        source.emitEvent({
          'status': 'detecting',
          'sessionGen': 1,
          'sourceMode': 'camera',
          'timestamp': t,
          'latencyMs': 15,
          'numPoses': 1,
          'landmarks': _buildFrontalPushUpLandmarkMaps(elbowAngleDeg: elbow),
          'inputImageWidth': _imgW,
          'inputImageHeight': _imgH,
        });
        await Future<void>.delayed(Duration.zero);
      }

      expect(controller.state.detectedViewAngle, CameraViewAngle.frontal);
      expect(
        controller.state.guideMessage,
        'Frontal angle limits depth tracking. Place camera at a 45° angle.',
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.repRecords, hasLength(1));

      final rec = controller.state.repRecords.single;
      expect(rec.repIndex, 1);
      expect(rec.viewAngle, CameraViewAngle.frontal);
      expect(rec.issueType, RepIssueType.frontalAngleWarning);
      expect(rec.isValid, isFalse);

      controller.dispose();
      source.dispose();
    });
  });
}

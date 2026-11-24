import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';

void main() {
  group('WorkoutCvMotionFeatures Unit Tests', () {
    // Helper to generate a full 33-landmark skeleton with default valid landmarks
    List<PoseLandmark> createTestLandmarks({
      Map<int, Map<String, dynamic>> overrides = const {},
    }) {
      return List.generate(33, (i) {
        if (overrides.containsKey(i)) {
          final o = overrides[i]!;
          return PoseLandmark(
            index: i,
            x: (o['x'] as num?)?.toDouble() ?? 0.5,
            y: (o['y'] as num?)?.toDouble() ?? 0.5,
            z: (o['z'] as num?)?.toDouble() ?? 0.0,
            visibility: (o['visibility'] as num?)?.toDouble() ?? 0.9,
          );
        }
        return PoseLandmark(
          index: i,
          x: 0.5,
          y: 0.5,
          z: 0.0,
          visibility: 0.9,
        );
      });
    }

    test(
        '1. Calculates exact 90-degree right angle in pixel space on non-square 1080x1920 image',
        () {
      // In a 1080x1920 image:
      // Elbow at center: (540 px, 960 px) -> normalized (0.5, 0.5)
      // Shoulder directly above elbow by 384 px:
      //   Shoulder y = 960 - 384 = 576 px -> normalized y = 576 / 1920 = 0.3
      //   Shoulder x = 540 px -> normalized x = 0.5
      // Wrist directly to the right of elbow by 384 px:
      //   Wrist x = 540 + 384 = 924 px -> normalized x = 924 / 1080 = 0.855555...
      //   Wrist y = 960 px -> normalized y = 0.5
      // In pixel space: Vector 1 = (0, -384), Vector 2 = (384, 0) -> Angle must be exactly 90.0 degrees!
      final landmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.5, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {'x': 0.2, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.leftElbow: {'x': 0.5, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.leftWrist: {
            'x': 924.0 / 1080.0,
            'y': 0.5,
            'visibility': 0.95
          },
        },
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
        isGateDetecting: true,
      );

      expect(features.leftSide.elbowAngleDeg.isValid, isTrue);
      expect(features.leftSide.elbowAngleDeg.value, closeTo(90.0, 1e-4));
    });

    test(
        '2. Calculates 180-degree straight arm and 45-degree acute angle accurately',
        () {
      // 180 deg straight arm: Shoulder at (540, 500), Elbow at (540, 700), Wrist at (540, 900)
      final straightLandmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {
            'x': 0.5,
            'y': 500.0 / 1000.0,
            'visibility': 0.95
          },
          PoseLandmark.rightShoulder: {
            'x': 0.2,
            'y': 500.0 / 1000.0,
            'visibility': 0.95
          },
          PoseLandmark.leftElbow: {
            'x': 0.5,
            'y': 700.0 / 1000.0,
            'visibility': 0.95
          },
          PoseLandmark.leftWrist: {
            'x': 0.5,
            'y': 900.0 / 1000.0,
            'visibility': 0.95
          },
        },
      );

      final straightFeatures =
          WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 1,
        timestampMs: 200,
        landmarks: straightLandmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
      );

      expect(straightFeatures.leftSide.elbowAngleDeg.isValid, isTrue);
      expect(
          straightFeatures.leftSide.elbowAngleDeg.value, closeTo(180.0, 1e-4));

      // 45 deg acute angle:
      // Elbow at (500, 500)
      // Shoulder at (500, 300) -> vector (0, -200)
      // Wrist at (500 + 200*sin(45), 500 - 200*cos(45)) -> vector (200*0.7071, -200*0.7071)
      final cos45 = math.cos(math.pi / 4);
      final sin45 = math.sin(math.pi / 4);
      final acuteLandmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.5, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {'x': 0.2, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.leftElbow: {'x': 0.5, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.leftWrist: {
            'x': (500.0 + 200.0 * sin45) / 1000.0,
            'y': (500.0 - 200.0 * cos45) / 1000.0,
            'visibility': 0.95,
          },
        },
      );

      final acuteFeatures = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 2,
        timestampMs: 300,
        landmarks: acuteLandmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
      );

      expect(acuteFeatures.leftSide.elbowAngleDeg.isValid, isTrue);
      expect(acuteFeatures.leftSide.elbowAngleDeg.value, closeTo(45.0, 1e-4));
    });

    test(
        '3. Non-square aspect ratio without pixel transform would skew angles; verifies pixel-corrected angle',
        () {
      // In a 500x1000 image:
      // Normalized delta: Shoulder(0.4, 0.4), Elbow(0.5, 0.5), Wrist(0.6, 0.4)
      // Normalized vectors: (-0.1, -0.1) and (0.1, -0.1) -> Dot = -0.01 + 0.01 = 0 -> 90 degrees if uncorrected!
      // But in 500x1000 pixels:
      // Shoulder: (200, 400), Elbow: (250, 500), Wrist: (300, 400)
      // v1 = (-50, -100), v2 = (50, -100)
      // Dot = -2500 + 10000 = 7500
      // L1 = L2 = sqrt(2500 + 10000) = sqrt(12500) = 111.803
      // cos = 7500 / 12500 = 0.6 -> Angle = acos(0.6) = 53.13 degrees!
      final landmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.4, 'y': 0.4, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {'x': 0.1, 'y': 0.4, 'visibility': 0.95},
          PoseLandmark.leftElbow: {'x': 0.5, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.leftWrist: {'x': 0.6, 'y': 0.4, 'visibility': 0.95},
        },
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 3,
        timestampMs: 400,
        landmarks: landmarks,
        imageWidth: 500.0,
        imageHeight: 1000.0,
      );

      // Must calculate true 53.13 deg, NOT the distorted 90.0 deg
      expect(features.leftSide.elbowAngleDeg.isValid, isTrue);
      expect(features.leftSide.elbowAngleDeg.value, closeTo(53.13, 0.01));
    });

    test(
        '4. Missing required landmark returns invalid with missingLandmark failure reason and null value',
        () {
      // Only 10 landmarks provided (missing shoulders, elbows, wrists)
      final partialLandmarks = List.generate(
        10,
        (i) => PoseLandmark(index: i, x: 0.5, y: 0.5, z: 0.0, visibility: 0.9),
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 4,
        timestampMs: 500,
        landmarks: partialLandmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(features.leftSide.elbowAngleDeg.isValid, isFalse);
      expect(features.leftSide.elbowAngleDeg.value, isNull);
      expect(features.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.missingLandmark);
      expect(features.shoulderWidthPx.isValid, isFalse);
    });

    test(
        '5. Landmark outside image boundary returns outOfBoundsCoordinate failure reason',
        () {
      final landmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.5, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {'x': 0.2, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.leftElbow: {
            'x': 1.15,
            'y': 0.5,
            'visibility': 0.95
          }, // x > 1.0
          PoseLandmark.leftWrist: {'x': 0.8, 'y': 0.5, 'visibility': 0.95},
        },
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 5,
        timestampMs: 600,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(features.leftSide.elbowAngleDeg.isValid, isFalse);
      expect(features.leftSide.elbowAngleDeg.value, isNull);
      expect(features.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.outOfBoundsCoordinate);
    });

    test('6. Landmark with low visibility returns lowVisibility failure reason',
        () {
      final landmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.5, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {'x': 0.2, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.leftElbow: {
            'x': 0.5,
            'y': 0.5,
            'visibility': 0.20
          }, // vis < 0.45
          PoseLandmark.leftWrist: {'x': 0.8, 'y': 0.5, 'visibility': 0.95},
        },
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 6,
        timestampMs: 700,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(features.leftSide.elbowAngleDeg.isValid, isFalse);
      expect(features.leftSide.elbowAngleDeg.value, isNull);
      expect(features.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.lowVisibility);
    });

    test(
        '7. Degenerate denominators (zero shoulder width or zero segment length) return degenerateGeometry without crash',
        () {
      // Zero shoulder width: both shoulders at exact same coordinate
      final zeroShoulderLandmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.5, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {
            'x': 0.5,
            'y': 0.3,
            'visibility': 0.95
          }, // Exact same
          PoseLandmark.leftElbow: {'x': 0.5, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.leftWrist: {'x': 0.8, 'y': 0.5, 'visibility': 0.95},
        },
      );

      final featuresZeroShoulder =
          WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 7,
        timestampMs: 800,
        landmarks: zeroShoulderLandmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(featuresZeroShoulder.shoulderWidthPx.isValid, isFalse);
      expect(featuresZeroShoulder.shoulderWidthPx.failure,
          MotionMetricFailure.degenerateGeometry);
      expect(featuresZeroShoulder.leftSide.wristRelY.isValid, isFalse);
      expect(featuresZeroShoulder.leftSide.wristRelY.failure,
          MotionMetricFailure.degenerateGeometry);

      // Zero segment length: Elbow at exact same coordinate as shoulder
      final zeroSegmentLandmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.5, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.rightShoulder: {'x': 0.2, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.leftElbow: {
            'x': 0.5,
            'y': 0.5,
            'visibility': 0.95
          }, // Same as shoulder
          PoseLandmark.leftWrist: {'x': 0.8, 'y': 0.5, 'visibility': 0.95},
        },
      );

      final featuresZeroSegment =
          WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 8,
        timestampMs: 900,
        landmarks: zeroSegmentLandmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(featuresZeroSegment.leftSide.elbowAngleDeg.isValid, isFalse);
      expect(featuresZeroSegment.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.degenerateGeometry);
    });

    test(
        '8. When isGateDetecting is false, all motion features are marked gateNotDetecting',
        () {
      final validLandmarks = createTestLandmarks();

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 9,
        timestampMs: 1000,
        landmarks: validLandmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
        isGateDetecting:
            false, // E.g., status was needsSetup / lost / multiplePeople
      );

      expect(features.isGateDetecting, isFalse);
      expect(features.hasAnyValidSignal, isFalse);
      expect(features.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.gateNotDetecting);
      expect(features.rightSide.wristRelY.failure,
          MotionMetricFailure.gateNotDetecting);
    });

    test(
        '9. Deterministic behavior: Identical inputs produce identical outputs',
        () {
      final landmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {'x': 0.6, 'y': 0.35, 'visibility': 0.92},
          PoseLandmark.rightShoulder: {'x': 0.3, 'y': 0.36, 'visibility': 0.91},
          PoseLandmark.leftElbow: {'x': 0.7, 'y': 0.55, 'visibility': 0.88},
          PoseLandmark.rightElbow: {'x': 0.2, 'y': 0.54, 'visibility': 0.89},
          PoseLandmark.leftWrist: {'x': 0.65, 'y': 0.45, 'visibility': 0.85},
          PoseLandmark.rightWrist: {'x': 0.25, 'y': 0.46, 'visibility': 0.86},
        },
      );

      final run1 = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 10,
        timestampMs: 1100,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      final run2 = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 10,
        timestampMs: 1100,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(run1.leftSide.elbowAngleDeg.value,
          equals(run2.leftSide.elbowAngleDeg.value));
      expect(run1.rightSide.wristRelY.value,
          equals(run2.rightSide.wristRelY.value));
      expect(run1.shoulderWidthPx.value, equals(run2.shoulderWidthPx.value));
    });

    test(
        '10. Non-finite landmark coordinates (NaN or Infinity) return nonFiniteCoordinate failure',
        () {
      final nanLandmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {
            'x': double.nan,
            'y': 0.3,
            'visibility': 0.95
          },
          PoseLandmark.rightShoulder: {'x': 0.2, 'y': 0.3, 'visibility': 0.95},
          PoseLandmark.leftElbow: {'x': 0.5, 'y': 0.5, 'visibility': 0.95},
          PoseLandmark.leftWrist: {
            'x': 0.5,
            'y': double.infinity,
            'visibility': 0.95
          },
        },
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: nanLandmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(features.shoulderWidthPx.isValid, isFalse);
      expect(features.shoulderWidthPx.failure,
          MotionMetricFailure.nonFiniteCoordinate);
      expect(features.leftSide.elbowAngleDeg.isValid, isFalse);
      expect(features.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.nonFiniteCoordinate);
      expect(features.leftSide.wristRelY.isValid, isFalse);
    });

    test(
        '11. Non-positive or non-finite image dimensions return invalidImageDimensions failure',
        () {
      final landmarks = createTestLandmarks();

      final zeroWidthFeatures =
          WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 0.0,
        imageHeight: 1920.0,
      );
      expect(zeroWidthFeatures.shoulderWidthPx.failure,
          MotionMetricFailure.invalidImageDimensions);
      expect(zeroWidthFeatures.leftSide.elbowAngleDeg.failure,
          MotionMetricFailure.invalidImageDimensions);

      final nanHeightFeatures =
          WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: double.nan,
      );
      expect(nanHeightFeatures.shoulderWidthPx.failure,
          MotionMetricFailure.invalidImageDimensions);
    });

    test(
        '12. Wrist relative position and distance normalized by shoulder width accurately computed',
        () {
      // Shoulder width: left at (600, 400), right at (400, 400) -> width = 200 px
      // Left wrist at (600, 500) -> dy = (500 - 400)/200 = +0.5 (below shoulder), dx = 0.0, dist = 100/200 = 0.5
      final landmarks = createTestLandmarks(
        overrides: {
          PoseLandmark.leftShoulder: {
            'x': 600.0 / 1000.0,
            'y': 400.0 / 1000.0,
            'visibility': 0.95
          },
          PoseLandmark.rightShoulder: {
            'x': 400.0 / 1000.0,
            'y': 400.0 / 1000.0,
            'visibility': 0.95
          },
          PoseLandmark.leftElbow: {
            'x': 600.0 / 1000.0,
            'y': 450.0 / 1000.0,
            'visibility': 0.95
          },
          PoseLandmark.leftWrist: {
            'x': 600.0 / 1000.0,
            'y': 500.0 / 1000.0,
            'visibility': 0.95
          },
        },
      );

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
      );

      expect(features.shoulderWidthPx.isValid, isTrue);
      expect(features.shoulderWidthPx.value, closeTo(200.0, 1e-4));
      expect(features.leftSide.wristRelY.isValid, isTrue);
      expect(features.leftSide.wristRelY.value, closeTo(0.5, 1e-4));
      expect(features.leftSide.wristRelX.isValid, isTrue);
      expect(features.leftSide.wristRelX.value, closeTo(0.0, 1e-4));
      expect(features.leftSide.wristDistance.isValid, isTrue);
      expect(features.leftSide.wristDistance.value, closeTo(0.5, 1e-4));
    });
  });

  group('Phase 3 Multi-Angle Math & ViewAngleDetector Tests', () {
    List<PoseLandmark> buildTorsoLandmarks({
      required double shoulderWidthNorm,
      double torsoHeightNorm = 0.40,
      double visibility = 0.90,
    }) {
      final halfSh = shoulderWidthNorm / 2.0;
      const shoulderY = 0.30;
      final hipY = shoulderY + torsoHeightNorm;
      return List.generate(33, (i) {
        if (i == PoseLandmark.leftShoulder) {
          return PoseLandmark(
            index: i,
            x: 0.5 - halfSh,
            y: shoulderY,
            z: 0.0,
            visibility: visibility,
          );
        }
        if (i == PoseLandmark.rightShoulder) {
          return PoseLandmark(
            index: i,
            x: 0.5 + halfSh,
            y: shoulderY,
            z: 0.0,
            visibility: visibility,
          );
        }
        if (i == PoseLandmark.leftHip) {
          return PoseLandmark(
            index: i,
            x: 0.45,
            y: hipY,
            z: 0.0,
            visibility: visibility,
          );
        }
        if (i == PoseLandmark.rightHip) {
          return PoseLandmark(
            index: i,
            x: 0.55,
            y: hipY,
            z: 0.0,
            visibility: visibility,
          );
        }
        return PoseLandmark(
          index: i,
          x: 0.5,
          y: 0.5,
          z: 0.0,
          visibility: visibility,
        );
      });
    }

    test('detects frontal, oblique45, and side90 accurately in pixel space', () {
      // Square 1000x1000 image, torsoHeight = 400px:
      // frontal: shoulderWidth = 280px -> ratio = 0.70 (>= 0.58)
      final frontalLm = buildTorsoLandmarks(shoulderWidthNorm: 0.28);
      expect(
        ViewAngleDetector.computeShoulderToTorsoRatio(
          landmarks: frontalLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        closeTo(0.70, 1e-4),
      );

      // oblique45: shoulderWidth = 180px -> ratio = 0.45 (0.30 < 0.45 < 0.58)
      final obliqueLm = buildTorsoLandmarks(shoulderWidthNorm: 0.18);
      expect(
        ViewAngleDetector.computeShoulderToTorsoRatio(
          landmarks: obliqueLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        closeTo(0.45, 1e-4),
      );

      // side90: shoulderWidth = 80px -> ratio = 0.20 (<= 0.30)
      final sideLm = buildTorsoLandmarks(shoulderWidthNorm: 0.08);
      expect(
        ViewAngleDetector.computeShoulderToTorsoRatio(
          landmarks: sideLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        closeTo(0.20, 1e-4),
      );

      final detector = ViewAngleDetector();
      expect(detector.currentAngle, CameraViewAngle.unknown);

      // Confirm frontal after 3 consecutive frames
      for (int i = 0; i < 2; i++) {
        expect(
          detector.update(
            landmarks: frontalLm,
            imageWidth: 1000.0,
            imageHeight: 1000.0,
          ),
          CameraViewAngle.unknown,
        );
      }
      expect(
        detector.update(
          landmarks: frontalLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.frontal,
      );
      expect(detector.lastRatio, closeTo(0.70, 1e-4));

      // Transition to oblique45 after 3 consecutive frames
      for (int i = 0; i < 2; i++) {
        expect(
          detector.update(
            landmarks: obliqueLm,
            imageWidth: 1000.0,
            imageHeight: 1000.0,
          ),
          CameraViewAngle.frontal,
        );
      }
      expect(
        detector.update(
          landmarks: obliqueLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.oblique45,
      );

      // Transition to side90 after 3 consecutive frames
      for (int i = 0; i < 2; i++) {
        expect(
          detector.update(
            landmarks: sideLm,
            imageWidth: 1000.0,
            imageHeight: 1000.0,
          ),
          CameraViewAngle.oblique45,
        );
      }
      expect(
        detector.update(
          landmarks: sideLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.side90,
      );
    });

    test('hysteresis and confirmFrames prevent flicker on transient shoulder twist', () {
      // Hysteresis checks in classifyRatio:
      // frontal stays frontal between exit (0.50) and enter (0.58)
      expect(
        ViewAngleDetector.classifyRatio(0.54, current: CameraViewAngle.frontal),
        CameraViewAngle.frontal,
      );
      expect(
        ViewAngleDetector.classifyRatio(0.49, current: CameraViewAngle.frontal),
        CameraViewAngle.oblique45,
      );
      // side90 stays side90 between enter (0.30) and exit (0.36)
      expect(
        ViewAngleDetector.classifyRatio(0.34, current: CameraViewAngle.side90),
        CameraViewAngle.side90,
      );
      expect(
        ViewAngleDetector.classifyRatio(0.37, current: CameraViewAngle.side90),
        CameraViewAngle.oblique45,
      );

      final detector = ViewAngleDetector(confirmFrames: 3);
      final frontalLm = buildTorsoLandmarks(shoulderWidthNorm: 0.28); // 0.70
      final hysteresisLm = buildTorsoLandmarks(shoulderWidthNorm: 0.216); // 0.54
      final noisyObliqueLm = buildTorsoLandmarks(shoulderWidthNorm: 0.16); // 0.40

      // Establish frontal
      for (int i = 0; i < 3; i++) {
        detector.update(
          landmarks: frontalLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        );
      }
      expect(detector.currentAngle, CameraViewAngle.frontal);

      // Ratio inside hysteresis band (0.54) never switches even over many frames
      for (int i = 0; i < 5; i++) {
        expect(
          detector.update(
            landmarks: hysteresisLm,
            imageWidth: 1000.0,
            imageHeight: 1000.0,
          ),
          CameraViewAngle.frontal,
        );
      }

      // Single noisy frame in oblique45 zone (0.40) does NOT flip angle
      expect(
        detector.update(
          landmarks: noisyObliqueLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.frontal,
      );
      // Next frame back in frontal resets candidate streak
      expect(
        detector.update(
          landmarks: frontalLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.frontal,
      );
      // Two noisy frames still do NOT flip when confirmFrames == 3
      expect(
        detector.update(
          landmarks: noisyObliqueLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.frontal,
      );
      expect(
        detector.update(
          landmarks: noisyObliqueLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        CameraViewAngle.frontal,
      );
      expect(detector.currentAngle, CameraViewAngle.frontal);
    });

    test('returns null on missing landmarks or degenerate torso and resets cleanly', () {
      // Degenerate torso (< 10px): 0.005 * 1000 = 5px
      final degenerateLm = buildTorsoLandmarks(
        shoulderWidthNorm: 0.20,
        torsoHeightNorm: 0.005,
      );
      expect(
        ViewAngleDetector.computeShoulderToTorsoRatio(
          landmarks: degenerateLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        isNull,
      );

      // Low visibility (< 0.40)
      final lowVisLm = buildTorsoLandmarks(
        shoulderWidthNorm: 0.28,
        visibility: 0.25,
      );
      expect(
        ViewAngleDetector.computeShoulderToTorsoRatio(
          landmarks: lowVisLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        ),
        isNull,
      );

      final detector = ViewAngleDetector();
      final frontalLm = buildTorsoLandmarks(shoulderWidthNorm: 0.28);
      for (int i = 0; i < 3; i++) {
        detector.update(
          landmarks: frontalLm,
          imageWidth: 1000.0,
          imageHeight: 1000.0,
        );
      }
      expect(detector.currentAngle, CameraViewAngle.frontal);
      expect(detector.lastRatio, isNotNull);

      detector.reset();
      expect(detector.currentAngle, CameraViewAngle.unknown);
      expect(detector.lastRatio, isNull);
    });
  });

  group('AngleSmoother Unit Tests', () {
    test('smooths high-frequency oscillating noise causally with EMA', () {
      final smoother = AngleSmoother(alpha: 0.40, maxGapMs: 500);
      final rawSeries = [100.0, 120.0, 80.0, 120.0, 80.0, 120.0];
      final smoothed = <double>[];

      for (int i = 0; i < rawSeries.length; i++) {
        final v = smoother.smooth(
          timestampMs: i * 33,
          rawAngleDeg: rawSeries[i],
        );
        expect(v, isNotNull);
        smoothed.add(v!);
      }

      // First sample initializes directly to rawAngleDeg
      expect(smoothed[0], closeTo(100.0, 1e-6));
      // Second sample: 0.4 * 120 + 0.6 * 100 = 108.0
      expect(smoothed[1], closeTo(108.0, 1e-6));
      // Third sample: 0.4 * 80 + 0.6 * 108 = 96.8
      expect(smoothed[2], closeTo(96.8, 1e-6));

      // Peak-to-peak swing of smoothed output is strictly smaller than raw 40 deg oscillation
      const rawSwing = 120.0 - 80.0;
      final smoothedTail = smoothed.sublist(2);
      final smoothedSwing =
          smoothedTail.reduce(math.max) - smoothedTail.reduce(math.min);
      expect(smoothedSwing, lessThan(rawSwing * 0.5));
      expect(smoother.currentValue, equals(smoothed.last));
    });

    test('returns null for invalid samples without fabricating and resets after maxGapMs', () {
      final smoother = AngleSmoother(alpha: 0.40, maxGapMs: 500);

      expect(smoother.smooth(timestampMs: 100, rawAngleDeg: 150.0), 150.0);

      // Invalid samples return null immediately (never hold previous value)
      expect(smoother.smooth(timestampMs: 200, rawAngleDeg: null), isNull);
      expect(
        smoother.smooth(timestampMs: 250, rawAngleDeg: double.nan),
        isNull,
      );
      expect(
        smoother.smooth(timestampMs: 300, rawAngleDeg: double.infinity),
        isNull,
      );
      // Within maxGapMs (300 - 100 = 200 <= 500), internal state is still retained
      expect(smoother.currentValue, closeTo(150.0, 1e-6));

      // Invalid sample beyond maxGapMs (700 - 100 = 600 > 500) clears state
      expect(smoother.smooth(timestampMs: 700, rawAngleDeg: null), isNull);
      expect(smoother.currentValue, isNull);

      // Next valid sample re-initializes cleanly without blending 150.0
      expect(smoother.smooth(timestampMs: 733, rawAngleDeg: 60.0), 60.0);

      // Direct gap > maxGapMs between two valid samples also resets cleanly
      expect(smoother.smooth(timestampMs: 1400, rawAngleDeg: 170.0), 170.0);

      smoother.reset();
      expect(smoother.currentValue, isNull);
    });
  });

  group('ViewAngleProjectionHelper Unit Tests', () {
    test('returns expected 2D projection compensation offsets for all view angles', () {
      expect(ViewAngleProjectionHelper.elbowFlexionOffsetDeg(CameraViewAngle.side90), 0.0);
      expect(ViewAngleProjectionHelper.elbowFlexionOffsetDeg(CameraViewAngle.oblique45), 6.0);
      expect(ViewAngleProjectionHelper.elbowFlexionOffsetDeg(CameraViewAngle.frontal), 12.0);
      expect(ViewAngleProjectionHelper.elbowFlexionOffsetDeg(CameraViewAngle.unknown), 0.0);

      expect(ViewAngleProjectionHelper.kneeDepthOffsetDeg(CameraViewAngle.side90), 0.0);
      expect(ViewAngleProjectionHelper.kneeDepthOffsetDeg(CameraViewAngle.oblique45), 6.0);
      expect(ViewAngleProjectionHelper.kneeDepthOffsetDeg(CameraViewAngle.frontal), 15.0);
      expect(ViewAngleProjectionHelper.kneeDepthOffsetDeg(CameraViewAngle.unknown), 0.0);

      expect(ViewAngleProjectionHelper.elbowExtensionOffsetDeg(CameraViewAngle.side90), 0.0);
      expect(ViewAngleProjectionHelper.elbowExtensionOffsetDeg(CameraViewAngle.oblique45), -4.0);
      expect(ViewAngleProjectionHelper.elbowExtensionOffsetDeg(CameraViewAngle.frontal), -8.0);
      expect(ViewAngleProjectionHelper.elbowExtensionOffsetDeg(CameraViewAngle.unknown), 0.0);
    });

    test('selectBestLockedSide preserves locked side until opposite exceeds switchMargin', () {
      // Locked on left in side90; right slightly higher (+0.08 < 0.12) -> stay left
      expect(
        ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: 0.72,
          rightScore: 0.80,
          lockedSide: 'left',
          viewAngle: CameraViewAngle.side90,
          switchMargin: 0.12,
        ),
        'left',
      );

      // Opposite exceeds locked side by >= 0.12 -> switch to right
      expect(
        ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: 0.70,
          rightScore: 0.85,
          lockedSide: 'left',
          viewAngle: CameraViewAngle.oblique45,
          switchMargin: 0.12,
        ),
        'right',
      );

      // Locked on right in oblique45; left slightly higher (+0.10 < 0.12) -> stay right
      expect(
        ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: 0.85,
          rightScore: 0.75,
          lockedSide: 'right',
          viewAngle: CameraViewAngle.oblique45,
          switchMargin: 0.12,
        ),
        'right',
      );

      // Frontal view picks higher score directly without lock margin
      expect(
        ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: 0.75,
          rightScore: 0.80,
          lockedSide: 'left',
          viewAngle: CameraViewAngle.frontal,
          switchMargin: 0.12,
        ),
        'right',
      );

      // Invalid locked side falls back to valid opposite side; both invalid -> 'none'
      expect(
        ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: 0.0,
          rightScore: 0.65,
          lockedSide: 'left',
          viewAngle: CameraViewAngle.side90,
        ),
        'right',
      );
      expect(
        ViewAngleProjectionHelper.selectBestLockedSide(
          leftScore: 0.0,
          rightScore: -1.0,
          lockedSide: 'left',
          viewAngle: CameraViewAngle.side90,
        ),
        'none',
      );
    });
  });

  group('Extended Core DTO Metrics & RepRecord Tests', () {
    List<PoseLandmark> createLandmarks(Map<int, Map<String, double>> overrides) {
      return List.generate(33, (i) {
        final o = overrides[i];
        return PoseLandmark(
          index: i,
          x: o?['x'] ?? 0.5,
          y: o?['y'] ?? 0.5,
          z: 0.0,
          visibility: o?['visibility'] ?? 0.92,
        );
      });
    }

    test('SquatFrameFeatures computes kneeValgusRatio and hipBelowKneeNorm in frontal view', () {
      // 1000x1000 frontal deep squat with knees caving inward (valgus):
      // Shoulders at y=0.30 (300px), Hips at y=0.62 (620px) -> torsoHeight = 320px
      // Knees at y=0.58 (580px): avgHipY - avgKneeY = +40px -> hipBelowKneeNorm = 40/320 = +0.125
      // Ankles x: 0.35 & 0.65 (300px apart), Knees x: 0.425 & 0.575 (150px apart) -> kneeValgusRatio = 0.50
      final valgusDeepSquat = createLandmarks({
        PoseLandmark.leftShoulder: {'x': 0.38, 'y': 0.30},
        PoseLandmark.rightShoulder: {'x': 0.62, 'y': 0.30},
        PoseLandmark.leftHip: {'x': 0.42, 'y': 0.62},
        PoseLandmark.rightHip: {'x': 0.58, 'y': 0.62},
        PoseLandmark.leftKnee: {'x': 0.425, 'y': 0.58},
        PoseLandmark.rightKnee: {'x': 0.575, 'y': 0.58},
        PoseLandmark.leftAnkle: {'x': 0.35, 'y': 0.88},
        PoseLandmark.rightAnkle: {'x': 0.65, 'y': 0.88},
      });

      final squatFeatures = WorkoutCvMotionFeatures.extractSquatFeatures(
        frameIndex: 1,
        timestampMs: 100,
        landmarks: valgusDeepSquat,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
        viewAngle: CameraViewAngle.frontal,
      );

      expect(squatFeatures.viewAngle, CameraViewAngle.frontal);
      expect(squatFeatures.kneeValgusRatio.isValid, isTrue);
      expect(squatFeatures.kneeValgusRatio.value, closeTo(0.50, 1e-4));
      expect(squatFeatures.hipBelowKneeNorm.isValid, isTrue);
      expect(squatFeatures.hipBelowKneeNorm.value, closeTo(0.125, 1e-4));

      // Standing upright: hips at y=0.50 (500px), knees at y=0.70 (700px), torso=200px
      // hipBelowKneeNorm = (500 - 700) / 200 = -1.0 (clearly above knee)
      // Narrow ankles (x: 0.498, 0.502 -> 4px < 10px) -> falls back to hip width (200px)
      final standingNarrowAnkles = createLandmarks({
        PoseLandmark.leftShoulder: {'x': 0.38, 'y': 0.30},
        PoseLandmark.rightShoulder: {'x': 0.62, 'y': 0.30},
        PoseLandmark.leftHip: {'x': 0.40, 'y': 0.50},
        PoseLandmark.rightHip: {'x': 0.60, 'y': 0.50},
        PoseLandmark.leftKnee: {'x': 0.41, 'y': 0.70},
        PoseLandmark.rightKnee: {'x': 0.59, 'y': 0.70},
        PoseLandmark.leftAnkle: {'x': 0.498, 'y': 0.90},
        PoseLandmark.rightAnkle: {'x': 0.502, 'y': 0.90},
      });

      final standingFeatures = WorkoutCvMotionFeatures.extractSquatFeatures(
        frameIndex: 2,
        timestampMs: 200,
        landmarks: standingNarrowAnkles,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
      );

      expect(standingFeatures.viewAngle, CameraViewAngle.unknown);
      expect(standingFeatures.kneeValgusRatio.isValid, isTrue);
      expect(standingFeatures.kneeValgusRatio.value, closeTo(0.90, 1e-4));
      expect(standingFeatures.hipBelowKneeNorm.isValid, isTrue);
      expect(standingFeatures.hipBelowKneeNorm.value, closeTo(-1.0, 1e-4));
    });

    test('LatPulldownFrameFeatures computes torsoLeanDeg and preserves viewAngle', () {
      // Hip at (500, 700), Shoulder at (600, 500) -> dx = +100, dy = -200
      // Lean from upward vertical (0, -1): atan2(100, 200) = 26.565 deg
      final leaningLandmarks = createLandmarks({
        PoseLandmark.leftShoulder: {'x': 0.60, 'y': 0.50, 'visibility': 0.95},
        PoseLandmark.rightShoulder: {'x': 0.40, 'y': 0.50, 'visibility': 0.90},
        PoseLandmark.leftElbow: {'x': 0.65, 'y': 0.40, 'visibility': 0.95},
        PoseLandmark.leftWrist: {'x': 0.60, 'y': 0.25, 'visibility': 0.95},
        PoseLandmark.leftHip: {'x': 0.50, 'y': 0.70, 'visibility': 0.95},
        PoseLandmark.rightHip: {'x': 0.40, 'y': 0.70, 'visibility': 0.90},
      });

      final features = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
        frameIndex: 5,
        timestampMs: 500,
        landmarks: leaningLandmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
        viewAngle: CameraViewAngle.oblique45,
      );

      expect(features.viewAngle, CameraViewAngle.oblique45);
      expect(features.torsoLeanDeg.isValid, isTrue);
      expect(features.torsoLeanDeg.value, closeTo(26.565, 0.05));
    });

    test('PullUp, PushUp, and BicepCurl DTOs propagate optional viewAngle cleanly', () {
      final landmarks = createLandmarks({
        PoseLandmark.leftShoulder: {'x': 0.4, 'y': 0.3},
        PoseLandmark.rightShoulder: {'x': 0.6, 'y': 0.3},
        PoseLandmark.leftElbow: {'x': 0.35, 'y': 0.45},
        PoseLandmark.rightElbow: {'x': 0.65, 'y': 0.45},
        PoseLandmark.leftWrist: {'x': 0.35, 'y': 0.20},
        PoseLandmark.rightWrist: {'x': 0.65, 'y': 0.20},
        PoseLandmark.leftHip: {'x': 0.42, 'y': 0.65},
        PoseLandmark.rightHip: {'x': 0.58, 'y': 0.65},
        PoseLandmark.leftAnkle: {'x': 0.42, 'y': 0.90},
        PoseLandmark.rightAnkle: {'x': 0.58, 'y': 0.90},
      });

      final pullUp = WorkoutCvMotionFeatures.extractPullUpFeatures(
        frameIndex: 1,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
        viewAngle: CameraViewAngle.frontal,
      );
      expect(pullUp.viewAngle, CameraViewAngle.frontal);

      final pushUp = WorkoutCvMotionFeatures.extractPushUpFeatures(
        frameIndex: 1,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
        viewAngle: CameraViewAngle.side90,
      );
      expect(pushUp.viewAngle, CameraViewAngle.side90);

      final bicep = WorkoutCvMotionFeatures.extractBicepCurlFeatures(
        frameIndex: 1,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1000.0,
        imageHeight: 1000.0,
        viewAngle: CameraViewAngle.oblique45,
      );
      expect(bicep.viewAngle, CameraViewAngle.oblique45);
    });

    test('RepRecord localizes all RepIssueType and CameraViewAngle values in VI and EN', () {
      for (final issue in RepIssueType.values) {
        final record = RepRecord(
          repIndex: 1,
          timestampSec: 4.5,
          durationSec: 2.3,
          metricAngleDeg: 88.5,
          isValid: issue == RepIssueType.none,
          issueType: issue,
          viewAngle: CameraViewAngle.oblique45,
        );
        expect(record.localizedIssueLabel(isVietnamese: true), isNotEmpty);
        expect(record.localizedIssueLabel(isVietnamese: false), isNotEmpty);
      }

      const shallow = RepRecord(
        repIndex: 2,
        timestampSec: 8.2,
        durationSec: 1.9,
        metricAngleDeg: 108.0,
        isValid: false,
        issueType: RepIssueType.shallowDepth,
        viewAngle: CameraViewAngle.frontal,
      );
      expect(shallow.localizedIssueLabel(isVietnamese: true), 'Chưa đủ độ sâu');
      expect(
        shallow.localizedIssueLabel(isVietnamese: false),
        'Insufficient depth',
      );
      expect(
        shallow.localizedViewAngleLabel(isVietnamese: true),
        '0° Chính diện',
      );
      expect(
        shallow.localizedViewAngleLabel(isVietnamese: false),
        '0° Front',
      );

      const valgus = RepRecord(
        repIndex: 3,
        timestampSec: 12.0,
        durationSec: 2.4,
        isValid: false,
        issueType: RepIssueType.kneeValgus,
        viewAngle: CameraViewAngle.side90,
      );
      expect(
        valgus.localizedIssueLabel(isVietnamese: true),
        'Gối chụm vào trong',
      );
      expect(valgus.localizedIssueLabel(isVietnamese: false), 'Knee valgus');
      expect(valgus.localizedViewAngleLabel(isVietnamese: true), '90° Ngang');
      expect(valgus.localizedViewAngleLabel(isVietnamese: false), '90° Side');

      const autoUnknown = RepRecord(
        repIndex: 4,
        timestampSec: 15.0,
        durationSec: 2.0,
        isValid: true,
      );
      expect(autoUnknown.localizedIssueLabel(isVietnamese: true), 'Đạt chuẩn');
      expect(autoUnknown.localizedIssueLabel(isVietnamese: false), 'Good form');
      expect(autoUnknown.localizedViewAngleLabel(isVietnamese: true), 'Tự động');
      expect(autoUnknown.localizedViewAngleLabel(isVietnamese: false), 'Auto');

      // Verify ExerciseCvState backward-compatible defaults, copyWith, and intact CvFormSummary.toJson()
      const baseState = ExerciseCvState();
      expect(baseState.repRecords, isEmpty);
      expect(baseState.detectedViewAngle, CameraViewAngle.unknown);

      final updatedState = baseState.copyWith(
        repRecords: [shallow, valgus],
        detectedViewAngle: CameraViewAngle.oblique45,
      );
      expect(updatedState.repRecords, hasLength(2));
      expect(updatedState.detectedViewAngle, CameraViewAngle.oblique45);
      expect(
        updatedState.formSummary.toJson().keys.toSet(),
        equals({
          'valid_reps',
          'fast_reps',
          'avg_elbow_angle_deg',
          'avg_tempo_sec',
          'abort_count',
        }),
      );
    });
  });
}

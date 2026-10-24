import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
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
}

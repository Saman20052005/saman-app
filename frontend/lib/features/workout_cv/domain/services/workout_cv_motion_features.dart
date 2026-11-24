import 'dart:math' as math;
import '../entities/pose_landmark.dart';

/// Failure reasons for geometric and kinematic feature measurements.
enum MotionMetricFailure {
  none,
  missingLandmark,
  lowVisibility,
  nonFiniteCoordinate,
  outOfBoundsCoordinate,
  degenerateGeometry,
  gateNotDetecting,
  invalidImageDimensions,
}

/// Immutable container for a single motion feature measurement.
///
/// If [isValid] is false, [value] is strictly null (never filled with 0.0 or held previous values).
class MotionMeasurement {
  final double? value;
  final bool isValid;
  final MotionMetricFailure failure;
  final String? details;

  const MotionMeasurement.valid(double val)
      : value = val,
        isValid = true,
        failure = MotionMetricFailure.none,
        details = null;

  const MotionMeasurement.invalid(this.failure, [this.details])
      : value = null,
        isValid = false;

  @override
  String toString() => isValid ? '$value' : 'INVALID($failure)';
}

/// Helper 2D pixel coordinate container for geometric calculations.
class _PixelPoint {
  final double x;
  final double y;

  const _PixelPoint(this.x, this.y);
}

/// Motion features extracted for a specific body side (based on model landmark IDs).
///
/// IMPORTANT: Model landmark IDs (11/13/15 vs 12/14/16) reflect the raw output labels
/// of the pose landmarker and are NOT anatomically verified as true physical left/right.
class LatPulldownSideFeatures {
  final String sideKey;
  final int shoulderId;
  final int elbowId;
  final int wristId;

  /// 2D Elbow angle in degrees [0.0, 180.0] formed by Shoulder -> Elbow -> Wrist in pixel space.
  final MotionMeasurement elbowAngleDeg;

  /// Visibility quality score (`minVis + avgVis * 1e-3`) for Shoulder -> Elbow -> Wrist.
  final double elbowVisibilityScore;

  /// Wrist vertical position relative to shoulder, normalized by shoulder width: (wrist_y - shoulder_y) / shoulder_width.
  /// Positive value indicates wrist is below shoulder; negative value indicates wrist is above shoulder.
  final MotionMeasurement wristRelY;

  /// Wrist horizontal position relative to shoulder, normalized by shoulder width: (wrist_x - shoulder_x) / shoulder_width.
  final MotionMeasurement wristRelX;

  /// 2D Euclidean distance from wrist to shoulder, normalized by shoulder width.
  final MotionMeasurement wristDistance;

  const LatPulldownSideFeatures({
    required this.sideKey,
    required this.shoulderId,
    required this.elbowId,
    required this.wristId,
    required this.elbowAngleDeg,
    this.elbowVisibilityScore = 0.0,
    required this.wristRelY,
    required this.wristRelX,
    required this.wristDistance,
  });
}

/// Full frame kinematic features for Lat Pulldown exercise.
class LatPulldownFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement shoulderWidthPx;
  final LatPulldownSideFeatures leftSide; // Model IDs 11, 13, 15
  final LatPulldownSideFeatures rightSide; // Model IDs 12, 14, 16

  const LatPulldownFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.shoulderWidthPx,
    required this.leftSide,
    required this.rightSide,
  });

  bool get hasAnyValidSignal =>
      leftSide.elbowAngleDeg.isValid ||
      rightSide.elbowAngleDeg.isValid ||
      leftSide.wristRelY.isValid ||
      rightSide.wristRelY.isValid;

  /// Selects the side with the highest valid elbow visibility score.
  LatPulldownSideFeatures get bestSide {
    final leftValid = leftSide.elbowAngleDeg.isValid;
    final rightValid = rightSide.elbowAngleDeg.isValid;
    if (leftValid && rightValid) {
      return leftSide.elbowVisibilityScore >= rightSide.elbowVisibilityScore
          ? leftSide
          : rightSide;
    }
    if (leftValid) return leftSide;
    if (rightValid) return rightSide;
    return leftSide;
  }

  MotionMeasurement get bestElbowAngleDeg => bestSide.elbowAngleDeg;
}

/// Extracted frame kinematic and spatial clearance features for Pull-up exercise.
class PullUpFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement bestElbowAngleDeg;
  final String bestSideKey;
  final bool isWristAboveShoulder;
  final bool isTopPositionReached;
  final bool? isChinCleared;
  final MotionMeasurement headToBarNorm;

  const PullUpFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.bestElbowAngleDeg,
    required this.bestSideKey,
    required this.isWristAboveShoulder,
    required this.isTopPositionReached,
    required this.isChinCleared,
    required this.headToBarNorm,
  });
}

/// Extracted frame kinematic and posture features for Squat exercise.
class SquatFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement bestKneeAngleDeg;
  final String bestSideKey;
  final MotionMeasurement bestHipAngleDeg;
  final MotionMeasurement torsoLeanDeg;

  const SquatFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.bestKneeAngleDeg,
    required this.bestSideKey,
    required this.bestHipAngleDeg,
    required this.torsoLeanDeg,
  });
}

/// Extracted frame kinematic and plank-posture features for Push-up exercise.
class PushUpFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement bestElbowAngleDeg;
  final String bestSideKey;
  final MotionMeasurement torsoLeanDeg;
  final MotionMeasurement bodyAlignmentDeg;

  const PushUpFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.bestElbowAngleDeg,
    required this.bestSideKey,
    required this.torsoLeanDeg,
    required this.bodyAlignmentDeg,
  });
}

/// Extracted frame kinematic and posture features for Overhead Press exercise.
class OverheadPressFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement bestElbowAngleDeg;
  final String bestSideKey;
  final bool isWristAboveShoulder;
  final MotionMeasurement torsoLeanDeg;

  const OverheadPressFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.bestElbowAngleDeg,
    required this.bestSideKey,
    required this.isWristAboveShoulder,
    required this.torsoLeanDeg,
  });
}

/// Extracted per-side kinematic and form features for Bicep Curl exercise.
class BicepCurlFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement leftElbowAngleDeg;
  final MotionMeasurement rightElbowAngleDeg;
  final double leftElbowVisibilityScore;
  final double rightElbowVisibilityScore;
  final MotionMeasurement leftUpperArmSwingDeg;
  final MotionMeasurement rightUpperArmSwingDeg;
  final MotionMeasurement torsoLeanDeg;

  const BicepCurlFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.leftElbowAngleDeg,
    required this.rightElbowAngleDeg,
    required this.leftElbowVisibilityScore,
    required this.rightElbowVisibilityScore,
    required this.leftUpperArmSwingDeg,
    required this.rightUpperArmSwingDeg,
    required this.torsoLeanDeg,
  });

  MotionMeasurement get bestElbowAngleDeg {
    if (leftElbowAngleDeg.isValid && rightElbowAngleDeg.isValid) {
      return leftElbowVisibilityScore >= rightElbowVisibilityScore
          ? leftElbowAngleDeg
          : rightElbowAngleDeg;
    }
    if (leftElbowAngleDeg.isValid) return leftElbowAngleDeg;
    if (rightElbowAngleDeg.isValid) return rightElbowAngleDeg;
    return leftElbowAngleDeg;
  }
}

/// Extracted joint angles and spatial cues across supported multi-exercise CV modules.
class MultiExerciseAngleFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement leftElbowAngleDeg;
  final MotionMeasurement rightElbowAngleDeg;
  final MotionMeasurement bestElbowAngleDeg;
  final MotionMeasurement leftKneeAngleDeg;
  final MotionMeasurement rightKneeAngleDeg;
  final MotionMeasurement bestKneeAngleDeg;
  final bool isWristAboveShoulder;

  const MultiExerciseAngleFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.leftElbowAngleDeg,
    required this.rightElbowAngleDeg,
    required this.bestElbowAngleDeg,
    required this.leftKneeAngleDeg,
    required this.rightKneeAngleDeg,
    required this.bestKneeAngleDeg,
    required this.isWristAboveShoulder,
  });
}

/// Extracted joint angles and spatial cues for extended curatedExerciseLibrary CV modules.
class ExtendedLibraryFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement leftElbowAngleDeg;
  final MotionMeasurement rightElbowAngleDeg;
  final double leftElbowVisibilityScore;
  final double rightElbowVisibilityScore;
  final MotionMeasurement leftShoulderAngleDeg;
  final MotionMeasurement rightShoulderAngleDeg;
  final double leftShoulderVisibilityScore;
  final double rightShoulderVisibilityScore;
  final MotionMeasurement bestHipAngleDeg;
  final MotionMeasurement bestKneeAngleDeg;
  final MotionMeasurement minValidKneeAngleDeg;
  final bool isWristAboveShoulder;
  final bool hasWristSignal;

  const ExtendedLibraryFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.leftElbowAngleDeg,
    required this.rightElbowAngleDeg,
    required this.leftElbowVisibilityScore,
    required this.rightElbowVisibilityScore,
    required this.leftShoulderAngleDeg,
    required this.rightShoulderAngleDeg,
    required this.leftShoulderVisibilityScore,
    required this.rightShoulderVisibilityScore,
    required this.bestHipAngleDeg,
    required this.bestKneeAngleDeg,
    required this.minValidKneeAngleDeg,
    required this.isWristAboveShoulder,
    required this.hasWristSignal,
  });
}

/// Extracted frame posture and alignment features for Plank Hold exercises.
class PlankHoldFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement bodyAlignmentDeg;
  final String bestSideKey;
  final MotionMeasurement torsoLeanDeg;

  const PlankHoldFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.bodyAlignmentDeg,
    required this.bestSideKey,
    required this.torsoLeanDeg,
  });
}

/// Extracted per-side elbow and torso posture features for Row exercises.
class RowFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement leftElbowAngleDeg;
  final MotionMeasurement rightElbowAngleDeg;
  final double leftElbowVisibilityScore;
  final double rightElbowVisibilityScore;
  final MotionMeasurement bestElbowAngleDeg;
  final double elbowVisibility;
  final String bestSideKey;
  final MotionMeasurement torsoLeanDeg;

  const RowFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.leftElbowAngleDeg,
    required this.rightElbowAngleDeg,
    required this.leftElbowVisibilityScore,
    required this.rightElbowVisibilityScore,
    required this.bestElbowAngleDeg,
    required this.elbowVisibility,
    required this.bestSideKey,
    required this.torsoLeanDeg,
  });
}

/// Extracted elbow and shoulder-level height features for Face Pull exercises.
class FacePullFrameFeatures {
  final int frameIndex;
  final int timestampMs;
  final bool isGateDetecting;
  final MotionMeasurement bestElbowAngleDeg;
  final String bestSideKey;
  final bool? isElbowAtShoulderHeight;

  const FacePullFrameFeatures({
    required this.frameIndex,
    required this.timestampMs,
    required this.isGateDetecting,
    required this.bestElbowAngleDeg,
    required this.bestSideKey,
    required this.isElbowAtShoulderHeight,
  });
}

/// Pure Dart service to extract Lat Pulldown motion signals from pose landmarks.
///
/// Designed for deterministic reuse in both live camera streams and offline replay benchmarks.
class WorkoutCvMotionFeatures {
  static const double defaultMinVisibility = 0.45;
  static const double pushUpMinVisibility = 0.35;
  static const double minSegmentLengthPx = 1e-3;
  static const double minShoulderWidthPx = 1.0;

  /// Extracts Lat Pulldown kinematic features for a single frame.
  ///
  /// Landmarks are converted from normalized space to pixel space using [imageWidth] and [imageHeight]
  /// before angular and distance calculations to avoid aspect-ratio distortions on non-square frames.
  static LatPulldownFrameFeatures extractLatPulldownFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    // 1. Gate precondition: If quality gate is not 'detecting', whole frame features are invalid
    if (!isGateDetecting) {
      const invalidGate = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return LatPulldownFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        shoulderWidthPx: invalidGate,
        leftSide: _createInvalidSideFeatures(
          sideKey: 'model_left_11_13_15',
          shoulderId: PoseLandmark.leftShoulder,
          elbowId: PoseLandmark.leftElbow,
          wristId: PoseLandmark.leftWrist,
          failure: MotionMetricFailure.gateNotDetecting,
          reason: 'Quality gate is not detecting',
        ),
        rightSide: _createInvalidSideFeatures(
          sideKey: 'model_right_12_14_16',
          shoulderId: PoseLandmark.rightShoulder,
          elbowId: PoseLandmark.rightElbow,
          wristId: PoseLandmark.rightWrist,
          failure: MotionMetricFailure.gateNotDetecting,
          reason: 'Quality gate is not detecting',
        ),
      );
    }

    // 2. Image dimensions validation
    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const invalidDim = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return LatPulldownFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        shoulderWidthPx: invalidDim,
        leftSide: _createInvalidSideFeatures(
          sideKey: 'model_left_11_13_15',
          shoulderId: PoseLandmark.leftShoulder,
          elbowId: PoseLandmark.leftElbow,
          wristId: PoseLandmark.leftWrist,
          failure: MotionMetricFailure.invalidImageDimensions,
        ),
        rightSide: _createInvalidSideFeatures(
          sideKey: 'model_right_12_14_16',
          shoulderId: PoseLandmark.rightShoulder,
          elbowId: PoseLandmark.rightElbow,
          wristId: PoseLandmark.rightWrist,
          failure: MotionMetricFailure.invalidImageDimensions,
        ),
      );
    }

    // 3. Resolve key landmarks
    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);

    // 4. Validate and measure shoulder width
    final lShCheck = _validateLandmark(lShoulder, minVisibility);
    final rShCheck = _validateLandmark(rShoulder, minVisibility);

    MotionMeasurement shoulderWidthMeasurement;
    double? validShoulderWidth;

    if (lShCheck != MotionMetricFailure.none) {
      shoulderWidthMeasurement =
          MotionMeasurement.invalid(lShCheck, 'Left shoulder invalid');
    } else if (rShCheck != MotionMetricFailure.none) {
      shoulderWidthMeasurement =
          MotionMeasurement.invalid(rShCheck, 'Right shoulder invalid');
    } else {
      final pLSh = _toPixelPoint(lShoulder!, imageWidth, imageHeight);
      final pRSh = _toPixelPoint(rShoulder!, imageWidth, imageHeight);
      final sw = math
          .sqrt(math.pow(pLSh.x - pRSh.x, 2) + math.pow(pLSh.y - pRSh.y, 2));
      if (!sw.isFinite || sw < minShoulderWidthPx) {
        shoulderWidthMeasurement = const MotionMeasurement.invalid(
          MotionMetricFailure.degenerateGeometry,
          'Shoulder distance degenerate (< $minShoulderWidthPx px)',
        );
      } else {
        shoulderWidthMeasurement = MotionMeasurement.valid(sw);
        validShoulderWidth = sw;
      }
    }

    // 5. Extract per-side features (Model Left: 11, 13, 15)
    final leftSideFeatures = _extractSide(
      sideKey: 'model_left_11_13_15',
      shoulderId: PoseLandmark.leftShoulder,
      elbowId: PoseLandmark.leftElbow,
      wristId: PoseLandmark.leftWrist,
      shoulderLm: lShoulder,
      elbowLm: lElbow,
      wristLm: lWrist,
      shoulderWidthPx: validShoulderWidth,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    // 6. Extract per-side features (Model Right: 12, 14, 16)
    final rightSideFeatures = _extractSide(
      sideKey: 'model_right_12_14_16',
      shoulderId: PoseLandmark.rightShoulder,
      elbowId: PoseLandmark.rightElbow,
      wristId: PoseLandmark.rightWrist,
      shoulderLm: rShoulder,
      elbowLm: rElbow,
      wristLm: rWrist,
      shoulderWidthPx: validShoulderWidth,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    return LatPulldownFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      shoulderWidthPx: shoulderWidthMeasurement,
      leftSide: leftSideFeatures,
      rightSide: rightSideFeatures,
    );
  }

  /// Extracts general pixel-space elbow/knee angles and wrist-above-shoulder state
  /// for multi-exercise CV modules (Squat, Push-up, Overhead Press, Bicep Curl).
  static MultiExerciseAngleFeatures extractMultiExerciseAngles({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    if (!isGateDetecting) {
      const inv = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return MultiExerciseAngleFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        leftElbowAngleDeg: inv,
        rightElbowAngleDeg: inv,
        bestElbowAngleDeg: inv,
        leftKneeAngleDeg: inv,
        rightKneeAngleDeg: inv,
        bestKneeAngleDeg: inv,
        isWristAboveShoulder: false,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const inv = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return MultiExerciseAngleFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        leftElbowAngleDeg: inv,
        rightElbowAngleDeg: inv,
        bestElbowAngleDeg: inv,
        leftKneeAngleDeg: inv,
        rightKneeAngleDeg: inv,
        bestKneeAngleDeg: inv,
        isWristAboveShoulder: false,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);

    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);
    final lKnee = _findLandmark(landmarks, PoseLandmark.leftKnee);
    final rKnee = _findLandmark(landmarks, PoseLandmark.rightKnee);
    final lAnkle = _findLandmark(landmarks, PoseLandmark.leftAnkle);
    final rAnkle = _findLandmark(landmarks, PoseLandmark.rightAnkle);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestElbow = _selectBestMeasurement(
      leftElbow.$1,
      leftElbow.$2,
      rightElbow.$1,
      rightElbow.$2,
    );

    final leftKnee = _measureTripletAngle(
      p1: lHip,
      vertex: lKnee,
      p2: lAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightKnee = _measureTripletAngle(
      p1: rHip,
      vertex: rKnee,
      p2: rAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestKnee = _selectBestMeasurement(
      leftKnee.$1,
      leftKnee.$2,
      rightKnee.$1,
      rightKnee.$2,
    );

    final isWristAboveShoulder = _computeWristAboveShoulder(
      lShoulder: lShoulder,
      lWrist: lWrist,
      rShoulder: rShoulder,
      rWrist: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    return MultiExerciseAngleFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      leftElbowAngleDeg: leftElbow.$1,
      rightElbowAngleDeg: rightElbow.$1,
      bestElbowAngleDeg: bestElbow,
      leftKneeAngleDeg: leftKnee.$1,
      rightKneeAngleDeg: rightKnee.$1,
      bestKneeAngleDeg: bestKnee,
      isWristAboveShoulder: isWristAboveShoulder,
    );
  }

  /// Extracts Pull-up kinematic and spatial bar-clearance features for a single frame.
  ///
  /// Selects the higher-visibility elbow angle, determines bar elevation from valid wrists,
  /// enforces wrist-above-shoulder posture, and evaluates chin/head/shoulder clearance
  /// against the bar with multi-tier fallbacks for rear-view recordings.
  static PullUpFrameFeatures extractPullUpFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    if (!isGateDetecting) {
      const invalidGate = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return PullUpFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        bestElbowAngleDeg: invalidGate,
        bestSideKey: 'none',
        isWristAboveShoulder: false,
        isTopPositionReached: false,
        isChinCleared: null,
        headToBarNorm: invalidGate,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const invalidDim = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return PullUpFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bestElbowAngleDeg: invalidDim,
        bestSideKey: 'none',
        isWristAboveShoulder: false,
        isTopPositionReached: false,
        isChinCleared: null,
        headToBarNorm: invalidDim,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestElbow = _selectBestMeasurement(
      leftElbow.$1,
      leftElbow.$2,
      rightElbow.$1,
      rightElbow.$2,
    );

    final String bestSideKey;
    if (leftElbow.$1.isValid && rightElbow.$1.isValid) {
      bestSideKey = leftElbow.$2 >= rightElbow.$2
          ? 'model_left_11_13_15'
          : 'model_right_12_14_16';
    } else if (leftElbow.$1.isValid) {
      bestSideKey = 'model_left_11_13_15';
    } else if (rightElbow.$1.isValid) {
      bestSideKey = 'model_right_12_14_16';
    } else {
      bestSideKey = 'none';
    }

    final lWrCheck = _validateLandmark(lWrist, minVisibility);
    final rWrCheck = _validateLandmark(rWrist, minVisibility);
    final pLWr = lWrCheck == MotionMetricFailure.none
        ? _toPixelPoint(lWrist!, imageWidth, imageHeight)
        : null;
    final pRWr = rWrCheck == MotionMetricFailure.none
        ? _toPixelPoint(rWrist!, imageWidth, imageHeight)
        : null;

    final double? barY = _averageY(pLWr, pRWr);
    if (barY == null) {
      final wristFailure = lWrCheck != MotionMetricFailure.missingLandmark
          ? lWrCheck
          : rWrCheck;
      return PullUpFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bestElbowAngleDeg: bestElbow,
        bestSideKey: bestSideKey,
        isWristAboveShoulder: false,
        isTopPositionReached: false,
        isChinCleared: null,
        headToBarNorm: MotionMeasurement.invalid(
          wristFailure,
          'No valid wrist landmark for bar reference',
        ),
      );
    }

    final pLSh = _validateLandmark(lShoulder, minVisibility) ==
            MotionMetricFailure.none
        ? _toPixelPoint(lShoulder!, imageWidth, imageHeight)
        : null;
    final pRSh = _validateLandmark(rShoulder, minVisibility) ==
            MotionMetricFailure.none
        ? _toPixelPoint(rShoulder!, imageWidth, imageHeight)
        : null;
    final double? shoulderY = _averageY(pLSh, pRSh);
    final bool isWristAboveShoulder =
        shoulderY != null && barY < shoulderY;

    final pLEl = _validateLandmark(lElbow, minVisibility) ==
            MotionMetricFailure.none
        ? _toPixelPoint(lElbow!, imageWidth, imageHeight)
        : null;
    final pREl = _validateLandmark(rElbow, minVisibility) ==
            MotionMetricFailure.none
        ? _toPixelPoint(rElbow!, imageWidth, imageHeight)
        : null;

    final double shoulderWidthPx =
        (pLSh != null && pRSh != null) ? _distance2D(pLSh, pRSh) : 0.0;
    final double leftForearmPx =
        (pLEl != null && pLWr != null) ? _distance2D(pLEl, pLWr) : 0.0;
    final double rightForearmPx =
        (pREl != null && pRWr != null) ? _distance2D(pREl, pRWr) : 0.0;
    final double bestForearmPx = math.max(leftForearmPx, rightForearmPx);
    final double leftUpperArmPx =
        (pLSh != null && pLEl != null) ? _distance2D(pLSh, pLEl) : 0.0;
    final double rightUpperArmPx =
        (pRSh != null && pREl != null) ? _distance2D(pRSh, pREl) : 0.0;
    final double bestUpperArmPx = math.max(leftUpperArmPx, rightUpperArmPx);

    final double scalePx = math.max(
      20.0,
      math.max(shoulderWidthPx, math.max(bestForearmPx, bestUpperArmPx)),
    );

    // Priority 1: Mouth landmarks (mouthLeft / mouthRight)
    final lMouth = _findLandmark(landmarks, PoseLandmark.mouthLeft);
    final rMouth = _findLandmark(landmarks, PoseLandmark.mouthRight);
    final pLMouth =
        _validateLandmark(lMouth, minVisibility) == MotionMetricFailure.none
            ? _toPixelPoint(lMouth!, imageWidth, imageHeight)
            : null;
    final pRMouth =
        _validateLandmark(rMouth, minVisibility) == MotionMetricFailure.none
            ? _toPixelPoint(rMouth!, imageWidth, imageHeight)
            : null;
    final double? mouthY = _averageY(pLMouth, pRMouth);

    MotionMeasurement headToBarNorm;
    bool? isChinCleared;
    bool isTopPositionReached;

    if (mouthY != null) {
      final norm = (mouthY - barY) / scalePx;
      headToBarNorm = MotionMeasurement.valid(norm);
      isChinCleared = norm <= 0.05;
      isTopPositionReached = norm <= 0.12;
    } else {
      // Priority 2: Nose landmark
      final nose = _findLandmark(landmarks, PoseLandmark.nose);
      final pNose =
          _validateLandmark(nose, minVisibility) == MotionMetricFailure.none
              ? _toPixelPoint(nose!, imageWidth, imageHeight)
              : null;
      if (pNose != null) {
        final norm = (pNose.y - barY) / scalePx;
        headToBarNorm = MotionMeasurement.valid(norm);
        isChinCleared = norm <= -0.03;
        isTopPositionReached = norm <= 0.05;
      } else {
        // Priority 3: Ear landmarks (rear/back-angle fallback)
        final lEar = _findLandmark(landmarks, PoseLandmark.leftEar);
        final rEar = _findLandmark(landmarks, PoseLandmark.rightEar);
        final pLEar =
            _validateLandmark(lEar, minVisibility) == MotionMetricFailure.none
                ? _toPixelPoint(lEar!, imageWidth, imageHeight)
                : null;
        final pREar =
            _validateLandmark(rEar, minVisibility) == MotionMetricFailure.none
                ? _toPixelPoint(rEar!, imageWidth, imageHeight)
                : null;
        final double? earY = _averageY(pLEar, pREar);
        if (earY != null) {
          final norm = (earY - barY) / scalePx;
          headToBarNorm = MotionMeasurement.valid(norm);
          isChinCleared = null;
          isTopPositionReached = norm <= 0.08;
        } else if (shoulderY != null) {
          // Priority 4: Shoulder elevation fallback (back-of-neck view)
          final shoulderToBarNorm = (shoulderY - barY) / scalePx;
          headToBarNorm = MotionMeasurement.valid(shoulderToBarNorm);
          isChinCleared = null;
          isTopPositionReached = shoulderToBarNorm <= 0.55;
        } else {
          headToBarNorm = const MotionMeasurement.invalid(
            MotionMetricFailure.missingLandmark,
            'No valid head or shoulder landmark',
          );
          isChinCleared = null;
          isTopPositionReached = false;
        }
      }
    }

    return PullUpFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      bestElbowAngleDeg: bestElbow,
      bestSideKey: bestSideKey,
      isWristAboveShoulder: isWristAboveShoulder,
      isTopPositionReached: isTopPositionReached,
      isChinCleared: isChinCleared,
      headToBarNorm: headToBarNorm,
    );
  }

  /// Extracts Squat kinematic and posture features for a single frame.
  ///
  /// Selects the higher-visibility knee angle, extracts the matching hip flexion
  /// angle (Shoulder -> Hip -> Knee) and torso lean angle from upward vertical `(0, -1)`
  /// in pixel space with cross-side fallback when one side's upper body is occluded.
  static SquatFrameFeatures extractSquatFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    if (!isGateDetecting) {
      const invalidGate = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return SquatFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        bestKneeAngleDeg: invalidGate,
        bestSideKey: 'none',
        bestHipAngleDeg: invalidGate,
        torsoLeanDeg: invalidGate,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const invalidDim = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return SquatFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bestKneeAngleDeg: invalidDim,
        bestSideKey: 'none',
        bestHipAngleDeg: invalidDim,
        torsoLeanDeg: invalidDim,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);
    final lKnee = _findLandmark(landmarks, PoseLandmark.leftKnee);
    final rKnee = _findLandmark(landmarks, PoseLandmark.rightKnee);
    final lAnkle = _findLandmark(landmarks, PoseLandmark.leftAnkle);
    final rAnkle = _findLandmark(landmarks, PoseLandmark.rightAnkle);

    final leftKnee = _measureTripletAngle(
      p1: lHip,
      vertex: lKnee,
      p2: lAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightKnee = _measureTripletAngle(
      p1: rHip,
      vertex: rKnee,
      p2: rAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestKnee = _selectBestMeasurement(
      leftKnee.$1,
      leftKnee.$2,
      rightKnee.$1,
      rightKnee.$2,
    );

    const leftSideKey = 'model_left_23_25_27';
    const rightSideKey = 'model_right_24_26_28';
    final String bestSideKey;
    if (leftKnee.$1.isValid && rightKnee.$1.isValid) {
      bestSideKey = leftKnee.$2 >= rightKnee.$2 ? leftSideKey : rightSideKey;
    } else if (leftKnee.$1.isValid) {
      bestSideKey = leftSideKey;
    } else if (rightKnee.$1.isValid) {
      bestSideKey = rightSideKey;
    } else {
      bestSideKey = 'none';
    }

    final leftHip = _measureTripletAngle(
      p1: lShoulder,
      vertex: lHip,
      p2: lKnee,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightHip = _measureTripletAngle(
      p1: rShoulder,
      vertex: rHip,
      p2: rKnee,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestHip = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftHip,
      right: rightHip,
    );

    final leftTorso = _measureTorsoLean(
      shoulder: lShoulder,
      hip: lHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightTorso = _measureTorsoLean(
      shoulder: rShoulder,
      hip: rHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final torsoLean = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftTorso,
      right: rightTorso,
    );

    return SquatFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      bestKneeAngleDeg: bestKnee,
      bestSideKey: bestSideKey,
      bestHipAngleDeg: bestHip,
      torsoLeanDeg: torsoLean,
    );
  }

  /// Extracts Push-up kinematic and plank-posture features for a single frame.
  ///
  /// Uses a lower default visibility threshold ([pushUpMinVisibility] = 0.35)
  /// to retain arm tracking near the floor while keeping finite/bounds checks strict.
  /// Selects the higher-visibility elbow angle, measures torso lean from upward
  /// vertical `(0, -1)` to `Hip -> Shoulder`, and measures `Shoulder -> Hip -> Ankle`
  /// body alignment in pixel space with cross-side fallback.
  static PushUpFrameFeatures extractPushUpFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = pushUpMinVisibility,
  }) {
    if (!isGateDetecting) {
      const invalidGate = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return PushUpFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        bestElbowAngleDeg: invalidGate,
        bestSideKey: 'none',
        torsoLeanDeg: invalidGate,
        bodyAlignmentDeg: invalidGate,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const invalidDim = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return PushUpFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bestElbowAngleDeg: invalidDim,
        bestSideKey: 'none',
        torsoLeanDeg: invalidDim,
        bodyAlignmentDeg: invalidDim,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);
    final lAnkle = _findLandmark(landmarks, PoseLandmark.leftAnkle);
    final rAnkle = _findLandmark(landmarks, PoseLandmark.rightAnkle);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestElbow = _selectBestMeasurement(
      leftElbow.$1,
      leftElbow.$2,
      rightElbow.$1,
      rightElbow.$2,
    );

    const leftSideKey = 'model_left_11_13_15';
    const rightSideKey = 'model_right_12_14_16';
    final String bestSideKey;
    if (leftElbow.$1.isValid && rightElbow.$1.isValid) {
      bestSideKey = leftElbow.$2 >= rightElbow.$2 ? leftSideKey : rightSideKey;
    } else if (leftElbow.$1.isValid) {
      bestSideKey = leftSideKey;
    } else if (rightElbow.$1.isValid) {
      bestSideKey = rightSideKey;
    } else {
      bestSideKey = 'none';
    }

    final leftTorso = _measureTorsoLean(
      shoulder: lShoulder,
      hip: lHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightTorso = _measureTorsoLean(
      shoulder: rShoulder,
      hip: rHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final torsoLean = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftTorso,
      right: rightTorso,
    );

    final leftBodyAlignment = _measureTripletAngle(
      p1: lShoulder,
      vertex: lHip,
      p2: lAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightBodyAlignment = _measureTripletAngle(
      p1: rShoulder,
      vertex: rHip,
      p2: rAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bodyAlignment = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftBodyAlignment,
      right: rightBodyAlignment,
    );

    return PushUpFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      bestElbowAngleDeg: bestElbow,
      bestSideKey: bestSideKey,
      torsoLeanDeg: torsoLean,
      bodyAlignmentDeg: bodyAlignment,
    );
  }

  /// Extracts Overhead Press kinematic and torso-posture features for a single frame.
  ///
  /// Selects the higher-visibility elbow angle (`Shoulder -> Elbow -> Wrist`),
  /// checks wrist elevation above shoulder on the active arm (with cross-side fallback),
  /// and measures torso lean from upward vertical `(0, -1)` to `Hip -> Shoulder`.
  static OverheadPressFrameFeatures extractOverheadPressFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    if (!isGateDetecting) {
      const invalidGate = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return OverheadPressFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        bestElbowAngleDeg: invalidGate,
        bestSideKey: 'none',
        isWristAboveShoulder: false,
        torsoLeanDeg: invalidGate,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const invalidDim = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return OverheadPressFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bestElbowAngleDeg: invalidDim,
        bestSideKey: 'none',
        isWristAboveShoulder: false,
        torsoLeanDeg: invalidDim,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestElbow = _selectBestMeasurement(
      leftElbow.$1,
      leftElbow.$2,
      rightElbow.$1,
      rightElbow.$2,
    );

    const leftSideKey = 'model_left_11_13_15';
    const rightSideKey = 'model_right_12_14_16';
    final bestSideKey = _resolveBestSideKey(
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftElbow,
      right: rightElbow,
    );

    final bool isWristAboveShoulder;
    if (bestSideKey == leftSideKey && lShoulder != null && lWrist != null) {
      isWristAboveShoulder =
          _toPixelPoint(lWrist, imageWidth, imageHeight).y <
              _toPixelPoint(lShoulder, imageWidth, imageHeight).y;
    } else if (bestSideKey == rightSideKey &&
        rShoulder != null &&
        rWrist != null) {
      isWristAboveShoulder =
          _toPixelPoint(rWrist, imageWidth, imageHeight).y <
              _toPixelPoint(rShoulder, imageWidth, imageHeight).y;
    } else {
      isWristAboveShoulder = _computeWristAboveShoulder(
        lShoulder: lShoulder,
        lWrist: lWrist,
        rShoulder: rShoulder,
        rWrist: rWrist,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        minVisibility: minVisibility,
      );
    }

    final leftTorso = _measureTorsoLean(
      shoulder: lShoulder,
      hip: lHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightTorso = _measureTorsoLean(
      shoulder: rShoulder,
      hip: rHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final torsoLean = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftTorso,
      right: rightTorso,
    );

    return OverheadPressFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      bestElbowAngleDeg: bestElbow,
      bestSideKey: bestSideKey,
      isWristAboveShoulder: isWristAboveShoulder,
      torsoLeanDeg: torsoLean,
    );
  }

  /// Extracts per-side Bicep Curl kinematic and posture features for a single frame.
  ///
  /// Measures left and right elbow flexion angles (`Shoulder -> Elbow -> Wrist`),
  /// per-side visibility scores, upper-arm swing (`Hip -> Shoulder -> Elbow`),
  /// and torso lean (`Hip -> Shoulder` vs upward vertical `(0, -1)`).
  static BicepCurlFrameFeatures extractBicepCurlFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    if (!isGateDetecting) {
      const invalidGate = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return BicepCurlFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        leftElbowAngleDeg: invalidGate,
        rightElbowAngleDeg: invalidGate,
        leftElbowVisibilityScore: 0.0,
        rightElbowVisibilityScore: 0.0,
        leftUpperArmSwingDeg: invalidGate,
        rightUpperArmSwingDeg: invalidGate,
        torsoLeanDeg: invalidGate,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const invalidDim = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return BicepCurlFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        leftElbowAngleDeg: invalidDim,
        rightElbowAngleDeg: invalidDim,
        leftElbowVisibilityScore: 0.0,
        rightElbowVisibilityScore: 0.0,
        leftUpperArmSwingDeg: invalidDim,
        rightUpperArmSwingDeg: invalidDim,
        torsoLeanDeg: invalidDim,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    final leftSwing = _measureTripletAngle(
      p1: lHip,
      vertex: lShoulder,
      p2: lElbow,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightSwing = _measureTripletAngle(
      p1: rHip,
      vertex: rShoulder,
      p2: rElbow,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    const leftSideKey = 'model_left_11_13_15';
    const rightSideKey = 'model_right_12_14_16';
    final bestSideKey = _resolveBestSideKey(
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftElbow,
      right: rightElbow,
    );

    final leftTorso = _measureTorsoLean(
      shoulder: lShoulder,
      hip: lHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightTorso = _measureTorsoLean(
      shoulder: rShoulder,
      hip: rHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final torsoLean = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftTorso,
      right: rightTorso,
    );

    return BicepCurlFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      leftElbowAngleDeg: leftElbow.$1,
      rightElbowAngleDeg: rightElbow.$1,
      leftElbowVisibilityScore: leftElbow.$1.isValid ? leftElbow.$2 : 0.0,
      rightElbowVisibilityScore: rightElbow.$1.isValid ? rightElbow.$2 : 0.0,
      leftUpperArmSwingDeg: leftSwing.$1,
      rightUpperArmSwingDeg: rightSwing.$1,
      torsoLeanDeg: torsoLean,
    );
  }

  /// Extracts kinematic features for the extended curated exercise library CV modules.
  ///
  /// Measures per-side elbow (`Shoulder -> Elbow -> Wrist`) and shoulder abduction
  /// (`Hip -> Shoulder -> Elbow`) angles with visibility scores, highest-visibility hip
  /// (`Shoulder -> Hip -> Knee`) and knee (`Hip -> Knee -> Ankle`) angles, minimum valid
  /// knee angle across legs, wrist-above-shoulder state, and wrist presence.
  static ExtendedLibraryFrameFeatures extractExtendedLibraryFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    if (!isGateDetecting) {
      const inv = MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
      return ExtendedLibraryFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: false,
        leftElbowAngleDeg: inv,
        rightElbowAngleDeg: inv,
        leftElbowVisibilityScore: 0.0,
        rightElbowVisibilityScore: 0.0,
        leftShoulderAngleDeg: inv,
        rightShoulderAngleDeg: inv,
        leftShoulderVisibilityScore: 0.0,
        rightShoulderVisibilityScore: 0.0,
        bestHipAngleDeg: inv,
        bestKneeAngleDeg: inv,
        minValidKneeAngleDeg: inv,
        isWristAboveShoulder: false,
        hasWristSignal: false,
      );
    }

    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      const inv = MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
      return ExtendedLibraryFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        leftElbowAngleDeg: inv,
        rightElbowAngleDeg: inv,
        leftElbowVisibilityScore: 0.0,
        rightElbowVisibilityScore: 0.0,
        leftShoulderAngleDeg: inv,
        rightShoulderAngleDeg: inv,
        leftShoulderVisibilityScore: 0.0,
        rightShoulderVisibilityScore: 0.0,
        bestHipAngleDeg: inv,
        bestKneeAngleDeg: inv,
        minValidKneeAngleDeg: inv,
        isWristAboveShoulder: false,
        hasWristSignal: false,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);
    final lKnee = _findLandmark(landmarks, PoseLandmark.leftKnee);
    final rKnee = _findLandmark(landmarks, PoseLandmark.rightKnee);
    final lAnkle = _findLandmark(landmarks, PoseLandmark.leftAnkle);
    final rAnkle = _findLandmark(landmarks, PoseLandmark.rightAnkle);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    final leftShoulder = _measureTripletAngle(
      p1: lHip,
      vertex: lShoulder,
      p2: lElbow,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightShoulder = _measureTripletAngle(
      p1: rHip,
      vertex: rShoulder,
      p2: rElbow,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    final leftHip = _measureTripletAngle(
      p1: lShoulder,
      vertex: lHip,
      p2: lKnee,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightHip = _measureTripletAngle(
      p1: rShoulder,
      vertex: rHip,
      p2: rKnee,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestHip = _selectBestMeasurement(
      leftHip.$1,
      leftHip.$2,
      rightHip.$1,
      rightHip.$2,
    );

    final leftKnee = _measureTripletAngle(
      p1: lHip,
      vertex: lKnee,
      p2: lAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightKnee = _measureTripletAngle(
      p1: rHip,
      vertex: rKnee,
      p2: rAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final bestKnee = _selectBestMeasurement(
      leftKnee.$1,
      leftKnee.$2,
      rightKnee.$1,
      rightKnee.$2,
    );

    final MotionMeasurement minValidKnee;
    if (leftKnee.$1.isValid && rightKnee.$1.isValid) {
      minValidKnee = leftKnee.$1.value! <= rightKnee.$1.value!
          ? leftKnee.$1
          : rightKnee.$1;
    } else if (leftKnee.$1.isValid) {
      minValidKnee = leftKnee.$1;
    } else if (rightKnee.$1.isValid) {
      minValidKnee = rightKnee.$1;
    } else {
      minValidKnee = leftKnee.$1;
    }

    final hasWristSignal =
        _validateLandmark(lWrist, minVisibility) == MotionMetricFailure.none ||
            _validateLandmark(rWrist, minVisibility) ==
                MotionMetricFailure.none;

    final isWristAboveShoulder = _computeWristAboveShoulder(
      lShoulder: lShoulder,
      lWrist: lWrist,
      rShoulder: rShoulder,
      rWrist: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    return ExtendedLibraryFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      leftElbowAngleDeg: leftElbow.$1,
      rightElbowAngleDeg: rightElbow.$1,
      leftElbowVisibilityScore: leftElbow.$1.isValid ? leftElbow.$2 : 0.0,
      rightElbowVisibilityScore: rightElbow.$1.isValid ? rightElbow.$2 : 0.0,
      leftShoulderAngleDeg: leftShoulder.$1,
      rightShoulderAngleDeg: rightShoulder.$1,
      leftShoulderVisibilityScore:
          leftShoulder.$1.isValid ? leftShoulder.$2 : 0.0,
      rightShoulderVisibilityScore:
          rightShoulder.$1.isValid ? rightShoulder.$2 : 0.0,
      bestHipAngleDeg: bestHip,
      bestKneeAngleDeg: bestKnee,
      minValidKneeAngleDeg: minValidKnee,
      isWristAboveShoulder: isWristAboveShoulder,
      hasWristSignal: hasWristSignal,
    );
  }

  /// Extracts Plank Hold alignment (`Shoulder -> Hip -> Ankle`) and torso lean features.
  ///
  /// Uses [pushUpMinVisibility] (0.35) by default to retain floor-level tracking.
  static PlankHoldFrameFeatures extractPlankHoldFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = pushUpMinVisibility,
  }) {
    final invalidFailure =
        _precheckFrame(isGateDetecting, imageWidth, imageHeight);
    if (invalidFailure != null) {
      return PlankHoldFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bodyAlignmentDeg: invalidFailure,
        bestSideKey: 'none',
        torsoLeanDeg: invalidFailure,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);
    final lAnkle = _findLandmark(landmarks, PoseLandmark.leftAnkle);
    final rAnkle = _findLandmark(landmarks, PoseLandmark.rightAnkle);

    final leftAlignment = _measureTripletAngle(
      p1: lShoulder,
      vertex: lHip,
      p2: lAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightAlignment = _measureTripletAngle(
      p1: rShoulder,
      vertex: rHip,
      p2: rAnkle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    const leftSideKey = 'model_left_11_23_27';
    const rightSideKey = 'model_right_12_24_28';
    final bestSideKey = _resolveBestSideKey(
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftAlignment,
      right: rightAlignment,
    );
    final bodyAlignmentDeg = _selectBestMeasurement(
      leftAlignment.$1,
      leftAlignment.$2,
      rightAlignment.$1,
      rightAlignment.$2,
    );

    final leftTorso = _measureTorsoLean(
      shoulder: lShoulder,
      hip: lHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightTorso = _measureTorsoLean(
      shoulder: rShoulder,
      hip: rHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final torsoLean = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftTorso,
      right: rightTorso,
    );

    return PlankHoldFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      bodyAlignmentDeg: bodyAlignmentDeg,
      bestSideKey: bestSideKey,
      torsoLeanDeg: torsoLean,
    );
  }

  /// Extracts Row elbow flexion (`Shoulder -> Elbow -> Wrist`), torso lean (`Shoulder -> Hip`),
  /// and elbow visibility score for a single frame.
  static RowFrameFeatures extractRowFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    final invalidFailure =
        _precheckFrame(isGateDetecting, imageWidth, imageHeight);
    if (invalidFailure != null) {
      return RowFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        leftElbowAngleDeg: invalidFailure,
        rightElbowAngleDeg: invalidFailure,
        leftElbowVisibilityScore: 0.0,
        rightElbowVisibilityScore: 0.0,
        bestElbowAngleDeg: invalidFailure,
        elbowVisibility: 0.0,
        bestSideKey: 'none',
        torsoLeanDeg: invalidFailure,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);
    final lHip = _findLandmark(landmarks, PoseLandmark.leftHip);
    final rHip = _findLandmark(landmarks, PoseLandmark.rightHip);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    const leftSideKey = 'model_left_11_13_15';
    const rightSideKey = 'model_right_12_14_16';
    final bestSideKey = _resolveBestSideKey(
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftElbow,
      right: rightElbow,
    );
    final bestElbow = _selectBestMeasurement(
      leftElbow.$1,
      leftElbow.$2,
      rightElbow.$1,
      rightElbow.$2,
    );
    final double elbowVisibility = bestSideKey == leftSideKey
        ? leftElbow.$2
        : (bestSideKey == rightSideKey ? rightElbow.$2 : 0.0);

    final leftTorso = _measureTorsoLean(
      shoulder: lShoulder,
      hip: lHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightTorso = _measureTorsoLean(
      shoulder: rShoulder,
      hip: rHip,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final torsoLean = _selectSidePreferredMeasurement(
      bestSideKey: bestSideKey,
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftTorso,
      right: rightTorso,
    );

    return RowFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      leftElbowAngleDeg: leftElbow.$1,
      rightElbowAngleDeg: rightElbow.$1,
      leftElbowVisibilityScore: leftElbow.$1.isValid ? leftElbow.$2 : 0.0,
      rightElbowVisibilityScore: rightElbow.$1.isValid ? rightElbow.$2 : 0.0,
      bestElbowAngleDeg: bestElbow,
      elbowVisibility: elbowVisibility,
      bestSideKey: bestSideKey,
      torsoLeanDeg: torsoLean,
    );
  }

  /// Extracts Face Pull elbow flexion (`Shoulder -> Elbow -> Wrist`) and shoulder-height
  /// elbow posture check for a single frame.
  static FacePullFrameFeatures extractFacePullFeatures({
    required int frameIndex,
    required int timestampMs,
    required List<PoseLandmark> landmarks,
    required double imageWidth,
    required double imageHeight,
    bool isGateDetecting = true,
    double minVisibility = defaultMinVisibility,
  }) {
    final invalidFailure =
        _precheckFrame(isGateDetecting, imageWidth, imageHeight);
    if (invalidFailure != null) {
      return FacePullFrameFeatures(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        isGateDetecting: isGateDetecting,
        bestElbowAngleDeg: invalidFailure,
        bestSideKey: 'none',
        isElbowAtShoulderHeight: null,
      );
    }

    final lShoulder = _findLandmark(landmarks, PoseLandmark.leftShoulder);
    final rShoulder = _findLandmark(landmarks, PoseLandmark.rightShoulder);
    final lElbow = _findLandmark(landmarks, PoseLandmark.leftElbow);
    final rElbow = _findLandmark(landmarks, PoseLandmark.rightElbow);
    final lWrist = _findLandmark(landmarks, PoseLandmark.leftWrist);
    final rWrist = _findLandmark(landmarks, PoseLandmark.rightWrist);

    final leftElbow = _measureTripletAngle(
      p1: lShoulder,
      vertex: lElbow,
      p2: lWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );
    final rightElbow = _measureTripletAngle(
      p1: rShoulder,
      vertex: rElbow,
      p2: rWrist,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    const leftSideKey = 'model_left_11_13_15';
    const rightSideKey = 'model_right_12_14_16';
    final bestSideKey = _resolveBestSideKey(
      leftSideKey: leftSideKey,
      rightSideKey: rightSideKey,
      left: leftElbow,
      right: rightElbow,
    );
    final bestElbow = _selectBestMeasurement(
      leftElbow.$1,
      leftElbow.$2,
      rightElbow.$1,
      rightElbow.$2,
    );

    final shoulderWidthPx = _validShoulderWidthPx(
      lShoulder: lShoulder,
      rShoulder: rShoulder,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      minVisibility: minVisibility,
    );

    final bool? isElbowAtShoulderHeight;
    if (bestSideKey == leftSideKey) {
      isElbowAtShoulderHeight = _checkElbowAtShoulderHeight(
        shoulder: lShoulder,
        elbow: lElbow,
        wrist: lWrist,
        shoulderWidthPx: shoulderWidthPx,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        minVisibility: minVisibility,
      );
    } else if (bestSideKey == rightSideKey) {
      isElbowAtShoulderHeight = _checkElbowAtShoulderHeight(
        shoulder: rShoulder,
        elbow: rElbow,
        wrist: rWrist,
        shoulderWidthPx: shoulderWidthPx,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        minVisibility: minVisibility,
      );
    } else {
      isElbowAtShoulderHeight = _checkElbowAtShoulderHeight(
            shoulder: lShoulder,
            elbow: lElbow,
            wrist: lWrist,
            shoulderWidthPx: shoulderWidthPx,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            minVisibility: minVisibility,
          ) ??
          _checkElbowAtShoulderHeight(
            shoulder: rShoulder,
            elbow: rElbow,
            wrist: rWrist,
            shoulderWidthPx: shoulderWidthPx,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            minVisibility: minVisibility,
          );
    }

    return FacePullFrameFeatures(
      frameIndex: frameIndex,
      timestampMs: timestampMs,
      isGateDetecting: isGateDetecting,
      bestElbowAngleDeg: bestElbow,
      bestSideKey: bestSideKey,
      isElbowAtShoulderHeight: isElbowAtShoulderHeight,
    );
  }

  static MotionMeasurement? _precheckFrame(
    bool isGateDetecting,
    double imageWidth,
    double imageHeight,
  ) {
    if (!isGateDetecting) {
      return const MotionMeasurement.invalid(
        MotionMetricFailure.gateNotDetecting,
        'Quality gate status is not detecting',
      );
    }
    if (!imageWidth.isFinite ||
        !imageHeight.isFinite ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return const MotionMeasurement.invalid(
        MotionMetricFailure.invalidImageDimensions,
        'Image width and height must be positive finite numbers',
      );
    }
    return null;
  }

  static double _validShoulderWidthPx({
    required PoseLandmark? lShoulder,
    required PoseLandmark? rShoulder,
    required double imageWidth,
    required double imageHeight,
    required double minVisibility,
  }) {
    if (_validateLandmark(lShoulder, minVisibility) !=
            MotionMetricFailure.none ||
        _validateLandmark(rShoulder, minVisibility) !=
            MotionMetricFailure.none) {
      return 0.0;
    }
    return _distance2D(
      _toPixelPoint(lShoulder!, imageWidth, imageHeight),
      _toPixelPoint(rShoulder!, imageWidth, imageHeight),
    );
  }

  static bool? _checkElbowAtShoulderHeight({
    required PoseLandmark? shoulder,
    required PoseLandmark? elbow,
    required PoseLandmark? wrist,
    required double shoulderWidthPx,
    required double imageWidth,
    required double imageHeight,
    required double minVisibility,
  }) {
    if (_validateLandmark(shoulder, minVisibility) !=
            MotionMetricFailure.none ||
        _validateLandmark(elbow, minVisibility) != MotionMetricFailure.none) {
      return null;
    }
    final pSh = _toPixelPoint(shoulder!, imageWidth, imageHeight);
    final pEl = _toPixelPoint(elbow!, imageWidth, imageHeight);
    final upperArmLenPx = _distance2D(pSh, pEl);
    final scalePx = math.max(
      upperArmLenPx,
      math.max(shoulderWidthPx * 0.6, imageHeight * 0.08),
    );
    if (!scalePx.isFinite || scalePx < minSegmentLengthPx) {
      return null;
    }

    // In pixel space (+y is downward), an elbow dropped below ~33 deg of shoulder
    // level fails shoulder-height check.
    final elbowDropOk = (pEl.y - pSh.y) <= 0.55 * scalePx;
    if (!elbowDropOk) return false;

    if (_validateLandmark(wrist, minVisibility) == MotionMetricFailure.none) {
      final pWr = _toPixelPoint(wrist!, imageWidth, imageHeight);
      if ((pWr.y - pSh.y) > 0.65 * scalePx) {
        return false;
      }
    }
    return true;
  }

  static String _resolveBestSideKey({
    required String leftSideKey,
    required String rightSideKey,
    required (MotionMeasurement, double) left,
    required (MotionMeasurement, double) right,
  }) {
    if (left.$1.isValid && right.$1.isValid) {
      return left.$2 >= right.$2 ? leftSideKey : rightSideKey;
    }
    if (left.$1.isValid) return leftSideKey;
    if (right.$1.isValid) return rightSideKey;
    return 'none';
  }

  static MotionMeasurement _selectSidePreferredMeasurement({
    required String bestSideKey,
    required String leftSideKey,
    required String rightSideKey,
    required (MotionMeasurement, double) left,
    required (MotionMeasurement, double) right,
  }) {
    if (bestSideKey == leftSideKey) {
      if (left.$1.isValid) return left.$1;
      if (right.$1.isValid) return right.$1;
      return left.$1;
    }
    if (bestSideKey == rightSideKey) {
      if (right.$1.isValid) return right.$1;
      if (left.$1.isValid) return left.$1;
      return right.$1;
    }
    return _selectBestMeasurement(left.$1, left.$2, right.$1, right.$2);
  }

  static (MotionMeasurement, double) _measureTorsoLean({
    required PoseLandmark? shoulder,
    required PoseLandmark? hip,
    required double imageWidth,
    required double imageHeight,
    required double minVisibility,
  }) {
    final shCheck = _validateLandmark(shoulder, minVisibility);
    if (shCheck != MotionMetricFailure.none) {
      return (
        MotionMeasurement.invalid(shCheck, 'Shoulder invalid: $shCheck'),
        -1.0,
      );
    }
    final hipCheck = _validateLandmark(hip, minVisibility);
    if (hipCheck != MotionMetricFailure.none) {
      return (
        MotionMeasurement.invalid(hipCheck, 'Hip invalid: $hipCheck'),
        -1.0,
      );
    }

    final pSh = _toPixelPoint(shoulder!, imageWidth, imageHeight);
    final pHip = _toPixelPoint(hip!, imageWidth, imageHeight);
    final dx = pSh.x - pHip.x;
    final dy = pSh.y - pHip.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (!len.isFinite || len < minSegmentLengthPx) {
      return (
        MotionMeasurement.invalid(
          MotionMetricFailure.degenerateGeometry,
          'Torso segment length too small or non-finite: len=$len',
        ),
        -1.0,
      );
    }

    final cosTheta = (-dy / len).clamp(-1.0, 1.0);
    final torsoLeanDeg = math.acos(cosTheta) * (180.0 / math.pi);
    if (!torsoLeanDeg.isFinite) {
      return (
        const MotionMeasurement.invalid(
            MotionMetricFailure.nonFiniteCoordinate),
        -1.0,
      );
    }

    final minVis = math.min(shoulder.visibility, hip.visibility);
    final avgVis = (shoulder.visibility + hip.visibility) / 2.0;
    return (MotionMeasurement.valid(torsoLeanDeg), minVis + avgVis * 1e-3);
  }

  static double? _averageY(_PixelPoint? a, _PixelPoint? b) {
    if (a != null && b != null) return (a.y + b.y) / 2.0;
    if (a != null) return a.y;
    if (b != null) return b.y;
    return null;
  }

  static double _distance2D(_PixelPoint a, _PixelPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static (MotionMeasurement, double) _measureTripletAngle({
    required PoseLandmark? p1,
    required PoseLandmark? vertex,
    required PoseLandmark? p2,
    required double imageWidth,
    required double imageHeight,
    required double minVisibility,
  }) {
    final c1 = _validateLandmark(p1, minVisibility);
    if (c1 != MotionMetricFailure.none) {
      return (MotionMeasurement.invalid(c1, 'First joint invalid: $c1'), -1.0);
    }
    final cv = _validateLandmark(vertex, minVisibility);
    if (cv != MotionMetricFailure.none) {
      return (MotionMeasurement.invalid(cv, 'Vertex joint invalid: $cv'), -1.0);
    }
    final c2 = _validateLandmark(p2, minVisibility);
    if (c2 != MotionMetricFailure.none) {
      return (MotionMeasurement.invalid(c2, 'Second joint invalid: $c2'), -1.0);
    }

    final angle = _calculateAngle2D(
      _toPixelPoint(p1!, imageWidth, imageHeight),
      _toPixelPoint(vertex!, imageWidth, imageHeight),
      _toPixelPoint(p2!, imageWidth, imageHeight),
    );
    if (!angle.isValid) {
      return (angle, -1.0);
    }
    final minVis = math.min(
      p1.visibility,
      math.min(vertex.visibility, p2.visibility),
    );
    final avgVis = (p1.visibility + vertex.visibility + p2.visibility) / 3.0;
    // Prioritize bottleneck visibility, breaking ties by mean triplet visibility.
    return (angle, minVis + avgVis * 1e-3);
  }

  static MotionMeasurement _selectBestMeasurement(
    MotionMeasurement left,
    double leftScore,
    MotionMeasurement right,
    double rightScore,
  ) {
    if (left.isValid && right.isValid) {
      return leftScore >= rightScore ? left : right;
    }
    if (left.isValid) return left;
    if (right.isValid) return right;
    return left;
  }

  static bool _computeWristAboveShoulder({
    required PoseLandmark? lShoulder,
    required PoseLandmark? lWrist,
    required PoseLandmark? rShoulder,
    required PoseLandmark? rWrist,
    required double imageWidth,
    required double imageHeight,
    required double minVisibility,
  }) {
    final lValid = _validateLandmark(lShoulder, minVisibility) ==
            MotionMetricFailure.none &&
        _validateLandmark(lWrist, minVisibility) == MotionMetricFailure.none;
    final rValid = _validateLandmark(rShoulder, minVisibility) ==
            MotionMetricFailure.none &&
        _validateLandmark(rWrist, minVisibility) == MotionMetricFailure.none;

    if (!lValid && !rValid) return false;

    final lScore = lValid
        ? math.min(lShoulder!.visibility, lWrist!.visibility)
        : -1.0;
    final rScore = rValid
        ? math.min(rShoulder!.visibility, rWrist!.visibility)
        : -1.0;

    final useLeft = lValid && (!rValid || lScore >= rScore);
    final sh = useLeft ? lShoulder! : rShoulder!;
    final wr = useLeft ? lWrist! : rWrist!;

    final pSh = _toPixelPoint(sh, imageWidth, imageHeight);
    final pWr = _toPixelPoint(wr, imageWidth, imageHeight);
    return pWr.y < pSh.y;
  }

  static LatPulldownSideFeatures _extractSide({
    required String sideKey,
    required int shoulderId,
    required int elbowId,
    required int wristId,
    required PoseLandmark? shoulderLm,
    required PoseLandmark? elbowLm,
    required PoseLandmark? wristLm,
    required double? shoulderWidthPx,
    required double imageWidth,
    required double imageHeight,
    required double minVisibility,
  }) {
    final shCheck = _validateLandmark(shoulderLm, minVisibility);
    final elCheck = _validateLandmark(elbowLm, minVisibility);
    final wrCheck = _validateLandmark(wristLm, minVisibility);

    // 1. Calculate 2D Elbow angle (Shoulder -> Elbow -> Wrist)
    MotionMeasurement elbowAngle;
    double elbowVisibilityScore = 0.0;
    if (shCheck != MotionMetricFailure.none) {
      elbowAngle =
          MotionMeasurement.invalid(shCheck, 'Shoulder invalid: $shCheck');
    } else if (elCheck != MotionMetricFailure.none) {
      elbowAngle =
          MotionMeasurement.invalid(elCheck, 'Elbow invalid: $elCheck');
    } else if (wrCheck != MotionMetricFailure.none) {
      elbowAngle =
          MotionMeasurement.invalid(wrCheck, 'Wrist invalid: $wrCheck');
    } else {
      final pSh = _toPixelPoint(shoulderLm!, imageWidth, imageHeight);
      final pEl = _toPixelPoint(elbowLm!, imageWidth, imageHeight);
      final pWr = _toPixelPoint(wristLm!, imageWidth, imageHeight);
      elbowAngle = _calculateAngle2D(pSh, pEl, pWr);
      if (elbowAngle.isValid) {
        final minVis = math.min(
          shoulderLm.visibility,
          math.min(elbowLm.visibility, wristLm.visibility),
        );
        final avgVis =
            (shoulderLm.visibility + elbowLm.visibility + wristLm.visibility) /
                3.0;
        elbowVisibilityScore = minVis + avgVis * 1e-3;
      }
    }

    // 2. Relative Wrist Positions (Requires shoulder, wrist, and valid shoulderWidth)
    MotionMeasurement wristRelY;
    MotionMeasurement wristRelX;
    MotionMeasurement wristDist;

    if (shoulderWidthPx == null || shoulderWidthPx < minShoulderWidthPx) {
      const reason = 'Shoulder width denominator invalid or degenerate';
      wristRelY = const MotionMeasurement.invalid(
          MotionMetricFailure.degenerateGeometry, reason);
      wristRelX = const MotionMeasurement.invalid(
          MotionMetricFailure.degenerateGeometry, reason);
      wristDist = const MotionMeasurement.invalid(
          MotionMetricFailure.degenerateGeometry, reason);
    } else if (shCheck != MotionMetricFailure.none) {
      wristRelY = MotionMeasurement.invalid(shCheck, 'Shoulder invalid');
      wristRelX = MotionMeasurement.invalid(shCheck, 'Shoulder invalid');
      wristDist = MotionMeasurement.invalid(shCheck, 'Shoulder invalid');
    } else if (wrCheck != MotionMetricFailure.none) {
      wristRelY = MotionMeasurement.invalid(wrCheck, 'Wrist invalid');
      wristRelX = MotionMeasurement.invalid(wrCheck, 'Wrist invalid');
      wristDist = MotionMeasurement.invalid(wrCheck, 'Wrist invalid');
    } else {
      final pSh = _toPixelPoint(shoulderLm!, imageWidth, imageHeight);
      final pWr = _toPixelPoint(wristLm!, imageWidth, imageHeight);

      final dy = (pWr.y - pSh.y) / shoulderWidthPx;
      final dx = (pWr.x - pSh.x) / shoulderWidthPx;
      final dist =
          math.sqrt(math.pow(pWr.x - pSh.x, 2) + math.pow(pWr.y - pSh.y, 2)) /
              shoulderWidthPx;

      wristRelY = dy.isFinite
          ? MotionMeasurement.valid(dy)
          : const MotionMeasurement.invalid(
              MotionMetricFailure.nonFiniteCoordinate);
      wristRelX = dx.isFinite
          ? MotionMeasurement.valid(dx)
          : const MotionMeasurement.invalid(
              MotionMetricFailure.nonFiniteCoordinate);
      wristDist = dist.isFinite
          ? MotionMeasurement.valid(dist)
          : const MotionMeasurement.invalid(
              MotionMetricFailure.nonFiniteCoordinate);
    }

    return LatPulldownSideFeatures(
      sideKey: sideKey,
      shoulderId: shoulderId,
      elbowId: elbowId,
      wristId: wristId,
      elbowAngleDeg: elbowAngle,
      elbowVisibilityScore: elbowVisibilityScore,
      wristRelY: wristRelY,
      wristRelX: wristRelX,
      wristDistance: wristDist,
    );
  }

  /// Calculates 2D angle in degrees [0, 180] formed by [p1] -> [vertex] -> [p2].
  static MotionMeasurement _calculateAngle2D(
      _PixelPoint p1, _PixelPoint vertex, _PixelPoint p2) {
    final v1x = p1.x - vertex.x;
    final v1y = p1.y - vertex.y;
    final v2x = p2.x - vertex.x;
    final v2y = p2.y - vertex.y;

    final l1 = math.sqrt(v1x * v1x + v1y * v1y);
    final l2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (!l1.isFinite ||
        !l2.isFinite ||
        l1 < minSegmentLengthPx ||
        l2 < minSegmentLengthPx) {
      return MotionMeasurement.invalid(
        MotionMetricFailure.degenerateGeometry,
        'Segment length too small or non-finite: l1=$l1, l2=$l2',
      );
    }

    final dot = v1x * v2x + v1y * v2y;
    final cosAngle = (dot / (l1 * l2)).clamp(-1.0, 1.0);
    final angleRad = math.acos(cosAngle);
    final angleDeg = angleRad * (180.0 / math.pi);

    return angleDeg.isFinite
        ? MotionMeasurement.valid(angleDeg)
        : const MotionMeasurement.invalid(
            MotionMetricFailure.nonFiniteCoordinate);
  }

  static _PixelPoint _toPixelPoint(
      PoseLandmark lm, double width, double height) {
    return _PixelPoint(lm.x * width, lm.y * height);
  }

  static PoseLandmark? _findLandmark(List<PoseLandmark> landmarks, int index) {
    if (index < landmarks.length && landmarks[index].index == index) {
      return landmarks[index];
    }
    for (final lm in landmarks) {
      if (lm.index == index) return lm;
    }
    return null;
  }

  static MotionMetricFailure _validateLandmark(
      PoseLandmark? lm, double minVisibility) {
    if (lm == null) {
      return MotionMetricFailure.missingLandmark;
    }
    if (!lm.isVisible(threshold: minVisibility)) {
      return MotionMetricFailure.lowVisibility;
    }
    if (!lm.x.isFinite || !lm.y.isFinite) {
      return MotionMetricFailure.nonFiniteCoordinate;
    }
    if (lm.x < 0.0 || lm.x > 1.0 || lm.y < 0.0 || lm.y > 1.0) {
      return MotionMetricFailure.outOfBoundsCoordinate;
    }
    return MotionMetricFailure.none;
  }

  static LatPulldownSideFeatures _createInvalidSideFeatures({
    required String sideKey,
    required int shoulderId,
    required int elbowId,
    required int wristId,
    required MotionMetricFailure failure,
    String? reason,
  }) {
    final inv = MotionMeasurement.invalid(failure, reason);
    return LatPulldownSideFeatures(
      sideKey: sideKey,
      shoulderId: shoulderId,
      elbowId: elbowId,
      wristId: wristId,
      elbowAngleDeg: inv,
      wristRelY: inv,
      wristRelX: inv,
      wristDistance: inv,
    );
  }
}

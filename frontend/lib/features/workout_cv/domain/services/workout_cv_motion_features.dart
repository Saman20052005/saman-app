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
}

/// Pure Dart service to extract Lat Pulldown motion signals from pose landmarks.
///
/// Designed for deterministic reuse in both live camera streams and offline replay benchmarks.
class WorkoutCvMotionFeatures {
  static const double defaultMinVisibility = 0.45;
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

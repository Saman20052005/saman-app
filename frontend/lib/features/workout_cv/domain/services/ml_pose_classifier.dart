import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../entities/pose_landmark.dart';
import 'phase5_ml_weights_data.dart';
import 'workout_cv_motion_features.dart';

/// Output of an on-device pure-Dart MLP forward pass.
@immutable
class MlPredictionResult {
  final String label;
  final double confidence;
  final List<double> probabilities;
  final int inferenceMicros;

  const MlPredictionResult({
    required this.label,
    required this.confidence,
    required this.probabilities,
    required this.inferenceMicros,
  });

  CameraViewAngle get cameraViewAngle =>
      MlPoseClassifier.labelToCameraViewAngle(label);
}

/// Pure-Dart (< 1 ms/frame, 0 native dependencies) 18-feature geometric extractor
/// and 2-layer MLP classifier (18 -> 16 ReLU -> 3 Softmax) for camera view angle
/// and 5 core exercises.
class MlPoseClassifier {
  static const double _radToDeg = 180.0 / math.pi;

  static const Map<String, String> _slugAliases = <String, String>{
    'pull-up': 'pull-up',
    'lat-pulldown': 'lat-pulldown',
    'squat': 'squat',
    'barbell-back-squat': 'squat',
    'goblet-squat': 'squat',
    'push-up': 'push-up',
    'bicep-curl': 'bicep-curl',
    'db-bicep-curl': 'bicep-curl',
    'dumbbell-bicep-curl': 'bicep-curl',
    'ez-bar-curl': 'bicep-curl',
    'hammer-curl': 'bicep-curl',
    'cable-biceps-curl': 'bicep-curl',
    'preacher-curl': 'bicep-curl',
  };

  const MlPoseClassifier();

  /// Maps any supported registry slug/alias to one of the 5 canonical ML keys,
  /// or returns `null` for exercises outside the 5-exercise Phase 5 scope.
  static String? resolveCanonicalExerciseKey(String exerciseSlug) {
    final normalized = exerciseSlug.toLowerCase().trim();
    if (normalized.isEmpty) return null;
    return _slugAliases[normalized];
  }

  /// Converts a view-angle model label to [CameraViewAngle].
  static CameraViewAngle labelToCameraViewAngle(String? label) {
    switch (label) {
      case 'frontal':
        return CameraViewAngle.frontal;
      case 'oblique45':
        return CameraViewAngle.oblique45;
      case 'side90':
        return CameraViewAngle.side90;
      default:
        return CameraViewAngle.unknown;
    }
  }

  static double _clamp(double val, double lo, double hi) {
    if (!val.isFinite) return lo;
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
  }

  static double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

  static double _angle2dNorm(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
  ) {
    final v1x = ax - bx;
    final v1y = ay - by;
    final v2x = cx - bx;
    final v2y = cy - by;
    final n1 = _hypot(v1x, v1y);
    final n2 = _hypot(v2x, v2y);
    if (n1 < 1e-6 || n2 < 1e-6) {
      return 0.0;
    }
    final dot = v1x * v2x + v1y * v2y;
    final cross = (v1x * v2y - v1y * v2x).abs();
    final angleDeg = math.atan2(cross, dot) * _radToDeg;
    return _clamp(angleDeg / 180.0, 0.0, 1.0);
  }

  static ({double x, double y, double z, double v}) _pt(
    List<PoseLandmark> landmarks,
    int idx,
  ) {
    PoseLandmark? lm;
    if (idx < landmarks.length && landmarks[idx].index == idx) {
      lm = landmarks[idx];
    } else {
      for (final candidate in landmarks) {
        if (candidate.index == idx) {
          lm = candidate;
          break;
        }
      }
    }
    if (lm == null) {
      return (x: 0.0, y: 0.0, z: 0.0, v: 0.0);
    }
    final x = lm.x.isFinite ? lm.x : 0.0;
    final y = lm.y.isFinite ? lm.y : 0.0;
    final z = lm.z.isFinite ? lm.z : 0.0;
    final v = _clamp(lm.visibility, 0.0, 1.0);
    return (x: x, y: y, z: z, v: v);
  }

  /// Extracts the exact 18 invariant geometric features matching
  /// `ml_research/phase5_multi_exercise/feature_extractor.py` to `< 1e-6`.
  static List<double> extractFeatures(List<PoseLandmark> landmarks) {
    final p11 = _pt(landmarks, 11);
    final p12 = _pt(landmarks, 12);
    final p13 = _pt(landmarks, 13);
    final p14 = _pt(landmarks, 14);
    final p15 = _pt(landmarks, 15);
    final p16 = _pt(landmarks, 16);
    final p23 = _pt(landmarks, 23);
    final p24 = _pt(landmarks, 24);
    final p25 = _pt(landmarks, 25);
    final p26 = _pt(landmarks, 26);
    final p27 = _pt(landmarks, 27);
    final p28 = _pt(landmarks, 28);

    // Midpoints & torso scale
    final shoulderMidX = 0.5 * (p11.x + p12.x);
    final shoulderMidY = 0.5 * (p11.y + p12.y);
    final hipMidX = 0.5 * (p23.x + p24.x);
    final hipMidY = 0.5 * (p23.y + p24.y);
    final elbowMidY = 0.5 * (p13.y + p14.y);
    final wristMidY = 0.5 * (p15.y + p16.y);
    final kneeMidY = 0.5 * (p25.y + p26.y);

    final torsoLen = math.max(
      _hypot(shoulderMidX - hipMidX, shoulderMidY - hipMidY),
      1e-3,
    );

    // 1-9: Joint angles normalized by 180 deg
    final leftElbow = _angle2dNorm(p11.x, p11.y, p13.x, p13.y, p15.x, p15.y);
    final rightElbow = _angle2dNorm(p12.x, p12.y, p14.x, p14.y, p16.x, p16.y);

    final wLeft = (p11.v + p13.v + p15.v) / 3.0;
    final wRight = (p12.v + p14.v + p16.v) / 3.0;
    final activeElbow = (wLeft + wRight) > 1e-6
        ? (wLeft * leftElbow + wRight * rightElbow) / (wLeft + wRight)
        : 0.5 * (leftElbow + rightElbow);

    final leftShoulder =
        _angle2dNorm(p23.x, p23.y, p11.x, p11.y, p13.x, p13.y);
    final rightShoulder =
        _angle2dNorm(p24.x, p24.y, p12.x, p12.y, p14.x, p14.y);
    final leftHip = _angle2dNorm(p11.x, p11.y, p23.x, p23.y, p25.x, p25.y);
    final rightHip = _angle2dNorm(p12.x, p12.y, p24.x, p24.y, p26.x, p26.y);
    final leftKnee = _angle2dNorm(p23.x, p23.y, p25.x, p25.y, p27.x, p27.y);
    final rightKnee = _angle2dNorm(p24.x, p24.y, p26.x, p26.y, p28.x, p28.y);

    // 10-12: Torso-normalized vertical relative positions
    final wristRelShoulderY =
        _clamp((wristMidY - shoulderMidY) / torsoLen, -2.5, 2.5);
    final elbowRelShoulderY =
        _clamp((elbowMidY - shoulderMidY) / torsoLen, -2.5, 2.5);
    final hipRelKneeY = _clamp((hipMidY - kneeMidY) / torsoLen, -2.5, 2.5);

    // 13-15: Camera view-angle discriminators
    final shoulderToTorsoRatio =
        _clamp((p11.x - p12.x).abs() / torsoLen, 0.0, 2.5);
    final hipToTorsoRatio =
        _clamp((p23.x - p24.x).abs() / torsoLen, 0.0, 2.5);
    final shoulderZDiff = _clamp((p11.z - p12.z).abs(), 0.0, 2.5);

    // 16: Torso lean relative to vertical axis, normalized by 90 deg
    final dx = (shoulderMidX - hipMidX).abs();
    final dy = (hipMidY - shoulderMidY).abs();
    final double torsoLeanNorm;
    if (dx < 1e-9 && dy < 1e-9) {
      torsoLeanNorm = 0.0;
    } else {
      torsoLeanNorm =
          _clamp((math.atan2(dx, dy) * _radToDeg) / 90.0, 0.0, 1.0);
    }

    // 17-18: Upper-body visibility summary & bilateral asymmetry
    final upperVisMean = _clamp(
      (p11.v + p12.v + p13.v + p14.v + p15.v + p16.v + p23.v + p24.v) / 8.0,
      0.0,
      1.0,
    );
    final leftVisMean = (p11.v + p13.v + p15.v + p23.v) / 4.0;
    final rightVisMean = (p12.v + p14.v + p16.v + p24.v) / 4.0;
    final bilateralVisAsym =
        _clamp((leftVisMean - rightVisMean).abs(), 0.0, 1.0);

    return <double>[
      leftElbow,
      rightElbow,
      activeElbow,
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
      wristRelShoulderY,
      elbowRelShoulderY,
      hipRelKneeY,
      shoulderToTorsoRatio,
      hipToTorsoRatio,
      shoulderZDiff,
      torsoLeanNorm,
      upperVisMean,
      bilateralVisAsym,
    ];
  }

  /// Predicts camera view angle (`frontal`, `oblique45`, `side90`) from landmarks.
  MlPredictionResult? predictViewAngle(List<PoseLandmark> landmarks) {
    if (landmarks.isEmpty) return null;
    final features = extractFeatures(landmarks);
    return predictViewAngleFromFeatures(features);
  }

  /// Predicts camera view angle from precomputed 18-element [features].
  MlPredictionResult? predictViewAngleFromFeatures(List<double> features) {
    if (features.length != Phase5MlWeightsData.inputDim) return null;
    return _predictWithWeights(features, Phase5MlWeightsData.viewAngleModel);
  }

  /// Predicts exercise phase (`top_idle`, `transition`, `bottom_peak`) for the
  /// 5 core exercises, or returns `null` for exercises outside scope.
  MlPredictionResult? predictExercisePhase(
    String exerciseSlug,
    List<PoseLandmark> landmarks,
  ) {
    if (landmarks.isEmpty) return null;
    final canonicalKey = resolveCanonicalExerciseKey(exerciseSlug);
    if (canonicalKey == null) return null;
    final weights = Phase5MlWeightsData.exercisePhaseModels[canonicalKey];
    if (weights == null) return null;
    final features = extractFeatures(landmarks);
    return _predictWithWeights(features, weights);
  }

  /// Predicts exercise phase from precomputed 18-element [features].
  MlPredictionResult? predictExercisePhaseFromFeatures(
    String exerciseSlug,
    List<double> features,
  ) {
    if (features.length != Phase5MlWeightsData.inputDim) return null;
    final canonicalKey = resolveCanonicalExerciseKey(exerciseSlug);
    if (canonicalKey == null) return null;
    final weights = Phase5MlWeightsData.exercisePhaseModels[canonicalKey];
    if (weights == null) return null;
    return _predictWithWeights(features, weights);
  }

  MlPredictionResult _predictWithWeights(
    List<double> features,
    MlMlpLayerWeights weights,
  ) {
    final sw = Stopwatch()..start();

    const inputDim = Phase5MlWeightsData.inputDim;
    const hiddenDim = Phase5MlWeightsData.hiddenDim;
    const outputDim = Phase5MlWeightsData.outputDim;

    final mean = weights.scalerMean;
    final scale = weights.scalerScale;
    final w1 = weights.w1;
    final b1 = weights.b1;
    final w2 = weights.w2;
    final b2 = weights.b2;

    // 1. StandardScaler: x_norm = (x - mean) / scale
    final xNorm = List<double>.filled(inputDim, 0.0);
    for (var i = 0; i < inputDim; i++) {
      final s = scale[i];
      xNorm[i] = (features[i] - mean[i]) / (s == 0.0 ? 1.0 : s);
    }

    // 2. Hidden layer (18 -> 16) + ReLU
    final hidden = List<double>.filled(hiddenDim, 0.0);
    for (var j = 0; j < hiddenDim; j++) {
      var acc = b1[j];
      for (var i = 0; i < inputDim; i++) {
        acc += xNorm[i] * w1[i][j];
      }
      hidden[j] = acc > 0.0 ? acc : 0.0;
    }

    // 3. Output layer (16 -> 3)
    final logits = List<double>.filled(outputDim, 0.0);
    var maxLogit = double.negativeInfinity;
    for (var k = 0; k < outputDim; k++) {
      var acc = b2[k];
      for (var j = 0; j < hiddenDim; j++) {
        acc += hidden[j] * w2[j][k];
      }
      logits[k] = acc;
      if (acc > maxLogit) {
        maxLogit = acc;
      }
    }

    // 4. Numerically stable Softmax
    final probs = List<double>.filled(outputDim, 0.0);
    var sumExp = 0.0;
    for (var k = 0; k < outputDim; k++) {
      final e = math.exp(logits[k] - maxLogit);
      probs[k] = e;
      sumExp += e;
    }

    var bestIdx = 0;
    var bestProb = -1.0;
    for (var k = 0; k < outputDim; k++) {
      final p = sumExp > 0.0 ? probs[k] / sumExp : 1.0 / outputDim;
      probs[k] = p;
      if (p > bestProb) {
        bestProb = p;
        bestIdx = k;
      }
    }

    sw.stop();
    return MlPredictionResult(
      label: weights.labels[bestIdx],
      confidence: bestProb,
      probabilities: List<double>.unmodifiable(probs),
      inferenceMicros: sw.elapsedMicroseconds,
    );
  }
}

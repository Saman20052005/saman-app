import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/bicep_curl_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/overhead_press_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/push_up_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/squat_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_result_screen.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<Map<String, dynamic>> _baseLandmarkMaps({double visibility = 0.95}) {
  return List.generate(
    33,
    (i) => <String, dynamic>{
      'index': i,
      'x': 0.5,
      'y': 0.5,
      'z': 0.0,
      'visibility': visibility,
    },
  );
}

/// Builds a pose event with an exact 2D angle at [vertexIdx] in pixel space.
/// [p1Idx] is placed directly above [vertexIdx] (or below if [p1OffsetY] > 0),
/// and [p2Idx] is rotated by [angleDeg] from the segment (vertex -> p1).
Map<String, dynamic> _armSidePoseEvent({
  required int timestampMs,
  required double elbowAngleDeg,
  bool useRightSideOnly = true,
  bool wristAboveShoulder = false,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: useRightSideOnly ? 0.1 : 0.92);
  final shoulderIdx =
      useRightSideOnly ? PoseLandmark.rightShoulder : PoseLandmark.leftShoulder;
  final elbowIdx =
      useRightSideOnly ? PoseLandmark.rightElbow : PoseLandmark.leftElbow;
  final wristIdx =
      useRightSideOnly ? PoseLandmark.rightWrist : PoseLandmark.leftWrist;

  // Center elbow at (540, 960) px -> (0.5, 0.5)
  const ex = 540.0;
  const ey = 960.0;
  const seg = 180.0;
  final rad = elbowAngleDeg * math.pi / 180.0;

  if (wristAboveShoulder) {
    // Shoulder below elbow? No: for overhead press, shoulder at (540, 1080),
    // elbow moves around shoulder/above, and wrist goes above shoulder as angle opens.
    // Place elbow at (540, 960), shoulder below-left or straight down?
    // Wait: if shoulder is at (540, 960 + seg*cos(rad/2)) etc., simpler:
    // Upper arm goes downward-outward from elbow? Let's place:
    // Shoulder = (540, 1140) -> vector elbow->shoulder = (0, +180) (downward).
    // Wrist = rotated by angleDeg from downward vector:
    //   at angle=80 deg: wrist is slightly above elbow / near shoulder level.
    //   at angle=165 deg: vector elbow->wrist points almost straight UP (y < shoulder.y)!
    landmarks[shoulderIdx] = {
      'index': shoulderIdx,
      'x': ex / _imgW,
      'y': (ey + seg) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[elbowIdx] = {
      'index': elbowIdx,
      'x': ex / _imgW,
      'y': ey / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[wristIdx] = {
      'index': wristIdx,
      'x': (ex + seg * math.sin(rad)) / _imgW,
      'y': (ey + seg * math.cos(rad)) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
  } else {
    // Standard arm pose: Shoulder directly above elbow: (540, 780) -> vec = (0, -180)
    // Wrist rotated by angleDeg from upward vector:
    //   at 180 deg -> straight down (540, 1140)
    //   at 45 deg -> curled upward (above/near shoulder)
    landmarks[shoulderIdx] = {
      'index': shoulderIdx,
      'x': ex / _imgW,
      'y': (ey - seg) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[elbowIdx] = {
      'index': elbowIdx,
      'x': ex / _imgW,
      'y': ey / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
    landmarks[wristIdx] = {
      'index': wristIdx,
      'x': (ex + seg * math.sin(rad)) / _imgW,
      'y': (ey - seg * math.cos(rad)) / _imgH,
      'z': 0.0,
      'visibility': 0.95,
    };
  }

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Map<String, dynamic> _pullUpPoseEvent({
  required int timestampMs,
  required double elbowAngleDeg,
  bool useRightSideOnly = false,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(
    visibility: useRightSideOnly ? 0.1 : 0.95,
  );
  const barY = 400.0;
  const seg = 150.0;
  const leftX = 420.0;
  const rightX = 660.0;
  final rad = elbowAngleDeg * math.pi / 180.0;
  final halfCos = math.cos(rad / 2.0);
  final halfSin = math.sin(rad / 2.0);
  final wristShoulderDist = 2.0 * seg * halfSin;
  final shoulderY = barY + wristShoulderDist;
  final elbowY = barY + wristShoulderDist / 2.0;
  final mouthY = shoulderY - 130.0;
  final noseY = shoulderY - 165.0;

  Map<String, dynamic> lm(int index, double xPx, double yPx, double vis) => {
        'index': index,
        'x': xPx / _imgW,
        'y': yPx / _imgH,
        'z': 0.0,
        'visibility': vis,
      };

  // Both shoulders remain visible for upper-body framing gate.
  landmarks[PoseLandmark.leftShoulder] =
      lm(PoseLandmark.leftShoulder, leftX, shoulderY, 0.95);
  landmarks[PoseLandmark.rightShoulder] =
      lm(PoseLandmark.rightShoulder, rightX, shoulderY, 0.95);

  final leftArmVis = useRightSideOnly ? 0.1 : 0.95;
  landmarks[PoseLandmark.leftElbow] =
      lm(PoseLandmark.leftElbow, leftX - seg * halfCos, elbowY, leftArmVis);
  landmarks[PoseLandmark.leftWrist] =
      lm(PoseLandmark.leftWrist, leftX, barY, leftArmVis);

  landmarks[PoseLandmark.rightElbow] =
      lm(PoseLandmark.rightElbow, rightX + seg * halfCos, elbowY, 0.95);
  landmarks[PoseLandmark.rightWrist] =
      lm(PoseLandmark.rightWrist, rightX, barY, 0.95);

  landmarks[PoseLandmark.leftHip] =
      lm(PoseLandmark.leftHip, 440.0, shoulderY + 320.0, 0.95);
  landmarks[PoseLandmark.rightHip] =
      lm(PoseLandmark.rightHip, 640.0, shoulderY + 320.0, 0.95);

  landmarks[PoseLandmark.mouthLeft] =
      lm(PoseLandmark.mouthLeft, 520.0, mouthY, 0.95);
  landmarks[PoseLandmark.mouthRight] =
      lm(PoseLandmark.mouthRight, 560.0, mouthY, 0.95);
  landmarks[PoseLandmark.nose] = lm(PoseLandmark.nose, 540.0, noseY, 0.95);

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Map<String, dynamic> _squatSidePoseEvent({
  required int timestampMs,
  required double kneeAngleDeg,
  int gen = 5,
}) {
  // Side view: only right leg (24-26-28) has high visibility; upper body occluded.
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const kx = 540.0;
  const ky = 1100.0;
  const seg = 220.0;
  final rad = kneeAngleDeg * math.pi / 180.0;

  landmarks[PoseLandmark.rightHip] = {
    'index': PoseLandmark.rightHip,
    'x': kx / _imgW,
    'y': (ky - seg) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.rightKnee] = {
    'index': PoseLandmark.rightKnee,
    'x': kx / _imgW,
    'y': ky / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };
  landmarks[PoseLandmark.rightAnkle] = {
    'index': PoseLandmark.rightAnkle,
    'x': (kx + seg * math.sin(rad)) / _imgW,
    'y': (ky - seg * math.cos(rad)) / _imgH,
    'z': 0.0,
    'visibility': 0.95,
  };

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Map<String, dynamic> _squatFullBodyPoseEvent({
  required int timestampMs,
  required double kneeAngleDeg,
  required double hipAngleDeg,
  required double torsoLeanDeg,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const hipX = 540.0;
  const hipY = 900.0;
  const torsoLen = 280.0;
  const thighLen = 220.0;
  const shinLen = 220.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final hipRad = hipAngleDeg * math.pi / 180.0;
  final kneeRad = kneeAngleDeg * math.pi / 180.0;

  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);
  final thighAzimuth = leanRad + hipRad;
  final kneeX = hipX + thighLen * math.sin(thighAzimuth);
  final kneeY = hipY - thighLen * math.cos(thighAzimuth);
  final shinAzimuth = thighAzimuth + math.pi - kneeRad;
  final ankleX = kneeX + shinLen * math.sin(shinAzimuth);
  final ankleY = kneeY - shinLen * math.cos(shinAzimuth);

  Map<String, dynamic> lm(int index, double xPx, double yPx) => {
        'index': index,
        'x': (xPx / _imgW).clamp(0.0, 1.0),
        'y': (yPx / _imgH).clamp(0.0, 1.0),
        'z': 0.0,
        'visibility': 0.95,
      };

  landmarks[PoseLandmark.rightShoulder] = lm(PoseLandmark.rightShoulder, shX, shY);
  landmarks[PoseLandmark.rightHip] = lm(PoseLandmark.rightHip, hipX, hipY);
  landmarks[PoseLandmark.rightKnee] = lm(PoseLandmark.rightKnee, kneeX, kneeY);
  landmarks[PoseLandmark.rightAnkle] = lm(PoseLandmark.rightAnkle, ankleX, ankleY);

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Map<String, dynamic> _pushUpFullBodyPoseEvent({
  required int timestampMs,
  required double elbowAngleDeg,
  required double torsoLeanDeg,
  required double bodyAlignmentDeg,
  double visibility = 0.95,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const hipX = 540.0;
  const hipY = 960.0;
  const torsoLen = 220.0;
  const legLen = 240.0;
  const armSeg = 120.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final alignRad = bodyAlignmentDeg * math.pi / 180.0;
  final elbowRad = elbowAngleDeg * math.pi / 180.0;

  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);
  final legAzimuth = leanRad + alignRad;
  final ankX = hipX + legLen * math.sin(legAzimuth);
  final ankY = hipY - legLen * math.cos(legAzimuth);
  final elX = shX;
  final elY = shY + armSeg;
  final wrX = elX + armSeg * math.sin(elbowRad);
  final wrY = elY - armSeg * math.cos(elbowRad);

  Map<String, dynamic> lm(int index, double xPx, double yPx) => {
        'index': index,
        'x': (xPx / _imgW).clamp(0.0, 1.0),
        'y': (yPx / _imgH).clamp(0.0, 1.0),
        'z': 0.0,
        'visibility': visibility,
      };

  landmarks[PoseLandmark.rightShoulder] = lm(PoseLandmark.rightShoulder, shX, shY);
  landmarks[PoseLandmark.rightElbow] = lm(PoseLandmark.rightElbow, elX, elY);
  landmarks[PoseLandmark.rightWrist] = lm(PoseLandmark.rightWrist, wrX, wrY);
  landmarks[PoseLandmark.rightHip] = lm(PoseLandmark.rightHip, hipX, hipY);
  landmarks[PoseLandmark.rightAnkle] = lm(PoseLandmark.rightAnkle, ankX, ankY);

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Map<String, dynamic> _ohpFullBodyPoseEvent({
  required int timestampMs,
  required double elbowAngleDeg,
  required double torsoLeanDeg,
  required bool wristAboveShoulder,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
  const hipX = 540.0;
  const hipY = 1150.0;
  const torsoLen = 250.0;
  const upperArmLen = 140.0;
  const forearmLen = 140.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final elbowRad = elbowAngleDeg * math.pi / 180.0;
  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);

  final ux = wristAboveShoulder ? 120.0 : 0.0;
  final uy = wristAboveShoulder ? -70.0 : upperArmLen;
  final elX = shX + ux;
  final elY = shY + uy;
  final thetaElToSh = math.atan2(shY - elY, shX - elX);
  final thetaElToWr = thetaElToSh + elbowRad;
  final wrX = elX + forearmLen * math.cos(thetaElToWr);
  final wrY = elY + forearmLen * math.sin(thetaElToWr);

  Map<String, dynamic> lm(int index, double xPx, double yPx) => {
        'index': index,
        'x': (xPx / _imgW).clamp(0.0, 1.0),
        'y': (yPx / _imgH).clamp(0.0, 1.0),
        'z': 0.0,
        'visibility': 0.95,
      };

  landmarks[PoseLandmark.rightShoulder] = lm(PoseLandmark.rightShoulder, shX, shY);
  landmarks[PoseLandmark.rightElbow] = lm(PoseLandmark.rightElbow, elX, elY);
  landmarks[PoseLandmark.rightWrist] = lm(PoseLandmark.rightWrist, wrX, wrY);
  landmarks[PoseLandmark.rightHip] = lm(PoseLandmark.rightHip, hipX, hipY);

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Map<String, dynamic> _bicepCurlFullBodyPoseEvent({
  required int timestampMs,
  required double leftElbowAngleDeg,
  required double rightElbowAngleDeg,
  double leftUpperArmSwingDeg = 8.0,
  double rightUpperArmSwingDeg = 8.0,
  double torsoLeanDeg = 6.0,
  double leftArmVisibility = 0.95,
  double rightArmVisibility = 0.95,
  int gen = 5,
}) {
  final landmarks = _baseLandmarkMaps(visibility: 0.1);
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

  Map<String, dynamic> lm(int index, double xPx, double yPx, double vis) => {
        'index': index,
        'x': (xPx / _imgW).clamp(0.0, 1.0),
        'y': (yPx / _imgH).clamp(0.0, 1.0),
        'z': 0.0,
        'visibility': vis,
      };

  landmarks[PoseLandmark.leftShoulder] =
      lm(PoseLandmark.leftShoulder, lShX, lShY, leftArmVisibility);
  landmarks[PoseLandmark.leftElbow] =
      lm(PoseLandmark.leftElbow, lElX, lElY, leftArmVisibility);
  landmarks[PoseLandmark.leftWrist] =
      lm(PoseLandmark.leftWrist, lWrX, lWrY, leftArmVisibility);
  landmarks[PoseLandmark.leftHip] =
      lm(PoseLandmark.leftHip, lHipX, hipY, 0.95);

  landmarks[PoseLandmark.rightShoulder] =
      lm(PoseLandmark.rightShoulder, rShX, rShY, rightArmVisibility);
  landmarks[PoseLandmark.rightElbow] =
      lm(PoseLandmark.rightElbow, rElX, rElY, rightArmVisibility);
  landmarks[PoseLandmark.rightWrist] =
      lm(PoseLandmark.rightWrist, rWrX, rWrY, rightArmVisibility);
  landmarks[PoseLandmark.rightHip] =
      lm(PoseLandmark.rightHip, rHipX, hipY, 0.95);

  return {
    'status': 'detecting',
    'sessionGen': gen,
    'sourceMode': 'camera',
    'timestamp': timestampMs,
    'latencyMs': 16,
    'numPoses': 1,
    'landmarks': landmarks,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
  };
}

Exercise _exercise({
  required String id,
  required String slug,
  required String name,
}) {
  return Exercise(
    id: id,
    slug: slug,
    name: name,
    nameVi: name,
    muscleGroup: 'Full Body',
    targetMuscles: const ['Primary'],
    secondaryMuscles: const [],
    equipment: const ['Bodyweight'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-12',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: const [],
    commonMistakes: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutCvExerciseRegistry', () {
    test('maps all supported exercise slugs and rejects unsupported ones', () {
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'lat-pulldown', slug: 'lat-pulldown'),
        CvExerciseModule.latPulldown,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'pull-up', slug: 'pull-up'),
        CvExerciseModule.pullUp,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'barbell-back-squat', slug: 'barbell-back-squat'),
        CvExerciseModule.squat,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'goblet-squat', slug: 'goblet-squat'),
        CvExerciseModule.squat,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'push-up', slug: 'push-up'),
        CvExerciseModule.pushUp,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'barbell-overhead-press', slug: 'barbell-overhead-press'),
        CvExerciseModule.overheadPress,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'db-shoulder-press', slug: 'dumbbell-shoulder-press'),
        CvExerciseModule.overheadPress,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'db-bicep-curl', slug: 'dumbbell-bicep-curl'),
        CvExerciseModule.bicepCurl,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'ez-bar-curl', slug: 'ez-bar-curl'),
        CvExerciseModule.bicepCurl,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'hammer-curl', slug: 'hammer-curl'),
        CvExerciseModule.bicepCurl,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'cable-biceps-curl', slug: 'cable-biceps-curl'),
        CvExerciseModule.bicepCurl,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'preacher-curl', slug: 'preacher-curl'),
        CvExerciseModule.bicepCurl,
      );

      expect(
        WorkoutCvExerciseRegistry.isSupported(
            id: 'db-bench-press', slug: 'dumbbell-bench-press'),
        isFalse,
      );
      expect(
        WorkoutCvExerciseRegistry.isSupported(
            id: 'seated-cable-row', slug: 'seated-cable-row'),
        isTrue,
      );
      expect(
        WorkoutCvExerciseRegistry.resolveModule(
            id: 'seated-cable-row', slug: 'seated-cable-row'),
        CvExerciseModule.row,
      );
    });
  });

  group('WorkoutCvMotionFeatures.extractMultiExerciseAngles', () {
    test('selects higher-visibility side and computes wristAboveShoulder in pixel space', () {
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

      // Left arm: valid 180 deg, lower visibility (0.55)
      landmarks[PoseLandmark.leftShoulder] = const PoseLandmark(
          index: PoseLandmark.leftShoulder, x: 0.3, y: 0.3, z: 0, visibility: 0.55);
      landmarks[PoseLandmark.leftElbow] = const PoseLandmark(
          index: PoseLandmark.leftElbow, x: 0.3, y: 0.5, z: 0, visibility: 0.55);
      landmarks[PoseLandmark.leftWrist] = const PoseLandmark(
          index: PoseLandmark.leftWrist, x: 0.3, y: 0.7, z: 0, visibility: 0.55);

      // Right arm: exact 90 deg in 1080x1920 pixel space, higher visibility (0.95)
      // Elbow at (540, 960), shoulder at (540, 576) -> y = 0.3,
      // wrist at (924, 960) -> x = 924/1080, y = 0.5
      landmarks[PoseLandmark.rightShoulder] = const PoseLandmark(
          index: PoseLandmark.rightShoulder, x: 0.5, y: 0.3, z: 0, visibility: 0.95);
      landmarks[PoseLandmark.rightElbow] = const PoseLandmark(
          index: PoseLandmark.rightElbow, x: 0.5, y: 0.5, z: 0, visibility: 0.95);
      landmarks[PoseLandmark.rightWrist] = const PoseLandmark(
          index: PoseLandmark.rightWrist, x: 924.0 / 1080.0, y: 0.5, z: 0, visibility: 0.95);

      // Right knee: 180 deg
      landmarks[PoseLandmark.rightHip] = const PoseLandmark(
          index: PoseLandmark.rightHip, x: 0.5, y: 0.5, z: 0, visibility: 0.9);
      landmarks[PoseLandmark.rightKnee] = const PoseLandmark(
          index: PoseLandmark.rightKnee, x: 0.5, y: 0.7, z: 0, visibility: 0.9);
      landmarks[PoseLandmark.rightAnkle] = const PoseLandmark(
          index: PoseLandmark.rightAnkle, x: 0.5, y: 0.9, z: 0, visibility: 0.9);

      final features = WorkoutCvMotionFeatures.extractMultiExerciseAngles(
        frameIndex: 0,
        timestampMs: 100,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );

      expect(features.bestElbowAngleDeg.isValid, isTrue);
      expect(features.bestElbowAngleDeg.value, closeTo(90.0, 1e-4));
      expect(features.bestKneeAngleDeg.isValid, isTrue);
      expect(features.bestKneeAngleDeg.value, closeTo(180.0, 1e-4));
      expect(features.isWristAboveShoulder, isFalse);

      // Move right wrist above right shoulder (y = 0.2 < 0.3)
      landmarks[PoseLandmark.rightWrist] = const PoseLandmark(
          index: PoseLandmark.rightWrist, x: 0.5, y: 0.2, z: 0, visibility: 0.95);
      final overheadFeatures = WorkoutCvMotionFeatures.extractMultiExerciseAngles(
        frameIndex: 1,
        timestampMs: 200,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
      );
      expect(overheadFeatures.isWristAboveShoulder, isTrue);

      // Gate not detecting never fabricates 0.0
      final gatedFeatures = WorkoutCvMotionFeatures.extractMultiExerciseAngles(
        frameIndex: 2,
        timestampMs: 300,
        landmarks: landmarks,
        imageWidth: 1080.0,
        imageHeight: 1920.0,
        isGateDetecting: false,
      );
      expect(gatedFeatures.bestElbowAngleDeg.isValid, isFalse);
      expect(gatedFeatures.bestElbowAngleDeg.value, isNull);
      expect(gatedFeatures.bestKneeAngleDeg.isValid, isFalse);
      expect(gatedFeatures.bestKneeAngleDeg.value, isNull);
      expect(gatedFeatures.isWristAboveShoulder, isFalse);
    });
  });

  group('Multi-Exercise Ground-Truth Kinematic & Gap Loss Tests', () {
    Future<void> emitAndDrain(
      MockWorkoutCvNativeSource source,
      Map<String, dynamic> event,
    ) async {
      source.emitEvent(event);
      await Future<void>.delayed(Duration.zero);
    }

    test('Pull-up full cycle, gap loss > 500ms abort, and summary compatibility', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(exerciseId: 'pull-up', exerciseSlug: 'pull-up');

      const pullUpCycle = <(int, double)>[
        (0, 165),
        (150, 165),
        (250, 165),
        (400, 90),
        (700, 50),
        (900, 52),
        (1100, 85),
        (1350, 165),
        (1550, 165),
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in pullUpCycle) {
        await emitAndDrain(source, _pullUpPoseEvent(timestampMs: t, elbowAngleDeg: angle));
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số lần kéo: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(50.0, 0.5));
      expect(CvFormSummaryCalculator.compute(reps: controller.state.replayRepEvents).totalReps, 1);

      // Start second rep, then inject >500ms gap
      await emitAndDrain(source, _pullUpPoseEvent(timestampMs: 1700, elbowAngleDeg: 90));
      await emitAndDrain(source, _pullUpPoseEvent(timestampMs: 1850, elbowAngleDeg: 50));
      await emitAndDrain(source, _pullUpPoseEvent(timestampMs: 2500, elbowAngleDeg: 165)); // 650ms gap
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Squat (side-view leg only) full cycle, label, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-back-squat',
        exerciseSlug: 'barbell-back-squat',
      );

      const squatCycle = <(int, double)>[
        (0, 170),
        (150, 170),
        (250, 170), // standing hold satisfied
        (400, 130), // descending
        (700, 85),  // bottom (<= 95)
        (950, 120), // ascending (> 110)
        (1250, 165), // return to standing (>= 155)
        (1450, 168), // extended hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, knee) in squatCycle) {
        await emitAndDrain(source, _squatSidePoseEvent(timestampMs: t, kneeAngleDeg: knee));
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(85.0, 0.5));
      expect(controller.state.replayRepEvents.single.durationMs, 1050);

      // Gap loss > 500ms during descent aborts incomplete cycle
      await emitAndDrain(source, _squatSidePoseEvent(timestampMs: 1600, kneeAngleDeg: 130));
      await emitAndDrain(source, _squatSidePoseEvent(timestampMs: 1750, kneeAngleDeg: 88));
      await emitAndDrain(source, _squatSidePoseEvent(timestampMs: 2400, kneeAngleDeg: 170)); // 650ms gap
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);
      expect(controller.state.abortCount, greaterThanOrEqualTo(1));

      // Direct SquatBaseline unit test sanity
      final direct = SquatBaseline();
      for (final (t, knee) in squatCycle) {
        direct.processSample(frameIndex: t, timestampMs: t, kneeAngleDeg: knee, isSampleValid: true);
      }
      expect(direct.completedReps, 1);

      controller.dispose();
      source.dispose();
    });

    test('Push-up (side-view arm only) full cycle, label, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(exerciseId: 'push-up', exerciseSlug: 'push-up');

      const pushUpCycle = <(int, double)>[
        (0, 165),
        (150, 165),
        (250, 165), // extended
        (400, 125), // lowering (< 135)
        (700, 85),  // bottom (<= 95)
        (950, 120), // pushing (> 110)
        (1250, 160), // >= 150
        (1450, 162), // rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in pushUpCycle) {
        await emitAndDrain(source, _armSidePoseEvent(timestampMs: t, elbowAngleDeg: angle));
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(85.0, 0.5));

      // Gap loss > 500ms aborts mid-rep
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 1600, elbowAngleDeg: 120));
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 2250, elbowAngleDeg: 160));
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      final direct = PushUpBaseline();
      for (final (t, angle) in pushUpCycle) {
        direct.processSample(frameIndex: t, timestampMs: t, elbowAngleDeg: angle, isSampleValid: true);
      }
      expect(direct.completedReps, 1);

      controller.dispose();
      source.dispose();
    });

    test('Overhead Press enforces wristAboveShoulder, completes cycle, and aborts on >500ms gap', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-overhead-press',
        exerciseSlug: 'barbell-overhead-press',
      );

      // Verify OverheadPressBaseline rejects >=150 deg when wrist is NOT above shoulder
      final ohp = OverheadPressBaseline();
      ohp.processSample(frameIndex: 0, timestampMs: 0, elbowAngleDeg: 85, isWristAboveShoulder: false, isSampleValid: true);
      ohp.processSample(frameIndex: 1, timestampMs: 250, elbowAngleDeg: 85, isWristAboveShoulder: false, isSampleValid: true);
      ohp.processSample(frameIndex: 2, timestampMs: 400, elbowAngleDeg: 120, isWristAboveShoulder: false, isSampleValid: true);
      final noOverhead = ohp.processSample(frameIndex: 3, timestampMs: 700, elbowAngleDeg: 165, isWristAboveShoulder: false, isSampleValid: true);
      expect(noOverhead.phase, OverheadPressPhase.pressing); // Must NOT reach lockout!

      // Full valid OHP cycle through controller
      const ohpCycle = <(int, double)>[
        (0, 80),
        (150, 80),
        (250, 80),   // ready (<= 95)
        (450, 125),  // pressing (> 110)
        (750, 165),  // lockout (>= 150 & wrist above shoulder)
        (1000, 125), // lowering (< 135)
        (1250, 85),  // rack (<= 95)
        (1450, 82),  // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in ohpCycle) {
        await emitAndDrain(
          source,
          _armSidePoseEvent(
            timestampMs: t,
            elbowAngleDeg: angle,
            wristAboveShoulder: true,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.durationMs, 1000);

      // Gap loss > 500ms aborts mid-rep
      await emitAndDrain(
        source,
        _armSidePoseEvent(timestampMs: 1600, elbowAngleDeg: 125, wristAboveShoulder: true),
      );
      await emitAndDrain(
        source,
        _armSidePoseEvent(timestampMs: 2250, elbowAngleDeg: 85, wristAboveShoulder: true),
      );
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      controller.dispose();
      source.dispose();
    });

    test('Bicep Curl full cycle, label, and >500ms gap abort', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'db-bicep-curl',
        exerciseSlug: 'dumbbell-bicep-curl',
      );

      const curlCycle = <(int, double)>[
        (0, 160),
        (150, 160),
        (250, 160), // extended (>= 145)
        (450, 115), // curling (< 130)
        (750, 50),  // flexed (<= 60)
        (1000, 95), // lowering (> 80)
        (1250, 155), // >= 145
        (1450, 160), // hold >= 150ms -> rep 1
      ];

      final phases = <LatPulldownPhase>{};
      for (final (t, angle) in curlCycle) {
        await emitAndDrain(source, _armSidePoseEvent(timestampMs: t, elbowAngleDeg: angle));
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
        phases.add(controller.state.analysisPhase);
      }

      expect(phases, containsAll(LatPulldownPhase.values));
      expect(controller.state.completedReps, 1);
      expect(controller.state.repCountLabel, 'Số rep: 1');
      expect(controller.state.replayRepEvents.single.minElbowAngleDeg, closeTo(50.0, 0.5));

      // Gap loss > 500ms aborts mid-rep
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 1600, elbowAngleDeg: 110));
      await emitAndDrain(source, _armSidePoseEvent(timestampMs: 2250, elbowAngleDeg: 160));
      expect(controller.state.completedReps, 1);
      expect(controller.state.analysisPhase, LatPulldownPhase.notReady);

      final direct = BicepCurlBaseline();
      for (final (t, angle) in curlCycle) {
        direct.processSample(frameIndex: t, timestampMs: t, elbowAngleDeg: angle, isSampleValid: true);
      }
      expect(direct.completedReps, 1);

      controller.dispose();
      source.dispose();
    });

    test('Squat and Pull-up standard-tempo cycles produce formSummary.validReps >= 1', () async {
      // Squat standard cycle: knee <= 95 deg and duration >= 1500ms
      final squatSource = MockWorkoutCvNativeSource();
      final squatController = WorkoutCvNotifier(squatSource);
      await squatController.initialize(
        exerciseId: 'barbell-back-squat',
        exerciseSlug: 'barbell-back-squat',
      );
      const standardSquatCycle = <(int, double)>[
        (0, 170),
        (150, 170),
        (250, 170),
        (500, 130),
        (850, 105),
        (1200, 85),
        (1550, 120),
        (1900, 165),
        (2150, 168), // duration = 2150 - 500 = 1650ms (within 1.5-4.5s)
      ];
      for (final (t, knee) in standardSquatCycle) {
        await emitAndDrain(squatSource, _squatSidePoseEvent(timestampMs: t, kneeAngleDeg: knee));
      }
      expect(squatController.state.completedReps, 1);
      expect(squatController.state.formSummary.validReps, greaterThanOrEqualTo(1));
      expect(squatController.state.formSummary.toJson()['valid_reps'], greaterThanOrEqualTo(1));
      squatController.dispose();
      squatSource.dispose();

      // Pull-up standard cycle: elbow <= 65 deg and duration >= 1500ms
      final pullUpSource = MockWorkoutCvNativeSource();
      final pullUpController = WorkoutCvNotifier(pullUpSource);
      await pullUpController.initialize(
        exerciseId: 'pull-up',
        exerciseSlug: 'pull-up',
      );
      const standardPullUpCycle = <(int, double)>[
        (0, 165),
        (150, 165),
        (250, 165),
        (500, 90),
        (850, 68),
        (1200, 55),
        (1550, 85),
        (1900, 165),
        (2150, 165), // duration = 2150 - 500 = 1650ms (within 1.5-4.0s)
      ];
      for (final (t, angle) in standardPullUpCycle) {
        await emitAndDrain(pullUpSource, _pullUpPoseEvent(timestampMs: t, elbowAngleDeg: angle));
      }
      expect(pullUpController.state.completedReps, 1);
      expect(pullUpController.state.formSummary.validReps, greaterThanOrEqualTo(1));
      expect(pullUpController.state.formSummary.toJson()['valid_reps'], greaterThanOrEqualTo(1));
      pullUpController.dispose();
      pullUpSource.dispose();
    });

    test('video_replay mode counts Pull-up and Squat reps when left side is occluded', () async {
      // Pull-up video_replay with left arm occluded (visibility 0.1), right arm visible
      final pullUpSource = MockWorkoutCvNativeSource();
      final pullUpController = WorkoutCvNotifier(pullUpSource);
      await pullUpController.initialize(
        exerciseId: 'pull-up',
        exerciseSlug: 'pull-up',
        videoReplay: true,
      );

      const pullUpReplayCycle = <(int, double)>[
        (20, 165),
        (170, 165),
        (270, 165),
        (470, 90),
        (800, 65),
        (1100, 52),
        (1450, 85),
        (1800, 165),
        (2050, 165), // duration = 2050 - 470 = 1580ms (within 1.5-4.0s)
      ];
      for (final (pts, angle) in pullUpReplayCycle) {
        final base = _pullUpPoseEvent(
          timestampMs: pts,
          elbowAngleDeg: angle,
          useRightSideOnly: true,
        );
        await emitAndDrain(pullUpSource, {
          ...base,
          'sourceMode': 'video_replay',
          'videoPtsMs': pts,
          'previewPtsMs': pts,
          'ptsSkewMs': 0,
          'isPtsVerified': true,
        });
      }
      expect(pullUpController.state.completedReps, 1);
      expect(pullUpController.state.formSummary.validReps, 1);
      pullUpController.dispose();
      pullUpSource.dispose();

      // Squat video_replay with left leg occluded (visibility 0.1), right leg visible
      final squatSource = MockWorkoutCvNativeSource();
      final squatController = WorkoutCvNotifier(squatSource);
      await squatController.initialize(
        exerciseId: 'barbell-back-squat',
        exerciseSlug: 'barbell-back-squat',
        videoReplay: true,
      );

      const squatReplayCycle = <(int, double)>[
        (20, 170),
        (170, 170),
        (270, 170),
        (470, 130),
        (800, 100),
        (1100, 85),
        (1450, 120),
        (1800, 165),
        (2050, 168), // duration = 2050 - 470 = 1580ms (within 1.5-4.5s)
      ];
      for (final (pts, knee) in squatReplayCycle) {
        final base = _squatSidePoseEvent(timestampMs: pts, kneeAngleDeg: knee);
        await emitAndDrain(squatSource, {
          ...base,
          'sourceMode': 'video_replay',
          'videoPtsMs': pts,
          'previewPtsMs': pts,
          'ptsSkewMs': 0,
          'isPtsVerified': true,
        });
      }
      expect(squatController.state.completedReps, 1);
      expect(squatController.state.formSummary.validReps, 1);
      squatController.dispose();
      squatSource.dispose();
    });

    test('Squat with full shoulder+hip+knee+ankle landmarks grades straight back as validReps == 1 and 62-deg lean as validReps == 0', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-back-squat',
        exerciseSlug: 'barbell-back-squat',
      );

      // Rep 1: standard form (knee=85, hip=80, torsoLean=28, duration=1700ms)
      const standardSquat = <(int, double, double, double)>[
        (0, 172, 172, 8),
        (150, 172, 172, 8),
        (250, 172, 172, 8),
        (500, 130, 120, 18),
        (850, 105, 95, 24),
        (1200, 85, 80, 28),
        (1550, 120, 112, 22),
        (1950, 165, 165, 10),
        (2200, 172, 172, 8),
      ];
      for (final (t, knee, hip, lean) in standardSquat) {
        await emitAndDrain(
          source,
          _squatFullBodyPoseEvent(
            timestampMs: t,
            kneeAngleDeg: knee,
            hipAngleDeg: hip,
            torsoLeanDeg: lean,
          ),
        );
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      final rep1 = controller.state.replayRepEvents.first as SquatRepEvent;
      expect(rep1.isBackStraight, isTrue);
      expect(rep1.maxTorsoLeanDeg, closeTo(28.0, 0.5));

      // Rep 2: excessive forward lean (knee=88, hip=70, torsoLean=62, duration=1700ms)
      const leanSquat = <(int, double, double, double)>[
        (2500, 130, 115, 40),
        (2850, 96, 76, 58),
        (3200, 88, 70, 62),
        (3550, 122, 112, 42),
        (3950, 165, 165, 12),
        (4200, 172, 172, 8),
      ];
      for (final (t, knee, hip, lean) in leanSquat) {
        await emitAndDrain(
          source,
          _squatFullBodyPoseEvent(
            timestampMs: t,
            kneeAngleDeg: knee,
            hipAngleDeg: hip,
            torsoLeanDeg: lean,
          ),
        );
      }

      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.totalReps, 2);
      expect(controller.state.formSummary.validReps, 1);
      final rep2 = controller.state.replayRepEvents[1] as SquatRepEvent;
      expect(rep2.isBackStraight, isFalse);
      expect(rep2.maxTorsoLeanDeg, closeTo(62.0, 0.5));

      controller.dispose();
      source.dispose();
    });

    test('Push-up full-body integration grades standard plank as validReps == 1, 142-deg sag as validReps == 0, and preserves bottom 0.38 visibility', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'push-up',
        exerciseSlug: 'push-up',
      );

      // Rep 1: standard plank (elbow=85, torsoLean=82, bodyAlignment=174, duration=1450ms)
      // Bottom frames drop visibility to 0.38 (< 0.45, >= 0.35)
      const standardPushUp = <(int, double, double, double, double)>[
        (0, 168, 82, 174, 0.95),
        (150, 168, 82, 174, 0.95),
        (250, 168, 82, 174, 0.95),
        (500, 128, 82, 174, 0.75),
        (850, 96, 82, 174, 0.38),
        (1150, 85, 82, 174, 0.38),
        (1450, 122, 82, 174, 0.75),
        (1750, 162, 82, 174, 0.95),
        (1950, 168, 82, 174, 0.95),
      ];
      for (final (t, elbow, lean, align, vis) in standardPushUp) {
        await emitAndDrain(
          source,
          _pushUpFullBodyPoseEvent(
            timestampMs: t,
            elbowAngleDeg: elbow,
            torsoLeanDeg: lean,
            bodyAlignmentDeg: align,
            visibility: vis,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      final rep1 = controller.state.replayRepEvents.first as PushUpRepEvent;
      expect(rep1.isPlankAligned, isTrue);
      expect(rep1.minBodyAlignmentDeg, closeTo(174.0, 0.5));

      // Rep 2: hip sag / pike (bodyAlignment=142 < 155, duration=1450ms) -> validReps stays 1
      const sagPushUp = <(int, double, double, double)>[
        (2300, 128, 78, 154),
        (2700, 88, 76, 142),
        (3150, 122, 78, 152),
        (3550, 164, 80, 166),
        (3750, 168, 80, 168),
      ];
      for (final (t, elbow, lean, align) in sagPushUp) {
        await emitAndDrain(
          source,
          _pushUpFullBodyPoseEvent(
            timestampMs: t,
            elbowAngleDeg: elbow,
            torsoLeanDeg: lean,
            bodyAlignmentDeg: align,
          ),
        );
      }

      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.totalReps, 2);
      expect(controller.state.formSummary.validReps, 1);
      final rep2 = controller.state.replayRepEvents[1] as PushUpRepEvent;
      expect(rep2.isPlankAligned, isFalse);
      expect(rep2.minBodyAlignmentDeg, closeTo(142.0, 0.5));

      controller.dispose();
      source.dispose();
    });

    test('Overhead Press full-body integration grades peak lockout >= 155 + vertical back as validReps == 1 and 32-deg arch as validReps == 0', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'barbell-overhead-press',
        exerciseSlug: 'barbell-overhead-press',
      );

      // Rep 1: standard OHP (rack 85 -> lockout 165 + wristAboveShoulder + lean 12, duration 1550ms)
      const standardOhp = <(int, double, double)>[
        (0, 85, 12),
        (150, 85, 12),
        (250, 85, 12),
        (500, 120, 12),
        (950, 165, 12),
        (1400, 125, 12),
        (1850, 88, 12),
        (2050, 85, 12),
      ];
      for (final (t, elbow, lean) in standardOhp) {
        await emitAndDrain(
          source,
          _ohpFullBodyPoseEvent(
            timestampMs: t,
            elbowAngleDeg: elbow,
            torsoLeanDeg: lean,
            wristAboveShoulder: true,
          ),
        );
        expect(controller.state.trackingStatus, TrackingStatus.detecting);
      }

      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      expect(controller.state.formSummary.avgElbowAngleDeg, closeTo(165.0, 0.5));
      final rep1 = controller.state.replayRepEvents.first as OverheadPressRepEvent;
      expect(rep1.isBackVertical, isTrue);
      expect(rep1.peakLockoutAngleDeg, closeTo(165.0, 0.5));

      // Rep 2: excessive torso arch (lean 32 > 25) -> totalReps 2, validReps remains 1
      const archOhp = <(int, double, double)>[
        (2400, 120, 22),
        (2900, 165, 32),
        (3400, 125, 20),
        (3800, 88, 12),
        (4000, 85, 12),
      ];
      for (final (t, elbow, lean) in archOhp) {
        await emitAndDrain(
          source,
          _ohpFullBodyPoseEvent(
            timestampMs: t,
            elbowAngleDeg: elbow,
            torsoLeanDeg: lean,
            wristAboveShoulder: true,
          ),
        );
      }

      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.totalReps, 2);
      expect(controller.state.formSummary.validReps, 1);
      final rep2 = controller.state.replayRepEvents[1] as OverheadPressRepEvent;
      expect(rep2.isBackVertical, isFalse);

      controller.dispose();
      source.dispose();
    });

    test('Bicep Curl full-body integration tracks alternating curls without jumping, penalizes 48-deg elbow swing, and supports preacher-curl 50-deg', () async {
      final source = MockWorkoutCvNativeSource();
      final controller = WorkoutCvNotifier(source);
      await controller.initialize(
        exerciseId: 'db-bicep-curl',
        exerciseSlug: 'dumbbell-bicep-curl',
      );

      // Rep 1: Left curls while Right is idle with higher vis (0.99 > 0.85) -> validReps == 1
      const leftRep = <(int, double, double, double)>[
        (0, 162, 165, 8),
        (150, 162, 165, 8),
        (250, 162, 165, 8),
        (500, 118, 165, 10),
        (1000, 50, 165, 12),
        (1500, 95, 165, 10),
        (1950, 155, 165, 8),
        (2150, 162, 165, 8),
      ];
      for (final (t, lElbow, rElbow, swing) in leftRep) {
        await emitAndDrain(
          source,
          _bicepCurlFullBodyPoseEvent(
            timestampMs: t,
            leftElbowAngleDeg: lElbow,
            rightElbowAngleDeg: rElbow,
            leftUpperArmSwingDeg: swing,
            leftArmVisibility: 0.85,
            rightArmVisibility: 0.99,
          ),
        );
      }
      expect(controller.state.completedReps, 1);
      expect(controller.state.formSummary.validReps, 1);
      final rep1 = controller.state.replayRepEvents.first as BicepCurlRepEvent;
      expect(rep1.activeSide, 'left');
      expect(rep1.isElbowPinned, isTrue);

      // Rep 2: Right curls with 48-deg elbow swing -> totalReps == 2, validReps stays 1
      const rightSwingRep = <(int, double, double, double)>[
        (2400, 162, 118, 25),
        (2900, 162, 50, 48),
        (3400, 162, 95, 28),
        (3850, 162, 155, 10),
        (4050, 162, 165, 8),
      ];
      for (final (t, lElbow, rElbow, swing) in rightSwingRep) {
        await emitAndDrain(
          source,
          _bicepCurlFullBodyPoseEvent(
            timestampMs: t,
            leftElbowAngleDeg: lElbow,
            rightElbowAngleDeg: rElbow,
            rightUpperArmSwingDeg: swing,
            leftArmVisibility: 0.99,
            rightArmVisibility: 0.85,
          ),
        );
      }
      expect(controller.state.completedReps, 2);
      expect(controller.state.formSummary.totalReps, 2);
      expect(controller.state.formSummary.validReps, 1);
      final rep2 = controller.state.replayRepEvents[1] as BicepCurlRepEvent;
      expect(rep2.activeSide, 'right');
      expect(rep2.isElbowPinned, isFalse);

      controller.dispose();
      source.dispose();

      // Preacher curl slug allows 50-deg braced upper arm (<= 75 deg)
      final preacherSource = MockWorkoutCvNativeSource();
      final preacherController = WorkoutCvNotifier(preacherSource);
      await preacherController.initialize(
        exerciseId: 'preacher-curl',
        exerciseSlug: 'preacher-curl',
      );
      const preacherRep = <(int, double)>[
        (0, 160),
        (250, 160),
        (500, 118),
        (1000, 50),
        (1500, 95),
        (1950, 155),
        (2150, 160),
      ];
      for (final (t, elbow) in preacherRep) {
        await emitAndDrain(
          preacherSource,
          _bicepCurlFullBodyPoseEvent(
            timestampMs: t,
            leftElbowAngleDeg: elbow,
            rightElbowAngleDeg: elbow,
            leftUpperArmSwingDeg: 50.0,
            rightUpperArmSwingDeg: 50.0,
          ),
        );
      }
      expect(preacherController.state.completedReps, 1);
      expect(preacherController.state.formSummary.validReps, 1);
      preacherController.dispose();
      preacherSource.dispose();
    });
  });

  group('ActiveWorkoutScreen & WorkoutCvScreen Multi-Exercise Integration', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'ActiveWorkoutScreen opens WorkoutCvScreen for Squat, Push-up, OHP, Bicep Curl, and keeps Dumbbell Bench Press Deferred',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final source = MockWorkoutCvNativeSource();

        final supportedExercises = [
          _exercise(
              id: 'barbell-back-squat',
              slug: 'barbell-back-squat',
              name: 'Barbell Back Squat'),
          _exercise(id: 'push-up', slug: 'push-up', name: 'Push-up'),
          _exercise(
              id: 'barbell-overhead-press',
              slug: 'barbell-overhead-press',
              name: 'Overhead Press'),
          _exercise(
              id: 'db-bicep-curl',
              slug: 'dumbbell-bicep-curl',
              name: 'Dumbbell Bicep Curl'),
        ];

        for (final ex in supportedExercises) {
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('scope_${ex.slug}'),
              overrides: [
                workoutCvNativeSourceProvider.overrideWithValue(source),
              ],
              child: MaterialApp(
                home: ActiveWorkoutScreen(
                  exercises: [ex],
                  autoTick: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
              find.byKey(const ValueKey('active_workout_form_check_badge')));
          await tester.pumpAndSettle();

          // Source sheet opens for supported Android exercise; choose real-time camera
          await tester
              .tap(find.byKey(const ValueKey('form_check_mode_realtime')));
          await tester.pumpAndSettle();

          expect(find.byType(WorkoutCvScreen), findsOneWidget,
              reason: '${ex.slug} should open WorkoutCvScreen');
          expect(find.text(ex.name), findsOneWidget);
          expect(find.byKey(const ValueKey('workout_cv_replay_rep_count')),
              findsOneWidget);
          expect(find.text('Reps: 0'), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
          await tester.pumpAndSettle();
          expect(find.byType(WorkoutCvScreen), findsNothing);
        }

        // Unsupported exercise (Dumbbell Bench Press) must show Deferred modal directly
        final benchPress = _exercise(
          id: 'db-bench-press',
          slug: 'dumbbell-bench-press',
          name: 'Dumbbell Bench Press',
        );
        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey('scope_bench_press'),
            overrides: [
              workoutCvNativeSourceProvider.overrideWithValue(source),
            ],
            child: MaterialApp(
              home: ActiveWorkoutScreen(
                exercises: [benchPress],
                autoTick: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
            find.byKey(const ValueKey('active_workout_form_check_badge')));
        await tester.pumpAndSettle();

        expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
        expect(find.byType(WorkoutCvScreen), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        source.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'WorkoutCvResultScreen renders Squat knee criteria and Pull-up elbow criteria dynamically',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: WorkoutCvResultScreen(
              exerciseId: 'barbell-back-squat',
              exerciseSlug: 'barbell-back-squat',
              exerciseName: 'Barbell Back Squat',
              repHistory: [
                LatPulldownRepEvent(
                  repNumber: 1,
                  startTimestampMs: 500,
                  bottomTimestampMs: 1200,
                  endTimestampMs: 2350,
                  durationMs: 1850,
                  minElbowAngleDeg: 85.0,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Knee ≤ 95°'), findsOneWidget);
        expect(find.text('1.5–4.5s'), findsOneWidget);
        expect(find.textContaining('Knee angle: 85.0°'), findsOneWidget);
        expect(find.text('STANDARD: 1/1 REPS'), findsOneWidget);

        await tester.pumpWidget(
          const MaterialApp(
            home: WorkoutCvResultScreen(
              exerciseId: 'pull-up',
              exerciseSlug: 'pull-up',
              exerciseName: 'Pull-up',
              repHistory: [
                LatPulldownRepEvent(
                  repNumber: 1,
                  startTimestampMs: 500,
                  bottomTimestampMs: 1200,
                  endTimestampMs: 2350,
                  durationMs: 1850,
                  minElbowAngleDeg: 55.0,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Angle ≤ 65°'), findsOneWidget);
        expect(find.text('1.5–4s'), findsOneWidget);
        expect(find.textContaining('Elbow angle: 55.0°'), findsOneWidget);
        expect(find.text('STANDARD: 1/1 REPS'), findsOneWidget);

        await tester.pumpWidget(
          const MaterialApp(
            home: WorkoutCvResultScreen(
              exerciseId: 'barbell-overhead-press',
              exerciseSlug: 'barbell-overhead-press',
              exerciseName: 'Overhead Press',
              repHistory: [
                OverheadPressRepEvent(
                  repNumber: 1,
                  startTimestampMs: 500,
                  bottomTimestampMs: 1200,
                  endTimestampMs: 2350,
                  durationMs: 1850,
                  minElbowAngleDeg: 165.0,
                  minRackElbowAngleDeg: 85.0,
                  maxTorsoLeanDeg: 12.0,
                  isBackVertical: true,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lockout ≥ 155°'), findsOneWidget);
        expect(find.text('1.5–4s'), findsOneWidget);
        expect(find.textContaining('Peak lockout: 165.0°'), findsOneWidget);
        expect(find.text('STANDARD: 1/1 REPS'), findsOneWidget);
      },
    );
  });
}

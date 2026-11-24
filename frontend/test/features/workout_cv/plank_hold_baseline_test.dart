import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/plank_hold_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

const double _imgW = 1080.0;
const double _imgH = 1920.0;

List<PoseLandmark> _buildPlankLandmarks({
  required double bodyAlignmentDeg,
  double torsoLeanDeg = 85.0,
  double visibility = 0.90,
}) {
  const hipX = 540.0;
  const hipY = 960.0;
  const torsoLen = 220.0;
  const legLen = 240.0;

  final leanRad = torsoLeanDeg * math.pi / 180.0;
  final alignRad = bodyAlignmentDeg * math.pi / 180.0;

  final shX = hipX + torsoLen * math.sin(leanRad);
  final shY = hipY - torsoLen * math.cos(leanRad);

  final legAzimuth = leanRad + alignRad;
  final ankX = hipX + legLen * math.sin(legAzimuth);
  final ankY = hipY - legLen * math.cos(legAzimuth);

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
      px(PoseLandmark.leftShoulder, shX, shY, visibility);
  landmarks[PoseLandmark.leftHip] =
      px(PoseLandmark.leftHip, hipX, hipY, visibility);
  landmarks[PoseLandmark.leftAnkle] =
      px(PoseLandmark.leftAnkle, ankX, ankY, visibility);

  landmarks[PoseLandmark.rightShoulder] =
      px(PoseLandmark.rightShoulder, shX, shY, visibility);
  landmarks[PoseLandmark.rightHip] =
      px(PoseLandmark.rightHip, hipX, hipY, visibility);
  landmarks[PoseLandmark.rightAnkle] =
      px(PoseLandmark.rightAnkle, ankX, ankY, visibility);

  return landmarks;
}

Map<String, dynamic> _plankPoseEvent({
  required int timestampMs,
  required double bodyAlignmentDeg,
  double torsoLeanDeg = 85.0,
  double visibility = 0.90,
}) {
  final landmarks = _buildPlankLandmarks(
    bodyAlignmentDeg: bodyAlignmentDeg,
    torsoLeanDeg: torsoLeanDeg,
    visibility: visibility,
  );
  return {
    'status': 'detecting',
    'timestamp': timestampMs,
    'latencyMs': 12,
    'numPoses': 1,
    'inputImageWidth': _imgW,
    'inputImageHeight': _imgH,
    'landmarks': landmarks
        .map((l) => {
              'index': l.index,
              'x': l.x,
              'y': l.y,
              'z': l.z,
              'visibility': l.visibility,
            })
        .toList(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlankHoldBaseline & WorkoutCvNotifier Plank Hold Tests', () {
    test('holding 3.2s with >= 165 deg emits exactly 3 events (3s) and keeps 5 canonical toJson keys', () {
      final baseline = PlankHoldBaseline();
      final emitted = <PlankHoldRepEvent>[];

      // 0ms..3200ms in 400ms increments (all <= 600ms maxAllowedGapMs)
      for (int i = 0; i <= 8; i++) {
        final t = i * 400;
        final features = WorkoutCvMotionFeatures.extractPlankHoldFeatures(
          frameIndex: i,
          timestampMs: t,
          landmarks: _buildPlankLandmarks(
            bodyAlignmentDeg: 175.0,
            torsoLeanDeg: 85.0,
            visibility: 0.40, // >= pushUpMinVisibility (0.35), < default (0.45)
          ),
          imageWidth: _imgW,
          imageHeight: _imgH,
        );
        expect(features.bodyAlignmentDeg.isValid, isTrue);
        expect(features.bodyAlignmentDeg.value, closeTo(175.0, 0.5));

        final res = baseline.processPlankHoldFeatures(features);
        expect(res.phase, PlankHoldPhase.holding);
        if (res.newRepEvent != null) {
          emitted.add(res.newRepEvent!);
        }
      }

      expect(emitted.length, 3);
      expect(baseline.completedReps, 3);
      expect(baseline.validSeconds, 3);
      expect(baseline.accumulatedValidMs, 200);
      for (final rep in emitted) {
        expect(rep.isAligned, isTrue);
        expect(rep.validHoldMs, 1000);
        expect(rep.durationMs, 1000);
        expect(rep.minElbowAngleDeg, closeTo(175.0, 0.5));
      }

      final summary = CvFormSummaryCalculator.compute(
        reps: baseline.repHistory,
        module: CvExerciseModule.plankHold,
      );
      expect(summary.totalReps, 3);
      expect(summary.validReps, 3);
      expect(summary.fastReps, 0);

      final json = summary.toJson();
      expect(
        json.keys.toSet(),
        equals({
          'valid_reps',
          'fast_reps',
          'avg_elbow_angle_deg',
          'avg_tempo_sec',
          'abort_count',
        }),
      );
      expect(json['valid_reps'], 3);
    });

    test('hip sag (140 deg < 165 deg) does not add seconds and resets hold', () {
      final baseline = PlankHoldBaseline();

      // Hold properly for 800ms (0 -> 400 -> 800)
      for (final t in [0, 400, 800]) {
        baseline.processSample(
          frameIndex: t,
          timestampMs: t,
          bodyAlignmentDeg: 172.0,
          torsoLeanDeg: 85.0,
          isSampleValid: true,
        );
      }
      expect(baseline.phase, PlankHoldPhase.holding);
      expect(baseline.accumulatedValidMs, 800);
      expect(baseline.completedReps, 0);

      // Hip sags to 140 deg at t = 1200 -> must NOT add 400ms to reach 1s; resets hold
      final sagResult = baseline.processSample(
        frameIndex: 1200,
        timestampMs: 1200,
        bodyAlignmentDeg: 140.0,
        torsoLeanDeg: 85.0,
        isSampleValid: true,
      );
      expect(sagResult.phase, PlankHoldPhase.notReady);
      expect(sagResult.transitionReason, 'hipMisaligned');
      expect(sagResult.resetReason, 'hipMisaligned');
      expect(baseline.completedReps, 0);
      expect(baseline.accumulatedValidMs, 0);

      // Recovering to 174 deg starts fresh hold from 0ms, not 800ms
      baseline.processSample(
        frameIndex: 1600,
        timestampMs: 1600,
        bodyAlignmentDeg: 174.0,
        torsoLeanDeg: 85.0,
        isSampleValid: true,
      );
      baseline.processSample(
        frameIndex: 2000,
        timestampMs: 2000,
        bodyAlignmentDeg: 174.0,
        torsoLeanDeg: 85.0,
        isSampleValid: true,
      );
      expect(baseline.completedReps, 0);
      expect(baseline.accumulatedValidMs, 400);
    });

    test('gap > 600ms resets hold, rejects non-monotonic timestamps, and resets cleanly', () {
      final baseline = PlankHoldBaseline();
      baseline.processSample(
        frameIndex: 0,
        timestampMs: 0,
        bodyAlignmentDeg: 175.0,
        isSampleValid: true,
      );
      baseline.processSample(
        frameIndex: 1,
        timestampMs: 500,
        bodyAlignmentDeg: 175.0,
        isSampleValid: true,
      );
      expect(baseline.accumulatedValidMs, 500);

      final nonMono = baseline.processSample(
        frameIndex: 2,
        timestampMs: 500,
        bodyAlignmentDeg: 175.0,
        isSampleValid: true,
      );
      expect(nonMono.resetReason, 'droppedNonMonotonicTimestamp');

      // 700ms gap (> 600ms maxAllowedGapMs) resets accumulated ms
      final afterGap = baseline.processSample(
        frameIndex: 3,
        timestampMs: 1200,
        bodyAlignmentDeg: 175.0,
        isSampleValid: true,
      );
      expect(afterGap.resetReason, 'dataLossGapBeforeValidSample');
      expect(baseline.accumulatedValidMs, 0);
      expect(baseline.completedReps, 0);

      baseline.reset();
      expect(baseline.phase, PlankHoldPhase.notReady);
      expect(baseline.completedReps, 0);
    });

    test('WorkoutCvNotifier integrates plank and side-plank with Giữ chuẩn label', () async {
      Future<void> emitAndDrain(
        MockWorkoutCvNativeSource source,
        Map<String, dynamic> event,
      ) async {
        source.emitEvent(event);
        await Future<void>.delayed(Duration.zero);
      }

      for (final slug in ['plank', 'side-plank']) {
        final source = MockWorkoutCvNativeSource();
        final controller = WorkoutCvNotifier(source);
        await controller.initialize(exerciseId: slug, exerciseSlug: slug);

        for (int i = 0; i <= 8; i++) {
          await emitAndDrain(
            source,
            _plankPoseEvent(
              timestampMs: i * 400,
              bodyAlignmentDeg: 174.0,
              visibility: 0.40,
            ),
          );
          expect(controller.state.trackingStatus, TrackingStatus.detecting);
        }

        expect(controller.state.completedReps, 3);
        expect(controller.state.repCountLabel, 'Giữ chuẩn: 3s');
        expect(controller.state.formSummary.validReps, 3);
        expect(
          controller.state.formSummary.toJson().keys.toSet(),
          equals({
            'valid_reps',
            'fast_reps',
            'avg_elbow_angle_deg',
            'avg_tempo_sec',
            'abort_count',
          }),
        );

        controller.dispose();
        source.dispose();
      }
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_native_source.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/ml_mode.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/ml_pose_classifier.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWorkoutCvNativeSource extends WorkoutCvNativeSource {
  final StreamController<Map<String, dynamic>> controller =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get eventStream => controller.stream;

  @override
  Future<String> checkPermission() async => 'granted';

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> startSession(String exerciseSlug) async => true;

  @override
  Future<bool> stopSession() async => true;
}

List<PoseLandmark> _landmarksFromMatrix(List<dynamic> matrix) {
  return List<PoseLandmark>.generate(matrix.length, (i) {
    final row = matrix[i] as List<dynamic>;
    return PoseLandmark(
      index: i,
      x: (row[0] as num).toDouble(),
      y: (row[1] as num).toDouble(),
      z: (row[2] as num).toDouble(),
      visibility: (row[3] as num).toDouble(),
    );
  });
}

List<Map<String, dynamic>> _landmarkMapsFromList(List<PoseLandmark> list) {
  return list
      .map(
        (lm) => <String, dynamic>{
          'index': lm.index,
          'x': lm.x,
          'y': lm.y,
          'z': lm.z,
          'visibility': lm.visibility,
        },
      )
      .toList(growable: false);
}

void main() {
  const classifier = MlPoseClassifier();

  Map<String, dynamic> loadParityJson() {
    final file = File(
      '../ml_research/phase5_multi_exercise/exported/parity_vectors.json',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Expected parity_vectors.json at ${file.path}',
    );
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  group('MlPoseClassifier — Phase 5 Parity, Latency & Fallback', () {
    test('Test 1: Numerical Parity 10/10 (< 1e-4) vs parity_vectors.json', () {
      final json = loadParityJson();
      final tolerance = (json['tolerance'] as num).toDouble();
      final vectors = json['vectors'] as List<dynamic>;
      expect(vectors.length, equals(10));

      var maxFeatureErr = 0.0;
      var maxViewProbErr = 0.0;
      var maxPhaseProbErr = 0.0;

      for (final rawVec in vectors) {
        final vec = rawVec as Map<String, dynamic>;
        final vectorId = vec['vector_id'] as String;
        final slug = vec['exercise_slug'] as String;
        final landmarks = _landmarksFromMatrix(
          vec['landmarks_33x4'] as List<dynamic>,
        );
        final expectedFeatures = (vec['expected_features_18'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(growable: false);
        final expectedViewProbs =
            (vec['expected_view_angle_probs'] as List<dynamic>)
                .map((e) => (e as num).toDouble())
                .toList(growable: false);
        final expectedPhaseProbs =
            (vec['expected_phase_probs'] as List<dynamic>)
                .map((e) => (e as num).toDouble())
                .toList(growable: false);

        final dartFeatures = MlPoseClassifier.extractFeatures(landmarks);
        expect(dartFeatures.length, equals(18));
        for (var i = 0; i < 18; i++) {
          final err = (dartFeatures[i] - expectedFeatures[i]).abs();
          if (err > maxFeatureErr) maxFeatureErr = err;
          expect(
            err,
            lessThan(tolerance),
            reason: '$vectorId feature[$i] parity drift: $err',
          );
        }

        final viewPred = classifier.predictViewAngle(landmarks);
        expect(viewPred, isNotNull, reason: '$vectorId viewPred null');
        expect(viewPred!.probabilities.length, equals(3));
        for (var k = 0; k < 3; k++) {
          final err = (viewPred.probabilities[k] - expectedViewProbs[k]).abs();
          if (err > maxViewProbErr) maxViewProbErr = err;
          expect(
            err,
            lessThan(tolerance),
            reason: '$vectorId view_angle_probs[$k] parity drift: $err',
          );
        }

        final phasePred = classifier.predictExercisePhase(slug, landmarks);
        expect(phasePred, isNotNull, reason: '$vectorId phasePred null');
        expect(phasePred!.probabilities.length, equals(3));
        for (var k = 0; k < 3; k++) {
          final err =
              (phasePred.probabilities[k] - expectedPhaseProbs[k]).abs();
          if (err > maxPhaseProbErr) maxPhaseProbErr = err;
          expect(
            err,
            lessThan(tolerance),
            reason: '$vectorId phase_probs[$k] parity drift: $err',
          );
        }
      }

      // ignore: avoid_print
      print(
        'PARITY_10_OF_10_PASS: '
        'MAX_FEATURE_ERR=${maxFeatureErr.toStringAsExponential(3)}, '
        'MAX_VIEW_PROB_ERR=${maxViewProbErr.toStringAsExponential(3)}, '
        'MAX_PHASE_PROB_ERR=${maxPhaseProbErr.toStringAsExponential(3)}',
      );
      expect(maxFeatureErr, lessThan(1e-4));
      expect(maxViewProbErr, lessThan(1e-4));
      expect(maxPhaseProbErr, lessThan(1e-4));
    });

    test('Test 2: Latency Benchmark < 1.0 ms/frame over 1,000 frames', () {
      final json = loadParityJson();
      final vectors = json['vectors'] as List<dynamic>;
      final samples = vectors.map((rawVec) {
        final vec = rawVec as Map<String, dynamic>;
        return (
          slug: vec['exercise_slug'] as String,
          landmarks: _landmarksFromMatrix(
            vec['landmarks_33x4'] as List<dynamic>,
          ),
        );
      }).toList(growable: false);

      // Warmup JIT
      for (var i = 0; i < 100; i++) {
        final s = samples[i % samples.length];
        final feats = MlPoseClassifier.extractFeatures(s.landmarks);
        classifier.predictViewAngleFromFeatures(feats);
        classifier.predictExercisePhaseFromFeatures(s.slug, feats);
      }

      const iterations = 1000;
      final sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final s = samples[i % samples.length];
        final feats = MlPoseClassifier.extractFeatures(s.landmarks);
        classifier.predictViewAngleFromFeatures(feats);
        classifier.predictExercisePhaseFromFeatures(s.slug, feats);
      }
      sw.stop();

      final avgMsPerFrame = sw.elapsedMicroseconds / 1000.0 / iterations;
      // ignore: avoid_print
      print('AVG_MS_PER_FRAME=${avgMsPerFrame.toStringAsFixed(4)}');
      expect(avgMsPerFrame, lessThan(1.0));
    });

    test('Test 3: Exercise alias mapping & safe null fallback', () {
      final json = loadParityJson();
      final vec = (json['vectors'] as List<dynamic>).first as Map<String, dynamic>;
      final landmarks = _landmarksFromMatrix(
        vec['landmarks_33x4'] as List<dynamic>,
      );

      // Canonical 5 exercises
      expect(MlPoseClassifier.resolveCanonicalExerciseKey('pull-up'), 'pull-up');
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('lat-pulldown'),
        'lat-pulldown',
      );
      expect(MlPoseClassifier.resolveCanonicalExerciseKey('squat'), 'squat');
      expect(MlPoseClassifier.resolveCanonicalExerciseKey('push-up'), 'push-up');
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('bicep-curl'),
        'bicep-curl',
      );

      // Registry aliases
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('barbell-back-squat'),
        'squat',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('goblet-squat'),
        'squat',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('db-bicep-curl'),
        'bicep-curl',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('dumbbell-bicep-curl'),
        'bicep-curl',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('ez-bar-curl'),
        'bicep-curl',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('hammer-curl'),
        'bicep-curl',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('cable-biceps-curl'),
        'bicep-curl',
      );
      expect(
        MlPoseClassifier.resolveCanonicalExerciseKey('preacher-curl'),
        'bicep-curl',
      );

      expect(
        classifier.predictExercisePhase('barbell-back-squat', landmarks),
        isNotNull,
      );
      expect(
        classifier.predictExercisePhase('db-bicep-curl', landmarks),
        isNotNull,
      );

      // Out-of-scope exercises return null for safe Rule-based fallback
      expect(MlPoseClassifier.resolveCanonicalExerciseKey('plank-hold'), isNull);
      expect(MlPoseClassifier.resolveCanonicalExerciseKey('face-pull'), isNull);
      expect(MlPoseClassifier.resolveCanonicalExerciseKey('face-pulls'), isNull);
      expect(
        classifier.predictExercisePhase('plank-hold', landmarks),
        isNull,
      );
      expect(
        classifier.predictExercisePhase('face-pull', landmarks),
        isNull,
      );
    });
  });

  group('MlMode enum, provider & WorkoutCvNotifier integration', () {
    test('Test 4: MlMode default ruleBased & wireName round-trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      expect(MlMode.fromWireName(null), equals(MlMode.ruleBased));
      expect(MlMode.fromWireName('unknown'), equals(MlMode.ruleBased));
      for (final mode in MlMode.values) {
        expect(MlMode.fromWireName(mode.wireName), equals(mode));
      }

      final notifier = MlModeNotifier(prefs: prefs);
      expect(notifier.state, equals(MlMode.ruleBased));

      await notifier.setMode(MlMode.mlShadow);
      expect(notifier.state, equals(MlMode.mlShadow));
      expect(prefs.getString(MlModeNotifier.prefKey), equals('mlShadow'));

      await notifier.setMode(MlMode.mlAssisted);
      expect(notifier.state, equals(MlMode.mlAssisted));
      expect(prefs.getString(MlModeNotifier.prefKey), equals('mlAssisted'));
    });

    test('Test 5: Controller MlMode (ruleBased / mlShadow / mlAssisted) & Opt-in telemetry guard', () async {
      final json = loadParityJson();
      final vec0 = (json['vectors'] as List<dynamic>)[0] as Map<String, dynamic>;
      final landmarks = _landmarksFromMatrix(
        vec0['landmarks_33x4'] as List<dynamic>,
      );
      final landmarkMaps = _landmarkMapsFromList(landmarks);

      Future<({
        WorkoutCvNotifier notifier,
        PendingCvTelemetrySnapshot? snapshot,
      })> runSession({
        required MlMode mode,
        required bool optIn,
      }) async {
        final fakeSource = _FakeWorkoutCvNativeSource();
        PendingCvTelemetrySnapshot? captured;
        final notifier = WorkoutCvNotifier(
          fakeSource,
          mlModeReader: () => mode,
          telemetryOptInReader: () => optIn,
          onPendingTelemetrySnapshot: (snap) => captured = snap,
        );

        await notifier.initialize(
          exerciseId: 'ex-pull-up',
          exerciseSlug: 'pull-up',
        );

        for (var i = 0; i < 4; i++) {
          fakeSource.controller.add(<String, dynamic>{
            'status': 'detecting',
            'numPoses': 1,
            'timestamp': 1000 + i * 33,
            'latencyMs': 8,
            'inputImageWidth': 720,
            'inputImageHeight': 1280,
            'landmarks': landmarkMaps,
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifier.stop();
        await fakeSource.controller.close();
        return (notifier: notifier, snapshot: captured);
      }

      // 1) ruleBased + optIn=false: 0 ML runs, 0 telemetry buffered, no snapshot
      final ruleRun = await runSession(mode: MlMode.ruleBased, optIn: false);
      expect(ruleRun.notifier.lastMlViewAngle, isNull);
      expect(ruleRun.notifier.lastMlPhase, isNull);
      expect(ruleRun.notifier.lastMlInferenceMicros, isNull);
      expect(ruleRun.notifier.bufferedTelemetryFrameCount, equals(0));
      expect(ruleRun.snapshot, isNull);

      // 2) mlShadow + optIn=true: ML runs in parallel, telemetry buffered & published
      final shadowRun = await runSession(mode: MlMode.mlShadow, optIn: true);
      expect(shadowRun.notifier.lastMlViewAngle, equals(CameraViewAngle.frontal));
      expect(shadowRun.notifier.lastMlPhase, isNotNull);
      expect(shadowRun.notifier.lastMlInferenceMicros, isNotNull);
      expect(
        shadowRun.notifier.state.detectedViewAngle,
        equals(ruleRun.notifier.state.detectedViewAngle),
      );
      expect(shadowRun.notifier.bufferedTelemetryFrameCount, equals(4));
      expect(shadowRun.snapshot, isNotNull);
      expect(shadowRun.snapshot!.exerciseId, equals('ex-pull-up'));
      expect(shadowRun.snapshot!.exerciseSlug, equals('pull-up'));
      expect(shadowRun.snapshot!.frames.length, equals(4));
      expect(shadowRun.snapshot!.mlMode, equals('mlShadow'));

      // 3) mlAssisted + optIn=false: ML stabilizes viewAngle, 0 telemetry buffered
      final assistedRun =
          await runSession(mode: MlMode.mlAssisted, optIn: false);
      expect(
        assistedRun.notifier.lastMlViewAngle,
        equals(CameraViewAngle.frontal),
      );
      expect(
        assistedRun.notifier.state.detectedViewAngle,
        equals(CameraViewAngle.frontal),
      );
      expect(assistedRun.notifier.bufferedTelemetryFrameCount, equals(0));
      expect(assistedRun.snapshot, isNull);
    });
  });
}

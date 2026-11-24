import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_native_source.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_hardware_radar_service.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_tts_coach.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:health_ai_app/features/workout_cv/presentation/widgets/cv_calibration_overlay.dart';
import 'package:health_ai_app/features/workout_cv/presentation/widgets/cv_exercise_guide_sheet.dart';
import 'package:health_ai_app/features/workout_cv/presentation/widgets/cv_hardware_radar_sheet.dart';
import 'package:health_ai_app/presentation/tokens/saman_workout_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCvTtsEngine implements CvTtsEngine {
  final List<String> spokenTexts = [];
  final List<String> configuredLanguages = [];
  final List<double> configuredRates = [];
  int stopCount = 0;

  @override
  Future<void> setLanguage(String lang) async {
    configuredLanguages.add(lang);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    configuredRates.add(rate);
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class _TestCvNativeSource implements WorkoutCvNativeSource {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  int requestAudioFocusCount = 0;
  int abandonAudioFocusCount = 0;

  @override
  Future<String> checkPermission() async => 'granted';

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> startSession(String exerciseSlug) async => true;

  @override
  Future<bool> startVideoReplay(String videoPath) async => true;

  @override
  Future<bool> switchSource(String mode, {String? videoPath}) async => true;

  @override
  Future<bool> restartVideoReplay() async => true;

  @override
  Future<bool> stopSession() async => true;

  @override
  Future<bool> acknowledgeReplayFrame(
    int sessionGen,
    int videoPtsMs,
    String phase,
  ) async =>
      true;

  @override
  Future<Map<String, dynamic>?> getDeviceHardwareInfo() async => null;

  @override
  Future<Map<String, dynamic>?> runPoseBenchmark({int frameCount = 12}) async =>
      null;

  @override
  Future<bool> requestAudioFocus() async {
    requestAudioFocusCount++;
    return true;
  }

  @override
  Future<bool> abandonAudioFocus() async {
    abandonAudioFocusCount++;
    return true;
  }

  @override
  Stream<Map<String, dynamic>> get eventStream => _events.stream;

  void emit(Map<String, dynamic> event) => _events.add(event);

  void dispose() => _events.close();
}

class _TestHardwareProbe implements CvHardwareProbe {
  @override
  Future<Map<String, dynamic>?> getDeviceHardwareInfo() async => {
        'deviceModel': 'Pixel 8',
        'manufacturer': 'Google',
        'socHardware': 'Tensor G3',
        'totalRamMb': 8192,
        'cpuCores': 9,
        'androidSdk': 34,
      };

  @override
  Future<Map<String, dynamic>?> runPoseBenchmark({int frameCount = 12}) async =>
      {
        'measuredFps': 22.4,
        'avgInferenceMs': 44.6,
        'framesRun': frameCount,
      };
}

List<PoseLandmark> _buildFullBodyLandmarks({
  double visibility = 0.92,
  double ankleY = 0.85,
  double shoulderY = 0.25,
  double hipY = 0.55,
  double? kneeVisibility,
  double? ankleVisibility,
  double? hipVisibility,
}) {
  return List<PoseLandmark>.generate(33, (i) {
    var y = 0.5;
    var x = 0.5;
    var vis = visibility;
    if (i == PoseLandmark.leftShoulder) {
      x = 0.42;
      y = shoulderY;
    } else if (i == PoseLandmark.rightShoulder) {
      x = 0.58;
      y = shoulderY;
    } else if (i == PoseLandmark.leftElbow) {
      x = 0.36;
      y = (shoulderY + hipY) / 2;
    } else if (i == PoseLandmark.rightElbow) {
      x = 0.64;
      y = (shoulderY + hipY) / 2;
    } else if (i == PoseLandmark.leftWrist) {
      x = 0.34;
      y = hipY;
    } else if (i == PoseLandmark.rightWrist) {
      x = 0.66;
      y = hipY;
    } else if (i == PoseLandmark.leftHip) {
      x = 0.44;
      y = hipY;
      vis = hipVisibility ?? visibility;
    } else if (i == PoseLandmark.rightHip) {
      x = 0.56;
      y = hipY;
      vis = hipVisibility ?? visibility;
    } else if (i == PoseLandmark.leftKnee) {
      x = 0.44;
      y = 0.72;
      vis = kneeVisibility ?? visibility;
    } else if (i == PoseLandmark.rightKnee) {
      x = 0.56;
      y = 0.72;
      vis = kneeVisibility ?? visibility;
    } else if (i == PoseLandmark.leftAnkle) {
      x = 0.44;
      y = ankleY;
      vis = ankleVisibility ?? visibility;
    } else if (i == PoseLandmark.rightAnkle) {
      x = 0.56;
      y = ankleY;
      vis = ankleVisibility ?? visibility;
    }
    return PoseLandmark(index: i, x: x, y: y, z: 0.0, visibility: vis);
  });
}

void main() {
  group('CvTtsCoach Unit Tests', () {
    late FakeCvTtsEngine fakeEngine;
    late DateTime currentTime;

    setUp(() {
      fakeEngine = FakeCvTtsEngine();
      currentTime = DateTime(2026, 11, 23, 12, 0, 0);
    });

    test('speakFormCue is rate-limited (< 2500ms) and speaks again after >= 2500ms', () async {
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        formCueCooldown: const Duration(milliseconds: 2500),
        sameCueCooldown: const Duration(milliseconds: 5000),
      );

      // First cue is spoken
      await coach.speakFormCue('chest_up', 'Ưỡn ngực');
      expect(fakeEngine.spokenTexts, equals(['Ưỡn ngực']));

      // Advance by 1000ms (< 2500ms) -> rate-limited
      currentTime = currentTime.add(const Duration(milliseconds: 1000));
      await coach.speakFormCue('knees_out', 'Mở rộng gối');
      expect(fakeEngine.spokenTexts, equals(['Ưỡn ngực']));

      // Advance by another 1600ms (total 2600ms >= 2500ms) -> allowed for a different cue key
      currentTime = currentTime.add(const Duration(milliseconds: 1600));
      await coach.speakFormCue('knees_out', 'Mở rộng gối');
      expect(fakeEngine.spokenTexts, equals(['Ưỡn ngực', 'Mở rộng gối']));
    });

    test('speakRepCount is prioritized immediately even right after speakFormCue', () async {
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        formCueCooldown: const Duration(milliseconds: 2500),
      );

      await coach.speakFormCue('core_tight', 'Gồng chặt cơ bụng');
      expect(fakeEngine.spokenTexts, equals(['Gồng chặt cơ bụng']));

      // speakRepCount immediately at same timestamp (0ms elapsed)
      await coach.speakRepCount(1);
      expect(fakeEngine.spokenTexts, equals(['Gồng chặt cơ bụng', '1']));

      // Rep count does not repeat identical number
      await coach.speakRepCount(1);
      expect(fakeEngine.spokenTexts, equals(['Gồng chặt cơ bụng', '1']));

      // New rep count works immediately
      await coach.speakRepCount(2);
      expect(fakeEngine.spokenTexts, equals(['Gồng chặt cơ bụng', '1', '2']));
    });

    test('when setMuted(true), speakRepCount and speakFormCue do not call engine', () async {
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
      );

      coach.setMuted(true);
      expect(coach.isMuted, isTrue);
      expect(fakeEngine.stopCount, equals(1));

      await coach.speakFormCue('cue_1', 'Lưng thẳng');
      await coach.speakRepCount(5);
      await coach.speakCountdown('3');

      expect(fakeEngine.spokenTexts, isEmpty);

      // Unmuting allows calls again
      coach.setMuted(false);
      expect(coach.isMuted, isFalse);

      await coach.speakRepCount(5);
      expect(fakeEngine.spokenTexts, equals(['5']));
    });

    test("updateLocale('vi') -> 'vi-VN' and updateLocale('en') -> 'en-US'", () async {
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        initialLanguageCode: 'vi',
      );

      expect(coach.currentLocale, equals('vi-VN'));
      expect(coach.isVietnamese, isTrue);

      await coach.updateLocale('en');
      expect(coach.currentLocale, equals('en-US'));
      expect(coach.isVietnamese, isFalse);
      expect(fakeEngine.configuredLanguages.contains('en-US'), isTrue);

      await coach.updateLocale('vi');
      expect(coach.currentLocale, equals('vi-VN'));
      expect(coach.isVietnamese, isTrue);
      expect(fakeEngine.configuredLanguages.contains('vi-VN'), isTrue);
    });

    test('Priority 1 speakUrgent interrupts immediately, bypasses form cooldown, and respects same-key cooldown', () async {
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        formCueCooldown: const Duration(milliseconds: 2500),
        urgentCueCooldown: const Duration(milliseconds: 3000),
      );

      await coach.speakFormCue('depth', 'Xuống sâu hơn nữa');
      expect(fakeEngine.spokenTexts, equals(['Xuống sâu hơn nữa']));
      expect(fakeEngine.stopCount, equals(0));

      // Urgent cue fires immediately at 0ms elapsed and calls stop() first
      await coach.speakUrgent('lost_body', 'Bước lại vào khung hình');
      expect(fakeEngine.stopCount, equals(1));
      expect(
        fakeEngine.spokenTexts,
        equals(['Xuống sâu hơn nữa', 'Bước lại vào khung hình']),
      );
      expect(coach.lastSpokenPriority, equals(CvTtsPriority.urgent));

      // Same urgent key within < 3000ms is suppressed
      currentTime = currentTime.add(const Duration(milliseconds: 1000));
      await coach.speakUrgent('lost_body', 'Bước lại vào khung hình');
      expect(fakeEngine.stopCount, equals(1));
      expect(fakeEngine.spokenTexts.length, equals(2));

      // Different urgent key interrupts immediately even within < 3000ms
      await coach.speakUrgent(
        'multi_person',
        'Có người khác trong khung hình, tạm dừng đếm',
      );
      expect(fakeEngine.stopCount, equals(2));
      expect(
        fakeEngine.spokenTexts.last,
        equals('Có người khác trong khung hình, tạm dừng đếm'),
      );

      // Reset clears urgent tracking so same key can speak again immediately
      coach.resetSessionTracking();
      await coach.speakUrgent(
        'multi_person',
        'Có người khác trong khung hình, tạm dừng đếm',
      );
      expect(fakeEngine.stopCount, equals(3));
      expect(fakeEngine.spokenTexts.length, equals(4));
    });

    test('Priority 2 speakCalibrationCue debounces same step >= 2.5s and allows step switch after >= 1.2s', () async {
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        calibrationCueCooldown: const Duration(milliseconds: 2500),
      );

      await coach.speakCalibrationCue(
        'step_back',
        'Lùi ra xa hơn để thấy cả chân',
      );
      expect(fakeEngine.spokenTexts, equals(['Lùi ra xa hơn để thấy cả chân']));
      expect(coach.lastSpokenPriority, equals(CvTtsPriority.calibration));

      // Different step too early (800ms < 1200ms) -> suppressed
      currentTime = currentTime.add(const Duration(milliseconds: 800));
      await coach.speakCalibrationCue(
        'rotate_body',
        'Xoay nhẹ người để thấy rõ vai và hông',
      );
      expect(fakeEngine.spokenTexts.length, equals(1));

      // Different step at 1200ms -> allowed early transition
      currentTime = currentTime.add(const Duration(milliseconds: 400));
      await coach.speakCalibrationCue(
        'rotate_body',
        'Xoay nhẹ người để thấy rõ vai và hông',
      );
      expect(
        fakeEngine.spokenTexts,
        equals([
          'Lùi ra xa hơn để thấy cả chân',
          'Xoay nhẹ người để thấy rõ vai và hông',
        ]),
      );

      // Same step after 1500ms (< 2500ms) -> suppressed
      currentTime = currentTime.add(const Duration(milliseconds: 1500));
      await coach.speakCalibrationCue(
        'rotate_body',
        'Xoay nhẹ người để thấy rõ vai và hông',
      );
      expect(fakeEngine.spokenTexts.length, equals(2));

      // Same step after 2500ms -> allowed
      currentTime = currentTime.add(const Duration(milliseconds: 1000));
      await coach.speakCalibrationCue(
        'rotate_body',
        'Xoay nhẹ người để thấy rõ vai và hông',
      );
      expect(fakeEngine.spokenTexts.length, equals(3));
    });

    test('Priority 4 speakRepCount plays Ting chime before speaking rep and 5s hold milestone', () async {
      final events = <String>[];
      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        initialLanguageCode: 'vi',
        onRepChime: () async {
          events.add('ting');
        },
      );

      await coach.speakRepCount(1);
      expect(events, equals(['ting']));
      expect(fakeEngine.spokenTexts, equals(['1']));
      expect(coach.lastSpokenPriority, equals(CvTtsPriority.repCount));

      // Duplicate rep does not chime again
      await coach.speakRepCount(1);
      expect(events, equals(['ting']));

      // Hold seconds: non-multiples of 5 ignored, multiples of 5 chime + speak
      await coach.speakRepCount(3, isHoldSecond: true);
      expect(events, equals(['ting']));

      await coach.speakRepCount(5, isHoldSecond: true);
      expect(events, equals(['ting', 'ting']));
      expect(fakeEngine.spokenTexts, equals(['1', '5 giây']));

      await coach.updateLocale('en');
      await coach.speakRepCount(10, isHoldSecond: true);
      expect(events, equals(['ting', 'ting', 'ting']));
      expect(fakeEngine.spokenTexts, equals(['1', '5 giây', '10 seconds']));
    });

    test('AudioFocus requests on speak and abandons on stop, setMuted(true), dispose, and release delay', () async {
      var requestCalls = 0;
      var abandonCalls = 0;

      final coach = CvTtsCoach(
        engine: fakeEngine,
        clock: () => currentTime,
        audioFocusReleaseDelay: const Duration(milliseconds: 40),
        onRequestAudioFocus: () async {
          requestCalls++;
          return true;
        },
        onAbandonAudioFocus: () async {
          abandonCalls++;
          return true;
        },
      );

      // 1. Auto-release after delay
      await coach.speakFormCue('c1', 'Chậm lại một chút');
      expect(requestCalls, equals(1));
      expect(abandonCalls, equals(0));
      expect(coach.hasAudioFocus, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(abandonCalls, equals(1));
      expect(coach.hasAudioFocus, isFalse);

      // 2. Immediate release on stop()
      await coach.speakRepCount(1);
      expect(requestCalls, equals(2));
      expect(coach.hasAudioFocus, isTrue);
      await coach.stop();
      expect(abandonCalls, equals(2));
      expect(coach.hasAudioFocus, isFalse);

      // 3. Immediate release on setMuted(true)
      await coach.speakRepCount(2);
      expect(requestCalls, equals(3));
      expect(coach.hasAudioFocus, isTrue);
      coach.setMuted(true);
      await Future<void>.delayed(Duration.zero);
      expect(abandonCalls, equals(3));
      expect(coach.hasAudioFocus, isFalse);

      // 4. Immediate release on dispose()
      coach.setMuted(false);
      await coach.speakRepCount(3);
      expect(requestCalls, equals(4));
      expect(coach.hasAudioFocus, isTrue);
      await coach.dispose();
      expect(abandonCalls, equals(4));
      expect(coach.hasAudioFocus, isFalse);
    });
  });

  group('CvCalibrationGuidance Face-ID Unit Tests', () {
    test('evaluates framing guidance in strict Face-ID priority order', () {
      // 1. Multiple people
      final multi = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.multiplePeople,
        posesDetected: 2,
        landmarks: _buildFullBodyLandmarks(),
        isVietnamese: true,
      );
      expect(multi.$1, equals('multi_person'));

      // 2. Lost / empty landmarks
      final lost = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.lost,
        posesDetected: 0,
        landmarks: const [],
        isVietnamese: false,
      );
      expect(lost.$1, equals('lost_body'));
      expect(lost.$2, equals('Step back into the frame'));

      // 3. Low light (average core visibility < 0.50)
      final lowLight = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.needsSetup,
        posesDetected: 1,
        landmarks: _buildFullBodyLandmarks(visibility: 0.30),
        isVietnamese: true,
      );
      expect(lowLight.$1, equals('low_light'));

      // 4a. Edge clipped (ankle y > 0.94)
      final clipped = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.needsSetup,
        posesDetected: 1,
        landmarks: _buildFullBodyLandmarks(ankleY: 0.97),
        exerciseModule: CvExerciseModule.squat,
        isVietnamese: true,
      );
      expect(clipped.$1, equals('step_back'));

      // 4b. Missing legs for squat
      final missingLegs = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.needsSetup,
        posesDetected: 1,
        landmarks: _buildFullBodyLandmarks(
          visibility: 0.95,
          kneeVisibility: 0.2,
          ankleVisibility: 0.1,
        ),
        exerciseModule: CvExerciseModule.squat,
        isVietnamese: false,
      );
      expect(missingLegs.$1, equals('step_back'));

      // 5. Unclear shoulder-hip axis
      final rotate = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.needsSetup,
        posesDetected: 1,
        landmarks: _buildFullBodyLandmarks(
          visibility: 0.90,
          hipVisibility: 0.20,
        ),
        exerciseModule: CvExerciseModule.pullUp,
        isVietnamese: true,
      );
      expect(rotate.$1, equals('rotate_body'));

      // 6. Ready for countdown
      final ready = CvCalibrationGuidance.resolve(
        trackingStatus: TrackingStatus.detecting,
        posesDetected: 1,
        landmarks: _buildFullBodyLandmarks(),
        exerciseModule: CvExerciseModule.squat,
        isVietnamese: true,
      );
      expect(ready.$1, equals('hold_steady'));
    });
  });

  group('CvCalibrationOverlay Widget Tests', () {
    testWidgets('does not countdown when trackingStatus != TrackingStatus.detecting', (tester) async {
      var calibratedCalled = false;
      int? tickedSecond;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.lost,
              posesDetected: 0,
              onCalibrated: () => calibratedCalled = true,
              onCountdownTick: (sec) => tickedSecond = sec,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('workout_cv_calibration_countdown')), findsNothing);
      expect(tickedSecond, isNull);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));

      expect(calibratedCalled, isFalse);
      expect(find.byKey(const ValueKey('workout_cv_calibration_countdown')), findsNothing);
    });

    testWidgets('counts down 3 -> 2 -> 1 and calls onCalibrated after 3s stable detecting', (tester) async {
      var calibratedCalled = false;
      final ticks = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.detecting,
              posesDetected: 1,
              initialCountdownSeconds: 3,
              onCalibrated: () => calibratedCalled = true,
              onCountdownTick: ticks.add,
            ),
          ),
        ),
      );

      // Initial state is 3
      expect(find.byKey(const ValueKey('workout_cv_calibration_countdown')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(ticks, equals([3]));
      expect(calibratedCalled, isFalse);

      // Tick 1s -> 2
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      expect(ticks, equals([3, 2]));
      expect(calibratedCalled, isFalse);

      // Tick 1s -> 1
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      expect(ticks, equals([3, 2, 1]));
      expect(calibratedCalled, isFalse);

      // Tick 1s -> finishes and calls onCalibrated
      await tester.pump(const Duration(seconds: 1));
      expect(calibratedCalled, isTrue);
    });

    testWidgets('resets to 3 if interrupted by TrackingStatus.lost or multiplePeople', (tester) async {
      var calibratedCalled = false;
      final ticks = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.detecting,
              posesDetected: 1,
              initialCountdownSeconds: 3,
              onCalibrated: () => calibratedCalled = true,
              onCountdownTick: ticks.add,
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);

      // Progress 1 second -> shows 2
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);

      // Status changes to lost
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.lost,
              posesDetected: 0,
              initialCountdownSeconds: 3,
              onCalibrated: () => calibratedCalled = true,
              onCountdownTick: ticks.add,
            ),
          ),
        ),
      );

      // Overlay hides countdown badge
      expect(find.byKey(const ValueKey('workout_cv_calibration_countdown')), findsNothing);

      // Status recovers to detecting -> restarts at 3
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.detecting,
              posesDetected: 1,
              initialCountdownSeconds: 3,
              onCalibrated: () => calibratedCalled = true,
              onCountdownTick: ticks.add,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('workout_cv_calibration_countdown')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Progress 1 second -> shows 2
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);

      // Interrupted by multiplePeople
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.multiplePeople,
              posesDetected: 2,
              initialCountdownSeconds: 3,
              onCalibrated: () => calibratedCalled = true,
              onCountdownTick: ticks.add,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('workout_cv_calibration_countdown')), findsNothing);
      expect(calibratedCalled, isFalse);
    });

    testWidgets('skip button workout_cv_calibration_skip_button calls onCalibrated immediately', (tester) async {
      var calibratedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.needsSetup,
              posesDetected: 0,
              initialCountdownSeconds: 3,
              onCalibrated: () => calibratedCalled = true,
            ),
          ),
        ),
      );

      expect(calibratedCalled, isFalse);
      final skipBtn = find.byKey(const ValueKey('workout_cv_calibration_skip_button'));
      expect(skipBtn, findsOneWidget);

      await tester.tap(skipBtn);
      await tester.pump();

      expect(calibratedCalled, isTrue);
    });

    testWidgets('emits onGuidanceCue as Face-ID setup steps change', (tester) async {
      final emitted = <(String, String)>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.needsSetup,
              posesDetected: 1,
              landmarks: _buildFullBodyLandmarks(visibility: 0.30),
              exerciseModule: CvExerciseModule.squat,
              onCalibrated: () {},
              onGuidanceCue: (k, m) => emitted.add((k, m)),
            ),
          ),
        ),
      );
      expect(emitted.map((e) => e.$1), equals(['low_light']));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvCalibrationOverlay(
              trackingStatus: TrackingStatus.needsSetup,
              posesDetected: 1,
              landmarks: _buildFullBodyLandmarks(ankleY: 0.97),
              exerciseModule: CvExerciseModule.squat,
              onCalibrated: () {},
              onGuidanceCue: (k, m) => emitted.add((k, m)),
            ),
          ),
        ),
      );
      expect(emitted.map((e) => e.$1), equals(['low_light', 'step_back']));
    });
  });

  group('WorkoutCvScreen Visual Border, Guide & Hardware Radar Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Color readStatusBorderColor(WidgetTester tester) {
      final container = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('workout_cv_status_border')),
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, equals(4.0));
      return border.top.color;
    }

    testWidgets('4px status border changes to Red (lost/multiplePeople), Amber (needsSetup), Green (detecting)', (tester) async {
      final source = _TestCvNativeSource();
      final container = ProviderContainer(
        overrides: [
          workoutCvNativeSourceProvider.overrideWithValue(source),
        ],
      );
      final fakeTts = FakeCvTtsEngine();
      final coach = CvTtsCoach(engine: fakeTts);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: WorkoutCvScreen(
              exerciseId: 'barbell-back-squat',
              exerciseSlug: 'barbell-back-squat',
              exerciseName: 'Barbell Back Squat',
              ttsCoach: coach,
            ),
          ),
        ),
      );
      await tester.pump();

      await container.read(workoutCvControllerProvider.notifier).initialize(
            exerciseId: 'barbell-back-squat',
            exerciseSlug: 'barbell-back-squat',
          );
      await tester.pump();

      // After initialize -> needsSetup -> Amber
      expect(readStatusBorderColor(tester), equals(SamanWorkoutTokens.amberAccent));

      // Lost -> Red
      source.emit({
        'status': 'lost',
        'timestamp': 1000,
        'latencyMs': 20,
        'numPoses': 0,
        'landmarks': [],
      });
      await tester.idle();
      await tester.pump();
      expect(readStatusBorderColor(tester), equals(SamanWorkoutTokens.crimsonAccent));

      // Multiple people -> Red
      source.emit({
        'status': 'multiplePeople',
        'timestamp': 2000,
        'latencyMs': 20,
        'numPoses': 2,
        'landmarks': [],
      });
      await tester.idle();
      await tester.pump();
      expect(readStatusBorderColor(tester), equals(SamanWorkoutTokens.crimsonAccent));

      // Detecting with valid full-body pose -> Green
      source.emit({
        'status': 'detecting',
        'timestamp': 3000,
        'latencyMs': 18,
        'numPoses': 1,
        'landmarks': _buildFullBodyLandmarks()
            .map(
              (lm) => {
                'index': lm.index,
                'x': lm.x,
                'y': lm.y,
                'z': lm.z,
                'visibility': lm.visibility,
              },
            )
            .toList(),
      });
      await tester.idle();
      await tester.pump();
      expect(readStatusBorderColor(tester), equals(SamanWorkoutTokens.emeraldAccent));

      await tester.pumpWidget(const SizedBox.shrink());
      await coach.dispose();
      container.dispose();
      source.dispose();
    });

    testWidgets('tapping ? button opens CvExerciseGuideSheet and tapping Radar button opens CvHardwareRadarSheet without 360px overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final source = _TestCvNativeSource();
      final radarService = CvHardwareRadarService(probe: _TestHardwareProbe());
      final coach = CvTtsCoach(engine: FakeCvTtsEngine());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvNativeSourceProvider.overrideWithValue(source),
          ],
          child: MaterialApp(
            locale: const Locale('vi'),
            home: WorkoutCvScreen(
              exerciseId: 'barbell-back-squat',
              exerciseSlug: 'barbell-back-squat',
              exerciseName: 'Barbell Back Squat',
              ttsCoach: coach,
              hardwareRadarService: radarService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap ? button -> opens CvExerciseGuideSheet
      final guideBtn = find.byKey(const ValueKey('workout_cv_guide_button'));
      expect(guideBtn, findsOneWidget);
      await tester.tap(guideBtn);
      await tester.pumpAndSettle();
      expect(find.byType(CvExerciseGuideSheet), findsOneWidget);

      // Close guide sheet
      await tester.tap(
        find.byKey(const ValueKey('cv_exercise_guide_confirm_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CvExerciseGuideSheet), findsNothing);

      // Tap Radar button -> opens CvHardwareRadarSheet
      final radarBtn =
          find.byKey(const ValueKey('workout_cv_hardware_radar_button'));
      expect(radarBtn, findsOneWidget);
      await tester.tap(radarBtn);
      await tester.pumpAndSettle();
      expect(find.byType(CvHardwareRadarSheet), findsOneWidget);

      // Acknowledge & close radar sheet
      await tester.tap(
        find.byKey(const ValueKey('cv_hardware_radar_ack_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CvHardwareRadarSheet), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coach.dispose();
      source.dispose();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_tts_coach.dart';
import 'package:health_ai_app/features/workout_cv/presentation/widgets/cv_calibration_overlay.dart';

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
  });
}

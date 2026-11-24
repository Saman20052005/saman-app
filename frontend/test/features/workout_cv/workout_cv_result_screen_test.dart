import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_native_source.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_tts_coach.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_result_screen.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCvTtsEngine implements CvTtsEngine {
  final List<String> spokenTexts = [];

  @override
  Future<void> setLanguage(String lang) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {}
}

class _NoopCvNativeSource implements WorkoutCvNativeSource {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

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
  Future<bool> requestAudioFocus() async => true;

  @override
  Future<bool> abandonAudioFocus() async => true;

  @override
  Stream<Map<String, dynamic>> get eventStream => _events.stream;

  void dispose() {
    _events.close();
  }
}

class _TestWorkoutCvNotifier extends WorkoutCvNotifier {
  _TestWorkoutCvNotifier(super.nativeSource);

  @override
  Future<void> initialize({
    required String exerciseId,
    required String exerciseSlug,
    String? videoPath,
    bool videoReplay = false,
  }) async {}

  void setTestState(ExerciseCvState next) {
    state = next;
  }
}

List<RepRecord> _buildSampleRepRecords() {
  return const [
    RepRecord(
      repIndex: 1,
      timestampSec: 1.2,
      durationSec: 2.1,
      metricAngleDeg: 88.5,
      isValid: true,
      issueType: RepIssueType.none,
      viewAngle: CameraViewAngle.oblique45,
    ),
    RepRecord(
      repIndex: 2,
      timestampSec: 4.0,
      durationSec: 1.8,
      metricAngleDeg: 108.0,
      isValid: false,
      issueType: RepIssueType.shallowDepth,
      viewAngle: CameraViewAngle.side90,
    ),
    RepRecord(
      repIndex: 3,
      timestampSec: 6.5,
      durationSec: 2.0,
      metricAngleDeg: 91.0,
      isValid: false,
      issueType: RepIssueType.kneeValgus,
      viewAngle: CameraViewAngle.frontal,
    ),
    RepRecord(
      repIndex: 4,
      timestampSec: 9.1,
      durationSec: 1.9,
      metricAngleDeg: 94.0,
      isValid: false,
      issueType: RepIssueType.hipSag,
      viewAngle: CameraViewAngle.side90,
    ),
    RepRecord(
      repIndex: 5,
      timestampSec: 11.4,
      durationSec: 1.7,
      metricAngleDeg: 72.0,
      isValid: false,
      issueType: RepIssueType.elbowSwing,
      viewAngle: CameraViewAngle.oblique45,
    ),
    RepRecord(
      repIndex: 6,
      timestampSec: 13.6,
      durationSec: 0.9,
      metricAngleDeg: 89.0,
      isValid: false,
      issueType: RepIssueType.tooFast,
      viewAngle: CameraViewAngle.frontal,
    ),
    RepRecord(
      repIndex: 7,
      timestampSec: 15.8,
      durationSec: 2.2,
      metricAngleDeg: 75.0,
      isValid: false,
      issueType: RepIssueType.chinNotCleared,
      viewAngle: CameraViewAngle.side90,
    ),
  ];
}

void main() {
  group('CvFormSummary Contract Lock', () {
    test('toJson() exposes exact 5 backend schema keys', () {
      const summary = CvFormSummary(
        validReps: 8,
        totalReps: 10,
        fastReps: 2,
        avgElbowAngleDeg: 64.5,
        avgTempoSec: 2.15,
        abortCount: 1,
      );

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
      expect(json.length, equals(5));
    });
  });

  group('WorkoutCvResultScreen Rep-by-Rep Breakdown', () {
    testWidgets(
      'renders VI dark mode rep records, view angles, issue summary, and pops CvFormSummary on Done (360x800)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final records = _buildSampleRepRecords();
        CvFormSummary? poppedSummary;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('vi'),
            supportedLocales: const [Locale('vi'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      poppedSummary =
                          await Navigator.of(context).push<CvFormSummary>(
                        MaterialPageRoute(
                          builder: (_) => WorkoutCvResultScreen(
                            repHistory: const [],
                            repRecords: records,
                            exerciseName: 'Squat',
                            exerciseId: 'barbell-back-squat',
                            exerciseSlug: 'barbell-back-squat',
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('workout_cv_result_issue_summary_banner')),
          findsOneWidget,
        );
        expect(find.textContaining('Điểm cần chú ý:'), findsOneWidget);

        // Issue labels in VI
        expect(find.text('Chưa đủ độ sâu'), findsOneWidget);
        expect(find.text('Gối chụm vào trong'), findsOneWidget);
        expect(find.text('Võng lưng / tụt hông'), findsOneWidget);
        expect(find.text('Vung cùi chỏ'), findsOneWidget);
        expect(find.text('Nhịp quá nhanh'), findsOneWidget);
        expect(find.text('Chưa lên hết tầm'), findsOneWidget);

        // View-angle chips in VI
        expect(find.text('0° Chính diện'), findsNWidgets(2));
        expect(find.text('45° Nghiêng'), findsNWidgets(2));
        expect(find.text('90° Ngang'), findsNWidgets(3));

        // Ensure empty-history fallback card is NOT shown
        expect(
          find.text('Chưa ghi nhận Rep hợp lệ nào trong phiên này.'),
          findsNothing,
        );

        // Tap Done and verify popped CvFormSummary
        await tester.tap(
          find.byKey(const ValueKey('workout_cv_result_done_button')),
        );
        await tester.pumpAndSettle();

        expect(poppedSummary, isNotNull);
        expect(poppedSummary!.validReps, equals(1));
        expect(poppedSummary!.totalReps, equals(7));
        expect(poppedSummary!.fastReps, equals(1));
      },
    );

    testWidgets(
      'renders EN light mode rep records, view angles, and issue summary without 360px overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final records = _buildSampleRepRecords();

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('vi'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData.light(),
            home: WorkoutCvResultScreen(
              repHistory: const [],
              repRecords: records,
              exerciseName: 'Squat',
              exerciseId: 'barbell-back-squat',
              exerciseSlug: 'barbell-back-squat',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('workout_cv_result_issue_summary_banner')),
          findsOneWidget,
        );
        expect(find.textContaining('Focus areas:'), findsOneWidget);

        // Issue labels in EN
        expect(find.text('Insufficient depth'), findsOneWidget);
        expect(find.text('Knee valgus'), findsOneWidget);
        expect(find.text('Hip sag'), findsOneWidget);
        expect(find.text('Elbow swing'), findsOneWidget);
        expect(find.text('Too fast'), findsOneWidget);
        expect(find.text('Incomplete top range'), findsOneWidget);

        // View-angle chips in EN
        expect(find.text('0° Front'), findsNWidgets(2));
        expect(find.text('45° Oblique'), findsNWidgets(2));
        expect(find.text('90° Side'), findsNWidgets(3));
      },
    );

    testWidgets(
      'displays 2-decimal duration (1.96s) instead of 2.0s for boundary tooFast Lat Pulldown repHistory (EN)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('vi'), Locale('en')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: WorkoutCvResultScreen(
              repHistory: [
                LatPulldownRepEvent(
                  repNumber: 1,
                  startTimestampMs: 1000,
                  bottomTimestampMs: 1980,
                  endTimestampMs: 2960,
                  durationMs: 1960,
                  minElbowAngleDeg: 65.0,
                  viewAngle: CameraViewAngle.frontal,
                ),
              ],
              exerciseName: 'Lat Pulldown',
              exerciseId: 'lat-pulldown',
              exerciseSlug: 'lat-pulldown',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('1.96s'), findsOneWidget);
        expect(find.text('Too fast'), findsOneWidget);
        expect(find.textContaining('2.0s'), findsNothing);
      },
    );

    testWidgets(
      'displays 2-decimal duration (1.96s) instead of 2.0s for boundary tooFast Lat Pulldown repRecord (VI)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            locale: Locale('vi'),
            supportedLocales: [Locale('vi'), Locale('en')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: WorkoutCvResultScreen(
              repHistory: [],
              repRecords: [
                RepRecord(
                  repIndex: 1,
                  timestampSec: 1.0,
                  durationSec: 1.96,
                  metricAngleDeg: 65.0,
                  isValid: false,
                  issueType: RepIssueType.tooFast,
                  viewAngle: CameraViewAngle.frontal,
                ),
              ],
              exerciseName: 'Lat Pulldown',
              exerciseId: 'lat-pulldown',
              exerciseSlug: 'lat-pulldown',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('1.96s'), findsOneWidget);
        expect(find.text('Nhịp quá nhanh'), findsOneWidget);
        expect(find.textContaining('2.0s'), findsNothing);
      },
    );
  });

  group('WorkoutCvScreen Push-up Frontal 0° Warning', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets(
      'speaks 45° angle cue and renders detected angle badge when push-up is frontal (360x800)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final source = _NoopCvNativeSource();
        final notifier = _TestWorkoutCvNotifier(source);
        final fakeTts = _FakeCvTtsEngine();
        final coach = CvTtsCoach(engine: fakeTts);
        addTearDown(source.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workoutCvNativeSourceProvider.overrideWithValue(source),
              workoutCvControllerProvider.overrideWith((ref) => notifier),
            ],
            child: MaterialApp(
              locale: const Locale('vi'),
              supportedLocales: const [Locale('vi'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: WorkoutCvScreen(
                exerciseId: 'push-up',
                exerciseSlug: 'push-up',
                exerciseName: 'Push-up',
                ttsCoach: coach,
                autoCheckHardwareRadar: false,
              ),
            ),
          ),
        );
        await tester.pump();

        // Activate camera in needsSetup so CvCalibrationOverlay mounts
        notifier.setTestState(
          const ExerciseCvState(
            exerciseId: 'push-up',
            exerciseSlug: 'push-up',
            trackingStatus: TrackingStatus.needsSetup,
            isCameraActive: true,
          ),
        );
        await tester.pump();

        // Skip calibration so _isCalibrated = true
        await tester.tap(
          find.byKey(const ValueKey('workout_cv_calibration_skip_button')),
        );
        await tester.pump();

        // Emit frontal angle on Push-up
        notifier.setTestState(
          const ExerciseCvState(
            exerciseId: 'push-up',
            exerciseSlug: 'push-up',
            trackingStatus: TrackingStatus.detecting,
            isCameraActive: true,
            detectedViewAngle: CameraViewAngle.frontal,
            guideMessage:
                'Frontal angle limits depth tracking. Place camera at a 45° angle.',
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          fakeTts.spokenTexts,
          contains(
            'Góc chính diện khó đo độ sâu, hãy đặt máy chếch nghiêng 45 độ',
          ),
        );
        expect(
          find.byKey(const ValueKey('workout_cv_detected_angle_badge')),
          findsOneWidget,
        );
        expect(find.text('0° Chính diện'), findsOneWidget);
        expect(
          find.text(
            'Góc chính diện khó đo độ sâu, hãy đặt máy chếch nghiêng 45 độ.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}

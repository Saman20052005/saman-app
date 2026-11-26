import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/data/models/muscle_group.dart';
import 'package:health_ai_app/data/models/workout_plan.dart';
import 'package:health_ai_app/data/repositories/exercise_repository.dart';
import 'package:health_ai_app/features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import 'package:health_ai_app/features/workout_cv/data/services/video_story_upload_service.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_result_screen.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVideoStoryUploadService extends VideoStoryUploadService {
  final VideoStoryUploadResult resultToReturn;
  int callCount = 0;
  String? lastVideoPath;
  String? lastExerciseSlug;
  Map<String, dynamic>? lastCvFormSummary;
  List<Map<String, dynamic>>? lastRepTimeline;

  _FakeVideoStoryUploadService(this.resultToReturn);

  @override
  Future<VideoStoryUploadResult> uploadVideoStory({
    required String videoPath,
    required String exerciseSlug,
    String? workoutSessionId,
    Map<String, dynamic>? cvFormSummary,
    List<Map<String, dynamic>>? repTimeline,
    void Function(double progress, String stageLabel)? onProgress,
  }) async {
    callCount++;
    lastVideoPath = videoPath;
    lastExerciseSlug = exerciseSlug;
    lastCvFormSummary = cvFormSummary;
    lastRepTimeline = repTimeline;
    onProgress?.call(0.5, 'uploading');
    onProgress?.call(1.0, 'completed');
    return resultToReturn;
  }
}

class _FakeExerciseRepository implements ExerciseRepository {
  WorkoutSession? lastSavedSession;

  @override
  Future<void> saveWorkoutSession(WorkoutSession session) async {
    lastSavedSession = session;
  }

  @override
  Future<List<MuscleGroup>> getMuscleGroups() async => const [];

  @override
  Future<List<Exercise>> getExercisesByMuscleGroup({
    required String muscleGroupSlug,
    String? difficulty,
    String? search,
  }) async =>
      const [];

  @override
  Future<List<Exercise>> getPopularExercises({int limit = 6}) async => const [];

  @override
  Future<List<WorkoutSession>> getWorkoutHistory() async => const [];

  @override
  Future<List<WorkoutPlan>> getMyPlans() async => const [];

  @override
  Future<void> deletePlan(String planId) async {}

  @override
  Future<WorkoutPlan> getPlanById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Exercise> getExerciseById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> getSessionById(String sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, LastExercisePerformance>> getLastPerformances(
    List<String> exerciseIds,
  ) async =>
      const {};

  @override
  Future<List<MuscleRecoveryItem>> getMuscleRecovery() async => const [];
}

List<RepRecord> _buildSampleRecords() {
  return const [
    RepRecord(
      repIndex: 1,
      timestampSec: 2.4,
      durationSec: 2.0,
      metricAngleDeg: 58.0,
      isValid: true,
      issueType: RepIssueType.none,
      viewAngle: CameraViewAngle.frontal,
    ),
    RepRecord(
      repIndex: 2,
      timestampSec: 5.1,
      durationSec: 1.2,
      metricAngleDeg: 74.0,
      isValid: false,
      issueType: RepIssueType.tooFast,
      viewAngle: CameraViewAngle.oblique45,
    ),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('WorkoutCvResultScreen Video Story E2E', () {
    testWidgets(
      'hides Save Video Story button when replayVideoPath is null and still pops repTimeline with 5-key toJson()',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final records = _buildSampleRecords();
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
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    poppedSummary =
                        await Navigator.of(context).push<CvFormSummary>(
                      MaterialPageRoute(
                        builder: (_) => WorkoutCvResultScreen(
                          repHistory: const [],
                          repRecords: records,
                          exerciseName: 'Lat Pulldown',
                          exerciseId: 'lat-pulldown',
                          exerciseSlug: 'lat-pulldown',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('workout_cv_result_save_video_story_button')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('workout_cv_result_done_button')),
        );
        await tester.pumpAndSettle();

        expect(poppedSummary, isNotNull);
        expect(poppedSummary!.videoStoryId, isNull);
        expect(poppedSummary!.repTimeline, isNotNull);
        expect(poppedSummary!.repTimeline!.length, equals(2));
        expect(poppedSummary!.toJson().keys.length, equals(5));
      },
    );

    testWidgets(
      'uploads Video Story on tap, shows saved badge, and pops videoStoryId + repTimeline',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final records = _buildSampleRecords();
        final fakeService = _FakeVideoStoryUploadService(
          const VideoStoryUploadResult(
            success: true,
            videoStoryId: 'story_abc_123',
            videoUrl: 'https://cdn.example.com/story_abc_123.mp4',
          ),
        );
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
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    poppedSummary =
                        await Navigator.of(context).push<CvFormSummary>(
                      MaterialPageRoute(
                        builder: (_) => WorkoutCvResultScreen(
                          repHistory: const [],
                          repRecords: records,
                          exerciseName: 'Lat Pulldown',
                          exerciseId: 'lat-pulldown',
                          exerciseSlug: 'lat-pulldown',
                          replayVideoPath: '/tmp/sample_workout.mp4',
                          uploadService: fakeService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(
          const ValueKey('workout_cv_result_save_video_story_button'),
        );
        expect(saveBtn, findsOneWidget);

        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(fakeService.callCount, equals(1));
        expect(fakeService.lastVideoPath, equals('/tmp/sample_workout.mp4'));
        expect(fakeService.lastExerciseSlug, equals('lat-pulldown'));
        expect(fakeService.lastCvFormSummary?.keys.length, equals(5));
        expect(fakeService.lastRepTimeline?.length, equals(2));

        expect(
          find.byKey(const ValueKey('workout_cv_result_video_story_saved_badge')),
          findsOneWidget,
        );
        expect(find.text('Đã lưu Video Story lên Cloud'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('workout_cv_result_done_button')),
        );
        await tester.pumpAndSettle();

        expect(poppedSummary, isNotNull);
        expect(poppedSummary!.videoStoryId, equals('story_abc_123'));
        expect(poppedSummary!.repTimeline, isNotNull);
        expect(poppedSummary!.repTimeline!.length, equals(2));
        expect(poppedSummary!.toJson().keys.length, equals(5));
      },
    );

    testWidgets(
      'opens UpgradeBottomSheet on 403 upgrade required, keeps videoStoryId null, and still pops repTimeline',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final records = _buildSampleRecords();
        final fakeService = _FakeVideoStoryUploadService(
          const VideoStoryUploadResult(
            success: false,
            isUpgradeRequired: true,
            errorMessage: 'Nâng cấp Plus để lưu Video Story lên Cloud.',
          ),
        );
        CvFormSummary? poppedSummary;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('vi'),
              supportedLocales: const [Locale('vi'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      poppedSummary =
                          await Navigator.of(context).push<CvFormSummary>(
                        MaterialPageRoute(
                          builder: (_) => WorkoutCvResultScreen(
                            repHistory: const [],
                            repRecords: records,
                            exerciseName: 'Lat Pulldown',
                            exerciseId: 'lat-pulldown',
                            exerciseSlug: 'lat-pulldown',
                            replayVideoPath: '/tmp/free_user.mp4',
                            uploadService: fakeService,
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

        await tester.tap(
          find.byKey(const ValueKey('workout_cv_result_save_video_story_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpgradeBottomSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workout_cv_result_video_story_saved_badge')),
          findsNothing,
        );

        // Dismiss the UpgradeBottomSheet
        Navigator.of(tester.element(find.byType(UpgradeBottomSheet))).pop();
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('workout_cv_result_done_button')),
        );
        await tester.pumpAndSettle();

        expect(poppedSummary, isNotNull);
        expect(poppedSummary!.videoStoryId, isNull);
        expect(poppedSummary!.repTimeline, isNotNull);
        expect(poppedSummary!.repTimeline!.length, equals(2));
        expect(poppedSummary!.toJson().keys.length, equals(5));
      },
    );
  });

  group('ActiveSessionSaver ExerciseSetLog Video Story mapping', () {
    test(
      'maps cvFormSummary (5 keys), repTimeline, and videoStoryId into ExerciseSetLog payload',
      () async {
        final fakeRepo = _FakeExerciseRepository();
        final container = ProviderContainer(
          overrides: [
            workoutSessionRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        const exercise = Exercise(
          id: 'lat-pulldown',
          slug: 'lat-pulldown',
          name: 'Lat Pulldown',
          nameVi: 'Kéo xô',
          muscleGroup: 'back',
          difficulty: 'intermediate',
          thumbnailUrl: '',
          defaultSets: 1,
          defaultReps: '10',
          restSeconds: 90,
          repType: 'reps',
        );

        final sessionNotifier =
            container.read(activeWorkoutSessionProvider.notifier);
        sessionNotifier.startSession([exercise], title: 'Back Day');
        sessionNotifier.logActiveSet();

        final repTimeline = _buildSampleRecords()
            .map((r) => r.toJson())
            .toList(growable: false);
        const summary = CvFormSummary(
          validReps: 1,
          totalReps: 2,
          fastReps: 1,
          avgElbowAngleDeg: 66.0,
          avgTempoSec: 1.6,
          abortCount: 0,
        );

        sessionNotifier.attachCvFormSummary(
          exercise.id,
          summary.toJson(),
          repTimeline: repTimeline,
          videoStoryId: 'story_backend_999',
        );

        final saved =
            await container.read(activeSessionSaverProvider.notifier).saveCurrentSession();

        expect(saved, isTrue);
        expect(fakeRepo.lastSavedSession, isNotNull);
        expect(fakeRepo.lastSavedSession!.exerciseLogs, hasLength(1));

        final logJson = fakeRepo.lastSavedSession!.exerciseLogs.first.toJson();
        expect(logJson['cvDetected'], isTrue);
        expect(
          (logJson['cvFormSummary'] as Map<String, dynamic>).keys.length,
          equals(5),
        );
        expect(logJson['repTimeline'], equals(repTimeline));
        expect(logJson['videoStoryId'], equals('story_backend_999'));
      },
    );
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/data/repositories/exercise_repository_impl.dart';
import 'package:health_ai_app/features/workout/data/repositories/mock_exercise_repository.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/session_detail_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/services/api_client.dart';

void main() {
  group('Workout Session Persistence Contract & Separation Tests', () {
    test(
        'Catalog and plans retain MockExerciseRepository while session repository uses API',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Catalog provider uses MockExerciseRepository
      final catalogRepo = container.read(exerciseRepositoryProvider);
      expect(catalogRepo, isA<MockExerciseRepository>());

      // Session repository provider uses ExerciseRepositoryImpl
      final sessionRepo = container.read(workoutSessionRepositoryProvider);
      expect(sessionRepo, isA<ExerciseRepositoryImpl>());
    });

    test(
        'ExerciseRepositoryImpl saveAndReturnWorkoutSession normalizes UTC and parses canonical ID',
        () async {
      final dio = Dio();
      RequestOptions? recordedRequest;

      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          recordedRequest = options;
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {
              'message': 'Workout session logged successfully',
              'session_id': '670a5c48b25f4a0000000001',
              'session': {
                'id': '670a5c48b25f4a0000000001',
                'planName': 'Chest Day',
                'startedAt': '2026-10-12T03:00:00.000Z',
                'finishedAt': '2026-10-12T03:45:00.000Z',
                'exerciseLogs': [
                  {
                    'exerciseId': 'db-bench-press',
                    'exerciseSlug': 'dumbbell-bench-press',
                    'setNumber': 1,
                    'repsCompleted': 10,
                    'unit': 'reps',
                    'weightKg': 24.0,
                    'isCompleted': true,
                  },
                  {
                    'exerciseId': 'plank',
                    'exerciseSlug': 'plank',
                    'setNumber': 2,
                    'repsCompleted': 0,
                    'unit': 'seconds',
                    'secondsCompleted': 60,
                    'weightKg': 0.0,
                    'isCompleted': true,
                  }
                ],
                'totalDurationMinutes': 45,
                'totalVolumeKg': 240,
              }
            },
          ));
        },
      ));

      final repo = ExerciseRepositoryImpl(dio: dio);
      final sessionToSave = WorkoutSession(
        id: 'demo-client-temp-id',
        planName: 'Chest Day',
        startedAt: DateTime.parse('2026-10-12 10:00:00'), // local time without Z
        finishedAt: DateTime.parse('2026-10-12 10:45:00'),
        exerciseLogs: [
          ExerciseSetLog(
            exerciseId: 'db-bench-press',
            exerciseSlug: 'dumbbell-bench-press',
            setNumber: 1,
            repsCompleted: 10,
            weightKg: 24.0,
            isCompleted: true,
          ),
          ExerciseSetLog(
            exerciseId: 'plank',
            exerciseSlug: 'plank',
            setNumber: 2,
            unit: SetUnit.seconds,
            secondsCompleted: 60,
            repsCompleted: 0,
            weightKg: 0.0,
            isCompleted: true,
          ),
        ],
        totalDurationMinutes: 45,
        totalVolumeKg: 240,
      );

      final saved = await repo.saveAndReturnWorkoutSession(sessionToSave);

      // Check request payload timestamp normalization to UTC
      expect(recordedRequest, isNotNull);
      final payload = recordedRequest!.data as Map<String, dynamic>;
      expect((payload['startedAt'] as String).endsWith('Z'), isTrue);
      expect((payload['finishedAt'] as String).endsWith('Z'), isTrue);

      // Check canonical server ID returned and parsed
      expect(saved.id, '670a5c48b25f4a0000000001');
      expect(saved.planName, 'Chest Day');
      expect(saved.exerciseLogs.length, 2);
      expect(saved.exerciseLogs[1].effectiveUnit, SetUnit.seconds);
      expect(saved.exerciseLogs[1].secondsCompleted, 60);
    });

    test('getWorkoutHistory reads preserved sessions envelope correctly',
        () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'sessions': [
                {
                  'id': 'session_hist_01',
                  'planName': 'Leg Day',
                  'startedAt': '2026-10-11T09:00:00.000Z',
                  'finishedAt': '2026-10-11T10:00:00.000Z',
                  'exerciseLogs': [],
                  'totalDurationMinutes': 60,
                  'totalVolumeKg': 1500,
                }
              ],
              'pagination': {'limit': 10, 'offset': 0, 'total': 1}
            },
          ));
        },
      ));

      final repo = ExerciseRepositoryImpl(dio: dio);
      final history = await repo.getWorkoutHistory();

      expect(history.length, 1);
      expect(history.first.id, 'session_hist_01');
      expect(history.first.planName, 'Leg Day');
      expect(history.first.totalVolumeKg, 1500);
    });

    test('getSessionById reads session detail envelope correctly', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path.endsWith('/session_detail_99'), isTrue);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'session': {
                'id': 'session_detail_99',
                'planName': 'Back & Biceps',
                'startedAt': '2026-10-10T08:00:00.000Z',
                'finishedAt': '2026-10-10T08:45:00.000Z',
                'exerciseLogs': [
                  {
                    'exerciseId': 'lat-pulldown',
                    'exerciseSlug': 'lat-pulldown',
                    'setNumber': 1,
                    'repsCompleted': 12,
                    'unit': 'reps',
                    'weightKg': 40.0,
                    'isCompleted': true,
                  }
                ],
                'totalDurationMinutes': 45,
                'totalVolumeKg': 480,
              }
            },
          ));
        },
      ));

      final repo = ExerciseRepositoryImpl(dio: dio);
      final session = await repo.getSessionById('session_detail_99');

      expect(session.id, 'session_detail_99');
      expect(session.planName, 'Back & Biceps');
      expect(session.exerciseLogs.length, 1);
      expect(session.exerciseLogs.first.exerciseId, 'lat-pulldown');
      expect(session.exerciseLogs.first.volumeKg, 480.0);
    });

    test(
        'ActiveSessionSaver propagates canonical ID to notifier and invalidates history',
        () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {
              'session_id': 'canonical_server_id_123',
              'session': {
                'id': 'canonical_server_id_123',
                'planName': 'Upper Body Strength',
                'startedAt': '2026-10-12T02:00:00.000Z',
                'finishedAt': '2026-10-12T02:30:00.000Z',
                'exerciseLogs': [
                  {
                    'exerciseId': 'db-bench-press',
                    'exerciseSlug': 'dumbbell-bench-press',
                    'setNumber': 1,
                    'repsCompleted': 10,
                    'unit': 'reps',
                    'weightKg': 20.0,
                    'isCompleted': true,
                  }
                ],
                'totalDurationMinutes': 30,
                'totalVolumeKg': 200,
              }
            },
          ));
        },
      ));

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      // Log 1 set so completedSetsCount > 0
      final activeNotifier = container.read(activeWorkoutSessionProvider.notifier);
      activeNotifier.logActiveSet();

      final initialClientSessionId = activeNotifier.sessionId;
      expect(initialClientSessionId.startsWith('demo-session-'), isTrue);

      final saver = container.read(activeSessionSaverProvider.notifier);
      final success = await saver.saveCurrentSession();

      expect(success, isTrue);
      // Notifier sessionId must now be updated with canonical server ID
      expect(activeNotifier.sessionId, 'canonical_server_id_123');
      expect(container.read(activeWorkoutSessionProvider).isFinished, isTrue);
    });

    test('API failure propagates error to saver and does not mark saved',
        () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.reject(DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: {'detail': 'Database connection error'},
            ),
            type: DioExceptionType.badResponse,
          ));
        },
      ));

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      // Keep autoDispose provider alive during assertions
      final subscription =
          container.listen(activeSessionSaverProvider, (_, __) {});
      addTearDown(subscription.close);

      final activeNotifier =
          container.read(activeWorkoutSessionProvider.notifier);
      activeNotifier.logActiveSet();

      final saver = container.read(activeSessionSaverProvider.notifier);
      final success = await saver.saveCurrentSession();

      // Must return false
      expect(success, isFalse);
      // Saver state must reflect error
      expect(container.read(activeSessionSaverProvider).hasError, isTrue);
      // Must NOT mark session as finished
      expect(container.read(activeWorkoutSessionProvider).isFinished, isFalse);
    });

    test('SessionDetailProvider reads through workoutSessionRepositoryProvider',
        () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'session': {
                'id': 'detail_test_id',
                'planName': 'Legs',
                'startedAt': '2026-10-12T01:00:00.000Z',
                'finishedAt': '2026-10-12T01:45:00.000Z',
                'exerciseLogs': [],
                'totalDurationMinutes': 45,
                'totalVolumeKg': 800,
              }
            },
          ));
        },
      ));

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final sessionDetail = await container.read(sessionDetailProvider('detail_test_id').future);
      expect(sessionDetail.id, 'detail_test_id');
      expect(sessionDetail.planName, 'Legs');
      expect(sessionDetail.totalVolumeKg, 800);
    });
  });
}

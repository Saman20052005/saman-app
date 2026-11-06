import 'dart:convert';

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
      expect(initialClientSessionId, matches(RegExp(r'^ws-[0-9a-f]{32}$')));

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

    test('Every new workout gets a distinct high-entropy client identity',
        () {
      final ids = <String>{};
      // Fresh containers model a reload: no process-local counter is reused.
      for (var i = 0; i < 3; i++) {
        final container = ProviderContainer();
        final notifier = container.read(activeWorkoutSessionProvider.notifier);
        ids.add(notifier.sessionId);
        for (var j = 0; j < 100; j++) {
          notifier.startScheduledSession();
          ids.add(notifier.sessionId);
        }
        container.dispose();
      }
      expect(ids, hasLength(303));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^ws-[0-9a-f]{32}$')));
      }
    });

    test(
        'Retry after an unconfirmed save resends the identical snapshot and adopts the canonical ID',
        () async {
      final payloads = <String>[];
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          payloads.add(jsonEncode(options.data));
          final sent = jsonDecode(payloads.last) as Map<String, dynamic>;
          if (payloads.length == 1) {
            // Server committed, but the gateway lost the response.
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 503),
              type: DioExceptionType.badResponse,
            ));
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {
              'session_id': '6ae201e94cbce547f0e0fbab',
              'session': {...sent, 'id': '6ae201e94cbce547f0e0fbab'},
            },
          ));
        },
      ));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);
      final subscription =
          container.listen(activeSessionSaverProvider, (_, __) {});
      addTearDown(subscription.close);

      final activeNotifier =
          container.read(activeWorkoutSessionProvider.notifier);
      activeNotifier.setDraftWeight(22);
      activeNotifier.setDraftReps(9);
      activeNotifier.logActiveSet();
      final clientId = activeNotifier.sessionId;
      final saver = container.read(activeSessionSaverProvider.notifier);

      expect(await saver.saveCurrentSession(), isFalse);
      expect(container.read(activeWorkoutSessionProvider).isFinished, isFalse);
      expect(activeNotifier.sessionId, clientId);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      for (var i = 0; i < 90; i++) {
        activeNotifier.tick();
      }

      expect(await saver.saveCurrentSession(), isTrue);
      expect(payloads, hasLength(2));
      expect(payloads[1], payloads[0]);
      final sent = jsonDecode(payloads[0]) as Map<String, dynamic>;
      expect(sent['id'], clientId);
      expect(sent['totalVolumeKg'], 198);
      expect(activeNotifier.sessionId, '6ae201e94cbce547f0e0fbab');
      expect(activeNotifier.pendingSaveSnapshot, isNull);
      expect(container.read(activeWorkoutSessionProvider).isFinished, isTrue);
    });

    test('Snapshot is immutable while save is pending confirmation; logging sets is blocked, and retry resends identical payload',
        () async {
      final payloads = <Map<String, dynamic>>[];
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          payloads.add(
              jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>);
          return handler.reject(DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 503),
            type: DioExceptionType.badResponse,
          ));
        },
      ));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);
      final subscription =
          container.listen(activeSessionSaverProvider, (_, __) {});
      addTearDown(subscription.close);

      final activeNotifier =
          container.read(activeWorkoutSessionProvider.notifier);
      activeNotifier.logActiveSet();
      final saver = container.read(activeSessionSaverProvider.notifier);
      expect(await saver.saveCurrentSession(), isFalse);
      expect(saver.saveStatus, SessionSaveStatus.unconfirmed);
      expect(activeNotifier.isSavePendingConfirmation, isTrue);

      // Attempting to mutate sets while save is pending confirmation must be blocked
      activeNotifier.logActiveSet();
      activeNotifier.addSet();
      activeNotifier.setDraftWeight(99.0);
      expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 1);

      // Retry resends identical payload
      expect(await saver.saveCurrentSession(), isFalse);

      expect(payloads, hasLength(2));
      expect(payloads[1]['id'], payloads[0]['id']);
      expect(payloads[0]['exerciseLogs'], hasLength(1));
      expect(payloads[1]['exerciseLogs'], hasLength(1));
      expect(payloads[1], equals(payloads[0]));
      expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 1);
    });

    test('409 Conflict with matching server data confirms save and adopts canonical ID',
        () async {
      final dio = Dio();
      late final String clientId;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 409,
                data: {'detail': 'Workout session identity already saved with different data'},
              ),
              type: DioExceptionType.badResponse,
            ));
          }
          if (options.method == 'GET' && options.path.contains(clientId)) {
            // Server has matching session
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'session': {
                  'id': 'canonical_server_match_409',
                  'planName': 'Upper Body Strength',
                  'startedAt': '2026-10-12T03:00:00.000Z',
                  'finishedAt': '2026-10-12T03:45:00.000Z',
                  'exerciseLogs': [
                    {
                      'exerciseId': 'ex_1',
                      'exerciseSlug': 'ex_1',
                      'setNumber': 1,
                      'repsCompleted': 8,
                      'unit': 'reps',
                      'weightKg': 26.0,
                      'isCompleted': true,
                    }
                  ],
                  'totalDurationMinutes': 0,
                  'totalVolumeKg': 208,
                }
              },
            ));
          }
          return handler.next(options);
        },
      ));

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);
      final subscription =
          container.listen(activeSessionSaverProvider, (_, __) {});
      addTearDown(subscription.close);

      final activeNotifier =
          container.read(activeWorkoutSessionProvider.notifier);
      clientId = activeNotifier.sessionId;
      activeNotifier.logActiveSet();

      final saver = container.read(activeSessionSaverProvider.notifier);
      final success = await saver.saveCurrentSession();

      expect(success, isTrue);
      expect(saver.saveStatus, SessionSaveStatus.saved);
      expect(activeNotifier.sessionId, 'canonical_server_match_409');
      expect(activeNotifier.pendingSaveSnapshot, isNull);
      expect(container.read(activeWorkoutSessionProvider).isFinished, isTrue);
    });

    test('409 Conflict with different data sets conflict status, keeps draft, does not overwrite',
        () async {
      final dio = Dio();
      late final String clientId;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 409,
                data: {'detail': 'Workout session identity already saved with different data'},
              ),
              type: DioExceptionType.badResponse,
            ));
          }
          if (options.method == 'GET' && options.path.contains(clientId)) {
            // Server has DIFFERENT session under this identity
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'session': {
                  'id': 'canonical_different_session',
                  'planName': 'Upper Body Strength',
                  'startedAt': '2026-10-12T03:00:00.000Z',
                  'finishedAt': '2026-10-12T03:45:00.000Z',
                  'exerciseLogs': [
                    {
                      'exerciseId': 'ex_1',
                      'exerciseSlug': 'bench-press',
                      'setNumber': 1,
                      'repsCompleted': 20,
                      'unit': 'reps',
                      'weightKg': 100.0,
                      'isCompleted': true,
                    }
                  ],
                  'totalDurationMinutes': 40,
                  'totalVolumeKg': 2000,
                }
              },
            ));
          }
          return handler.next(options);
        },
      ));

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);
      final subscription =
          container.listen(activeSessionSaverProvider, (_, __) {});
      addTearDown(subscription.close);

      final activeNotifier =
          container.read(activeWorkoutSessionProvider.notifier);
      clientId = activeNotifier.sessionId;
      activeNotifier.logActiveSet();

      final saver = container.read(activeSessionSaverProvider.notifier);
      final success = await saver.saveCurrentSession();

      expect(success, isFalse);
      expect(saver.saveStatus, SessionSaveStatus.conflict);
      expect(saver.conflictMessage, contains('409 Conflict'));
      // Draft remains in memory, unchanged
      expect(activeNotifier.pendingSaveSnapshot, isNotNull);
      expect(activeNotifier.sessionId, clientId);
      expect(container.read(activeWorkoutSessionProvider).isFinished, isFalse);
    });

    test('Starting a new workout after save confirmed produces a new session identity and empty logs',
        () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: {
              'session_id': 'saved_canonical_456',
              'session': {
                'id': 'saved_canonical_456',
                'planName': 'Upper Body Strength',
                'startedAt': '2026-10-12T03:00:00.000Z',
                'finishedAt': '2026-10-12T03:45:00.000Z',
                'exerciseLogs': [],
                'totalVolumeKg': 0,
              }
            },
          ));
        },
      ));

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final activeNotifier =
          container.read(activeWorkoutSessionProvider.notifier);
      final firstSessionId = activeNotifier.sessionId;
      activeNotifier.logActiveSet();

      final saver = container.read(activeSessionSaverProvider.notifier);
      expect(await saver.saveCurrentSession(), isTrue);
      expect(activeNotifier.sessionId, 'saved_canonical_456');

      // Start new scheduled session
      activeNotifier.startScheduledSession();
      final newSession = container.read(activeWorkoutSessionProvider);

      expect(activeNotifier.sessionId, isNot(equals(firstSessionId)));
      expect(activeNotifier.sessionId, isNot(equals('saved_canonical_456')));
      expect(activeNotifier.sessionId, matches(RegExp(r'^ws-[0-9a-f]{32}$')));
      expect(newSession.isFinished, isFalse);
      expect(newSession.completedSetsCount, 0);
      expect(activeNotifier.pendingSaveSnapshot, isNull);
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

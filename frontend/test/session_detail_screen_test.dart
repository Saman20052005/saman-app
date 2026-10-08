import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout/data/repositories/mock_exercise_repository.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/session_detail_providers.dart';
import 'package:health_ai_app/presentation/screens/session_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';
import 'package:health_ai_app/presentation/widgets/exercise_set_log_card.dart';

class _LookupRepository extends MockExerciseRepository {
  _LookupRepository(super.exercises);

  final requestedIds = <String>[];
  Completer<Exercise>? pending;

  @override
  Future<Exercise> getExerciseById(String id) {
    requestedIds.add(id);
    return pending?.future ?? super.getExerciseById(id);
  }
}

WorkoutSession _session(String exerciseId) => WorkoutSession(
      id: 'saved-session-detail',
      planName: 'Upper Body Strength',
      startedAt: DateTime.utc(2026, 10, 8),
      totalVolumeKg: 416,
      exerciseLogs: [
        for (final setNumber in [1, 2])
          ExerciseSetLog(
            exerciseId: exerciseId,
            exerciseSlug: exerciseId,
            setNumber: setNumber,
            repsCompleted: 8,
            weightKg: 26,
            isCompleted: true,
          ),
      ],
    );

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _LookupRepository repo,
  WorkoutSession session, {
  bool fromHistory = false,
}) async {
  await repo.saveWorkoutSession(session);
  final container = ProviderContainer(overrides: [
    exerciseRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: fromHistory
          ? const WorkoutHistoryScreen()
          : SessionDetailScreen(sessionId: session.id),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void _expectSavedSets(WidgetTester tester, WorkoutSession session) {
  expect(find.text('Set 1'), findsOneWidget);
  expect(find.text('Set 2'), findsOneWidget);
  expect(find.text('8 reps'), findsNWidgets(2));
  expect(find.text('26 kg'), findsNWidgets(2));
  expect(find.text('Total volume: 416 kg'), findsOneWidget);
  final cards = tester
      .widgetList<ExerciseSetLogCard>(find.byType(ExerciseSetLogCard))
      .toList();
  expect(cards, hasLength(2));
  for (var index = 0; index < cards.length; index++) {
    expect(cards[index].log, same(session.exerciseLogs[index]));
  }
}

void main() {
  testWidgets('Mixed units within one Plank group preserve legacy reps per log', (tester) async {
    final repo = _LookupRepository(curatedExerciseLibrary);
    final session = WorkoutSession(
      id: 'mixed-units-one-exercise', planName: 'Mixed units',
      startedAt: DateTime.utc(2026, 10, 8),
      exerciseLogs: [
        ExerciseSetLog.fromJson({
          'exerciseId': 'plank', 'exerciseSlug': 'plank', 'setNumber': 1,
          'repsCompleted': 8, 'weightKg': 26.0, 'isCompleted': true,
        }),
        ExerciseSetLog(
          exerciseId: 'plank', exerciseSlug: 'plank', setNumber: 2,
          repsCompleted: 0, weightKg: 0, isCompleted: true,
          unit: SetUnit.seconds, secondsCompleted: 50,
        ),
      ],
    );
    await _mount(tester, repo, session);
    expect(find.text('Reps / Seconds'), findsOneWidget);
    expect(find.text('8 reps'), findsOneWidget);
    expect(find.text('26 kg'), findsOneWidget);
    expect(find.text('50 s'), findsOneWidget);
    expect(find.text('0 reps'), findsNothing);
    expect(find.text('0 kg'), findsNothing);
    expect(find.text('Total volume: 208 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'History detail resolves ex_1 and preserves two saved 8 x 26 sets',
      (tester) async {
    final repo = _LookupRepository(curatedExerciseLibrary);
    final session = _session('ex_1');
    final container = await _mount(tester, repo, session, fromHistory: true);
    await tester.tap(find.text(session.planName));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<SessionDetailScreen>(find.byType(SessionDetailScreen))
            .sessionId,
        session.id);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('ex_1'), findsNothing);
    expect(find.text('db-bench-press'), findsNothing);
    expect(repo.requestedIds, ['db-bench-press']);
    _expectSavedSets(tester, session);

    // Refreshing the session rebuilds its cards without re-fetching the name.
    container.invalidate(sessionDetailProvider(session.id));
    await tester.pumpAndSettle();
    expect(repo.requestedIds, ['db-bench-press']);
    expect(await repo.getSessionById(session.id), same(session));
    _expectSavedSets(tester, session);
  });

  testWidgets('Missing exercise shows a readable fallback and keeps saved sets',
      (tester) async {
    final repo = _LookupRepository([]);
    final session = _session('removed-exercise-id');
    await _mount(tester, repo, session);

    expect(find.text('Bài tập không còn trong thư viện'), findsOneWidget);
    expect(find.textContaining('removed-exercise-id'), findsNothing);
    expect(repo.requestedIds, ['removed-exercise-id']);
    _expectSavedSets(tester, session);
  });

  testWidgets('Name loading keeps saved sets visible without repeated lookup',
      (tester) async {
    final repo = _LookupRepository(curatedExerciseLibrary)
      ..pending = Completer<Exercise>();
    final session = _session('db-bench-press');
    await _mount(tester, repo, session);

    expect(find.text('Đang tải tên bài tập…'), findsOneWidget);
    expect(find.text('db-bench-press'), findsNothing);
    _expectSavedSets(tester, session);
    await tester.pump();
    expect(repo.requestedIds, ['db-bench-press']);

    repo.pending!.complete(curatedExerciseLibrary.first);
    await tester.pumpAndSettle();
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    _expectSavedSets(tester, session);
  });

  testWidgets('Name lookup error hides technical details and offers retry',
      (tester) async {
    final repo = _LookupRepository(curatedExerciseLibrary)
      ..pending = Completer<Exercise>();
    final session = _session('ex_1');
    await _mount(tester, repo, session);
    repo.pending!.completeError(Exception('Technical lookup failure for ex_1'));
    await tester.pumpAndSettle();

    expect(find.text('Không tải được tên bài tập'), findsOneWidget);
    expect(find.textContaining('ex_1'), findsNothing);
    _expectSavedSets(tester, session);

    repo.pending = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(repo.requestedIds, ['db-bench-press', 'db-bench-press']);
    _expectSavedSets(tester, session);
  });
}

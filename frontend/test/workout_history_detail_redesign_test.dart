import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout/data/repositories/mock_exercise_repository.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/session_detail_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';

ExerciseSetLog log(
        {String id = 'bench',
        int reps = 8,
        double weight = 26,
        bool completed = true,
        int? seconds}) =>
    ExerciseSetLog(
      exerciseId: id,
      exerciseSlug: id,
      setNumber: 1,
      repsCompleted: seconds == null ? reps : 0,
      weightKg: weight,
      isCompleted: completed,
      unit: seconds == null ? null : SetUnit.seconds,
      secondsCompleted: seconds,
    );

WorkoutSession session(String id, String date,
        {String title = 'Bench day',
        List<ExerciseSetLog>? logs,
        int? minutes}) =>
    WorkoutSession(
      id: id,
      planName: title,
      startedAt: DateTime.parse(date),
      exerciseLogs: logs ?? [log()],
      totalDurationMinutes: minutes,
    );

class HistoryRepository extends MockExerciseRepository {
  HistoryRepository() : super(curatedExerciseLibrary);
  final requests = <Completer<List<WorkoutSession>>>[];
  final detailRequests = <Completer<WorkoutSession>>[];
  @override
  Future<WorkoutSession> getSessionById(String id) {
    final request = Completer<WorkoutSession>();
    detailRequests.add(request);
    return request.future;
  }

  @override
  Future<List<WorkoutSession>> getWorkoutHistory() {
    final request = Completer<List<WorkoutSession>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);
  final fixtures = [
    session('before', '2026-09-30T16:59:59Z'),
    session('oct', '2026-09-30T17:00:00Z'),
    session('sun', '2026-10-18T16:59:59Z', title: 'Leg day'),
    session('mon', '2026-10-18T17:00:00Z'),
    session('last', '2026-10-31T16:59:59Z'),
    session('next', '2026-10-31T17:00:00Z'),
  ];
  List<String> filtered(
          {HistoryPeriod period = HistoryPeriod.allTime,
          DateTime? date,
          String query = ''}) =>
      filterWorkoutHistory(
              fixtures,
              WorkoutHistoryFilterState(
                  calendarMonth: DateTime(2026, 10),
                  period: period,
                  selectedDate: date,
                  searchQuery: query),
              now)
          .map((s) => s.id)
          .toList();

  test('UTC+7 month boundaries include first and last second only', () {
    expect(filtered(period: HistoryPeriod.thisMonth),
        ['last', 'mon', 'sun', 'oct']);
  });
  test('Monday week is half-open and independent from calendar month', () {
    expect(filtered(period: HistoryPeriod.thisWeek), ['mon']);
  });
  test(
      'Selected date overrides period and intersects trimmed case-insensitive search',
      () {
    expect(
        filtered(
            date: DateTime(2026, 10, 1),
            query: ' BENCH ',
            period: HistoryPeriod.thisWeek),
        ['oct']);
    expect(filtered(date: DateTime(2026, 10, 1), query: 'leg'), isEmpty);
  });
  test(
      'Search matches title or recorded exercise slug; clearing restores sorted input',
      () {
    expect(filtered(query: 'leg'), ['sun']);
    expect(filtered(query: 'bench'), hasLength(6));
    expect(filtered(query: 'missing'), isEmpty);
    expect(filtered(), ['next', 'last', 'mon', 'sun', 'oct', 'before']);
    expect(fixtures.first.id, 'before');
  });
  test('Year rollover and UTC+7 date bucket', () {
    final s = session('year', '2026-12-31T17:00:00Z');
    expect(
        filterWorkoutHistory(
            [s],
            WorkoutHistoryFilterState(
                calendarMonth: DateTime(2027, 1),
                period: HistoryPeriod.thisMonth),
            now),
        [s]);
    expect(toVietnamTime(s.startedAt), DateTime.utc(2027, 1, 1));
  });
  test(
      'Overview denominator is only filtered loaded data; duration null differs from zero',
      () {
    final rows = [
      session('zero', '2026-10-24T00:00:00Z', minutes: 0),
      session('unknown', '2026-10-24T01:00:00Z')
    ];
    final result = WorkoutHistoryOverviewData(rows);
    expect(result.completedWorkouts, 2);
    expect(result.totalSets, 2);
    expect(result.totalVolumeKg, 416);
    expect(result.knownDurationSeconds, 0);
    expect(result.unknownDurations, 1);
    expect(SessionDetailMetrics.compute(rows.first).durationSeconds, 0);
    expect(SessionDetailMetrics.compute(rows.last).durationSeconds, isNull);
  });
  test('Mixed explicit units ignore slug heuristics and incomplete sets', () {
    final s = session('mixed', '2026-10-24T00:00:00Z', logs: [
      log(id: 'plank'),
      log(id: 'plank', seconds: 50, weight: 99),
      log(id: 'push-up', reps: 10, weight: 0),
      log(id: 'unresolved', reps: 999, weight: 999, completed: false),
    ]);
    final m = SessionDetailMetrics.compute(s);
    expect(m.completedSetsCount, 3);
    expect(m.completedExercisesCount, 2);
    expect(m.totalReps, 18);
    expect(m.totalTimedSeconds, 50);
    expect(m.totalVolumeKg, 208);
    expect(m.exerciseGroups.first.totalTimedSeconds, 50);
    expect(m.exerciseGroups.first.totalVolumeKg, 208);
    expect(m.exerciseGroups.last.completedSetsCount, 0);
    expect(m.exerciseGroups[1].hasExternalLoad, isFalse);
  });
  test('Timed and bodyweight sessions never create external load volume', () {
    for (final sets in [
      [log(seconds: 60, weight: 100)],
      [log(weight: 0)]
    ]) {
      final m = SessionDetailMetrics.compute(
          session('s', '2026-10-24T00:00:00Z', logs: sets));
      expect(m.totalVolumeKg, 0);
      expect(m.exerciseGroups.single.hasExternalLoad, isFalse);
    }
  });
  test(
      'Zero reps are completed only by explicit flag; fractional load is retained',
      () {
    final m = SessionDetailMetrics.compute(
        session('s', '2026-10-24T00:00:00Z', logs: [
      log(reps: 0, weight: 10),
      log(reps: 1, weight: 0.25),
      log(reps: 10, weight: 10, completed: false),
    ]));
    expect(m.completedSetsCount, 2);
    expect(m.totalVolumeKg, 0.25);
    expect(m.totalReps, 1);
  });
  test(
      'Known finish duration preserves zero and falls back for invalid interval',
      () {
    final s = session('s', '2026-10-24T00:00:00Z', minutes: 32);
    expect(getSessionDurationSeconds(s.copyWith(finishedAt: s.startedAt)), 0);
    expect(
        getSessionDurationSeconds(s.copyWith(
            finishedAt: s.startedAt.subtract(const Duration(seconds: 1)))),
        1920);
  });

  testWidgets(
      'Real history provider loading/error/retry, search empty/clear and calendar actions',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-only'});
    final repo = HistoryRepository();
    final container = ProviderContainer(overrides: [
      workoutSessionRepositoryProvider.overrideWithValue(repo),
      exerciseRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WorkoutHistoryScreen())));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.requests.single.completeError(Exception('boundary failure'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load workout history'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    repo.requests.last.complete([fixtures[1]]);
    await tester.pumpAndSettle();
    expect(find.text('Bench day'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No workouts match your filters'), findsOneWidget);
    expect(find.text('No workout history yet'), findsNothing);
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Bench day'), findsOneWidget);
    await tester.tap(find.text('Calendar and period overview'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await tester.tap(find.text('Calendar month'));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    picker.onDateChanged(DateTime(2026, 10, 2));
    await tester.pumpAndSettle();
    expect(find.text('Bench day'), findsNothing);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    if (find.byType(CalendarDatePicker).evaluate().isEmpty) {
      await tester.tap(find.text('Calendar and period overview'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('1 of 1 loaded workouts'), findsOneWidget);
    expect(repo.requests, hasLength(2));
  });

  testWidgets('Empty API history is distinct from no matching results',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-only'});
    final repo = HistoryRepository();
    await tester.pumpWidget(ProviderScope(overrides: [
      workoutSessionRepositoryProvider.overrideWithValue(repo),
    ], child: const MaterialApp(home: WorkoutHistoryScreen())));
    await tester.pump();
    repo.requests.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No workout history yet'), findsOneWidget);
    expect(find.text('No workouts match your filters'), findsNothing);
  });

  test('Account switch discards late A history response', () async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-only'});
    final repo = HistoryRepository();
    final container = ProviderContainer(
        overrides: [workoutSessionRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final sub = container.listen(workoutHistoryProvider, (_, __) {});
    addTearDown(sub.close);
    final a = container.read(workoutHistoryProvider.future);
    await Future<void>.delayed(Duration.zero);
    container.read(workoutAuthScopeProvider.notifier).state++;
    await Future<void>.delayed(Duration.zero);
    final b = container.read(workoutHistoryProvider.future);
    repo.requests.last.complete([fixtures.last]);
    await b;
    repo.requests.first.complete([fixtures.first]);
    await a;
    expect(
        container.read(workoutHistoryProvider).requireValue, [fixtures.last]);
  });

  test('Account switch discards late detail response for reused session id',
      () async {
    final repo = HistoryRepository();
    final container = ProviderContainer(
        overrides: [workoutSessionRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final sub = container.listen(sessionDetailProvider('same-id'), (_, __) {});
    addTearDown(sub.close);
    final a = container.read(sessionDetailProvider('same-id').future);
    container.read(workoutAuthScopeProvider.notifier).state++;
    final b = container.read(sessionDetailProvider('same-id').future);
    repo.detailRequests.last.complete(fixtures.last);
    await b;
    repo.detailRequests.first.complete(fixtures.first);
    await a;
    expect(container.read(sessionDetailProvider('same-id')).requireValue,
        fixtures.last);
  });
}

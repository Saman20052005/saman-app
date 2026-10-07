import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout/data/repositories/mock_exercise_repository.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:health_ai_app/presentation/screens/create_plan_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/presentation/screens/my_plans_screen.dart';
import 'package:health_ai_app/presentation/screens/session_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/services/api_client.dart';

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<ProviderContainer> mount(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [
    dioProvider
        .overrideWith((ref) => throw StateError('Backend must not be used')),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: SamanTheme.light(), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

class DelayedRepository extends MockExerciseRepository {
  DelayedRepository() : super(curatedExerciseLibrary);
  final gate = Completer<void>();
  int writes = 0;
  @override
  Future<void> saveWorkoutSession(WorkoutSession session) async {
    writes++;
    await gate.future;
    await super.saveWorkoutSession(session);
  }
}

class RetryRepository extends MockExerciseRepository {
  RetryRepository() : super(curatedExerciseLibrary);
  bool fail = true;
  @override
  Future<void> saveWorkoutSession(WorkoutSession session) async {
    if (fail) throw StateError('Simulated local write failure');
    await super.saveWorkoutSession(session);
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
      'Home Start -> log -> Finish -> Back -> Save -> History -> detail',
      (tester) async {
    final container = await mount(tester, const WorkoutHomeScreen());
    await tap(tester, find.text('Start workout'));
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    final active = container.read(activeWorkoutSessionProvider.notifier);
    expect(tester.widget<Text>(find.byKey(const ValueKey('active_workout_draft_reps'))).data, '8');
    expect(container.read(activeWorkoutSessionProvider).exerciseCount, 5);
    await tap(
        tester, find.byKey(const ValueKey('active_workout_log_set_button')));
    final before = container.read(activeWorkoutSessionProvider);
    await tap(
        tester, find.byKey(const ValueKey('active_workout_finish_button')));
    expect(find.text('Workout Review & Save'), findsOneWidget);
    expect(await container.read(exerciseRepositoryProvider).getWorkoutHistory(),
        isEmpty);
    active.tick();
    expect(container.read(activeWorkoutSessionProvider).elapsedSeconds,
        before.elapsedSeconds);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(activeWorkoutSessionProvider).exercises,
        same(before.exercises));
    expect(container.read(activeWorkoutSessionProvider).restSecondsLeft,
        before.restSecondsLeft);
    expect(container.read(activeWorkoutSessionProvider).isPaused, false);
    await tap(
        tester, find.byKey(const ValueKey('active_workout_finish_button')));
    // Two physical taps before the next frame must still write once.
    await tester.tap(find.byKey(const ValueKey('save_session_button')));
    await tester.tap(find.byKey(const ValueKey('save_session_button')),
        warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    final history =
        await container.read(exerciseRepositoryProvider).getWorkoutHistory();
    expect(history, hasLength(1));
    expect(history.single.exerciseLogs, hasLength(1));
    expect(history.single.exerciseLogs.single.weightKg, 26);
    expect(history.single.exerciseLogs.single.repsCompleted, 8);
    expect(history.single.totalVolumeKg, 208);
    expect(history.single.totalDurationMinutes, before.elapsedSeconds ~/ 60);
    expect(container.read(activeWorkoutSessionProvider).isFinished, true);
    await tap(tester, find.text('Upper Body Strength'));
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.text('26 kg'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Quick Start selects exactly one exercise and preserves its prescription',
      (tester) async {
    final container = await mount(tester, const WorkoutHomeScreen());
    await tap(tester, find.text('Quick start'));
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('exercise_row_lat-pulldown')));
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    final session = container.read(activeWorkoutSessionProvider);
    final exercise =
        curatedExerciseLibrary.firstWhere((e) => e.id == 'lat-pulldown');
    expect(session.title, 'Quick Start');
    expect(session.exercises.single.id, exercise.id);
    expect(session.exercises.single.slug, exercise.slug);
    expect(session.exercises.single.sets.length, exercise.defaultSets);
    expect(session.completedSetsCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'My Plans -> Create -> Library -> Save -> edit -> start -> delete locally',
      (tester) async {
    final container = await mount(tester, const WorkoutHomeScreen());
    await tap(tester, find.text('My Plans'));
    expect(find.byType(MyPlansScreen), findsOneWidget);
    await tap(tester, find.text('Tạo Plan mới'));
    expect(find.byType(CreatePlanScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Local strength');
    await tap(tester, find.text('Mở Library'));
    await tap(
        tester, find.byKey(const ValueKey('exercise_row_db-bench-press')));
    await tap(tester, find.text('Lưu Plan'));
    expect(find.byType(MyPlansScreen), findsOneWidget);
    final repo = container.read(exerciseRepositoryProvider);
    final plans = await repo.getMyPlans();
    expect(plans.single.name, 'Local strength');
    expect(plans.single.exerciseIds, ['db-bench-press']);
    await tap(tester, find.text('Local strength'));
    await tester.enterText(find.byType(TextField), 'Edited strength');
    await tap(tester, find.text('Lưu Plan'));
    expect((await repo.getMyPlans()).single.id, plans.single.id);
    expect((await repo.getMyPlans()).single.name, 'Edited strength');
    await tap(tester, find.text('Bắt đầu'));
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    final session = container.read(activeWorkoutSessionProvider);
    expect(session.title, 'Edited strength');
    expect(session.exercises.single.id, 'db-bench-press');
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, find.byIcon(Icons.delete_outline));
    await tap(tester, find.text('Xóa'));
    expect(await repo.getMyPlans(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Empty Review cannot save; dismiss preserves paused session',
      (tester) async {
    final container =
        await mount(tester, const ActiveWorkoutScreen(autoTick: false));
    container.read(activeWorkoutSessionProvider.notifier).pauseWorkout();
    await tester.pump();
    await tap(
        tester, find.byKey(const ValueKey('active_workout_finish_button')));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save_session_button')))
            .onPressed,
        isNull);
    await tap(tester, find.text('Keep Training'));
    expect(container.read(activeWorkoutSessionProvider).isPaused, true);
    expect(await container.read(exerciseRepositoryProvider).getWorkoutHistory(),
        isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  test(
      'Saver and repository reject repeated writes; new session has a new identity',
      () async {
    final repo = DelayedRepository();
    final container = ProviderContainer(overrides: [
      exerciseRepositoryProvider.overrideWith((ref) => repo),
    ]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(activeSessionSaverProvider, (_, __) {});
    addTearDown(subscription.close);
    final active = container.read(activeWorkoutSessionProvider.notifier);
    active.logActiveSet();
    final saver = container.read(activeSessionSaverProvider.notifier);
    final first = saver.saveCurrentSession();
    expect(await saver.saveCurrentSession(), false);
    expect(repo.writes, 1);
    repo.gate.complete();
    expect(await first, true);
    expect(await saver.saveCurrentSession(), false);
    final saved = (await repo.getWorkoutHistory()).single;
    await repo.saveWorkoutSession(saved);
    expect(await repo.getWorkoutHistory(), hasLength(1));
    active.startSession([curatedExerciseLibrary.first]);
    active.logActiveSet();
    expect(await saver.saveCurrentSession(), true);
    expect(await repo.getWorkoutHistory(), hasLength(2));
    expect((await repo.getWorkoutHistory()).first.id, isNot(saved.id));
  });

  test(
      'Failed Save preserves active sets and retry saves the same session once',
      () async {
    final repo = RetryRepository();
    final container = ProviderContainer(overrides: [
      exerciseRepositoryProvider.overrideWith((ref) => repo),
    ]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(activeSessionSaverProvider, (_, __) {});
    addTearDown(subscription.close);
    container.read(activeWorkoutSessionProvider.notifier).logActiveSet();
    final before = container.read(activeWorkoutSessionProvider);
    final saver = container.read(activeSessionSaverProvider.notifier);
    expect(await saver.saveCurrentSession(), false);
    expect(container.read(activeSessionSaverProvider).hasError, true);
    expect(container.read(activeWorkoutSessionProvider), same(before));
    expect(await repo.getWorkoutHistory(), isEmpty);
    repo.fail = false;
    expect(await saver.saveCurrentSession(), true);
    expect(await repo.getWorkoutHistory(), hasLength(1));
  });

  testWidgets(
      'Complete sets advances to next exercise; queue keeps logged results',
      (tester) async {
    final container = await mount(
        tester,
        ActiveWorkoutScreen.fromExercises(
          exercises: curatedExerciseLibrary
              .take(2)
              .map((exercise) => exercise.copyWith(defaultSets: 1))
              .toList(),
        ));
    await tap(tester, find.text('Log Set 1'));
    expect(find.text('Next exercise'), findsOneWidget);
    await tap(tester, find.text('Next exercise'));
    expect(
        container.read(activeWorkoutSessionProvider).currentExerciseIndex, 1);
    expect(container.read(activeWorkoutSessionProvider).isResting, false);
    await tap(tester, find.text('Log Set 1'));
    expect(find.text('Review session'), findsOneWidget);
    await tap(tester, find.text('View all 2 exercises →'));
    await tap(tester, find.text(curatedExerciseLibrary.first.name));
    expect(
        container.read(activeWorkoutSessionProvider).currentExerciseIndex, 0);
    expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 2);
    await tap(
        tester, find.byKey(const ValueKey('active_workout_finish_button')));
    await tap(tester, find.text('Save Session'));
    final saved =
        (await container.read(exerciseRepositoryProvider).getWorkoutHistory())
            .single;
    expect(saved.exerciseLogs.map((log) => log.exerciseId).toSet(),
        curatedExerciseLibrary.take(2).map((exercise) => exercise.id).toSet());
    await tester.pumpWidget(const SizedBox());
  });
}

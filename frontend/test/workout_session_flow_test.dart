import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout/data/repositories/mock_exercise_repository.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/session_detail_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:health_ai_app/presentation/screens/create_plan_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/my_plans_screen.dart';
import 'package:health_ai_app/presentation/screens/session_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_review_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_complete_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/presentation/widgets/exercise_set_log_card.dart';
import 'package:health_ai_app/presentation/widgets/exercise_thumbnail.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

import 'main_screen_test.dart' show FakeProfileNotifier, FakeNutritionNotifier;
import 'workout_exercise_catalog_test.dart' show expectedNewExercises;
import 'workout_exercise_images_test.dart'
    show loadImages, loadTestFonts, testWorkoutThemeExtension;

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<ProviderContainer> mount(WidgetTester tester, Widget home,
    {List<Override> overrides = const [], bool workoutOnlyTheme = false}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [
    dioProvider
        .overrideWith((ref) => throw StateError('Backend must not be used')),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: workoutOnlyTheme
          ? ThemeData(fontFamily: 'Roboto', extensions: const [testWorkoutThemeExtension])
          : SamanTheme.light(),
      home: home,
    ),
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
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadTestFonts();
  });
  for (final id in ['one-arm-dumbbell-row', 'reverse-lunge', 'dead-bug']) {
    testWidgets('$id real Detail -> Log all sets -> Review -> resume -> Save -> detail',
        (tester) async {
      final expected = expectedNewExercises[id]!;
      final container = await mount(tester,
          const ExerciseLibraryScreen(initialCategory: 'All'), workoutOnlyTheme: true);
      await loadImages(tester, curatedExerciseLibrary.expand((e) =>
          [e.thumbnailUrl, exercisePosterSource(e.thumbnailUrl)]));
      await tester.enterText(find.byType(TextField), expected.$2);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(ValueKey('exercise_row_$id')));
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(find.text(expected.$2), findsOneWidget);
      expect(tester.widget<ExerciseThumbnail>(find.byType(ExerciseThumbnail)).source,
          'assets/images/exercises/$id-poster.jpg');
      await tap(tester, find.byKey(const ValueKey('exercise_detail_start_button')));
      final active = container.read(activeWorkoutSessionProvider.notifier);
      final sessionId = active.sessionId;
      expect(container.read(activeWorkoutSessionProvider).exercises.single.id, id);
      expect(container.read(activeWorkoutSessionProvider).exercises.single.slug, id);
      final weight = id == 'one-arm-dumbbell-row' ? 20.0 : 0.0;
      for (var set = 0; set < 3; set++) {
        expect(container.read(activeWorkoutSessionProvider).currentExercise!.draftWeightKg, 20);
        if (weight == 0) {
          final minus = find.byKey(const ValueKey('active_workout_weight_minus'));
          await tester.ensureVisible(minus);
          for (var kg = 20; kg > 0; kg--) {
            await tester.tap(minus);
            await tester.pump();
          }
        }
        expect(container.read(activeWorkoutSessionProvider).currentExercise!.draftWeightKg, weight);
        await tap(tester, find.byKey(const ValueKey('active_workout_log_set_button')));
        final logged = container.read(activeWorkoutSessionProvider).exercises.single.sets[set];
        expect(logged.reps, 20); // Total entered reps stay 20, never 40.
        expect(logged.weightKg, weight);
        if (set < 2) {
          await tap(tester, find.byKey(const ValueKey('active_workout_rest_skip')));
        }
      }
      await tap(tester, find.byKey(const ValueKey('active_workout_finish_button')));
      final volumeColumn = find.ancestor(
          of: find.text('TOTAL VOLUME'), matching: find.byType(Column)).first;
      expect(find.descendant(of: volumeColumn,
          matching: find.text(weight == 0 ? '0' : '1,200')), findsOneWidget);
      expect(tester.widgetList<ExerciseThumbnail>(find.byType(ExerciseThumbnail))
          .map((w) => w.source),
          ['assets/images/exercises/$id-poster.jpg', 'assets/images/exercises/$id-thumb.jpg']);
      final before = container.read(activeWorkoutSessionProvider);
      await tap(tester, find.byKey(const ValueKey('keep_training_button')));
      expect(active.sessionId, sessionId);
      expect(container.read(activeWorkoutSessionProvider).exercises, same(before.exercises));
      await tap(tester, find.byKey(const ValueKey('active_workout_finish_button')));
      await tester.tap(find.byKey(const ValueKey('save_session_button')));
      await tester.tap(find.byKey(const ValueKey('save_session_button')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCompleteScreen), findsOneWidget);
      final repo = container.read(exerciseRepositoryProvider);
      final saved = await repo.getSessionById(sessionId);
      expect(await repo.getWorkoutHistory(), hasLength(1));
      expect(saved.exerciseLogs.map((l) => l.exerciseId), [id, id, id]);
      expect(saved.exerciseLogs.map((l) => l.exerciseSlug), [id, id, id]);
      expect(saved.exerciseLogs.map((l) => l.repsCompleted), [20, 20, 20]);
      expect(saved.exerciseLogs.map((l) => l.weightKg), [weight, weight, weight]);
      expect(saved.totalVolumeKg, weight == 0 ? 0 : 1200);
      await tap(tester, find.text('View workout history'));
      await tap(tester, find.text(expected.$1));
      expect(find.byType(SessionDetailScreen), findsOneWidget);
      expect(find.text(expected.$1), findsOneWidget);
      expect(find.text('20 reps'), findsNWidgets(3));
      expect(find.text(weight == 0 ? '0 kg' : '20 kg'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final entry in expectedNewExercises.entries) {
    testWidgets('${entry.key} selected in Create Plan -> save -> edit -> start resolves exact ID',
        (tester) async {
      final container = await mount(tester, const MyPlansScreen(), workoutOnlyTheme: true);
      await loadImages(tester, curatedExerciseLibrary.expand((e) =>
          [e.thumbnailUrl, exercisePosterSource(e.thumbnailUrl)]));
      await tap(tester, find.text('Tạo Plan mới'));
      await tester.enterText(find.byType(TextField), 'Plan ${entry.key}');
      await tap(tester, find.text('Mở Library'));
      await tester.enterText(find.byType(TextField), entry.value.$2);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(ValueKey('exercise_row_${entry.key}')));
      expect(find.byType(CreatePlanScreen), findsOneWidget);
      expect(find.text(entry.value.$1), findsOneWidget);
      await tap(tester, find.text('Lưu Plan'));
      final repo = container.read(exerciseRepositoryProvider);
      final plan = (await repo.getMyPlans()).single;
      expect(plan.exerciseIds, [entry.key]);
      await tap(tester, find.text(plan.name));
      expect(find.text(entry.value.$1), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Edited ${entry.key}');
      await tap(tester, find.text('Lưu Plan'));
      final edited = (await repo.getMyPlans()).single;
      expect(edited.id, plan.id);
      expect(edited.exerciseIds, [entry.key]);
      await tap(tester, find.text('Bắt đầu'));
      final started = container.read(activeWorkoutSessionProvider);
      expect(started.title, edited.name);
      expect(started.exercises.single.id, entry.key);
      expect(started.exercises.single.slug, entry.key);
      expect(started.exercises.single.imageUrl,
          'assets/images/exercises/${entry.key}-thumb.jpg');
      expect(started.exercises.single.sets, hasLength(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final durationCase in <(int?, String)>[
    (0, '<1 min'),
    (null, '—'),
    (32, '32m'),
  ]) {
    testWidgets('History duration ${durationCase.$1} shows ${durationCase.$2}',
        (tester) async {
      final container = await mount(tester, const WorkoutHistoryScreen());
      final session = WorkoutSession(
        id: 'history-duration-${durationCase.$1}',
        planName: 'Duration display check',
        startedAt: DateTime.utc(2026, 10, 8),
        exerciseLogs: const [],
        totalDurationMinutes: durationCase.$1,
      );
      final repo = container.read(exerciseRepositoryProvider);
      await repo.saveWorkoutSession(session);
      container.invalidate(workoutHistoryProvider);
      await tester.pumpAndSettle();

      expect(find.text(durationCase.$2), findsOneWidget);
      expect(find.text('0m'), findsNothing);
      expect((await repo.getSessionById(session.id)).totalDurationMinutes,
          durationCase.$1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final dismiss in ['Keep training', 'Review Back', 'System Back']) {
    testWidgets('$dismiss preserves logs and drafts; log another set and Finish',
        (tester) async {
      final container =
          await mount(tester, const ActiveWorkoutScreen(autoTick: false));
      final active = container.read(activeWorkoutSessionProvider.notifier);
      final sessionId = active.sessionId;
      active.setDraftWeight(22.5);
      active.setDraftReps(9);
      await tester.pump();
      await tap(tester,
          find.byKey(const ValueKey('active_workout_log_set_button')));
      active.setDraftWeight(30);
      active.setDraftReps(11);
      await tester.pump();
      final before = container.read(activeWorkoutSessionProvider);

      await tap(tester,
          find.byKey(const ValueKey('active_workout_finish_button')));
      expect(find.byType(WorkoutReviewScreen), findsOneWidget);
      if (dismiss == 'System Back') {
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      } else {
        await tap(
            tester,
            find.byKey(ValueKey(dismiss == 'Keep training'
                ? 'keep_training_button'
                : 'workout_review_back_button')));
      }
      final resumed = container.read(activeWorkoutSessionProvider);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(active.sessionId, sessionId);
      expect(resumed.exercises, same(before.exercises));
      expect(resumed.elapsedSeconds, before.elapsedSeconds);
      expect(resumed.restSecondsLeft, before.restSecondsLeft);
      expect(resumed.isPaused, before.isPaused);
      expect(resumed.currentExercise!.sets.first.setNumber, 1);
      expect(resumed.currentExercise!.sets.first.reps, 9);
      expect(resumed.currentExercise!.sets.first.weightKg, 22.5);
      expect(resumed.currentExercise!.draftReps, 11);
      expect(resumed.currentExercise!.draftWeightKg, 30);

      await tap(tester, find.byKey(const ValueKey('active_workout_rest_skip')));
      await tap(tester,
          find.byKey(const ValueKey('active_workout_log_set_button')));
      final continued = container.read(activeWorkoutSessionProvider);
      expect(continued.completedSetsCount, 2);
      expect(continued.currentExercise!.sets[1].setNumber, 2);
      expect(continued.currentExercise!.sets[1].reps, 11);
      expect(continued.currentExercise!.sets[1].weightKg, 30);
      await tap(tester,
          find.byKey(const ValueKey('active_workout_finish_button')));
      expect(find.byType(WorkoutReviewScreen), findsOneWidget);
      expect(find.textContaining('2 sets logged'), findsOneWidget);
      expect(await container.read(exerciseRepositoryProvider).getWorkoutHistory(),
          isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Save -> 07 -> Workout tab; system Back cannot reopen saved routes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = await mount(tester, const MainScreen(), overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      profileProvider.overrideWith((ref) => FakeProfileNotifier()),
      nutritionProvider.overrideWith((ref) => FakeNutritionNotifier()),
      mainNavIndexProvider.overrideWith((ref) => 1),
    ]);
    await tap(tester, find.text('Start workout'));
    await tap(tester,
        find.byKey(const ValueKey('active_workout_log_set_button')));
    await tap(tester,
        find.byKey(const ValueKey('active_workout_finish_button')));
    await tap(tester, find.byKey(const ValueKey('save_session_button')));
    expect(find.byType(WorkoutCompleteScreen), findsOneWidget);
    await tap(tester, find.text('Back to Workout'));
    expect(find.byType(MainScreen), findsOneWidget);
    expect(container.read(mainNavIndexProvider), 1);
    expect(tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar)).currentIndex, 1);
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(mainNavIndexProvider), 1);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(WorkoutCompleteScreen), findsNothing);
    expect(find.byType(WorkoutReviewScreen), findsNothing);
    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(await container.read(exerciseRepositoryProvider).getWorkoutHistory(),
        hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(find.byType(WorkoutReviewScreen), findsOneWidget);
    expect(find.text('STAGE • PENDING CONFIRMATION'), findsOneWidget);
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
    // Checkpoint 07: Workout Complete screen is displayed with confirmed session!
    expect(find.byType(WorkoutCompleteScreen), findsOneWidget);
    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(find.byType(WorkoutReviewScreen), findsNothing);
    final history =
        await container.read(exerciseRepositoryProvider).getWorkoutHistory();
    expect(history, hasLength(1));
    expect(history.single.exerciseLogs, hasLength(1));
    expect(history.single.exerciseLogs.single.weightKg, 26);
    expect(history.single.exerciseLogs.single.repsCompleted, 8);
    expect(history.single.totalVolumeKg, 208);
    expect(history.single.totalDurationMinutes, before.elapsedSeconds ~/ 60);
    expect(container.read(activeWorkoutSessionProvider).isFinished, true);

    // From Complete screen: View workout history
    await tap(tester, find.text('View workout history'));
    expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
    await tap(tester, find.text('Upper Body Strength'));
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(tester.widget<SessionDetailScreen>(find.byType(SessionDetailScreen))
        .sessionId, history.single.id);
    final detailed = await container
        .read(sessionDetailProvider(history.single.id).future);
    expect(detailed, history.single);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text(history.single.exerciseLogs.single.exerciseSlug),
        findsNothing);
    expect(find.text('Set 1'), findsOneWidget);
    expect(find.text('8 reps'), findsOneWidget);
    expect(find.text('26 kg'), findsOneWidget);
    expect(tester.widget<ExerciseSetLogCard>(find.byType(ExerciseSetLogCard)).log,
        history.single.exerciseLogs.single);
    await tester.binding.handlePopRoute(); // Back from detail to History
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
    await tester.binding.handlePopRoute(); // Back from History to Complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkoutCompleteScreen), findsOneWidget);
    // From Complete screen: Back to Workout returns to WorkoutHomeScreen
    await tap(tester, find.text('Back to Workout'));
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
    expect(find.byType(WorkoutCompleteScreen), findsNothing);
    expect(find.byType(WorkoutReviewScreen), findsNothing);
    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(await container.read(exerciseRepositoryProvider).getWorkoutHistory(),
        hasLength(1));
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
    expect(find.byType(WorkoutReviewScreen), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save_session_button')))
            .onPressed,
        isNull);
    expect(find.text('At least 1 completed set required to save'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save_session_button')));
    await tester.pump();
    expect(find.byType(WorkoutReviewScreen), findsOneWidget);
    expect(await container.read(exerciseRepositoryProvider).getWorkoutHistory(),
        isEmpty);
    await tap(tester, find.byKey(const ValueKey('keep_training_button')));
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 0);
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
    await tap(tester, find.byKey(const ValueKey('save_session_button')));
    expect(find.byType(WorkoutCompleteScreen), findsOneWidget);
    final saved =
        (await container.read(exerciseRepositoryProvider).getWorkoutHistory())
            .single;
    expect(saved.exerciseLogs.map((log) => log.exerciseId).toSet(),
        curatedExerciseLibrary.take(2).map((exercise) => exercise.id).toSet());
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets(
      'Screen 06 formats decimal weight and displays duration 0 as <1 min',
      (tester) async {
    final container = await mount(
        tester,
        ActiveWorkoutScreen.fromExercises(
          exercises: [
            curatedExerciseLibrary.first.copyWith(
              defaultSets: 1,
            ),
          ],
        ));
    container.read(activeWorkoutSessionProvider.notifier).setDraftWeight(22.5);
    await tester.pump();
    await tap(tester, find.text('Log Set 1'));
    await tap(
        tester, find.byKey(const ValueKey('active_workout_finish_button')));
    expect(find.byType(WorkoutReviewScreen), findsOneWidget);
    expect(find.text('<1'), findsOneWidget);
    expect(find.text('min'), findsWidgets);
    expect(find.textContaining('22.5 kg'), findsWidgets);
    await tap(tester, find.byKey(const ValueKey('keep_training_button')));
    expect(find.byType(WorkoutReviewScreen), findsNothing);
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Screen 07 shows a dash when saved duration is missing',
      (tester) async {
    final repo = MockExerciseRepository(curatedExerciseLibrary);
    final session = WorkoutSession(
      id: 'session-missing-duration',
      planName: 'Missing duration',
      startedAt: DateTime.utc(2026, 10, 8),
      exerciseLogs: const [],
    );
    await repo.saveWorkoutSession(session);
    await mount(tester, WorkoutCompleteScreen(sessionId: session.id), overrides: [
      exerciseRepositoryProvider.overrideWithValue(repo),
    ]);

    final durationMetric = find
        .ancestor(of: find.text('ACTIVE DURATION'), matching: find.byType(Column))
        .first;
    expect(find.descendant(of: durationMetric, matching: find.text('—')),
        findsOneWidget);
    expect(find.descendant(of: durationMetric, matching: find.text('<1')),
        findsNothing);
    expect(find.descendant(of: durationMetric, matching: find.text('0')),
        findsNothing);
    expect((await repo.getSessionById(session.id)).totalDurationMinutes, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Screen 07 displays exact session by ID, omits chart on zero volume, handles duration 0',
      (tester) async {
    final repo = MockExerciseRepository(curatedExerciseLibrary);
    final now = DateTime.now();
    final session1 = WorkoutSession(
      id: 'session-id-1',
      planName: 'First Heavy Session',
      startedAt: now.subtract(const Duration(hours: 2)),
      finishedAt: now.subtract(const Duration(hours: 1)),
      totalDurationMinutes: 60,
      totalVolumeKg: 1200,
      exerciseLogs: [
        ExerciseSetLog(
          exerciseId: 'dumbbell-bench-press',
          exerciseSlug: 'dumbbell-bench-press',
          setNumber: 1,
          repsCompleted: 10,
          weightKg: 50.0,
          isCompleted: true,
        ),
      ],
    );
    final session2 = WorkoutSession(
      id: 'session-id-2-zero-vol',
      planName: 'Zero Volume Bodyweight',
      startedAt: now.subtract(const Duration(minutes: 5)),
      finishedAt: now.subtract(const Duration(minutes: 5)),
      totalDurationMinutes: 0,
      totalVolumeKg: 0,
      exerciseLogs: [
        ExerciseSetLog(
          exerciseId: 'bodyweight-squat',
          exerciseSlug: 'bodyweight-squat',
          setNumber: 1,
          repsCompleted: 20,
          weightKg: 0.0,
          isCompleted: true,
        ),
      ],
    );
    await repo.saveWorkoutSession(session1);
    await repo.saveWorkoutSession(session2);

    final container = ProviderContainer(
      overrides: [
        exerciseRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: WorkoutCompleteScreen(sessionId: 'session-id-2-zero-vol'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify exact session by ID was loaded
    expect(find.text('Zero Volume Bodyweight'), findsOneWidget);
    expect(find.text('First Heavy Session'), findsNothing);

    // Verify duration 0 shows '<1'
    expect(find.text('<1'), findsOneWidget);

    // Verify zero volume omits the volume breakdown bar
    expect(find.text('VOLUME BY EXERCISE'), findsNothing);

    // Verify demo memory note
    expect(
        find.textContaining(
            'Demo only. This workout is kept in memory and disappears when the app restarts. It is not synced.'),
        findsOneWidget);

    // Verify actions exist
    expect(find.text('Back to Workout'), findsOneWidget);
    expect(find.text('View workout history'), findsOneWidget);

    // Tap View workout history
    await tester.tap(find.text('View workout history'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutHistoryScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

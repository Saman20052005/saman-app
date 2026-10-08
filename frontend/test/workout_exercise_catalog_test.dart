import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/active_workout_state.dart';
import 'package:health_ai_app/presentation/providers/create_plan_providers.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/my_plans_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';

const originalExerciseIds = [
  'db-bench-press',
  'lat-pulldown',
  'seated-cable-row',
  'db-shoulder-press',
  'push-up',
  'db-bicep-curl',
  'triceps-rope-pushdown',
  'barbell-back-squat',
  'romanian-deadlift',
  'barbell-hip-thrust',
  'leg-press',
  'lying-leg-curl',
  'standing-calf-raise',
  'plank',
  'hanging-leg-raise',
  'cable-woodchopper',
  'ab-wheel-rollout',
];

// Independent task specification: name, Vietnamese name, group, equipment,
// difficulty, reps and rest. Shared by the catalog and actual route tests.
const expectedNewExercises =
    <String, (String, String, String, List<String>, String, String, int)>{
  'incline-dumbbell-flyes': (
    'Incline Dumbbell Flyes',
    'Ép ngực tạ đơn trên ghế nghiêng',
    'Chest',
    ['Dumbbells', 'Incline Bench'],
    'intermediate',
    '10-12',
    60,
  ),
  'overhead-triceps-extension': (
    'Overhead Dumbbell Triceps Extension',
    'Duỗi tay sau qua đầu với tạ đơn',
    'Arms',
    ['Dumbbells'],
    'beginner',
    '10-12',
    60,
  ),
  'face-pulls': (
    'Face Pull',
    'Kéo cáp dây thừng về mặt',
    'Shoulders',
    ['Cable Machine', 'Rope Attachment'],
    'intermediate',
    '12-15',
    60,
  ),
  'incline-dumbbell-press': (
    'Incline Dumbbell Press',
    'Đẩy ngực tạ đơn trên ghế nghiêng',
    'Chest',
    ['Dumbbells', 'Incline Bench'],
    'intermediate',
    '8-10',
    90,
  ),
  'one-arm-dumbbell-row': (
    'One-Arm Dumbbell Row',
    'Kéo tạ đơn một tay có ghế hỗ trợ',
    'Back',
    ['Dumbbells', 'Flat bench'],
    'intermediate',
    '20-24',
    75,
  ),
  'dumbbell-lateral-raise': (
    'Dumbbell Lateral Raise',
    'Nâng tạ đơn sang ngang',
    'Shoulders',
    ['Dumbbells'],
    'beginner',
    '12-15',
    60,
  ),
  'hammer-curl': (
    'Hammer Curl',
    'Cuốn tạ đơn kiểu búa',
    'Arms',
    ['Dumbbells'],
    'beginner',
    '10-12',
    60,
  ),
  'goblet-squat': (
    'Goblet Squat',
    'Squat ôm một tạ đơn trước ngực',
    'Quads',
    ['Dumbbells'],
    'beginner',
    '10-12',
    90,
  ),
  'reverse-lunge': (
    'Reverse Lunge',
    'Chùng chân bước lùi luân phiên',
    'Quads',
    ['Bodyweight'],
    'beginner',
    '20',
    60,
  ),
  'dead-bug': (
    'Dead Bug',
    'Duỗi tay chân đối bên khi nằm ngửa',
    'Abs',
    ['Bodyweight'],
    'beginner',
    '20',
    60,
  ),
};

const expectedCategoryIds = <String, List<String>>{
  'Upper Body': [
    'db-bench-press',
    'lat-pulldown',
    'seated-cable-row',
    'db-shoulder-press',
    'push-up',
    'db-bicep-curl',
    'triceps-rope-pushdown',
    'incline-dumbbell-flyes',
    'overhead-triceps-extension',
    'face-pulls',
    'incline-dumbbell-press',
    'one-arm-dumbbell-row',
    'dumbbell-lateral-raise',
    'hammer-curl',
  ],
  'Lower Body': [
    'barbell-back-squat',
    'romanian-deadlift',
    'barbell-hip-thrust',
    'leg-press',
    'lying-leg-curl',
    'standing-calf-raise',
    'goblet-squat',
    'reverse-lunge',
  ],
  'Core': [
    'plank',
    'hanging-leg-raise',
    'cable-woodchopper',
    'ab-wheel-rollout',
    'dead-bug',
  ],
};

void main() {
  test('Plank timed targets, draft, transitions and save preserve units and zero weight', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(activeSessionSaverProvider, (_, __) {});
    addTearDown(subscription.close);
    final repo = container.read(exerciseRepositoryProvider);
    final plank = await repo.getExerciseById('plank');
    final active = container.read(activeWorkoutSessionProvider.notifier);
    active.startSession([plank, curatedExerciseLibrary.first]);
    var current = container.read(activeWorkoutSessionProvider).currentExercise!;
    expect(current.unit, SetUnit.seconds);
    expect(current.sets, hasLength(3));
    expect(current.restSeconds, 60);
    expect(current.draftSeconds, 45);
    expect(current.draftReps, 0);
    expect(current.sets.map((s) => s.unit), everyElement(SetUnit.seconds));
    expect(current.sets.map((s) => s.targetSeconds), everyElement(45));
    expect(current.sets.map((s) => s.targetWeightKg), everyElement(0));
    active.setDraftWeight(26);
    active.adjustDraftWeight(26);
    active.setDraftSeconds(50);
    active.selectExercise(1);
    active.setDraftReps(8);
    active.setDraftWeight(26);
    active.logActiveSet();
    active.selectExercise(0);
    current = container.read(activeWorkoutSessionProvider).currentExercise!;
    expect(current.draftSeconds, 50);
    expect(current.draftWeightKg, 0);
    active.tick();
    expect(container.read(activeWorkoutSessionProvider).currentExercise!.draftSeconds, 50);
    active.logActiveSet();
    expect(container.read(activeWorkoutSessionProvider).currentExercise!.draftSeconds, 45);
    for (var i = 1; i < 3; i++) {
      active.setDraftSeconds(50);
      active.logActiveSet();
      active.setDraftSeconds(60);
      active.tick();
      active.addRestSeconds(30);
      active.skipRest();
      expect(container.read(activeWorkoutSessionProvider).currentExercise!.draftSeconds, 60);
    }
    active.setDraftSeconds(50);
    active.addSet();
    current = container.read(activeWorkoutSessionProvider).currentExercise!;
    expect(current.sets.last.unit, SetUnit.seconds);
    expect(current.sets.last.targetSeconds, 50);
    expect(current.sets.last.targetWeightKg, 0);
    active.logActiveSet();
    expect(container.read(activeWorkoutSessionProvider).currentExercise!.sets.map((s) => s.seconds),
        everyElement(50));
    expect(container.read(activeWorkoutSessionProvider).currentExercise!.sets.map((s) => s.weightKg),
        everyElement(0));
    final saver = container.read(activeSessionSaverProvider.notifier);
    expect(await saver.saveCurrentSession(), true);
    expect(await saver.saveCurrentSession(), false);
    final saved = await repo.getSessionById(active.sessionId);
    expect(saved.totalVolumeKg, 208);
    expect(saved.totalDurationMinutes, 0);
    final timed = saved.exerciseLogs.where((s) => s.effectiveUnit == SetUnit.seconds);
    expect(timed, hasLength(4));
    expect(timed.map((s) => s.secondsCompleted), everyElement(50));
    expect(timed.map((s) => s.repsCompleted), everyElement(0));
    expect(timed.map((s) => s.weightKg), everyElement(0));
    expect(timed.map((s) => s.volumeKg), everyElement(0));
  });

  test('Invalid seconds cannot log and rep-based bodyweight defaults remain 20 kg', () {
    final active = ActiveWorkoutSessionNotifier();
    addTearDown(active.dispose);
    active.startSession([curatedExerciseLibrary.singleWhere((e) => e.id == 'plank')]);
    for (final seconds in [null, 0, -1, 1000]) {
      active.setDraftSeconds(seconds);
      active.logActiveSet();
      expect(active.state.completedSetsCount, 0);
      expect(active.state.currentExercise!.draftSeconds, isNull);
      active.pauseWorkout(); active.resumeWorkout();
      expect(active.state.currentExercise!.canLogSet, false);
    }
    for (final seconds in [1, 999]) {
      active.setDraftSeconds(seconds);
      active.logActiveSet();
    }
    expect(active.state.currentExercise!.sets.take(2).map((s) => s.seconds), [1, 999]);
    active.startSession([curatedExerciseLibrary.singleWhere((e) => e.id == 'dead-bug')]);
    expect(active.state.currentExercise!.unit, SetUnit.reps);
    expect(active.state.currentExercise!.draftWeightKg, 20);
    expect(active.state.currentExercise!.draftReps, 20);
    expect(active.state.currentExercise!.draftSeconds, isNull);
  });

  test('Plank Create Plan save/edit/reorder/start retains metadata', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(createPlanNotifierProvider, (_, __) {});
    addTearDown(subscription.close);
    final repo = container.read(exerciseRepositoryProvider);
    final draft = container.read(createPlanNotifierProvider.notifier);
    draft.setName('Timed plan');
    draft.addExercise(await repo.getExerciseById('plank'));
    draft.addExercise(curatedExerciseLibrary.first);
    expect(await draft.savePlan(), true);
    final plan = (await repo.getMyPlans()).single;
    draft.setName('Edited timed plan');
    draft.reorderExercises(0, 2);
    expect(await draft.savePlan(planId: plan.id), true);
    final edited = await repo.getPlanById(plan.id);
    expect(edited.exerciseIds, ['db-bench-press', 'plank']);
    final resolved = await Future.wait(edited.exerciseIds.map(repo.getExerciseById));
    final active = container.read(activeWorkoutSessionProvider.notifier);
    active.startSession(resolved, title: edited.name);
    active.selectExercise(1);
    expect(active.state.currentExercise!.unit, SetUnit.seconds);
    expect(active.state.currentExercise!.draftSeconds, 45);
    expect(active.state.currentExercise!.draftWeightKg, 0);
  });

  test('Exactly ten new unique IDs/slugs; every original field is unchanged',
      () {
    expect(curatedExerciseLibrary, hasLength(27));
    expect(curatedExerciseLibrary.map((e) => e.id),
        [...originalExerciseIds, ...expectedNewExercises.keys]);
    expect(curatedExerciseLibrary.map((e) => e.id).toSet(), hasLength(27));
    expect(curatedExerciseLibrary.map((e) => e.slug).toSet(), hasLength(27));
    // SHA-256 of jsonEncode(toJson()) for the original 17 records, captured
    // before catalog edits on the handed-off HEAD with Flutter 3.22/Dart 3.4.
    final originalJson = jsonEncode(
        curatedExerciseLibrary.take(17).map((e) => e.toJson()).toList());
    expect(sha256.convert(utf8.encode(originalJson)).toString(),
        'c0d91a0c3351a66acec16436a3b985a26a516676d220ca1908eb5b7cb51838dd');
    final legacy = createDefaultUpperBodySession().exercises;
    expect(legacy.map((e) => e.id), ['ex_1', 'ex_2', 'ex_3', 'ex_4', 'ex_5']);
    expect(legacy.map((e) => e.draftWeightKg), [26, 45, 16, 20, 15]);
    expect(legacy.map((e) => e.draftReps), [8, 10, 12, 12, 15]);
    expect(legacy.map((e) => e.sets.length), [4, 4, 3, 3, 4]);
  });

  test('Provider and repository serve the same entire catalog without aliases',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final library = await container.read(exerciseLibraryListProvider.future);
    final repo = container.read(exerciseRepositoryProvider);
    final all = await container
        .read(exercisesByMuscleProvider(muscleGroupSlug: 'all').future);
    expect(library, curatedExerciseLibrary);
    expect(all, library);
    expect(await repo.getPopularExercises(limit: 27), library);
    for (final exercise in library) {
      expect(await repo.getExerciseById(exercise.id), exercise);
    }
    // Legacy IDs remain separate; no alias is inferred from a display name.
    await expectLater(repo.getExerciseById('ex_3'), throwsStateError);
    expect(
        (await repo.getExercisesByMuscleGroup(
          muscleGroupSlug: 'all',
          search: 'bench press',
        ))
            .map((e) => e.id),
        ['db-bench-press']);
    expect(
        (await repo.getExercisesByMuscleGroup(
          muscleGroupSlug: 'back',
          difficulty: 'beginner',
          search: 'LAT',
        ))
            .map((e) => e.id),
        ['lat-pulldown']);
  });

  for (final entry in expectedNewExercises.entries) {
    final id = entry.key;
    final expected = entry.value;
    test('$id has its exact prescription, muscles, cues and approved mapping',
        () {
      final e = curatedExerciseLibrary.singleWhere((e) => e.id == id);
      expect(e.slug, id);
      expect(e.name, expected.$1);
      expect(e.nameVi, expected.$2);
      expect(e.muscleGroup, expected.$3);
      expect(e.equipment, expected.$4);
      expect(e.difficulty, expected.$5);
      expect(e.defaultReps, expected.$6);
      expect(e.restSeconds, expected.$7);
      expect(e.defaultSets, 3);
      expect(e.repType, 'reps');
      expect(e.cvSupported, false);
      expect(e.cvModuleId, isNull);
      expect(e.youtubeVideoId, isNull);
      expect(e.targetMuscles, contains(expected.$3));
      expect(e.secondaryMuscles, isNotEmpty);
      expect(e.cues.length, inInclusiveRange(2, 4));
      expect(e.commonMistakes.length, inInclusiveRange(2, 3));
      expect(e.cues.toSet(), hasLength(e.cues.length));
      expect(e.defaultReps, matches(RegExp(r'^\d+(?:-\d+)?$')));
      expect(e.thumbnailUrl, 'assets/images/exercises/$id-thumb.jpg');
      expect(exercisePosterSource(e.thumbnailUrl),
          'assets/images/exercises/$id-poster.jpg');
    });

    test('$id initializes, logs all sets and saves unchanged reps/ID/slug',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saverListener =
          container.listen(activeSessionSaverProvider, (_, __) {});
      addTearDown(saverListener.close);
      final exercise =
          await container.read(exerciseRepositoryProvider).getExerciseById(id);
      final active = container.read(activeWorkoutSessionProvider.notifier);
      active.startSession([exercise], title: expected.$1);
      final initial =
          container.read(activeWorkoutSessionProvider).exercises.single;
      final reps = int.parse(expected.$6.split('-').first);
      expect(initial.id, id);
      expect(initial.slug, id);
      expect(initial.imageUrl, exercise.thumbnailUrl);
      expect(initial.sets, hasLength(3));
      expect(initial.restSeconds, expected.$7);
      expect(initial.sets.map((s) => s.targetReps), everyElement(reps));
      expect(initial.sets.map((s) => s.targetWeightKg), everyElement(20));
      expect(initial.draftWeightKg, 20);
      final weight = id == 'reverse-lunge' || id == 'dead-bug' ? 0.0 : 20.0;
      for (var set = 0; set < 3; set++) {
        // Existing session targets reset each next set to 20; bodyweight
        // needs this explicit manual adjustment for every logged set.
        active.setDraftWeight(weight);
        active.logActiveSet();
        active.skipRest();
      }
      final saver = container.read(activeSessionSaverProvider.notifier);
      expect(await saver.saveCurrentSession(), true);
      expect(await saver.saveCurrentSession(), false);
      final repo = container.read(exerciseRepositoryProvider);
      final saved = await repo.getSessionById(active.sessionId);
      expect(await repo.getWorkoutHistory(), hasLength(1));
      expect(saved.exerciseLogs, hasLength(3));
      expect(saved.exerciseLogs.map((l) => l.exerciseId), everyElement(id));
      expect(saved.exerciseLogs.map((l) => l.exerciseSlug), everyElement(id));
      expect(
          saved.exerciseLogs.map((l) => l.repsCompleted), everyElement(reps));
      expect(saved.exerciseLogs.map((l) => l.weightKg), everyElement(weight));
      expect(saved.totalVolumeKg, (3 * reps * weight).round());
    });
  }

  test('Total-rep conventions are explicit in Row, Lunge and Dead Bug cues',
      () {
    for (final id in ['one-arm-dumbbell-row', 'reverse-lunge', 'dead-bug']) {
      final cues =
          curatedExerciseLibrary.singleWhere((e) => e.id == id).cues.join(' ');
      expect(cues, contains('10 left + 10 right = 20'));
      if (id == 'one-arm-dumbbell-row') {
        expect(cues, contains('both sides before Log Set'));
        expect(cues, contains('single dumbbell'));
      } else {
        expect(cues, contains('one rep'));
        expect(cues, contains('0 kg before each Log Set'));
      }
    }
  });

  test('Create Plan saves, edits and resolves all ten exact IDs for start',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final listener = container.listen(createPlanNotifierProvider, (_, __) {});
    addTearDown(listener.close);
    final draft = container.read(createPlanNotifierProvider.notifier);
    final repo = container.read(exerciseRepositoryProvider);
    draft.setName('Library round one');
    for (final id in expectedNewExercises.keys) {
      draft.addExercise(await repo.getExerciseById(id));
    }
    expect(await draft.savePlan(), true);
    final plan = (await container.read(myPlansNotifierProvider.future)).single;
    expect(plan.exerciseIds, expectedNewExercises.keys.toList());
    draft.setName('Edited round one');
    draft.reorderExercises(0, 10);
    expect(await draft.savePlan(planId: plan.id), true);
    final edited = await repo.getPlanById(plan.id);
    expect(edited.name, 'Edited round one');
    expect(await repo.getMyPlans(), hasLength(1));
    final expectedIds = [
      ...expectedNewExercises.keys.skip(1),
      expectedNewExercises.keys.first
    ];
    expect(edited.exerciseIds, expectedIds);
    final resolved =
        await Future.wait(edited.exerciseIds.map(repo.getExerciseById));
    container
        .read(activeWorkoutSessionProvider.notifier)
        .startSession(resolved, title: edited.name);
    final started = container.read(activeWorkoutSessionProvider);
    expect(started.title, edited.name);
    expect(started.exercises.map((e) => e.id), expectedIds);
    expect(started.exercises.map((e) => e.slug), expectedIds);
    expect(started.exercises.map((e) => e.imageUrl),
        expectedIds.map((id) => 'assets/images/exercises/$id-thumb.jpg'));
  });
}

import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_detail_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_review_screen.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';

import 'workout_exercise_catalog_test.dart'
    show expectedCategoryIds, allCatalogExercises;
import 'workout_exercise_images_test.dart' show loadImages, loadTestFonts;

void main() {
  setUpAll(loadTestFonts);
  testWidgets('Actual Library filters return exact Upper 30 / Lower 12 / Core 7 IDs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ExerciseLibraryScreen()),
    ));
    await tester.pump();
    await loadImages(tester, curatedExerciseLibrary.map((e) => e.thumbnailUrl));
    for (final entry in expectedCategoryIds.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      final ids = tester.allWidgets
          .map((w) => w.key)
          .whereType<ValueKey<String>>()
          .map((key) => key.value)
          .where((key) => key.startsWith('exercise_row_'))
          .map((key) => key.substring('exercise_row_'.length))
          .toList();
      expect(ids, entry.value, reason: entry.key);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Library searches every new English and accented Vietnamese name',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ExerciseLibraryScreen(initialCategory: 'All')),
    ));
    await tester.pump();
    await loadImages(tester, curatedExerciseLibrary.map((e) => e.thumbnailUrl));
    for (final entry in allCatalogExercises.entries) {
      for (final query in [entry.value.$1, entry.value.$2]) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('exercise_row_${entry.key}')), findsOneWidget,
            reason: query);
        final list = tester.widget<ListView>(find.byType(ListView));
        final expectedCount = (entry.key == 'barbell-bench-press' &&
                query == entry.value.$1)
            ? 3
            : 1;
        expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount,
            expectedCount,
            reason: query);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Library muscle filters retain exact membership including round two',
      (tester) async {
    const expected = <(String, String), List<String>>{
      ('Upper Body', 'Chest'): [
        'db-bench-press',
        'push-up',
        'incline-dumbbell-flyes',
        'incline-dumbbell-press',
        'cable-chest-fly',
        'barbell-bench-press',
        'incline-barbell-bench-press',
        'machine-chest-press',
        'pec-deck-fly',
      ],
      ('Upper Body', 'Back'): [
        'lat-pulldown',
        'seated-cable-row',
        'one-arm-dumbbell-row',
        'pull-up',
        'bent-over-barbell-row',
        'chest-supported-dumbbell-row',
      ],
      ('Upper Body', 'Shoulders'): [
        'db-shoulder-press',
        'face-pulls',
        'dumbbell-lateral-raise',
        'reverse-dumbbell-fly',
        'barbell-overhead-press',
        'cable-lateral-raise',
        'reverse-pec-deck',
      ],
      ('Upper Body', 'Arms'): [
        'db-bicep-curl',
        'triceps-rope-pushdown',
        'overhead-triceps-extension',
        'hammer-curl',
        'ez-bar-curl',
        'lying-ez-bar-triceps-extension',
        'preacher-curl',
        'cable-biceps-curl',
      ],
      ('Lower Body', 'Quads'): [
        'barbell-back-squat',
        'leg-press',
        'goblet-squat',
        'reverse-lunge',
        'bulgarian-split-squat',
        'leg-extension',
      ],
      ('Lower Body', 'Glutes'): [
        'barbell-hip-thrust',
        'bulgarian-split-squat',
        'glute-bridge',
      ],
      ('Lower Body', 'Hamstrings'): [
        'romanian-deadlift',
        'lying-leg-curl',
      ],
      ('Lower Body', 'Calves'): [
        'standing-calf-raise',
        'seated-calf-raise',
      ],
      ('Core', 'Abs'): [
        'plank',
        'hanging-leg-raise',
        'ab-wheel-rollout',
        'dead-bug',
        'reverse-crunch',
      ],
      ('Core', 'Obliques'): [
        'cable-woodchopper',
        'side-plank',
      ],
    };
    await tester.binding.setSurfaceSize(const Size(430, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ExerciseLibraryScreen()),
    ));
    await tester.pump();
    await loadImages(tester, curatedExerciseLibrary.map((e) => e.thumbnailUrl));
    for (final entry in expected.entries) {
      await tester.tap(find.text(entry.key.$1));
      await tester.pumpAndSettle();
      final chip = find.text(entry.key.$2).first;
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final ids = tester.allWidgets.map((w) => w.key)
          .whereType<ValueKey<String>>().map((key) => key.value)
          .where((key) => key.startsWith('exercise_row_'))
          .map((key) => key.substring('exercise_row_'.length));
      expect(ids, entry.value, reason: '${entry.key}');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Flow: Tap Upper Body exercise (Lat Pulldown) opens Detail with matching ID, taxonomy, cues, and mistakes',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'Upper Body'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Upper Body list contains Lat Pulldown
    final latRow = find.byKey(const ValueKey('exercise_row_lat-pulldown'));
    expect(latRow, findsOneWidget);

    // Tap Lat Pulldown row to navigate to Detail
    await tester.tap(latRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final detailScreen = find.byType(ExerciseDetailScreen);
    expect(detailScreen, findsOneWidget);

    // 1. Verify exact exercise.id and title inside Detail Screen
    expect(find.byKey(const ValueKey('exercise_detail_lat-pulldown')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Lat Pulldown')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Kéo xô máy')),
        findsOneWidget);

    // 2. Verify Taxonomy
    expect(find.descendant(of: detailScreen, matching: find.text('PRIMARY')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Back')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('SECONDARY')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Biceps, Rear Deltoid')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('EQUIPMENT')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Cable Machine, Lat Bar')),
        findsOneWidget);

    // 3. Verify Cues
    expect(find.descendant(of: detailScreen, matching: find.text('How to perform')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('3 STEPS')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text('Grip slightly wider than shoulder width')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching:
                find.text('Pull down towards upper chest with elbows leading')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Squeeze lats at the bottom')),
        findsOneWidget);

    // 4. Verify Common Mistakes
    expect(find.descendant(of: detailScreen, matching: find.text('Common mistakes')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Leaning back excessively')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Pulling behind the neck')),
        findsOneWidget);

    // 5. Verify Dumbbell Bench Press content is NOT leaked into Detail Screen
    expect(find.descendant(of: detailScreen, matching: find.text('Dumbbell Bench Press')),
        findsNothing);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find
                .text('A chest exercise using dumbbells and a flat bench.')),
        findsNothing);
    expect(find.descendant(of: detailScreen, matching: find.text('Setup')),
        findsNothing);
    expect(find.descendant(of: detailScreen, matching: find.text('Lower')),
        findsNothing);
    expect(find.descendant(of: detailScreen, matching: find.text('Press')),
        findsNothing);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Keep your feet planted')),
        findsNothing);
  });

  testWidgets(
      'Flow: Tap Lower Body exercise (Barbell Back Squat) opens Detail with matching ID, taxonomy, cues, and mistakes',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'Lower Body'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Lower Body list contains Barbell Back Squat
    final squatRow =
        find.byKey(const ValueKey('exercise_row_barbell-back-squat'));
    expect(squatRow, findsOneWidget);

    // Tap Barbell Back Squat row to navigate to Detail
    await tester.tap(squatRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final detailScreen = find.byType(ExerciseDetailScreen);
    expect(detailScreen, findsOneWidget);

    // 1. Verify exact exercise.id and title inside Detail Screen
    expect(find.byKey(const ValueKey('exercise_detail_barbell-back-squat')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Barbell Back Squat')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Gánh tạ đòn ngang lưng')),
        findsOneWidget);

    // 2. Verify Taxonomy
    expect(find.descendant(of: detailScreen, matching: find.text('PRIMARY')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Quads')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('SECONDARY')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Glutes, Hamstrings, Core')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('EQUIPMENT')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Barbell, Squat Rack')),
        findsOneWidget);

    // 3. Verify Cues
    expect(find.descendant(of: detailScreen, matching: find.text('How to perform')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('4 STEPS')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text(
                'Rest barbell securely across upper traps with chest proud')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text(
                'Hinge hips back and bend knees tracking in line with toes')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text(
                'Descend until thighs are at least parallel to the floor')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text(
                'Drive through midfoot and heels to return upright')),
        findsOneWidget);

    // 4. Verify Common Mistakes
    expect(find.descendant(of: detailScreen, matching: find.text('Common mistakes')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text('Knees caving inward during ascent')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Heels lifting off the floor')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text('Rounding the lower back in the hole')),
        findsOneWidget);

    // 5. Verify Dumbbell Bench Press content is NOT leaked
    expect(find.descendant(of: detailScreen, matching: find.text('Dumbbell Bench Press')),
        findsNothing);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Keep your feet planted')),
        findsNothing);
  });

  testWidgets(
      'Flow: Tap Core exercise (Plank) opens Detail with matching ID, taxonomy, cues, and mistakes',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'Core'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Core list contains Plank
    final plankRow = find.byKey(const ValueKey('exercise_row_plank'));
    expect(plankRow, findsOneWidget);

    // Tap Plank row to navigate to Detail
    await tester.tap(plankRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final detailScreen = find.byType(ExerciseDetailScreen);
    expect(detailScreen, findsOneWidget);

    // 1. Verify exact exercise.id and title inside Detail Screen
    expect(find.byKey(const ValueKey('exercise_detail_plank')), findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Plank')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Giữ tư thế plank chống khuỷu')),
        findsOneWidget);

    // 2. Verify Taxonomy
    expect(find.descendant(of: detailScreen, matching: find.text('PRIMARY')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Abs')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('SECONDARY')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Shoulders, Glutes')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('EQUIPMENT')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Bodyweight')),
        findsOneWidget);

    // 3. Verify Cues
    expect(find.descendant(of: detailScreen, matching: find.text('How to perform')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('3 STEPS')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text(
                'Place forearms on floor with elbows directly under shoulders')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching:
                find.text('Maintain rigid straight line from head to heels')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text('Brace abdominal wall and squeeze glutes firmly')),
        findsOneWidget);

    // 4. Verify Common Mistakes
    expect(find.descendant(of: detailScreen, matching: find.text('Common mistakes')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Sagging hips towards floor')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text('Piking hips upward to relieve abdominal tension')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detailScreen,
            matching: find.text('Holding breath instead of breathing rhythmically')),
        findsOneWidget);

    // 5. Verify Dumbbell Bench Press content is NOT leaked
    expect(find.descendant(of: detailScreen, matching: find.text('Dumbbell Bench Press')),
        findsNothing);
    expect(
        find.descendant(
            of: detailScreen, matching: find.text('Keep your feet planted')),
        findsNothing);
  });

  testWidgets(
      'Flow: Filter and Search state are preserved when returning from Detail via Back button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'All'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Switch to Lower Body
    await tester.tap(find.text('Lower Body'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 2. Select Quads subfilter
    await tester.tap(find.text('Quads'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Quads movements: Barbell Back Squat & Leg Press
    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Leg Press'), findsOneWidget);
    expect(find.text('Romanian Deadlift'), findsNothing);

    // 3. Enter Search Query "press"
    await tester.enterText(find.byType(TextField), 'press');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Only "Leg Press" matches Lower Body + Quads + "press"
    expect(find.text('Leg Press'), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsNothing);

    // 4. Tap Leg Press to navigate to Detail
    await tester.tap(find.byKey(const ValueKey('exercise_row_leg-press')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final detailScreen = find.byType(ExerciseDetailScreen);
    expect(detailScreen, findsOneWidget);
    expect(find.byKey(const ValueKey('exercise_detail_leg-press')),
        findsOneWidget);
    expect(find.descendant(of: detailScreen, matching: find.text('Leg Press')),
        findsOneWidget);

    // 5. Tap Back affordance (< Exercise Library)
    final backBtn = find.byKey(const ValueKey('exercise_detail_back_button'));
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // 6. Verify returned to Exercise Library with all filter/search state preserved
    expect(find.byType(ExerciseDetailScreen), findsNothing);
    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'press'), findsOneWidget);
    expect(find.text('Leg Press'), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsNothing);
    expect(find.text('Dumbbell Bench Press'), findsNothing);
  });

  testWidgets('CTA: Bookmark button shows honest non-persisted feedback',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseLibraryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final bookmarkBtn =
        find.byKey(const ValueKey('exercise_library_bookmark_button'));
    expect(bookmarkBtn, findsOneWidget);

    await tester.tap(bookmarkBtn);
    await tester.pump();

    // Verify honest message (does not pretend bookmark was saved)
    expect(
        find.text(
            'Bookmark feature is in development (no exercises are bookmarked yet).'),
        findsOneWidget);
  });

  testWidgets(
      'CTA: Detail Start Exercise starts only the selected exercise; Video preview shows honest status',
      (WidgetTester tester) async {
    final squatExercise = curatedExerciseLibrary
        .firstWhere((e) => e.id == 'barbell-back-squat');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExerciseDetailScreen(exercise: squatExercise),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Video preview tap shows honest status
    final videoPreview =
        find.byKey(const ValueKey('exercise_detail_video_preview'));
    expect(videoPreview, findsOneWidget);

    await tester.tap(videoPreview);
    await tester.pump();

    expect(
        find.text(
            'Video guide for "Barbell Back Squat" is currently in production and not yet available.'),
        findsOneWidget);

    final startBtn = find.byKey(const ValueKey('exercise_detail_start_button'));
    await tester.tap(startBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveWorkoutScreen)),
    );
    final session = container.read(activeWorkoutSessionProvider);
    expect(session.exercises.single.id, squatExercise.id);
    expect(session.exercises.single.sets.length, squatExercise.defaultSets);
    expect(session.completedSetsCount, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Full Route Stack: Workout Home -> Library -> filter/search -> Detail -> Back returns to Library with filters intact -> Back returns to Workout Home',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: WorkoutHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Initial State: on WorkoutHomeScreen
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Browse library'), findsOneWidget);
    expect(find.byType(ExerciseLibraryScreen), findsNothing);
    expect(find.byType(ExerciseDetailScreen), findsNothing);

    // 2. Tap "Browse library" to push ExerciseLibraryScreen (Route 1)
    await tester.tap(find.text('Browse library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    expect(find.text('Exercise Library'), findsOneWidget);

    // 3. Apply category filter: Lower Body
    final lowerBodyTab = find.descendant(
      of: find.byType(ExerciseLibraryScreen),
      matching: find.text('Lower Body'),
    );
    await tester.tap(lowerBodyTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 4. Apply subfilter chip: Quads
    final quadsChip = find.descendant(
      of: find.byType(ExerciseLibraryScreen),
      matching: find.text('Quads'),
    );
    await tester.tap(quadsChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 5. Apply search: "press"
    await tester.enterText(
        find.descendant(
          of: find.byType(ExerciseLibraryScreen),
          matching: find.byType(TextField),
        ),
        'press');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Leg Press'), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsNothing);

    // 6. Tap "Leg Press" to push ExerciseDetailScreen (Route 2)
    final legPressRow = find.byKey(const ValueKey('exercise_row_leg-press'));
    expect(legPressRow, findsOneWidget);
    await tester.tap(legPressRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify on ExerciseDetailScreen
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('exercise_detail_leg-press')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ExerciseDetailScreen),
            matching: find.text('Leg Press')),
        findsOneWidget);

    // 7. Action: Tap Back in ExerciseDetailScreen (< Exercise Library)
    final detailBackBtn =
        find.byKey(const ValueKey('exercise_detail_back_button'));
    expect(detailBackBtn, findsOneWidget);
    await tester.tap(detailBackBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // 8. Verification: Pops Route 2 -> returns to ExerciseLibraryScreen (Route 1)
    expect(find.byType(ExerciseDetailScreen), findsNothing);
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    // Verify filter & search state is preserved
    expect(find.widgetWithText(TextField, 'press'), findsOneWidget);
    expect(find.text('Leg Press'), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsNothing);
    expect(find.text('Dumbbell Bench Press'), findsNothing);

    // 9. Action: Tap Back in ExerciseLibraryScreen (AppBar leading chevron)
    final libraryBackBtn = find.descendant(
      of: find.byType(ExerciseLibraryScreen),
      matching: find.byIcon(Icons.chevron_left),
    );
    expect(libraryBackBtn, findsOneWidget);
    await tester.tap(libraryBackBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // 10. Verification: Pops Route 1 -> returns to WorkoutHomeScreen (Route 0)
    expect(find.byType(ExerciseDetailScreen), findsNothing);
    expect(find.byType(ExerciseLibraryScreen), findsNothing);
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
    expect(find.text('TODAY’S SCHEDULED SESSION'), findsOneWidget);
  });

  testWidgets(
      'Full Route Stack: Browser/System Back pops Detail to Library, then Library to Workout Home',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: WorkoutHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. From Workout Home, navigate to Library
    await tester.tap(find.text('Browse library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);

    // 2. Select filter
    final upperBodyTab = find.descendant(
      of: find.byType(ExerciseLibraryScreen),
      matching: find.text('Upper Body'),
    );
    await tester.tap(upperBodyTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 3. Navigate to Detail
    await tester.tap(find.byKey(const ValueKey('exercise_row_lat-pulldown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);

    // 4. Simulate Browser Back / System Back on Detail screen
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // 5. Must land on Library, not Workout Home; filter preserved
    expect(find.byType(ExerciseDetailScreen), findsNothing);
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsOneWidget);

    // 6. Simulate Browser Back / System Back on Library screen
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // 7. Must land on Workout Home
    expect(find.byType(ExerciseLibraryScreen), findsNothing);
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
  });

  testWidgets(
      'Full Route Stack: In Library, tapping bottom navigation bar Workout tab pops back to Workout Home',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: WorkoutHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Navigate to Library
    await tester.tap(find.text('Browse library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);

    // 2. In Library bottom bar, tap Workout tab (index 1)
    final bottomNavWorkout = find.descendant(
      of: find.byType(ExerciseLibraryScreen),
      matching: find.text('Workout'),
    );
    expect(bottomNavWorkout, findsOneWidget);
    await tester.tap(bottomNavWorkout);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // 3. Must pop Library and land on Workout Home
    expect(find.byType(ExerciseLibraryScreen), findsNothing);
    expect(find.byType(WorkoutHomeScreen), findsOneWidget);
  });

  for (final exId in [
    'chest-supported-dumbbell-row',
    'lying-ez-bar-triceps-extension',
    'preacher-curl',
    'pec-deck-fly',
    'reverse-pec-deck',
    'cable-biceps-curl',
  ]) {
    testWidgets(
        'Flow: $exId Detail -> Active -> Log Set -> Review displays correct identity, poster and volume',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final exercise = curatedExerciseLibrary.firstWhere((e) => e.id == exId);
      final posterSource = exercisePosterSource(exercise.thumbnailUrl);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ExerciseDetailScreen(exercise: exercise),
          ),
        ),
      );
      await tester.pump();
      await loadImages(tester, [exercise.thumbnailUrl, posterSource]);

      // 1. Verify Detail Screen identity & poster
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(find.text(exercise.name), findsOneWidget);
      expect(find.text(exercise.nameVi), findsOneWidget);
      expect(find.byKey(ValueKey(posterSource)), findsOneWidget);

      // 2. Tap Start Exercise -> Navigate to ActiveWorkoutScreen
      final startBtn = find.byKey(const ValueKey('exercise_detail_start_button'));
      await tester.ensureVisible(startBtn);
      await tester.tap(startBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(find.text(exercise.name), findsWidgets);
      expect(find.byKey(ValueKey(posterSource)), findsWidgets);

      // 3. Verify draft weight starts at 20.0 kg fallback
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActiveWorkoutScreen)),
      );
      final session = container.read(activeWorkoutSessionProvider);
      expect(session.currentExercise?.draftWeightKg, 20.0);

      // 4. Log Set 1
      final logBtn = find.byKey(const ValueKey('active_workout_log_set_button'));
      await tester.ensureVisible(logBtn);
      await tester.tap(logBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 1);

      // 5. Tap Finish -> Navigate to WorkoutReviewScreen
      final finishBtn = find.byKey(const ValueKey('active_workout_finish_button'));
      await tester.ensureVisible(finishBtn);
      await tester.tap(finishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(WorkoutReviewScreen), findsOneWidget);

      // 6. Verify single-exercise Review banner uses exercise's own poster,
      // and Movement Breakdown shows exercise thumbnail
      expect(find.byKey(ValueKey(posterSource)), findsOneWidget);
      expect(find.byKey(ValueKey(exercise.thumbnailUrl)), findsOneWidget);
      expect(find.text(exercise.name), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'Mixed-session: CP07 exercise + another exercise in Review uses fallback/banner, not single-exercise poster',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ex1 = curatedExerciseLibrary.firstWhere((e) => e.id == 'pec-deck-fly');
    final ex2 = curatedExerciseLibrary.firstWhere((e) => e.id == 'lat-pulldown');
    final ex1Poster = exercisePosterSource(ex1.thumbnailUrl);
    final ex2Poster = exercisePosterSource(ex2.thumbnailUrl);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ActiveWorkoutScreen.fromExercises(
            exercises: [ex1, ex2],
            title: 'Upper Body Mixed Workout',
          ),
        ),
      ),
    );
    await tester.pump();
    await loadImages(tester, [
      ex1.thumbnailUrl,
      ex1Poster,
      ex2.thumbnailUrl,
      ex2Poster,
    ]);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveWorkoutScreen)),
    );

    // 1. Log Set 1 for Exercise 1 (Machine Chest Press)
    final logBtn = find.byKey(const ValueKey('active_workout_log_set_button'));
    await tester.ensureVisible(logBtn);
    await tester.tap(logBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 1);

    // 2. Advance to Exercise 2 (Lat Pulldown) and log Set 1
    final nextBtn = find.text('Next exercise');
    if (nextBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      container.read(activeWorkoutSessionProvider.notifier).selectExercise(1);
      await tester.pump();
    }

    await tester.ensureVisible(logBtn);
    await tester.tap(logBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(activeWorkoutSessionProvider).completedSetsCount, 2);

    // 3. Finish workout -> Navigate to WorkoutReviewScreen
    final finishBtn = find.byKey(const ValueKey('active_workout_finish_button'));
    await tester.ensureVisible(finishBtn);
    await tester.tap(finishBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(WorkoutReviewScreen), findsOneWidget);

    // 4. Verify Review banner does NOT use poster of exercise 1 nor exercise 2
    expect(find.byKey(ValueKey(ex1Poster)), findsNothing,
        reason: 'Mixed session must not take CP07 exercise poster as whole-session banner');
    expect(find.byKey(ValueKey(ex2Poster)), findsNothing,
        reason: 'Mixed session must not take second exercise poster as whole-session banner');

    // 5. Verify both exercises appear in Movement Breakdown
    expect(find.text(ex1.name), findsOneWidget);
    expect(find.text(ex2.name), findsOneWidget);
    expect(find.text('2 sets logged • 2 exercises'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

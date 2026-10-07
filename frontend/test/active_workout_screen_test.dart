import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';

void main() {
  group('Active Workout Screen & Provider Checkpoint Tests', () {
    testWidgets(
        '1. Initial rendering displays clean session (elapsed 00:00, 0 sets completed, no rest countdown, Set 1 active)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveWorkoutScreen(autoTick: false),
          ),
        ),
      );
      await tester.pump();

      // Top bar & live timer starting at 00:00
      expect(find.text('Upper Body Strength'), findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_timer_text')),
          findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_finish_button')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_minimize_button')),
          findsOneWidget);

      // Horizon progress: 0 of 4 sets completed
      expect(find.text('Exercise 1 of 5'), findsOneWidget);
      expect(find.text('0 of 4 sets completed'), findsOneWidget);

      // Current Exercise anchor
      expect(find.text('Dumbbell Bench Press'), findsOneWidget);
      expect(find.text('Dumbbells · Flat bench'), findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_video_guide_button')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_form_check_badge')),
          findsOneWidget);

      // REST timer is NOT active initially
      expect(find.text('REST'), findsNothing);
      expect(find.byKey(const ValueKey('active_workout_rest_timer_text')),
          findsNothing);
      expect(find.byKey(const ValueKey('active_workout_rest_add_30s')),
          findsNothing);
      expect(find.byKey(const ValueKey('active_workout_rest_skip')),
          findsNothing);

      // Set matrix: Table headers, Set 1 is ACTIVE, Sets 2-4 upcoming
      expect(find.text('SET'), findsOneWidget);
      expect(find.text('KG'), findsOneWidget);
      expect(find.text('REPS'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('SET 1 (ACTIVE)'), findsOneWidget);
      expect(find.text('TARGET: 26 KG × 8'), findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_weight_minus')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_weight_plus')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_reps_minus')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_reps_plus')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_add_set_button')),
          findsOneWidget);

      // Up Next Preview
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('Lat Pulldown (Wide Grip)'), findsOneWidget);

      // Grounded dock: Log Set 1
      expect(find.byKey(const ValueKey('active_workout_log_set_button')),
          findsOneWidget);
      expect(find.text('Log Set 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('active_workout_pause_button')),
          findsOneWidget);
      expect(find.text('Pause workout'), findsOneWidget);

      // Verification: Global bottom nav is strictly hidden
      expect(find.byType(SamanBottomNavigationBar), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '2. Full sequence: edit draft -> Log Set 1 -> REST starts -> Skip/+30s -> Set 2 active',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveWorkoutScreen(autoTick: false),
          ),
        ),
      );
      await tester.pump();

      // Verify initial state for Set 1
      expect(find.text('Log Set 1'), findsOneWidget);
      expect(find.text('0 of 4 sets completed'), findsOneWidget);
      expect(find.text('REST'), findsNothing);

      // Step 1: Chỉnh draft (edit draft values)
      // Tap + on weight stepper: 26 -> 27 kg
      await tester.tap(find.byKey(const ValueKey('active_workout_weight_plus')));
      await tester.pump();

      // Tap - on reps stepper: 8 -> 7 reps
      await tester.tap(find.byKey(const ValueKey('active_workout_reps_minus')));
      await tester.pump();

      final sessionAfterEdit = container.read(activeWorkoutSessionProvider);
      final currentEx = sessionAfterEdit.currentExercise!;
      expect(currentEx.draftWeightKg, 27.0);
      expect(currentEx.draftReps, 7);
      // Contract check: Still 0 sets completed, Set 1 still active, still no REST
      expect(currentEx.completedSetsCount, 0);
      expect(currentEx.activeSet?.setNumber, 1);
      expect(sessionAfterEdit.isResting, false);

      // Step 2: Bấm Log Set 1
      await tester.tap(find.byKey(const ValueKey('active_workout_log_set_button')));
      await tester.pump();

      // Set 1 is completed with 27 kg x 7 reps!
      final sessionAfterLog1 = container.read(activeWorkoutSessionProvider);
      final currentExAfterLog1 = sessionAfterLog1.currentExercise!;
      expect(currentExAfterLog1.completedSetsCount, 1);
      expect(currentExAfterLog1.sets[0].isCompleted, true);
      expect(currentExAfterLog1.sets[0].weightKg, 27.0);
      expect(currentExAfterLog1.sets[0].reps, 7);

      // Set 2 is now active
      expect(currentExAfterLog1.activeSet?.setNumber, 2);

      // Step 3: REST timer starts only after Log Set 1
      expect(sessionAfterLog1.isResting, true);
      expect(sessionAfterLog1.restSecondsLeft, 90);
      expect(find.text('REST'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('1 of 4 sets completed'), findsOneWidget);

      // Step 4: Test REST controls (+30s and Skip)
      // Tap +30s -> 90 + 30 = 120s (02:00)
      await tester.tap(find.byKey(const ValueKey('active_workout_rest_add_30s')));
      await tester.pump();

      expect(find.text('02:00'), findsOneWidget);
      expect(container.read(activeWorkoutSessionProvider).restSecondsLeft, 120);

      // Tap Skip -> rest ends immediately
      await tester.tap(find.byKey(const ValueKey('active_workout_rest_skip')));
      await tester.pump();

      final sessionAfterSkip = container.read(activeWorkoutSessionProvider);
      expect(sessionAfterSkip.isResting, false);
      expect(sessionAfterSkip.restSecondsLeft, 0);
      expect(find.text('REST'), findsNothing);

      // Step 5: Set 2 is active in UI and dock shows Log Set 2
      expect(find.text('SET 2 (ACTIVE)'), findsOneWidget);
      expect(find.text('Log Set 2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '3. Chronometer starts at 00:00; Pause stops chronometer; Resume continues time progression',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveWorkoutScreen(autoTick: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Pause workout'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);

      // Advance chronometer by 5 seconds
      for (int i = 0; i < 5; i++) {
        container.read(activeWorkoutSessionProvider.notifier).tick();
      }
      await tester.pump();
      expect(find.text('00:05'), findsOneWidget);

      // Tap Pause workout
      await tester.tap(find.byKey(const ValueKey('active_workout_pause_button')));
      await tester.pump();

      expect(container.read(activeWorkoutSessionProvider).isPaused, true);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Resume workout'), findsOneWidget);

      // Trigger tick while paused: elapsed should NOT advance
      container.read(activeWorkoutSessionProvider.notifier).tick();
      await tester.pump();
      expect(container.read(activeWorkoutSessionProvider).elapsedSeconds, 5);

      // Tap Resume workout
      await tester.tap(find.byKey(const ValueKey('active_workout_resume_button')));
      await tester.pump();

      expect(container.read(activeWorkoutSessionProvider).isPaused, false);
      expect(find.text('Pause workout'), findsOneWidget);

      // Trigger tick: elapsed advances
      container.read(activeWorkoutSessionProvider.notifier).tick();
      await tester.pump();
      expect(container.read(activeWorkoutSessionProvider).elapsedSeconds, 6);
      expect(find.text('00:06'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '4. Minimize / Back button preserves ongoing workout state across re-entry without resetting',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const ActiveWorkoutScreen(autoTick: false),
                      ),
                    ),
                    child: const Text('Start workout'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Start workout" to enter ActiveWorkoutScreen
      expect(find.text('Start workout'), findsOneWidget);
      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();

      // Now inside ActiveWorkoutScreen: starts at 00:00, Set 1 active
      expect(find.text('Upper Body Strength'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Log Set 1'), findsOneWidget);

      // Edit draft weight to 30 kg
      container
          .read(activeWorkoutSessionProvider.notifier)
          .setDraftWeight(30.0);
      await tester.pump();

      // Tap Log Set 1
      await tester.tap(find.byKey(const ValueKey('active_workout_log_set_button')));
      await tester.pump();

      // Set 1 logged, Set 2 active
      expect(find.text('Log Set 2'), findsOneWidget);
      expect(find.text('1 of 4 sets completed'), findsOneWidget);

      // Advance timer by 15 seconds
      for (int i = 0; i < 15; i++) {
        container.read(activeWorkoutSessionProvider.notifier).tick();
      }
      await tester.pump();

      // Minimize the session by tapping the discreet top-left down chevron
      await tester.tap(find.byKey(const ValueKey('active_workout_minimize_button')));
      await tester.pumpAndSettle();

      // Back on host screen!
      expect(find.text('Start workout'), findsOneWidget);

      // Re-enter the workout via "Start workout"
      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();

      // CRITICAL VERIFICATION: State is preserved! Does not create new or reset!
      // Set 1 is completed with 30 kg, Set 2 is active, elapsed time >= 15s
      expect(find.text('Log Set 2'), findsOneWidget);
      expect(find.text('1 of 4 sets completed'), findsOneWidget);
      final session = container.read(activeWorkoutSessionProvider);
      expect(session.elapsedSeconds >= 15, true);
      final currentEx = session.currentExercise!;
      expect(currentEx.sets[0].isCompleted, true);
      expect(currentEx.sets[0].weightKg, 30.0);
      expect(currentEx.sets[1].isActive, true);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '5. Finish button opens honest Review & Save modal without committing to History or backend',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveWorkoutScreen(autoTick: false),
          ),
        ),
      );
      await tester.pump();

      // Tap Finish button
      await tester.tap(find.byKey(const ValueKey('active_workout_finish_button')));
      await tester.pumpAndSettle();

      // Honest modal is shown
      expect(find.text('Workout Review & Save'), findsOneWidget);
      expect(find.text('Save Session'), findsOneWidget);
      expect(find.text('In Development'), findsNothing);
      expect(find.text('Keep Training'), findsOneWidget);

      // Verifies no history was created
      final session = container.read(activeWorkoutSessionProvider);
      expect(session.isFinished, false);

      // Dismiss modal
      await tester.tap(find.byKey(const ValueKey('active_workout_review_understood_button')));
      await tester.pumpAndSettle();

      expect(find.text('Upper Body Strength'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '6. Video Guide and Check Form display honest un-faked status sheets',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActiveWorkoutScreen(autoTick: false),
          ),
        ),
      );
      await tester.pump();

      // Tap Video Guide badge
      await tester.tap(find.byKey(const ValueKey('active_workout_video_guide_button')));
      await tester.pumpAndSettle();

      // Honest guidance modal
      expect(find.text('Dumbbell Bench Press — Video Guide'), findsOneWidget);
      expect(find.text('Video Demo in Preparation · Verified Form Cues Active'),
          findsOneWidget);
      expect(find.text('Keep your feet firmly planted on the floor'),
          findsOneWidget);

      // Dismiss
      await tester.tap(find.byKey(const ValueKey('active_workout_video_guide_close_button')));
      await tester.pumpAndSettle();

      // Tap Check form badge
      await tester.tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();

      // Honest CV modal
      expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
      expect(
          find.text(
              'Computer Vision Form Check is planned for a future release (deferred checkpoint). No camera feed has been activated and no reps will be auto-logged.'),
          findsOneWidget);

      // Dismiss
      await tester.tap(find.byKey(const ValueKey('active_workout_form_check_close_button')));
      await tester.pumpAndSettle();

      expect(find.text('Upper Body Strength'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

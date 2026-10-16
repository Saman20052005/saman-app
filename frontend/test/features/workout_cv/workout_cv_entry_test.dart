import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_native_source.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';

class FakeWorkoutCvNativeSource implements WorkoutCvNativeSource {
  @override
  Future<String> checkPermission() async => 'granted';
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> startSession(String exerciseSlug) async => true;
  @override
  Future<bool> stopSession() async => true;
  @override
  Stream<Map<String, dynamic>> get eventStream => const Stream.empty();
}

Exercise _createPullUpExercise() {
  return const Exercise(
    id: 'pull-up',
    slug: 'pull-up',
    name: 'Pull-up',
    nameVi: 'Hít xà đơn',
    muscleGroup: 'Back',
    targetMuscles: ['Back', 'Lats'],
    secondaryMuscles: ['Biceps'],
    equipment: ['Pull-up Bar'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-10',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: ['Pull chin over bar'],
    commonMistakes: ['Kipping'],
  );
}

Exercise _createBenchPressExercise() {
  return const Exercise(
    id: 'dumbbell-bench-press',
    slug: 'dumbbell-bench-press',
    name: 'Dumbbell Bench Press',
    nameVi: 'Đẩy ngực tạ đơn',
    muscleGroup: 'Chest',
    targetMuscles: ['Chest'],
    secondaryMuscles: ['Triceps'],
    equipment: ['Dumbbells'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-10',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: ['Retract scapula'],
    commonMistakes: ['Bouncing weights'],
  );
}

void main() {
  group('Active Workout Form Check Entry and State Preservation Tests', () {
    testWidgets('1. Non-supported exercise (Bench Press) retains Deferred modal on tap',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final benchEx = _createBenchPressExercise();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ActiveWorkoutScreen(
              exercises: [benchEx],
              autoTick: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap form check badge
      final formCheckBadge = find.byKey(const ValueKey('active_workout_form_check_badge'));
      expect(formCheckBadge, findsOneWidget);
      await tester.tap(formCheckBadge);
      await tester.pumpAndSettle();

      // Expect honest deferred modal
      expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
      expect(find.byType(WorkoutCvScreen), findsNothing);

      // Close modal
      final closeButton = find.byKey(const ValueKey('active_workout_form_check_close_button'));
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.text('Live Form Check (Deferred)'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '2. Pull-up exercise on Android opens WorkoutCvScreen, pauses workout, and preserves draft inputs and sets',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pullUpEx = _createPullUpExercise();
      final fakeSource = FakeWorkoutCvNativeSource();

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvNativeSourceProvider.overrideWithValue(fakeSource),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return MaterialApp(
                home: ActiveWorkoutScreen(
                  exercises: [pullUpEx],
                  autoTick: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial state
      final initialSession = capturedRef.read(activeWorkoutSessionProvider);
      expect(initialSession.isPaused, isFalse);
      expect(initialSession.completedSetsCount, 0);
      final initialDraftReps = initialSession.currentExercise!.draftReps;
      final initialDraftWeight = initialSession.currentExercise!.draftWeightKg;

      // Tap form check badge
      final formCheckBadge = find.byKey(const ValueKey('active_workout_form_check_badge'));
      expect(formCheckBadge, findsOneWidget);
      await tester.tap(formCheckBadge);
      await tester.pumpAndSettle();

      // Verified WorkoutCvScreen is opened
      expect(find.byType(WorkoutCvScreen), findsOneWidget);
      expect(find.text('Pull-up'), findsOneWidget);

      // Verify timer was paused while in CV
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      // Tap close button on WorkoutCvScreen
      final cvCloseButton = find.byKey(const ValueKey('workout_cv_close_button'));
      expect(cvCloseButton, findsOneWidget);
      await tester.tap(cvCloseButton);
      await tester.pumpAndSettle();

      // Returned to ActiveWorkoutScreen
      expect(find.byType(WorkoutCvScreen), findsNothing);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);

      // Verify timer resumed because it was active prior to opening
      final restoredSession = capturedRef.read(activeWorkoutSessionProvider);
      expect(restoredSession.isPaused, isFalse);

      // Verify draft inputs and completed sets are 100% intact
      expect(restoredSession.currentExercise!.draftReps, initialDraftReps);
      expect(restoredSession.currentExercise!.draftWeightKg, initialDraftWeight);
      expect(restoredSession.completedSetsCount, 0);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '3. When workout was already paused prior to opening CV, it remains paused upon closing',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pullUpEx = _createPullUpExercise();
      final fakeSource = FakeWorkoutCvNativeSource();

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvNativeSourceProvider.overrideWithValue(fakeSource),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return MaterialApp(
                home: ActiveWorkoutScreen(
                  exercises: [pullUpEx],
                  autoTick: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pause the workout explicitly beforehand
      capturedRef.read(activeWorkoutSessionProvider.notifier).pauseWorkout();
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      // Open CV
      await tester.tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCvScreen), findsOneWidget);

      // Close CV
      await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
      await tester.pumpAndSettle();

      // Verify it REMAINS paused
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}

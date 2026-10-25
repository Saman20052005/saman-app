import 'dart:async';
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
  Future<bool> acknowledgeReplayFrame(int sessionGen, int videoPtsMs, String phase) async => true;

  String permissionStatus = 'granted';
  bool requestPermissionResult = true;
  bool startSessionResult = true;
  bool startSessionCalled = false;
  bool stopSessionCalled = false;

  @override
  Future<String> checkPermission() async => permissionStatus;

  @override
  Future<bool> requestPermission() async => requestPermissionResult;

  @override
  Future<bool> startSession(String exerciseSlug) async {
    startSessionCalled = true;
    return startSessionResult;
  }

  @override
  Future<bool> startVideoReplay(String videoPath) async => false;

  @override
  Future<bool> switchSource(String mode, {String? videoPath}) async => false;

  @override
  Future<bool> restartVideoReplay() async => false;

  @override
  Future<bool> stopSession() async {
    stopSessionCalled = true;
    return true;
  }

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

Exercise _createLatPulldownExercise() {
  return const Exercise(
    id: 'lat-pulldown',
    slug: 'lat-pulldown',
    name: 'Lat Pulldown',
    nameVi: 'Kéo xô',
    muscleGroup: 'Back',
    targetMuscles: ['Back', 'Lats'],
    secondaryMuscles: ['Biceps'],
    equipment: ['Cable Machine'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: ['Pull bar to upper chest'],
    commonMistakes: ['Leaning too far back'],
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

Exercise _createSpoofedDisplayNameExercise() {
  return const Exercise(
    id: 'ex_1',
    slug: 'seated-cable-row',
    name: 'Pull-up',
    nameVi: 'Ngồi kéo cáp',
    muscleGroup: 'Back',
    targetMuscles: ['Back'],
    secondaryMuscles: ['Biceps'],
    equipment: ['Cable Machine'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-10',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: true,
    cues: ['Keep torso upright'],
    commonMistakes: ['Rounding back'],
  );
}

void main() {
  group('Active Workout Form Check Entry and State Preservation Tests', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '1. Non-supported exercise (Bench Press) retains Deferred modal on tap',
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
      final formCheckBadge =
          find.byKey(const ValueKey('active_workout_form_check_badge'));
      expect(formCheckBadge, findsOneWidget);
      await tester.tap(formCheckBadge);
      await tester.pumpAndSettle();

      // Expect honest deferred modal
      expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
      expect(find.byType(WorkoutCvScreen), findsNothing);

      // Close modal
      final closeButton =
          find.byKey(const ValueKey('active_workout_form_check_close_button'));
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
      final formCheckBadge =
          find.byKey(const ValueKey('active_workout_form_check_badge'));
      expect(formCheckBadge, findsOneWidget);
      await tester.tap(formCheckBadge);
      await tester.pumpAndSettle();

      // Verified WorkoutCvScreen is opened
      expect(find.byType(WorkoutCvScreen), findsOneWidget);
      expect(find.text('Pull-up'), findsOneWidget);

      // Verify timer was paused while in CV
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      // Tap close button on WorkoutCvScreen
      final cvCloseButton =
          find.byKey(const ValueKey('workout_cv_close_button'));
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
      expect(
          restoredSession.currentExercise!.draftWeightKg, initialDraftWeight);
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
      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCvScreen), findsOneWidget);

      // Close CV
      await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
      await tester.pumpAndSettle();

      // Verify it REMAINS paused
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '4. Supported exercise on non-Android platform (iOS) retains Deferred modal and does not open CV',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
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

      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();

      expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
      expect(find.byType(WorkoutCvScreen), findsNothing);
      expect(fakeSource.startSessionCalled, isFalse);
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isFalse);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '5. Lat Pulldown opens CV on Android whereas spoofed display name with unsupported ID/slug retains Deferred modal',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final latPulldownEx = _createLatPulldownExercise();
      final spoofedEx = _createSpoofedDisplayNameExercise();
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
                  exercises: [latPulldownEx, spoofedEx],
                  autoTick: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exercise 1: lat-pulldown opens WorkoutCvScreen
      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCvScreen), findsOneWidget);
      expect(find.text('Lat Pulldown'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCvScreen), findsNothing);

      // Switch to Exercise 2: display name is 'Pull-up' and cvSupported is true, but id='ex_1' and slug='seated-cable-row'
      capturedRef.read(activeWorkoutSessionProvider.notifier).nextExercise();
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();
      expect(find.text('Live Form Check (Deferred)'), findsOneWidget);
      expect(find.byType(WorkoutCvScreen), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '6. Session changed or finished while CV is open does not resume timer on pop',
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

      // Case A: Session changes (new session started) and is paused while CV is open
      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCvScreen), findsOneWidget);

      final notifier = capturedRef.read(activeWorkoutSessionProvider.notifier);
      notifier.startSession([pullUpEx], title: 'New Session');
      notifier.pauseWorkout();
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
      await tester.pumpAndSettle();

      // Must NOT resume because sessionId changed while CV was open
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      // Case B: Session is active, opens CV, then session is marked saved/finished while CV is open
      notifier.resumeWorkout();
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isFalse);

      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCvScreen), findsOneWidget);

      notifier.markSaved();
      expect(capturedRef.read(activeWorkoutSessionProvider).isFinished, isTrue);
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      await tester.tap(find.byKey(const ValueKey('workout_cv_close_button')));
      await tester.pumpAndSettle();

      // Must remain paused because session was finished
      expect(capturedRef.read(activeWorkoutSessionProvider).isPaused, isTrue);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '7. Permission denial and channel failure inside WorkoutCvScreen show honest feedback without crashing',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pullUpEx = _createPullUpExercise();
      final fakeSource = FakeWorkoutCvNativeSource()
        ..permissionStatus = 'denied'
        ..requestPermissionResult = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvNativeSourceProvider.overrideWithValue(fakeSource),
          ],
          child: MaterialApp(
            home: ActiveWorkoutScreen(
              exercises: [pullUpEx],
              autoTick: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('active_workout_form_check_badge')));
      await tester.pumpAndSettle();

      // Permission denied UI is shown
      expect(find.byType(WorkoutCvScreen), findsOneWidget);
      expect(find.text('NO PERMISSION'), findsOneWidget);
      expect(find.text('Camera Permission Required'), findsOneWidget);
      expect(find.text('Grant Permission'), findsOneWidget);

      // Now simulate user granting permission on retry, but native startSession fails
      fakeSource.requestPermissionResult = true;
      fakeSource.startSessionResult = false;
      await tester.tap(find.text('Grant Permission'));
      await tester.pumpAndSettle();

      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('Unable to start camera session.'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}

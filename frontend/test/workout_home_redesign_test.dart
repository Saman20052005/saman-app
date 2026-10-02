import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/data/repositories/exercise_repository.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_detail_screen.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/presentation/tokens/saman_workout_tokens.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/screens/main_screen.dart';

void main() {
  testWidgets(
      'WorkoutHomeScreen renders scheduled session, quick actions, train by focus and plans (no sample history)',
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
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Title & Subtitle
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Train, log & explore movements'), findsOneWidget);
    expect(find.text('My Plans'), findsOneWidget);

    // Verify Today's Scheduled Session Hero
    expect(find.text('TODAY’S SCHEDULED SESSION'), findsOneWidget);
    expect(find.text('Planned'), findsWidgets);
    expect(find.text('UPPER BODY PROTOCOL'), findsOneWidget);
    expect(find.text('Upper Body Strength'), findsOneWidget);
    expect(find.text('50 min'), findsOneWidget);
    expect(find.text('5 exercises'), findsWidgets);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('View plan'), findsOneWidget);

    // Verify Quick Actions
    expect(find.text('Quick start'), findsOneWidget);
    expect(find.text('Train without a plan'), findsOneWidget);
    expect(find.text('Browse library'), findsOneWidget);
    expect(find.text('Explore exercises'), findsOneWidget);

    // Verify Train by Focus
    expect(find.text('TRAIN BY FOCUS'), findsOneWidget);
    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('Upper Body'), findsOneWidget);
    expect(find.text('Lower Body'), findsOneWidget);

    // Verify Your Plan
    expect(find.text('YOUR PLAN'), findsOneWidget);
    expect(find.text('View full plan'), findsOneWidget);

    // Verify Last Workout - No sample history row ("Leg Day & Posterior Chain — Yesterday" removed)
    expect(find.text('LAST WORKOUT'), findsOneWidget);
    expect(find.text('View history'), findsOneWidget);
    expect(find.text('No saved workouts yet'), findsOneWidget);
    expect(find.text('Leg Day & Posterior Chain'), findsNothing);
  });

  testWidgets(
      'WorkoutHomeScreen displays completed session with finishedAt as Last Workout',
      (WidgetTester tester) async {
    final finishedSession = WorkoutSession(
      id: 'session-123',
      planName: 'Upper Body Hypertrophy',
      startedAt: DateTime.now().subtract(const Duration(minutes: 60)),
      finishedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      totalDurationMinutes: 50,
      totalVolumeKg: 1200,
      exerciseLogs: const [
        ExerciseSetLog(
          exerciseId: 'db-bench-press',
          exerciseSlug: 'dumbbell-bench-press',
          setNumber: 1,
          repsCompleted: 10,
          weightKg: 24,
          isCompleted: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryProvider.overrideWith((ref) async => [finishedSession]),
        ],
        child: const MaterialApp(
          home: WorkoutHomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('LAST WORKOUT'), findsOneWidget);
    expect(find.text('Upper Body Hypertrophy'), findsOneWidget);
    expect(find.text('No saved workouts yet'), findsNothing);
  });

  testWidgets(
      'WorkoutHomeScreen does not treat in-progress session (finishedAt == null) as Last Workout',
      (WidgetTester tester) async {
    final inProgressSession = WorkoutSession(
      id: 'session-active',
      planName: 'Live Active Session',
      startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      finishedAt: null, // In progress
      exerciseLogs: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryProvider.overrideWith((ref) async => [inProgressSession]),
        ],
        child: const MaterialApp(
          home: WorkoutHomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('LAST WORKOUT'), findsOneWidget);
    expect(find.text('Live Active Session'), findsNothing);
    expect(find.text('No saved workouts yet'), findsOneWidget);
  });

  testWidgets(
      'ExerciseLibraryScreen filters exercises by initialCategory, tab switching, chips, search, and verifies names present/absent',
      (WidgetTester tester) async {
    const testExercises = [
      Exercise(
        id: 'db-bench-press',
        slug: 'dumbbell-bench-press',
        name: 'Dumbbell Bench Press',
        nameVi: 'Đẩy ngực với tạ đơn',
        muscleGroup: 'Chest',
        targetMuscles: ['Chest', 'Pectoralis Major'],
        secondaryMuscles: ['Triceps'],
        equipment: ['Dumbbells'],
        difficulty: 'intermediate',
        thumbnailUrl: 'https://example.com/bench.jpg',
        defaultSets: 4,
        defaultReps: '8-10',
        restSeconds: 90,
        repType: 'reps',
        cvSupported: false,
      ),
      Exercise(
        id: 'lat-pulldown',
        slug: 'lat-pulldown',
        name: 'Lat Pulldown',
        nameVi: 'Kéo xô máy',
        muscleGroup: 'Back',
        targetMuscles: ['Back', 'Latissimus Dorsi'],
        secondaryMuscles: ['Biceps'],
        equipment: ['Cable Machine'],
        difficulty: 'beginner',
        thumbnailUrl: 'https://example.com/lat.jpg',
        defaultSets: 3,
        defaultReps: '10-12',
        restSeconds: 60,
        repType: 'reps',
        cvSupported: false,
      ),
      Exercise(
        id: 'db-shoulder-press',
        slug: 'dumbbell-shoulder-press',
        name: 'Dumbbell Shoulder Press',
        nameVi: 'Đẩy vai với tạ đơn',
        muscleGroup: 'Shoulders',
        targetMuscles: ['Shoulders', 'Anterior Deltoid'],
        secondaryMuscles: ['Triceps'],
        equipment: ['Dumbbells'],
        difficulty: 'intermediate',
        thumbnailUrl: 'https://example.com/shoulder.jpg',
        defaultSets: 4,
        defaultReps: '8-10',
        restSeconds: 90,
        repType: 'reps',
        cvSupported: false,
      ),
    ];

    // 1. Open with initialCategory = 'Upper Body'
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider.overrideWith((ref) async => testExercises),
        ],
        child: const MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'Upper Body'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Header & Search
    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.text('Search exercises'), findsOneWidget);

    // Verify Upper Body movements are present
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsOneWidget);
    expect(find.text('Dumbbell Shoulder Press'), findsOneWidget);

    // 2. Select sub-filter chip "Chest"
    await tester.tap(find.text('Chest').first);
    await tester.pump();

    // Dumbbell Bench Press is present; Lat Pulldown and Shoulder Press are absent
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsNothing);
    expect(find.text('Dumbbell Shoulder Press'), findsNothing);

    // 3. Combine with search
    await tester.enterText(find.byType(TextField), 'Press');
    await tester.pump();

    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsNothing);

    // Search query with no match
    await tester.enterText(find.byType(TextField), 'Squat');
    await tester.pump();

    expect(find.text('Dumbbell Bench Press'), findsNothing);
    expect(find.text('No exercises found'), findsOneWidget);

    // Clear search
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    // 4. Switch category tab to "Lower Body"
    await tester.tap(find.text('Lower Body'));
    await tester.pump();

    // Verify sub-filter chip was reset, empty state shown, no fake exercises
    expect(find.text('No lower body exercises yet'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsNothing);
    expect(find.text('Lat Pulldown'), findsNothing);
    expect(find.text('Dumbbell Shoulder Press'), findsNothing);

    // 5. Switch category tab to "Core"
    await tester.tap(find.text('Core'));
    await tester.pump();

    expect(find.text('No core exercises yet'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsNothing);

    // 6. Switch back to "All"
    await tester.tap(find.text('All').first);
    await tester.pump();

    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsOneWidget);
    expect(find.text('Dumbbell Shoulder Press'), findsOneWidget);
  });

  testWidgets(
      'ExerciseDetailScreen renders Dumbbell Bench Press, video guide, 3 phases, form cues and dynamic muscleGroup without CHEST / PUSH',
      (WidgetTester tester) async {
    const exercise = Exercise(
      id: 'db-bench-press',
      slug: 'dumbbell-bench-press',
      name: 'Dumbbell Bench Press',
      nameVi: 'Đẩy ngực với tạ đơn',
      muscleGroup: 'Chest',
      targetMuscles: ['Chest'],
      secondaryMuscles: ['Triceps', 'Shoulders'],
      equipment: ['Dumbbells', 'Flat bench'],
      difficulty: 'intermediate',
      thumbnailUrl: 'https://example.com/bench.jpg',
      defaultSets: 4,
      defaultReps: '8-10',
      restSeconds: 90,
      repType: 'reps',
      cvSupported: false,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseDetailScreen(exercise: exercise),
        ),
      ),
    );

    await tester.pump();

    // Verify Header & TopBar: dynamic muscleGroup instead of CHEST / PUSH
    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.text('CHEST'), findsOneWidget);
    expect(find.text('CHEST / PUSH'), findsNothing);

    // Verify Video Guide Badge & Play are absent (no false promises or fake play action)
    expect(find.text('VIDEO GUIDE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    // Verify Title & Subtitle
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('A chest exercise using dumbbells and a flat bench.'),
        findsOneWidget);

    // Verify Taxonomy Card
    expect(find.text('PRIMARY'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('SECONDARY'), findsOneWidget);
    expect(find.text('Triceps, Shoulders'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('Dumbbells, Flat bench'), findsOneWidget);

    // Verify 3 Phases
    expect(find.text('How to perform'), findsOneWidget);
    expect(find.text('3 PHASES'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Lower'), findsOneWidget);
    expect(find.text('Press'), findsOneWidget);

    // Verify Form Cues
    expect(find.text('Form cues'), findsOneWidget);
    expect(find.text('Keep your feet planted'), findsOneWidget);
    expect(find.text('Keep your wrists straight'), findsOneWidget);
    expect(find.text('Move slowly and stay in control'), findsOneWidget);

    // Verify Floating CTA
    expect(find.text('Start exercise'), findsOneWidget);

    // Contract Verification: Zero CV Form Check on Dumbbell Bench Press
    expect(find.text('Check my form'), findsNothing);
    expect(find.text('Live Form Check'), findsNothing);

    // Tap Start Exercise -> Open Decision Point Bottom Sheet
    await tester.tap(find.text('Start exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Start Exercise Flow Decision'), findsOneWidget);
  });

  testWidgets(
      'ExerciseDetailScreen renders BACK for Back exercise muscleGroup',
      (WidgetTester tester) async {
    const backExercise = Exercise(
      id: 'lat-pulldown',
      slug: 'lat-pulldown',
      name: 'Lat Pulldown',
      nameVi: 'Kéo xô máy',
      muscleGroup: 'Back',
      targetMuscles: ['Back'],
      secondaryMuscles: ['Biceps'],
      equipment: ['Cable Machine'],
      difficulty: 'beginner',
      thumbnailUrl: 'https://example.com/lat.jpg',
      defaultSets: 3,
      defaultReps: '10-12',
      restSeconds: 60,
      repType: 'reps',
      cvSupported: false,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseDetailScreen(exercise: backExercise),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('BACK'), findsOneWidget);
    expect(find.text('CHEST / PUSH'), findsNothing);
  });

  const testLibExercises = [
    Exercise(
      id: 'db-bench-press',
      slug: 'dumbbell-bench-press',
      name: 'Dumbbell Bench Press',
      nameVi: 'Đẩy ngực với tạ đơn',
      muscleGroup: 'Chest',
      targetMuscles: ['Chest'],
      secondaryMuscles: ['Triceps'],
      equipment: ['Dumbbells'],
      difficulty: 'intermediate',
      thumbnailUrl: 'https://example.com/bench.jpg',
      defaultSets: 4,
      defaultReps: '8-10',
      restSeconds: 90,
      repType: 'reps',
      cvSupported: false,
    ),
  ];

  testWidgets(
      'ExerciseLibraryScreen search field has dark theme styling and transparent fill without white background',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider
              .overrideWith((ref) async => testLibExercises),
        ],
        child: const MaterialApp(
          home: ExerciseLibraryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.cursorColor, SamanWorkoutTokens.emeraldAccent);
    expect(textField.style?.color, SamanWorkoutTokens.textPrimary);

    final decoration = textField.decoration;
    expect(decoration, isNotNull);
    expect(decoration!.fillColor, Colors.transparent);
    expect(decoration.filled, isFalse);
    expect(decoration.hintStyle?.color, SamanWorkoutTokens.textSecondary);
  });

  testWidgets(
      'ExerciseLibraryScreen renders exactly one SamanBottomNavigationBar with Workout active (index 1)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider
              .overrideWith((ref) async => testLibExercises),
        ],
        child: const MaterialApp(
          home: ExerciseLibraryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SamanBottomNavigationBar), findsOneWidget);
    final navBar = tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar));
    expect(navBar.currentIndex, 1);
  });

  testWidgets(
      'ExerciseLibraryScreen back button and Workout bottom bar tab pop back to caller',
      (WidgetTester tester) async {
    bool poppedViaBack = false;
    bool poppedViaWorkoutTab = false;

    // Sub-case A: Pop via AppBar back button
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider
              .overrideWith((ref) async => testLibExercises),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExerciseLibraryScreen(),
                    ),
                  ).then((_) => poppedViaBack = true);
                },
                child: const Text('Open Library'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Library'));
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(poppedViaBack, isTrue);
    expect(find.byType(ExerciseLibraryScreen), findsNothing);

    // Sub-case B: Pop via Workout tab on bottom bar
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider
              .overrideWith((ref) async => testLibExercises),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExerciseLibraryScreen(),
                    ),
                  ).then((_) => poppedViaWorkoutTab = true);
                },
                child: const Text('Open Library 2'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Library 2'));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);

    await tester.tap(find.text('Workout'));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(poppedViaWorkoutTab, isTrue);
    expect(find.byType(ExerciseLibraryScreen), findsNothing);
  });

  testWidgets(
      'ExerciseLibraryScreen bottom navigation bar switches tabs via mainNavIndexProvider and pops',
      (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        exerciseLibraryListProvider
            .overrideWith((ref) async => testLibExercises),
      ],
    );
    addTearDown(container.dispose);

    // Initial state: Workout tab (index 1)
    container.read(mainNavIndexProvider.notifier).state = 1;

    bool popped = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExerciseLibraryScreen(),
                    ),
                  ).then((_) => popped = true);
                },
                child: const Text('Open Library'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Library'));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    expect(find.byType(SamanBottomNavigationBar), findsOneWidget);
    final navBar = tester.widget<SamanBottomNavigationBar>(
        find.byType(SamanBottomNavigationBar));
    expect(navBar.currentIndex, 1);

    // Tap Home tab (index 0)
    await tester.tap(find.text('Home'));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify Library was popped and mainNavIndexProvider updated to 0
    expect(popped, isTrue);
    expect(container.read(mainNavIndexProvider), 0);
    expect(find.byType(ExerciseLibraryScreen), findsNothing);
  });

  testWidgets(
      'ExerciseLibraryScreen with curatedExerciseLibrary renders Arms, Lower Body, Core, and subfilter chips correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider
              .overrideWith((ref) async => curatedExerciseLibrary),
        ],
        child: const MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'Upper Body'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 1. In Upper Body, tap "Arms" chip
    await tester.tap(find.text('Arms'));
    await tester.pump();

    // Verify Arms exercises present, others absent
    expect(find.text('Dumbbell Bicep Curl'), findsOneWidget);
    expect(find.text('Triceps Rope Pushdown'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsNothing);
    expect(find.text('Lat Pulldown'), findsNothing);
    expect(find.text('Barbell Back Squat'), findsNothing);

    // Verify Dumbbell Bicep Curl does not promise Video guide
    expect(find.text('Video guide'), findsNothing);

    // 2. Switch to "Lower Body"
    await tester.tap(find.text('Lower Body'));
    await tester.pump();

    // Subfilter "All" shows lower body exercises
    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Romanian Deadlift'), findsOneWidget);
    expect(find.text('Barbell Hip Thrust'), findsOneWidget);

    // Tap "Quads" chip
    await tester.tap(find.text('Quads'));
    await tester.pump();
    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Leg Press'), findsOneWidget);
    expect(find.text('Romanian Deadlift'), findsNothing);
    expect(find.text('Standing Calf Raise'), findsNothing);

    // Tap "Calves" chip
    await tester.tap(find.text('Calves'));
    await tester.pump();
    expect(find.text('Standing Calf Raise'), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsNothing);

    // 3. Switch to "Core"
    await tester.tap(find.text('Core'));
    await tester.pump();

    expect(find.text('Plank'), findsOneWidget);
    expect(find.text('Hanging Leg Raise'), findsOneWidget);
    expect(find.text('Cable Woodchopper'), findsOneWidget);
    expect(find.text('Ab Wheel Rollout'), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsNothing);

    // Tap "Obliques" chip
    await tester.tap(find.text('Obliques'));
    await tester.pump();
    expect(find.text('Cable Woodchopper'), findsOneWidget);
    expect(find.text('Plank'), findsNothing);

    // 4. Search functionality with Vietnamese name
    await tester.enterText(find.byType(TextField), 'vặn sườn');
    await tester.pump();
    expect(find.text('Cable Woodchopper'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Không Có Bài Này');
    await tester.pump();
    expect(find.text('Cable Woodchopper'), findsNothing);
    expect(find.text('No exercises found'), findsOneWidget);
  });

  testWidgets(
      'ExerciseDetailScreen for non-Bench-Press exercise isolates content and does not promise Video Guide',
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

    // Verify Title & Vietnamese subtitle
    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Gánh tạ đòn ngang lưng'), findsOneWidget);

    // Verify dynamic TopBar & Taxonomy
    expect(find.text('QUADS'), findsOneWidget);
    expect(find.text('PRIMARY'), findsOneWidget);
    expect(find.text('Quads'), findsOneWidget);
    expect(find.text('SECONDARY'), findsOneWidget);
    expect(find.text('Glutes, Hamstrings, Core'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('Barbell, Squat Rack'), findsOneWidget);

    // Verify zero Bench Press leak
    expect(find.text('Triceps, Shoulders'), findsNothing);
    expect(find.text('Dumbbells, Flat bench'), findsNothing);
    expect(find.text('A chest exercise using dumbbells and a flat bench.'),
        findsNothing);
    expect(find.text('Setup'), findsNothing);
    expect(find.text('Lower'), findsNothing);
    expect(find.text('Press'), findsNothing);
    expect(find.text('Keep your feet planted'), findsNothing);
    expect(find.text('Keep your wrists straight'), findsNothing);

    // Verify honest media state: NO Video Guide or play arrow
    expect(find.text('VIDEO GUIDE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('Exercise image unavailable'), findsOneWidget);

    // Verify honest instructions state and actual form cues
    expect(find.text('How to perform'), findsOneWidget);
    expect(
        find.text('Movement instructions are being prepared for this exercise.'),
        findsNothing);
    expect(
        find.text(
            'Rest barbell securely across upper traps with chest proud'),
        findsOneWidget);
    expect(
        find.text(
            'Hinge hips back and bend knees tracking in line with toes'),
        findsOneWidget);
    expect(
        find.text(
            'Descend until thighs are at least parallel to the floor'),
        findsOneWidget);
    expect(
        find.text(
            'Drive through midfoot and heels to return upright'),
        findsOneWidget);
    expect(find.text('Common mistakes'), findsOneWidget);
    expect(find.text('Knees caving inward during ascent'), findsOneWidget);
  });

  testWidgets(
      'ExerciseDetailScreen displays honest empty states when cues and media are missing',
      (WidgetTester tester) async {
    const minimalExercise = Exercise(
      id: 'custom-exercise',
      slug: 'custom-exercise',
      name: 'Custom Lift',
      nameVi: 'Bài tập tùy chỉnh',
      muscleGroup: 'Arms',
      targetMuscles: ['Arms'],
      secondaryMuscles: [],
      equipment: [],
      difficulty: 'beginner',
      thumbnailUrl: '',
      defaultSets: 3,
      defaultReps: '10',
      restSeconds: 60,
      repType: 'reps',
      cvSupported: false,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ExerciseDetailScreen(exercise: minimalExercise),
        ),
      ),
    );

    await tester.pump();

    // Verify honest taxonomy fallbacks
    expect(find.text('PRIMARY'), findsOneWidget);
    expect(find.text('Arms'), findsOneWidget);
    expect(find.text('SECONDARY'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);

    // Verify honest instructions state without fake text
    expect(find.text('Movement instructions are being prepared for this exercise.'),
        findsOneWidget);
    expect(find.text('Form cues are being documented for this exercise.'),
        findsNothing);

    // Verify fake texts are absent
    expect(find.text('Preparation'), findsNothing);
    expect(find.text('Maintain neutral spinal alignment'), findsNothing);
    expect(find.text('VIDEO GUIDE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets(
      'exerciseLibraryListProvider serves complete 17-exercise local catalog consistently regardless of repository override or error',
      (WidgetTester tester) async {
    const singleExercise = Exercise(
      id: 'mock-single-item',
      slug: 'mock-single-item',
      name: 'Mock Single Item',
      nameVi: 'Bài tập đơn lẻ từ API',
      muscleGroup: 'Chest',
      targetMuscles: ['Chest'],
      secondaryMuscles: [],
      equipment: ['Bodyweight'],
      difficulty: 'beginner',
      thumbnailUrl: '',
      defaultSets: 3,
      defaultReps: '10',
      restSeconds: 60,
      repType: 'reps',
      cvSupported: false,
    );

    // Case 1: Repository provider overridden with a different/single exercise or error
    final mockRepo = _SingleExerciseMockRepository(singleExercise);

    final container = ProviderContainer(
      overrides: [
        exerciseRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    addTearDown(container.dispose);

    // 1. Verify Riverpod provider deterministically serves 17-exercise catalog
    final exercises = await container.read(exerciseLibraryListProvider.future);
    expect(exercises.length, 17);

    // 2. Verify UI renders 17-exercise catalog across categories without leak of single mock item
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ExerciseLibraryScreen(initialCategory: 'All'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Mock Single Item'), findsNothing);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);

    // Switch to Arms category
    await tester.tap(find.text('Arms'));
    await tester.pump();
    expect(find.text('Dumbbell Bicep Curl'), findsOneWidget);
    expect(find.text('VIDEO GUIDE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    // Switch to Lower Body category - verify legitimate items in correct group and no fake video
    await tester.tap(find.text('Lower Body'));
    await tester.pump();
    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Romanian Deadlift'), findsOneWidget);
    expect(find.text('Barbell Hip Thrust'), findsOneWidget);
    expect(find.text('Leg Press'), findsOneWidget);

    // Scroll ListView to bring off-screen lower body exercises into view
    await tester.scrollUntilVisible(
      find.text('Lying Leg Curl'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Lying Leg Curl'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Standing Calf Raise'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Standing Calf Raise'), findsOneWidget);
    expect(find.text('VIDEO GUIDE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    // Switch to Core category - verify legitimate items in correct group and no fake video
    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();
    expect(find.text('Plank'), findsOneWidget);
    expect(find.text('Hanging Leg Raise'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cable Woodchopper'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Cable Woodchopper'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Ab Wheel Rollout'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Ab Wheel Rollout'), findsOneWidget);
    expect(find.text('VIDEO GUIDE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets(
      'exerciseLibraryListProvider remains consistent when repository provider throws an error',
      (WidgetTester tester) async {
    final errorContainer = ProviderContainer(
      overrides: [
        exerciseRepositoryProvider.overrideWithValue(_ThrowingMockRepository()),
      ],
    );
    addTearDown(errorContainer.dispose);

    final exercises =
        await errorContainer.read(exerciseLibraryListProvider.future);
    expect(exercises.length, 17);
    expect(exercises, equals(curatedExerciseLibrary));
  });
}

class _ThrowingMockRepository implements ExerciseRepository {
  @override
  Future<List<Exercise>> getExercisesByMuscleGroup({
    required String muscleGroupSlug,
    String? difficulty,
    String? search,
  }) async {
    throw Exception('Simulated network outage or database down');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SingleExerciseMockRepository implements ExerciseRepository {
  final Exercise singleExercise;
  _SingleExerciseMockRepository(this.singleExercise);

  @override
  Future<List<Exercise>> getExercisesByMuscleGroup({
    required String muscleGroupSlug,
    String? difficulty,
    String? search,
  }) async =>
      [singleExercise];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

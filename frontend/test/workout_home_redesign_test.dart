import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_library_screen.dart';
import 'package:health_ai_app/presentation/screens/exercise_detail_screen.dart';

void main() {
  testWidgets('WorkoutHomeScreen renders scheduled session, quick actions, train by focus and plans',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: WorkoutHomeScreen(),
        ),
      ),
    );

    await tester.pump();

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

    // Verify Last Workout
    expect(find.text('LAST WORKOUT'), findsOneWidget);
    expect(find.text('View history'), findsOneWidget);
    expect(find.text('Leg Day & Posterior Chain'), findsOneWidget);
  });

  testWidgets('ExerciseLibraryScreen renders search, category tabs, filter chips and movement rows',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseLibraryListProvider.overrideWith((ref) async {
            return const [
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
                thumbnailUrl: 'https://example.com/image.jpg',
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
                targetMuscles: ['Back'],
                secondaryMuscles: ['Biceps'],
                equipment: ['Cable Machine'],
                difficulty: 'beginner',
                thumbnailUrl: 'https://example.com/image.jpg',
                defaultSets: 3,
                defaultReps: '10-12',
                restSeconds: 60,
                repType: 'reps',
                cvSupported: false,
              ),
            ];
          }),
        ],
        child: const MaterialApp(
          home: ExerciseLibraryScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Header & Search
    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.text('Search exercises'), findsOneWidget);

    // Verify Category Tabs
    expect(find.text('All'), findsWidgets);
    expect(find.text('Upper Body'), findsOneWidget);
    expect(find.text('Lower Body'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);

    // Verify Secondary Filters
    expect(find.text('Chest'), findsWidgets);
    expect(find.text('Back'), findsWidgets);
    expect(find.text('Shoulders'), findsWidgets);
    expect(find.text('Equipment'), findsOneWidget);

    // Verify Movements header
    expect(find.text('MOVEMENTS'), findsOneWidget);

    // Verify Exercise Rows
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsOneWidget);
    expect(find.text('Video guide'), findsWidgets);
  });

  testWidgets(
      'ExerciseDetailScreen renders Dumbbell Bench Press, video guide, 3 phases, form cues and no CV',
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

    // Verify Header & TopBar
    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.text('CHEST / PUSH'), findsOneWidget);

    // Verify Video Guide Badge & Play
    expect(find.text('VIDEO GUIDE'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

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
}


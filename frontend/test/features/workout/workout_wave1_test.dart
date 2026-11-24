import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/active_workout_state.dart';
import 'package:health_ai_app/presentation/providers/muscle_recovery_provider.dart';
import 'package:health_ai_app/presentation/widgets/muscle_recovery_card.dart';
import 'package:health_ai_app/presentation/widgets/plate_calculator_sheet.dart';

Exercise _makeExercise(String id, {int sets = 3, int restSeconds = 90}) {
  return Exercise(
    id: id,
    slug: id,
    name: 'Exercise $id',
    nameVi: 'Bài tập $id',
    muscleGroup: 'chest',
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: sets,
    defaultReps: '8-10',
    restSeconds: restSeconds,
    repType: 'reps',
  );
}

void main() {
  group('Wave 1 Data Models & Serialization', () {
    test('ExerciseSetLog.fromJson/toJson preserves legacy JSON backward compatibility', () {
      final legacy = <String, dynamic>{
        'exerciseId': 'bench-press',
        'exerciseSlug': 'bench-press',
        'setNumber': 1,
        'repsCompleted': 8,
        'weightKg': 60.0,
        'isCompleted': true,
        'restTakenSeconds': null,
        'cvDetected': false,
      };

      final parsed = ExerciseSetLog.fromJson(legacy);
      expect(parsed.setType, SetType.normal);
      expect(parsed.rpe, isNull);
      expect(parsed.note, isNull);
      expect(parsed.supersetGroupId, isNull);
      expect(parsed.isPr, isFalse);
      expect(parsed.toJson(), equals(legacy));
    });

    test('ExerciseSetLog supports Wave 1 fields and snake_case normalization', () {
      final snakePayload = <String, dynamic>{
        'exerciseId': 'squat',
        'exerciseSlug': 'squat',
        'setNumber': 2,
        'repsCompleted': 5,
        'weightKg': 100.0,
        'isCompleted': true,
        'restTakenSeconds': 120,
        'cvDetected': false,
        'set_type': 'drop',
        'rpe': 8.5,
        'note': 'Deep pause',
        'superset_group_id': 'ss_1',
        'is_pr': true,
      };

      final parsed = ExerciseSetLog.fromJson(snakePayload);
      expect(parsed.setType, SetType.drop);
      expect(parsed.rpe, 8.5);
      expect(parsed.note, 'Deep pause');
      expect(parsed.supersetGroupId, 'ss_1');
      expect(parsed.isPr, isTrue);

      final roundTrip = ExerciseSetLog.fromJson(
        jsonDecode(jsonEncode(parsed)) as Map<String, dynamic>,
      );
      expect(roundTrip, equals(parsed));
    });
  });

  group('Wave 1 ActiveWorkoutSessionNotifier', () {
    test('setSetType, setSetRpe, setExerciseNote update state accurately', () {
      final notifier = ActiveWorkoutSessionNotifier(
        ActiveWorkoutSessionState.fromExercises([
          _makeExercise('ex1'),
          _makeExercise('ex2'),
        ]),
      );

      notifier.setSetType(0, 0, SetType.warmup);
      notifier.setSetRpe(0, 0, 8.5);
      notifier.setExerciseNote(0, 'Tuck elbows 45 deg');

      final ex0 = notifier.state.exercises[0];
      expect(ex0.sets[0].setType, SetType.warmup);
      expect(ex0.sets[0].rpe, 8.5);
      expect(ex0.note, 'Tuck elbows 45 deg');

      notifier.setSetRpe(0, 0, null);
      expect(notifier.state.exercises[0].sets[0].rpe, isNull);
    });

    test('toggleSupersetWithNext links A1->A2 flow without rest, and A2 triggers rest', () {
      final notifier = ActiveWorkoutSessionNotifier(
        ActiveWorkoutSessionState.fromExercises([
          _makeExercise('a1', sets: 2, restSeconds: 90),
          _makeExercise('a2', sets: 2, restSeconds: 60),
          _makeExercise('b1', sets: 2, restSeconds: 60),
        ]),
      );

      notifier.toggleSupersetWithNext(0);
      expect(notifier.state.isInSuperset(0), isTrue);
      expect(notifier.state.isInSuperset(1), isTrue);
      expect(notifier.state.supersetBadgeLabel(0), 'A1');
      expect(notifier.state.supersetBadgeLabel(1), 'A2');
      expect(notifier.state.supersetBadgeLabel(2), isNull);

      // Log set on A1 -> jumps to A2 with isResting == false
      notifier.logActiveSet();
      expect(notifier.state.currentExerciseIndex, 1);
      expect(notifier.state.isResting, isFalse);
      expect(notifier.state.restSecondsLeft, 0);

      // Log set on A2 -> starts rest timer normally
      notifier.logActiveSet();
      expect(notifier.state.isResting, isTrue);
      expect(notifier.state.restSecondsLeft, 60);
    });

    test('reorderExercises updates exercise order and preserves currentExerciseIndex tracking', () {
      final notifier = ActiveWorkoutSessionNotifier(
        ActiveWorkoutSessionState.fromExercises([
          _makeExercise('ex1'),
          _makeExercise('ex2'),
          _makeExercise('ex3'),
        ]),
      );

      notifier.selectExercise(0);
      expect(notifier.state.currentExercise?.id, 'ex1');

      notifier.reorderExercises(0, 3);
      expect(notifier.state.exercises.map((e) => e.id).toList(), ['ex2', 'ex3', 'ex1']);
      expect(notifier.state.currentExerciseIndex, 2);
      expect(notifier.state.currentExercise?.id, 'ex1');
    });

    test('Local PR check marks isPr=true when beating lastPerformance and skips warmup', () {
      final notifier = ActiveWorkoutSessionNotifier(
        ActiveWorkoutSessionState.fromExercises([
          _makeExercise('bench', sets: 3),
        ]),
      );

      notifier.applyLastPerformanceHints({
        'bench': const LastExercisePerformance(
          exerciseId: 'bench',
          lastWeightKg: 80.0,
          lastReps: 8,
          suggestedWeightKg: 82.5,
          suggestedReps: 8,
          suggestionReason: 'completed_target_add_weight',
        ),
      });

      // Warmup set exceeding weight must NOT be marked PR
      notifier.setSetType(0, 0, SetType.warmup);
      notifier.setDraftWeight(90.0);
      notifier.setDraftReps(8);
      notifier.logActiveSet();
      expect(notifier.state.exercises[0].sets[0].isPr, isFalse);

      // Normal set beating 80kg x 8 must be marked PR
      notifier.setDraftWeight(85.0);
      notifier.setDraftReps(8);
      notifier.logActiveSet();
      expect(notifier.state.exercises[0].sets[1].isPr, isTrue);
    });

    test('restFinishedCount increments on natural tick 1->0 and not on skipRest', () {
      final notifier = ActiveWorkoutSessionNotifier(
        ActiveWorkoutSessionState.fromExercises([
          _makeExercise('ex1', restSeconds: 2),
        ]),
      );

      notifier.logActiveSet();
      expect(notifier.state.isResting, isTrue);
      expect(notifier.state.restSecondsLeft, 2);
      expect(notifier.state.restFinishedCount, 0);

      notifier.tick();
      expect(notifier.state.restSecondsLeft, 1);
      expect(notifier.state.restFinishedCount, 0);

      notifier.tick();
      expect(notifier.state.isResting, isFalse);
      expect(notifier.state.restSecondsLeft, 0);
      expect(notifier.state.restFinishedCount, 1);

      // skipRest should NOT increment restFinishedCount
      notifier.logActiveSet();
      expect(notifier.state.isResting, isTrue);
      notifier.skipRest();
      expect(notifier.state.isResting, isFalse);
      expect(notifier.state.restFinishedCount, 1);
    });
  });

  group('Wave 1 UI Widgets', () {
    testWidgets('PlateCalculatorSheet calculates 100kg on 20kg bar -> 40kg per side (25, 15)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: PlateCalculatorSheet(initialWeightKg: 60.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('plate_calc_target_input')),
        '100',
      );
      await tester.pumpAndSettle();

      expect(find.text('40 kg'), findsOneWidget);
      expect(find.text('1×25kg'), findsOneWidget);
      expect(find.text('1×15kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MuscleRecoveryCard renders 6 muscle groups cleanly in Dark and Light themes',
        (tester) async {
      const items = [
        MuscleRecoveryItem(muscleGroup: 'chest', recoveryPercent: 92, status: 'ready'),
        MuscleRecoveryItem(muscleGroup: 'back', recoveryPercent: 85, status: 'ready'),
        MuscleRecoveryItem(muscleGroup: 'legs', recoveryPercent: 40, status: 'fatigued'),
        MuscleRecoveryItem(muscleGroup: 'shoulders', recoveryPercent: 72, status: 'recovering'),
        MuscleRecoveryItem(muscleGroup: 'arms', recoveryPercent: 64, status: 'recovering'),
        MuscleRecoveryItem(muscleGroup: 'core', recoveryPercent: 95, status: 'ready'),
      ];

      for (final theme in [ThemeData.dark(), ThemeData.light()]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              muscleRecoveryProvider.overrideWith((ref) async => items),
            ],
            child: MaterialApp(
              theme: theme,
              home: const Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: MuscleRecoveryCard(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('muscle_recovery_card')), findsOneWidget);
        for (final item in items) {
          expect(
            find.byKey(ValueKey('muscle_recovery_item_${item.muscleGroup}')),
            findsOneWidget,
          );
        }
        expect(find.byKey(const ValueKey('muscle_recovery_train_cta')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}

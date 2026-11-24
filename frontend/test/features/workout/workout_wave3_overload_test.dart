import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/screens/active_workout_screen.dart';

Exercise _makeTestExercise({
  String id = 'lat-pulldown',
  String name = 'Lat Pulldown',
  String defaultReps = '10',
}) {
  return Exercise(
    id: id,
    slug: id,
    name: name,
    nameVi: 'Kéo xô',
    muscleGroup: 'back',
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: defaultReps,
    restSeconds: 90,
    repType: 'reps',
  );
}

void main() {
  group('Wave 3 LastExercisePerformance Serialization', () {
    test('fromJson parses cv_form_score and cv_fast_reps (snake_case and camelCase)', () {
      final snake = LastExercisePerformance.fromJson({
        'exercise_id': 'lat-pulldown',
        'last_weight_kg': 60.0,
        'last_reps': 10,
        'suggested_weight_kg': 62.5,
        'suggested_reps': 10,
        'suggestion_reason': 'cv_form_verified_add_weight',
        'last_date': '2026-11-20',
        'cv_form_score': 92,
        'cv_fast_reps': 1,
      });

      expect(snake.exerciseId, 'lat-pulldown');
      expect(snake.lastWeightKg, 60.0);
      expect(snake.lastReps, 10);
      expect(snake.suggestedWeightKg, 62.5);
      expect(snake.suggestedReps, 10);
      expect(snake.suggestionReason, 'cv_form_verified_add_weight');
      expect(snake.cvFormScore, 92);
      expect(snake.cvFastReps, 1);

      final camel = LastExercisePerformance.fromJson({
        'exerciseId': 'pull-up',
        'last_weight_kg': 0,
        'last_reps': 10,
        'suggested_weight_kg': 0,
        'suggested_reps': 11,
        'suggestion_reason': 'cv_form_verified_add_rep',
        'cvFormScore': 95,
        'cvFastReps': 0,
      });

      expect(camel.exerciseId, 'pull-up');
      expect(camel.cvFormScore, 95);
      expect(camel.cvFastReps, 0);
    });

    test('fromJson defaults cvFormScore and cvFastReps to null for legacy payloads', () {
      final legacy = LastExercisePerformance.fromJson({
        'exercise_id': 'barbell-bench-press',
        'last_weight_kg': 70.0,
        'last_reps': 8,
        'suggested_weight_kg': 72.5,
        'suggested_reps': 8,
        'suggestion_reason': 'completed_target_add_weight',
      });

      expect(legacy.cvFormScore, isNull);
      expect(legacy.cvFastReps, isNull);
      expect(legacy.suggestedWeightKg, 72.5);
      expect(legacy.suggestionReason, 'completed_target_add_weight');
    });
  });

  group('Wave 3 CV Progressive Overload UI in ActiveWorkoutScreen', () {
    testWidgets(
      'displays Form CV >= 85% add-weight suggestion and applies weight & reps on 1-tap button',
      (tester) async {
        late WidgetRef capturedRef;
        final exercise = _makeTestExercise(id: 'lat-pulldown');

        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return MaterialApp(
                  locale: const Locale('vi'),
                  supportedLocales: const [Locale('vi'), Locale('en')],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: ActiveWorkoutScreen(
                    exercises: [exercise],
                    autoTick: false,
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final notifier = capturedRef.read(activeWorkoutSessionProvider.notifier);
        notifier.applyLastPerformanceHints({
          'lat-pulldown': const LastExercisePerformance(
            exerciseId: 'lat-pulldown',
            lastWeightKg: 60.0,
            lastReps: 10,
            suggestedWeightKg: 62.5,
            suggestedReps: 10,
            suggestionReason: 'cv_form_verified_add_weight',
            cvFormScore: 92,
            cvFastReps: 1,
          ),
        });
        // Set different draft values first to prove 1-tap apply updates them immediately
        notifier.setDraftWeight(50.0);
        notifier.setDraftReps(8);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('active_workout_cv_form_score_badge')),
          findsOneWidget,
        );
        expect(find.text('Form CV: 92%'), findsOneWidget);
        expect(
          find.text('Đề xuất tăng +2.5 kg (Form chuẩn) → 62.5kg × 10'),
          findsOneWidget,
        );

        final applyBtn =
            find.byKey(const ValueKey('active_workout_apply_overload_button'));
        expect(applyBtn, findsOneWidget);

        await tester.ensureVisible(applyBtn);
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        final currentEx =
            capturedRef.read(activeWorkoutSessionProvider).currentExercise!;
        expect(currentEx.draftWeightKg, 62.5);
        expect(currentEx.draftReps, 10);

        final weightWidget = tester.widget<Text>(
          find.byKey(const ValueKey('active_workout_draft_weight')),
        );
        final repsWidget = tester.widget<Text>(
          find.byKey(const ValueKey('active_workout_draft_reps')),
        );
        expect(weightWidget.data, '62.5');
        expect(repsWidget.data, '10');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'displays refine-technique suggestion when cvFormScore < 70 and maintains load on apply',
      (tester) async {
        late WidgetRef capturedRef;
        final exercise = _makeTestExercise(id: 'barbell-squat', name: 'Squat');

        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return MaterialApp(
                  locale: const Locale('vi'),
                  supportedLocales: const [Locale('vi'), Locale('en')],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: ActiveWorkoutScreen(
                    exercises: [exercise],
                    autoTick: false,
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final notifier = capturedRef.read(activeWorkoutSessionProvider.notifier);
        notifier.applyLastPerformanceHints({
          'barbell-squat': const LastExercisePerformance(
            exerciseId: 'barbell-squat',
            lastWeightKg: 80.0,
            lastReps: 10,
            suggestedWeightKg: 80.0,
            suggestedReps: 10,
            suggestionReason: 'cv_form_refine_technique',
            cvFormScore: 55,
            cvFastReps: 4,
          ),
        });
        notifier.setDraftWeight(85.0);
        notifier.setDraftReps(8);
        await tester.pumpAndSettle();

        expect(find.text('Form CV: 55%'), findsOneWidget);
        expect(
          find.text('Giữ nguyên mức tạ để hoàn thiện kỹ thuật (80kg × 10)'),
          findsOneWidget,
        );

        final applyBtn =
            find.byKey(const ValueKey('active_workout_apply_overload_button'));
        await tester.ensureVisible(applyBtn);
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        final currentEx =
            capturedRef.read(activeWorkoutSessionProvider).currentExercise!;
        expect(currentEx.draftWeightKg, 80.0);
        expect(currentEx.draftReps, 10);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders English translations for bodyweight cv_form_verified_add_rep',
      (tester) async {
        late WidgetRef capturedRef;
        final exercise = _makeTestExercise(id: 'pull-up', name: 'Pull-up');

        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return MaterialApp(
                  locale: const Locale('en'),
                  supportedLocales: const [Locale('en'), Locale('vi')],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: ActiveWorkoutScreen(
                    exercises: [exercise],
                    autoTick: false,
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final notifier = capturedRef.read(activeWorkoutSessionProvider.notifier);
        notifier.applyLastPerformanceHints({
          'pull-up': const LastExercisePerformance(
            exerciseId: 'pull-up',
            lastWeightKg: 0.0,
            lastReps: 10,
            suggestedWeightKg: 0.0,
            suggestedReps: 11,
            suggestionReason: 'cv_form_verified_add_rep',
            cvFormScore: 95,
            cvFastReps: 0,
          ),
        });
        await tester.pumpAndSettle();

        expect(find.text('CV Form: 95%'), findsOneWidget);
        expect(
          find.text('Suggest +1 rep (Clean form) → 11 reps'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

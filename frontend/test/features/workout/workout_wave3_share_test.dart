import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/community_create_story_sheet.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_result_screen.dart';
import 'package:health_ai_app/presentation/providers/session_detail_providers.dart';
import 'package:health_ai_app/presentation/screens/workout_complete_screen.dart';

WorkoutSession _buildSampleSession() {
  final start = DateTime.utc(2026, 11, 23, 10, 0);
  final end = DateTime.utc(2026, 11, 23, 10, 42);
  return WorkoutSession(
    id: 'sess-wave3-share',
    planName: 'Upper Power Day',
    startedAt: start,
    finishedAt: end,
    totalDurationMinutes: 42,
    totalVolumeKg: 2400,
    exerciseLogs: [
      ExerciseSetLog(
        exerciseId: 'bench-press',
        exerciseSlug: 'bench-press',
        setNumber: 1,
        repsCompleted: 8,
        weightKg: 80,
        isCompleted: true,
      ),
      ExerciseSetLog(
        exerciseId: 'lat-pulldown',
        exerciseSlug: 'lat-pulldown',
        setNumber: 1,
        repsCompleted: 10,
        weightKg: 60,
        isCompleted: true,
      ),
    ],
  );
}

List<LatPulldownRepEvent> _buildSampleCvReps() {
  return const [
    LatPulldownRepEvent(
      repNumber: 1,
      startTimestampMs: 1000,
      bottomTimestampMs: 2200,
      endTimestampMs: 3400,
      durationMs: 2400,
      minElbowAngleDeg: 38,
      status: 'CONFIRMED',
    ),
    LatPulldownRepEvent(
      repNumber: 2,
      startTimestampMs: 3800,
      bottomTimestampMs: 5000,
      endTimestampMs: 6200,
      durationMs: 2400,
      minElbowAngleDeg: 40,
      status: 'CONFIRMED',
    ),
  ];
}

Widget _wrapTestApp({
  required Widget child,
  Locale locale = const Locale('vi'),
  ThemeMode themeMode = ThemeMode.dark,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  group('Wave 3B Community Share Integration', () {
    testWidgets(
      'WorkoutCompleteScreen renders Share button in VI & attaches snapshot with includeLoadOrMacros=false',
      (tester) async {
        final session = _buildSampleSession();
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionDetailProvider(session.id)
                  .overrideWith((ref) async => session),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  locale: const Locale('vi'),
                  supportedLocales: const [Locale('en'), Locale('vi')],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: ThemeData.dark(useMaterial3: true),
                  home: WorkoutCompleteScreen(sessionId: session.id),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final shareFinder =
            find.byKey(const ValueKey('workout_complete_share_button'));
        expect(shareFinder, findsOneWidget);
        expect(find.text('Chia sẻ lên Cộng đồng'), findsOneWidget);
        expect(find.text('Xem lịch sử tập luyện'), findsOneWidget);

        // Touch target >= 44px
        final size = tester.getSize(shareFinder);
        expect(size.height, greaterThanOrEqualTo(44.0));

        // Open bottom sheet and select Publish Community Post
        await tester.tap(shareFinder);
        await tester.pumpAndSettle();

        final postOption =
            find.byKey(const ValueKey('workout_share_post_option'));
        final storyOption =
            find.byKey(const ValueKey('workout_share_story_option'));
        expect(postOption, findsOneWidget);
        expect(storyOption, findsOneWidget);

        await tester.tap(postOption);
        await tester.pumpAndSettle();

        final composerState = container.read(communityComposerProvider);
        final attached = composerState.attachedActivity;
        expect(attached, isNotNull);
        expect(attached!.type, AttachmentType.workout);
        expect(attached.includeDuration, isTrue);
        expect(attached.includeExercisesOrFoods, isTrue);
        expect(attached.includeLoadOrMacros, isFalse);
        expect(attached.loadSummaryFormatted, isNull);
        expect(attached.setCount, isNull);
        expect(find.byType(PostComposePublishScreen), findsOneWidget);
      },
    );

    testWidgets(
      'WorkoutCompleteScreen renders Share button in English locale (Light theme)',
      (tester) async {
        final session = _buildSampleSession();
        await tester.pumpWidget(
          _wrapTestApp(
            locale: const Locale('en'),
            themeMode: ThemeMode.light,
            overrides: [
              sessionDetailProvider(session.id)
                  .overrideWith((ref) async => session),
            ],
            child: WorkoutCompleteScreen(sessionId: session.id),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('workout_complete_share_button')),
          findsOneWidget,
        );
        expect(find.text('Share to Community'), findsOneWidget);
      },
    );

    testWidgets(
      'WorkoutCvResultScreen renders Share button in VI & attaches CV summary with includeLoadOrMacros=false',
      (tester) async {
        final reps = _buildSampleCvReps();
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  locale: const Locale('vi'),
                  supportedLocales: const [Locale('en'), Locale('vi')],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: ThemeData.dark(useMaterial3: true),
                  home: WorkoutCvResultScreen(
                    repHistory: reps,
                    exerciseName: 'Lat Pulldown',
                    exerciseId: 'lat-pulldown',
                    exerciseSlug: 'lat-pulldown',
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final cvShareFinder =
            find.byKey(const ValueKey('workout_cv_result_share_button'));
        final cvDoneFinder =
            find.byKey(const ValueKey('workout_cv_result_done_button'));
        expect(cvShareFinder, findsOneWidget);
        expect(cvDoneFinder, findsOneWidget);
        expect(find.text('Chia sẻ'), findsOneWidget);
        expect(tester.getSize(cvShareFinder).height, greaterThanOrEqualTo(44.0));

        await tester.tap(cvShareFinder);
        await tester.pumpAndSettle();

        final postOption =
            find.byKey(const ValueKey('workout_cv_share_post_option'));
        final storyOption =
            find.byKey(const ValueKey('workout_cv_share_story_option'));
        expect(postOption, findsOneWidget);
        expect(storyOption, findsOneWidget);

        await tester.tap(postOption);
        await tester.pumpAndSettle();

        final attached =
            container.read(communityComposerProvider).attachedActivity;
        expect(attached, isNotNull);
        expect(attached!.type, AttachmentType.workout);
        expect(attached.includeLoadOrMacros, isFalse);
        expect(attached.title, contains('2/2 (100% Chuẩn)'));
        expect(find.byType(PostComposePublishScreen), findsOneWidget);
      },
    );

    testWidgets(
      'WorkoutCvResultScreen renders English Share CTA and CommunityCreateStorySheet supports prefill',
      (tester) async {
        final reps = _buildSampleCvReps();
        await tester.pumpWidget(
          _wrapTestApp(
            locale: const Locale('en'),
            themeMode: ThemeMode.light,
            child: WorkoutCvResultScreen(
              repHistory: reps,
              exerciseName: 'Lat Pulldown',
              exerciseId: 'lat-pulldown',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('workout_cv_result_share_button')),
          findsOneWidget,
        );
        expect(find.text('Share'), findsOneWidget);

        // Verify CommunityCreateStorySheet accepts optional prefill params
        await tester.pumpWidget(
          _wrapTestApp(
            locale: const Locale('vi'),
            child: const Scaffold(
              body: CommunityCreateStorySheet(
                initialCaption: 'Vừa hoàn thành Upper Power Day',
                initialPrivacy: 'followers_only',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Vừa hoàn thành Upper Power Day'), findsWidgets);
      },
    );
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/features/workout_cv/presentation/screens/workout_cv_screen.dart';
import 'package:health_ai_app/features/workout_cv/presentation/workout_cv_replay_trial.dart';
import 'workout_cv_controller_test.dart' show MockWorkoutCvNativeSource;

// Run this file with no define and with WORKOUT_CV_REPLAY_TRIAL=true.
const _trialBuild = bool.fromEnvironment('WORKOUT_CV_REPLAY_TRIAL');

class _RecordingNotifier extends WorkoutCvNotifier {
  _RecordingNotifier(super.source);

  final replayEntries = <bool>[];

  @override
  Future<void> initialize({
    required String exerciseId,
    required String exerciseSlug,
    bool videoReplay = false,
  }) {
    replayEntries.add(videoReplay);
    return super.initialize(
      exerciseId: exerciseId,
      exerciseSlug: exerciseSlug,
      videoReplay: videoReplay,
    );
  }

  void showPermissionRetry() {
    state = state.copyWith(
      trackingStatus: TrackingStatus.permissionDenied,
      isCameraActive: false,
    );
  }
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('replay entry requires opt-in, native Android and Lat pulldown', () {
    for (final platform in TargetPlatform.values) {
      for (final isWeb in [false, true]) {
        for (final slug in ['lat-pulldown', 'pull-up', 'seated-cable-row']) {
          expect(
            shouldUseWorkoutCvReplayTrial(
              exerciseSlug: slug,
              platform: platform,
              isWeb: isWeb,
            ),
            _trialBuild &&
                !isWeb &&
                platform == TargetPlatform.android &&
                slug == 'lat-pulldown',
            reason: '$platform web=$isWeb slug=$slug trial=$_trialBuild',
          );
        }
      }
    }
  });

  for (final entry in [
    (TargetPlatform.android, 'lat-pulldown'),
    (TargetPlatform.android, 'pull-up'),
    (TargetPlatform.iOS, 'lat-pulldown'),
  ]) {
    testWidgets('open, resume, retry and controls share policy: $entry',
        (tester) async {
      debugDefaultTargetPlatformOverride = entry.$1;
      final replayExpected = _trialBuild &&
          entry.$1 == TargetPlatform.android &&
          entry.$2 == 'lat-pulldown';
      final source = MockWorkoutCvNativeSource();
      final notifier = _RecordingNotifier(source);
      final container = ProviderContainer(overrides: [
        workoutCvControllerProvider.overrideWith((ref) => notifier),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WorkoutCvScreen(
            exerciseId: entry.$2,
            exerciseSlug: entry.$2,
            exerciseName: 'Form Check',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(notifier.replayEntries, [replayExpected]);
      expect(source.startVideoReplayCalled, replayExpected);
      expect(source.startSessionCalled, !replayExpected);
      expect(find.byKey(const ValueKey('workout_cv_switch_replay_button')),
          replayExpected ? findsOneWidget : findsNothing);
      expect(find.text('Chạy lại'),
          replayExpected ? findsOneWidget : findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifier.replayEntries, [replayExpected, replayExpected]);

      // Exercise the permission retry UI even in a replay build, where the
      // native replay entry normally does not ask for camera permission.
      notifier.showPermissionRetry();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grant Permission'));
      await tester.pumpAndSettle();
      expect(notifier.replayEntries,
          [replayExpected, replayExpected, replayExpected]);
      expect(notifier.state.sourceMode,
          replayExpected ? 'video_replay' : 'camera');
      expect(source.startVideoReplayCalled, replayExpected);
      expect(source.startSessionCalled, !replayExpected);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      source.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

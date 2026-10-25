import 'package:flutter/foundation.dart';

const workoutCvReplayTrialEnabled = bool.fromEnvironment(
  'WORKOUT_CV_REPLAY_TRIAL',
  defaultValue: false,
);

bool shouldUseWorkoutCvReplayTrial({
  required String exerciseSlug,
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) =>
    workoutCvReplayTrialEnabled &&
    !isWeb &&
    (platform ?? defaultTargetPlatform) == TargetPlatform.android &&
    exerciseSlug == 'lat-pulldown';

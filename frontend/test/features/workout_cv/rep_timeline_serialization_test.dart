import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/active_workout_state.dart';

void main() {
  group('RepRecord serialization & backward compatibility', () {
    test('toJson emits exact 10 snake_case keys when explicit timestamps set',
        () {
      const record = RepRecord(
        repIndex: 2,
        timestampSec: 12.3456,
        durationSec: 2.5,
        metricAngleDeg: 41.2,
        isValid: true,
        issueType: RepIssueType.none,
        viewAngle: CameraViewAngle.oblique45,
        startSec: 9.8456,
        bottomSec: 11.1,
        endSec: 12.3456,
        visibilityConfidence: 0.9123,
      );

      final json = record.toJson();
      expect(
        json.keys.toSet(),
        equals({
          'rep_index',
          'start_sec',
          'bottom_sec',
          'end_sec',
          'duration_sec',
          'metric_angle_deg',
          'is_valid',
          'issue_type',
          'view_angle',
          'visibility_confidence',
        }),
      );
      expect(json['rep_index'], 2);
      expect(json['start_sec'], 9.846);
      expect(json['bottom_sec'], 11.1);
      expect(json['end_sec'], 12.346);
      expect(json['duration_sec'], 2.5);
      expect(json['metric_angle_deg'], 41.2);
      expect(json['is_valid'], isTrue);
      expect(json['issue_type'], 'none');
      expect(json['view_angle'], 'oblique45');
      expect(json['visibility_confidence'], 0.912);
    });

    test('legacy constructor falls back to effectiveStart/Bottom/EndSec', () {
      const legacy = RepRecord(
        repIndex: 1,
        timestampSec: 5.0,
        durationSec: 2.0,
        metricAngleDeg: 52.0,
        isValid: false,
        issueType: RepIssueType.shallowDepth,
        viewAngle: CameraViewAngle.side90,
      );

      expect(legacy.effectiveStartSec, closeTo(3.0, 1e-9));
      expect(legacy.effectiveBottomSec, closeTo(4.0, 1e-9));
      expect(legacy.effectiveEndSec, closeTo(5.0, 1e-9));
      expect(legacy.visibilityConfidence, 1.0);

      final json = legacy.toJson();
      expect(json['start_sec'], 3.0);
      expect(json['bottom_sec'], 4.0);
      expect(json['end_sec'], 5.0);
      expect(json['visibility_confidence'], 1.0);
    });
  });

  group('WorkoutCvNotifier.computeFrameVisibilityConfidence', () {
    test('ignores nose landmark 0 and averages 8 upper-body joints', () {
      const upperBodyIndices = {11, 12, 13, 14, 15, 16, 23, 24};
      final landmarks = List<PoseLandmark>.generate(33, (index) {
        final visibility = index == 0
            ? 0.0 // Back-facing Lat Pulldown: nose is occluded
            : (upperBodyIndices.contains(index) ? 0.9 : 0.2);
        return PoseLandmark(
          index: index,
          x: 0.5,
          y: 0.5,
          z: 0.0,
          visibility: visibility,
        );
      });

      final confidence =
          WorkoutCvNotifier.computeFrameVisibilityConfidence(landmarks);
      expect(confidence, closeTo(0.9, 1e-6));
    });

    test('returns 0.0 when landmarks list is empty', () {
      expect(WorkoutCvNotifier.computeFrameVisibilityConfidence(const []), 0.0);
    });
  });

  group('CvFormSummary additive contract', () {
    test('toJson remains locked to exact 5 keys even with repTimeline/storyId',
        () {
      const base = CvFormSummary(
        validReps: 8,
        totalReps: 10,
        fastReps: 2,
        avgElbowAngleDeg: 43.5,
        avgTempoSec: 2.4,
        abortCount: 1,
      );
      final extended = base.copyWith(
        repTimeline: [
          {'rep_index': 1, 'start_sec': 1.0, 'end_sec': 3.2},
        ],
        videoStoryId: 'story_abc123',
      );

      expect(extended.repTimeline, hasLength(1));
      expect(extended.videoStoryId, 'story_abc123');
      expect(
        extended.toJson().keys.toSet(),
        equals({
          'valid_reps',
          'fast_reps',
          'avg_elbow_angle_deg',
          'avg_tempo_sec',
          'abort_count',
        }),
      );
    });
  });

  group('ExerciseSetLog repTimeline & videoStoryId serialization', () {
    test('legacy payload without repTimeline/videoStoryId omits optional keys',
        () {
      final log = ExerciseSetLog.fromJson({
        'exerciseId': 'ex_lat',
        'exerciseSlug': 'lat-pulldown',
        'setNumber': 1,
        'repsCompleted': 10,
        'weightKg': 45.0,
        'isCompleted': true,
      });

      expect(log.repTimeline, isNull);
      expect(log.videoStoryId, isNull);
      final json = log.toJson();
      expect(json.containsKey('repTimeline'), isFalse);
      expect(json.containsKey('videoStoryId'), isFalse);
    });

    test('reads snake_case and camelCase and serializes camelCase', () {
      final fromSnake = ExerciseSetLog.fromJson({
        'exerciseId': 'ex_lat',
        'exerciseSlug': 'lat-pulldown',
        'setNumber': 1,
        'repsCompleted': 8,
        'weightKg': 50.0,
        'isCompleted': true,
        'rep_timeline': [
          {'rep_index': 1, 'start_sec': 0.5, 'end_sec': 2.8},
        ],
        'video_story_id': 'vs_001',
      });

      expect(fromSnake.repTimeline, hasLength(1));
      expect(fromSnake.repTimeline!.first['rep_index'], 1);
      expect(fromSnake.videoStoryId, 'vs_001');

      final serialized = fromSnake.toJson();
      expect(serialized['repTimeline'], hasLength(1));
      expect(serialized['videoStoryId'], 'vs_001');

      final roundTrip = ExerciseSetLog.fromJson(serialized);
      expect(roundTrip.repTimeline, equals(fromSnake.repTimeline));
      expect(roundTrip.videoStoryId, 'vs_001');
    });
  });

  group('ActiveWorkoutSessionNotifier.attachCvFormSummary', () {
    test('stores cvFormSummary, repTimeline, and videoStoryId on target exercise',
        () {
      final notifier = ActiveWorkoutSessionNotifier(
        createDefaultUpperBodySession(),
      );

      notifier.attachCvFormSummary(
        'ex_2',
        const {'valid_reps': 10, 'fast_reps': 0},
        repTimeline: const [
          {'rep_index': 1, 'start_sec': 1.0, 'end_sec': 3.5},
        ],
        videoStoryId: 'story_99',
      );

      final updated =
          notifier.state.exercises.firstWhere((e) => e.id == 'ex_2');
      expect(updated.cvFormSummary, {'valid_reps': 10, 'fast_reps': 0});
      expect(updated.repTimeline, hasLength(1));
      expect(updated.videoStoryId, 'story_99');

      // Backward-compatible 2-argument call preserves existing behavior.
      notifier.attachCvFormSummary(
        'ex_1',
        const {'valid_reps': 8},
      );
      final ex1 = notifier.state.exercises.firstWhere((e) => e.id == 'ex_1');
      expect(ex1.cvFormSummary, {'valid_reps': 8});
      expect(ex1.repTimeline, isNull);
      expect(ex1.videoStoryId, isNull);
    });
  });
}

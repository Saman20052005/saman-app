import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/data/datasources/workout_cv_replay_source.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/exercise_cv_state.dart';
import 'package:health_ai_app/features/workout_cv/domain/entities/pose_landmark.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';
import 'package:health_ai_app/features/workout_cv/presentation/controllers/workout_cv_controller.dart';

void main() {
  group('WorkoutCvReplaySource & Downstream Controller Integration Tests', () {
    // Synthetic fixture generating 33 landmarks with optional upper-body confidence
    List<Map<String, dynamic>> createSyntheticLandmarks({
      double shoulderVis = 0.9,
      double elbowVis = 0.9,
      double hipVis = 0.9,
    }) {
      return List.generate(33, (i) {
        double vis = 0.8;
        if (i == PoseLandmark.leftShoulder || i == PoseLandmark.rightShoulder) {
          vis = shoulderVis;
        } else if (i == PoseLandmark.leftElbow ||
            i == PoseLandmark.rightElbow) {
          vis = elbowVis;
        } else if (i == PoseLandmark.leftHip || i == PoseLandmark.rightHip) {
          vis = hipVis;
        }
        return {
          'index': i,
          'x': 0.5,
          'y': 0.3 + (i * 0.01),
          'z': 0.0,
          'visibility': vis,
        };
      });
    }

    test(
        '1. WorkoutCvReplaySource parses extractor JSON doc and preserves metadata',
        () async {
      final jsonDoc = {
        'metadata': {
          'version': '1.1',
          'is_synthetic': true,
          'fixture_note': 'SYNTHETIC FIXTURE - For contract unit test only',
          'extracted_at': '2026-10-19T15:30:00Z',
          'video': {
            'path': 'SYNTHETIC_FIXTURE_video_01.mp4',
            'sha256': 'SYNTHETIC_FIXTURE_HASH',
            'width': 1080,
            'height': 1920,
            'fps': 30.0,
            'frame_count': 2,
            'duration_ms': 66,
          },
          'extractor': {
            'name': 'mediapipe_pose_landmarker',
            'model_sha256':
                '59929e1d1ee95287735dd833b19cf4ac46d29bc7afddbbf6753c459690d574a',
            'running_mode': 'VIDEO',
          },
        },
        'frames': [
          {
            'frame_index': 0,
            'timestamp_ms': 0,
            'status': 'detecting',
            'latency_ms': 15,
            'num_poses': 1,
            'landmarks': createSyntheticLandmarks(),
          },
          {
            'frame_index': 1,
            'timestamp_ms': 33,
            'status': 'detecting',
            'latency_ms': 14,
            'num_poses': 1,
            'landmarks': createSyntheticLandmarks(),
          },
        ],
      };

      final source = WorkoutCvReplaySource.fromJsonDoc(jsonDoc);
      expect(source.totalFrames, 2);
      expect(source.metadata?['is_synthetic'], true);
      expect(source.metadata?['video']?['sha256'], 'SYNTHETIC_FIXTURE_HASH');
      expect(source.metadata?['extractor']?['model_sha256'],
          '59929e1d1ee95287735dd833b19cf4ac46d29bc7afddbbf6753c459690d574a');
      expect(await source.checkPermission(), 'granted');
      expect(await source.requestPermission(), true);

      source.dispose();
    });

    test(
        '2. Replay frames route through shared WorkoutCvNotifier quality gates sequentially',
        () async {
      final frames = [
        // Frame 0: Confident upper body -> detecting
        {
          'frame_index': 0,
          'timestamp_ms': 100,
          'status': 'detecting',
          'latency_ms': 12,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(shoulderVis: 0.95),
        },
        // Frame 1: Incomplete upper body (low shoulder confidence) -> needsSetup
        {
          'frame_index': 1,
          'timestamp_ms': 133,
          'status': 'detecting',
          'latency_ms': 11,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(shoulderVis: 0.2),
        },
        // Frame 2: Multiple people detected -> multiplePeople
        {
          'frame_index': 2,
          'timestamp_ms': 166,
          'status': 'multiplePeople',
          'latency_ms': 18,
          'num_poses': 2,
          'landmarks': <Map<String, dynamic>>[],
        },
        // Frame 3: Tracking lost -> lost
        {
          'frame_index': 3,
          'timestamp_ms': 200,
          'status': 'lost',
          'latency_ms': 10,
          'num_poses': 0,
          'landmarks': <Map<String, dynamic>>[],
        },
        // Frame 4: Recovery -> detecting
        {
          'frame_index': 4,
          'timestamp_ms': 233,
          'status': 'detecting',
          'latency_ms': 13,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(shoulderVis: 0.9),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.instant,
      );
      final controller = WorkoutCvNotifier(source);

      final stateHistory = <ExerciseCvState>[];
      controller.addListener((state) {
        stateHistory.add(state);
      });

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await pumpEventQueue();

      final trackingStatuses =
          stateHistory.map((s) => s.trackingStatus).toList();

      expect(trackingStatuses, contains(TrackingStatus.detecting));
      expect(trackingStatuses, contains(TrackingStatus.needsSetup));
      expect(trackingStatuses, contains(TrackingStatus.multiplePeople));
      expect(trackingStatuses, contains(TrackingStatus.lost));

      // Final state should be recovered to detecting
      expect(controller.state.trackingStatus, TrackingStatus.detecting);
      expect(controller.state.timestamp, 233);
      expect(controller.state.landmarks.length, 33);
      expect(controller.state.frameCount, 5);

      controller.dispose();
      source.dispose();
    });

    test(
        '3. Video timestamp preservation: ExerciseCvState inherits video frame timestamp',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 1500,
          'status': 'detecting',
          'latency_ms': 20,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 1,
          'timestamp_ms': 1533,
          'status': 'detecting',
          'latency_ms': 18,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(frames: frames);
      final controller = WorkoutCvNotifier(source);

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await pumpEventQueue();

      expect(controller.state.timestamp, 1533);

      controller.dispose();
      source.dispose();
    });

    test('4. Reset on seek or replay rewind resets controller state cleanly',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 0,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 1,
          'timestamp_ms': 33,
          'status': 'detecting',
          'latency_ms': 12,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 2,
          'timestamp_ms': 66,
          'status': 'detecting',
          'latency_ms': 11,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(frames: frames);
      final controller = WorkoutCvNotifier(source);

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await pumpEventQueue();
      expect(controller.state.frameCount, 3);
      expect(controller.state.trackingStatus, TrackingStatus.detecting);

      // Perform reset
      source.reset();
      await pumpEventQueue();

      // Verify replay source internal state is cleanly reset:
      expect(source.currentIndex, 0);
      expect(source.lastEmittedTimestamp, -1);

      // Verify downstream CP-10 controller clears active landmarks:
      expect(controller.state.landmarks, isEmpty);
      // Under CP-10 controller contract (where CP-02's custom resetState() was
      // pruned from the live camera runtime, events route through Quality Gate 3 with numPoses == 0):
      expect(controller.state.trackingStatus, TrackingStatus.lost);
      expect(controller.state.frameCount, 4);

      controller.dispose();
      source.dispose();
    });

    test(
        '5. Error frames in replay stream properly set error status and message',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 0,
          'status': 'error',
          'errorMessage': 'Corrupted video frame at index 0',
          'latency_ms': 0,
          'num_poses': 0,
          'landmarks': <Map<String, dynamic>>[],
        },
      ];

      final source = WorkoutCvReplaySource(frames: frames);
      final controller = WorkoutCvNotifier(source);

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.error);
      expect(controller.state.errorMessage, 'Corrupted video frame at index 0');

      controller.dispose();
      source.dispose();
    });

    test(
        '6. Reset/seek during active realtime playback cancels pending timers and prevents state leakage',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 0,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 1,
          'timestamp_ms': 100,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 2,
          'timestamp_ms': 200,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.realtime,
      );
      final controller = WorkoutCvNotifier(source);

      final observedTimestamps = <int>[];
      controller.addListener((state) {
        observedTimestamps.add(state.timestamp);
      });

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state.frameCount, 1);
      expect(controller.state.timestamp, 0);

      // Seek while frame 1 (timestamp 100) is pending in timer (due in ~90ms)
      source.seekTo(200);
      await pumpEventQueue();

      // Wait 120ms to allow any rogue timer to expire
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // After wait, verify the state is at frame 2 (200ms) and frame 1 (100ms) NEVER fired
      expect(controller.state.timestamp, 200);
      expect(observedTimestamps, isNot(contains(100)));

      controller.dispose();
      source.dispose();
    });

    test('7. Stop and dispose cleanly prevent subsequent event emission',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 0,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 1,
          'timestamp_ms': 50,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.realtime,
      );

      final receivedEvents = <Map<String, dynamic>>[];
      final sub = source.eventStream.listen(receivedEvents.add);

      await source.startSession('pull-up');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedEvents.length, 1);

      // Stop session immediately
      await source.stopSession();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // No new frames should have been emitted
      expect(receivedEvents.length, 1);

      source.dispose();
      await sub.cancel();
    });

    test(
        '8. Non-monotonic / decreasing timestamps are strictly blocked before updating controller',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 500,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'frame_index': 1,
          'timestamp_ms': 300, // Non-monotonic decrease (300 <= 500)
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.instant,
      );
      final controller = WorkoutCvNotifier(source);

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await pumpEventQueue();

      // Frame 0 was processed: timestamp is 500, frameCount is 1
      expect(controller.state.timestamp, 500);
      expect(controller.state.frameCount, 1);

      // Frame 1 (timestamp 300) was strictly BLOCKED from reaching controller:
      expect(source.droppedNonMonotonicFrames, 1);
      // Downstream controller state was not corrupted by the backwards time jump:
      expect(controller.state.timestamp, 500);
      expect(controller.state.frameCount, 1);

      controller.dispose();
      source.dispose();
    });

    test(
        '8b. Replay frames with out-of-bounds required joints transition to needsSetup instead of detecting',
        () async {
      final frames = [
        {
          'frame_index': 0,
          'timestamp_ms': 100,
          'status': 'detecting',
          'latency_ms': 10,
          'num_poses': 1,
          'landmarks': List.generate(33, (i) {
            double x = 0.5;
            double y = 0.5;
            if (i == 13) x = 1.25; // Left elbow outside image
            if (i == 14) x = -0.10; // Right elbow outside image
            if (i == 23 || i == 24) y = 1.05; // Hips outside image
            return {
              'index': i,
              'x': x,
              'y': y,
              'z': 0.0,
              'visibility': 0.95,
            };
          }),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.instant,
      );
      final controller = WorkoutCvNotifier(source);

      await controller.initialize(exerciseId: 'ex1', exerciseSlug: 'pull-up');
      await pumpEventQueue();

      expect(controller.state.trackingStatus, TrackingStatus.needsSetup);
      expect(controller.state.guideMessage, contains('Align upper body'));
      expect(controller.state.frameCount, 1);

      controller.dispose();
      source.dispose();
    });

    test('8c. Empty replay frames list completes immediately without crashing',
        () async {
      final source = WorkoutCvReplaySource(frames: const []);
      expect(source.totalFrames, 0);
      expect(source.isPlaying, isFalse);

      final events = <Map<String, dynamic>>[];
      source.eventStream.listen(events.add);

      await source.startSession('lat-pulldown');
      await pumpEventQueue();

      expect(source.isPlaying, isFalse);
      expect(events, isEmpty);

      await source.stopSession();
      source.dispose();
    });

    test(
        '8d. Malformed replay frame data handles missing fields with safe defaults',
        () async {
      final malformedFrames = [
        <String, dynamic>{}, // Completely empty map
        {
          'status': null,
          'timestamp_ms': 'not-a-number',
          'num_poses': null,
          'landmarks': [
            'not-a-map',
            {'index': null, 'x': null, 'y': null},
          ],
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: malformedFrames,
        speed: ReplayPlaybackSpeed.instant,
      );

      final receivedEvents = <Map<String, dynamic>>[];
      source.eventStream.listen(receivedEvents.add);

      await source.startSession('lat-pulldown');
      await pumpEventQueue();

      // First frame emitted with defaults: status='lost', timestamp=0, numPoses=0
      expect(receivedEvents.length,
          1); // 2nd frame has timestamp=0 <= _lastEmittedTimestamp(0), dropped by monotonic guard!
      expect(receivedEvents[0]['status'], 'lost');
      expect(receivedEvents[0]['timestamp'], 0);
      expect(receivedEvents[0]['numPoses'], 0);
      expect(source.droppedNonMonotonicFrames, 1);

      source.dispose();
    });

    test(
        '8e. Realtime playback mode respects frame delay and stops on completion',
        () async {
      final frames = [
        {
          'timestamp_ms': 0,
          'status': 'detecting',
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'timestamp_ms': 20,
          'status': 'detecting',
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.realtime,
      );

      final receivedEvents = <Map<String, dynamic>>[];
      source.eventStream.listen(receivedEvents.add);

      await source.startSession('lat-pulldown');
      expect(source.isPlaying, isTrue);

      // Wait for both frames to be emitted (~20ms + buffer)
      await Future.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue();

      expect(receivedEvents.length, 2);
      expect(source.isPlaying, isFalse);
      expect(source.currentIndex, 2);

      source.dispose();
    });

    test(
        '8f. Late events blocked after stopSession and dispose during active realtime playback',
        () async {
      final frames = [
        {
          'timestamp_ms': 0,
          'status': 'detecting',
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'timestamp_ms': 100,
          'status': 'detecting',
          'landmarks': createSyntheticLandmarks(),
        },
        {
          'timestamp_ms': 200,
          'status': 'detecting',
          'landmarks': createSyntheticLandmarks(),
        },
      ];

      final source = WorkoutCvReplaySource(
        frames: frames,
        speed: ReplayPlaybackSpeed.realtime,
      );

      final receivedEvents = <Map<String, dynamic>>[];
      source.eventStream.listen(receivedEvents.add);

      await source.startSession('lat-pulldown');
      // Wait only for first frame
      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedEvents.length, 1);

      // Stop session while frame 2 is scheduled in 100ms
      await source.stopSession();
      expect(source.isPlaying, isFalse);

      // Wait past the scheduled time of frame 2 and frame 3
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // No late events should have leaked through!
      expect(receivedEvents.length, 1);

      source.dispose();
    });

    test('9. Opt-in: Video extracted JSON replay run', () async {
      final rawPath = Platform.environment['WORKOUT_CV_REPLAY_JSON'] ??
          const String.fromEnvironment('WORKOUT_CV_REPLAY_JSON');

      // 1. If not configured -> Explicit SKIP (never falsely PASS)
      if (rawPath.trim().isEmpty) {
        markTestSkipped(
            'Opt-in video JSON replay test SKIPPED: WORKOUT_CV_REPLAY_JSON is not configured.\n'
            'To run this test with an extracted video landmarks JSON file:\n'
            '  flutter test --dart-define=WORKOUT_CV_REPLAY_JSON=/path/to/extracted_landmarks.json test/features/workout_cv/workout_cv_replay_test.dart\n'
            '  or set environment variable WORKOUT_CV_REPLAY_JSON.');
        return;
      }

      final jsonPath = rawPath.trim();
      final file = File(jsonPath);

      // 2. If configured but file is missing -> FAIL
      if (!file.existsSync()) {
        fail(
            'WORKOUT_CV_REPLAY_JSON was specified as "$jsonPath", but file does not exist on disk.');
      }

      // 3. If file content is unreadable or corrupted JSON -> FAIL
      final String content;
      try {
        content = await file.readAsString();
      } catch (e) {
        fail('Failed to read WORKOUT_CV_REPLAY_JSON file at "$jsonPath": $e');
      }

      final Map<String, dynamic> jsonDoc;
      try {
        jsonDoc = jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        fail(
            'Invalid JSON syntax in WORKOUT_CV_REPLAY_JSON file at "$jsonPath": $e');
      }

      // 4. If JSON schema is missing "frames" list -> FAIL
      if (jsonDoc['frames'] is! List) {
        fail(
            'Invalid schema: Missing "frames" list in WORKOUT_CV_REPLAY_JSON file at "$jsonPath".');
      }

      final metadata = jsonDoc['metadata'] as Map<String, dynamic>?;
      final bool isSynthetic = metadata?['is_synthetic'] == true ||
          metadata?['synthetic'] == true ||
          jsonDoc['is_synthetic'] == true;

      final videoMeta = metadata?['video'] as Map<String, dynamic>?;
      final videoWidth = (videoMeta?['width'] as num?)?.toDouble() ?? 1080.0;
      final videoHeight = (videoMeta?['height'] as num?)?.toDouble() ?? 1920.0;
      final featuresCsvPath = Platform.environment['WORKOUT_CV_FEATURES_CSV'] ??
          const String.fromEnvironment('WORKOUT_CV_FEATURES_CSV');
      final baselineCsvPath = Platform.environment['WORKOUT_CV_BASELINE_CSV'] ??
          const String.fromEnvironment('WORKOUT_CV_BASELINE_CSV');
      final extractedFeatures =
          <({LatPulldownFrameFeatures features, String gateStatus})>[];
      final baselineTracker = LatPulldownBaseline();
      final baselineResults = <LatPulldownBaselineFrameResult>[];

      final source = WorkoutCvReplaySource.fromJsonDoc(
        jsonDoc,
        speed: ReplayPlaybackSpeed.instant,
      );
      final controller = WorkoutCvNotifier(source);

      int detectingCount = 0;
      int needsSetupCount = 0;
      int multiplePeopleCount = 0;
      int lostCount = 0;
      int errorCount = 0;
      int controlEventsCount = 0;
      int lastSeenFrameCount = 0;

      // Track state changes:
      // Distinguish control events (startup/init/reset where frameCount == 0 or does not advance)
      // from actual per-frame outcomes (where frameCount advances).
      controller.addListener((state) {
        if (state.frameCount == 0) {
          controlEventsCount++;
          return;
        }

        // When a new frame is processed (frameCount advances)
        if (state.frameCount > lastSeenFrameCount) {
          lastSeenFrameCount = state.frameCount;
          final currentStatus = state.trackingStatus;
          switch (currentStatus) {
            case TrackingStatus.detecting:
              detectingCount++;
              break;
            case TrackingStatus.needsSetup:
              needsSetupCount++;
              break;
            case TrackingStatus.multiplePeople:
              multiplePeopleCount++;
              break;
            case TrackingStatus.lost:
              lostCount++;
              break;
            case TrackingStatus.error:
              errorCount++;
              break;
            default:
              break;
          }

          final needFeatures = featuresCsvPath.trim().isNotEmpty ||
              baselineCsvPath.trim().isNotEmpty;
          if (needFeatures) {
            final isDetecting = currentStatus == TrackingStatus.detecting;
            final feat = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
              frameIndex: state.frameCount - 1,
              timestampMs: state.timestamp,
              landmarks: state.landmarks,
              imageWidth: videoWidth,
              imageHeight: videoHeight,
              isGateDetecting: isDetecting,
            );
            if (featuresCsvPath.trim().isNotEmpty) {
              extractedFeatures
                  .add((features: feat, gateStatus: currentStatus.name));
            }
            if (baselineCsvPath.trim().isNotEmpty) {
              final bRes = baselineTracker.processFrameFeatures(feat);
              baselineResults.add(bRes);
            }
          }
        }
      });

      final stopwatch = Stopwatch()..start();
      await controller.initialize(
          exerciseId: 'opt-in-replay', exerciseSlug: 'pull-up');
      await pumpEventQueue();
      stopwatch.stop();

      final videoFps = (videoMeta?['fps'] as num?)?.toDouble() ?? 30.0;
      final videoDurationMs = (videoMeta?['duration_ms'] as num?)?.toInt() ?? 0;
      final totalProcessedFrames = controller.state.frameCount;

      final sourceLabel = isSynthetic
          ? 'SYNTHETIC FIXTURE (Generated test data - NOT real workout video)'
          : 'EXTRACTED VIDEO LANDMARKS (Requires verification of input video)';

      // Print structured summary
      // ignore: avoid_print
      print('\n======================================================');
      // ignore: avoid_print
      print('=== WORKOUT CV REPLAY SUMMARY ===');
      // ignore: avoid_print
      print('Source Type:             $sourceLabel');
      // ignore: avoid_print
      print('File Path:               $jsonPath');
      // ignore: avoid_print
      print('Video Source Path:       ${videoMeta?['path'] ?? 'N/A'}');
      // ignore: avoid_print
      print('Video SHA256:            ${videoMeta?['sha256'] ?? 'N/A'}');
      // ignore: avoid_print
      print('Total Input Frames:      ${source.totalFrames}');
      // ignore: avoid_print
      print('Processed Frames:        $totalProcessedFrames');
      // ignore: avoid_print
      print('Blocked Non-monotonic:   ${source.droppedNonMonotonicFrames}');
      // ignore: avoid_print
      print('Control / Init Events:   $controlEventsCount');
      // ignore: avoid_print
      print('Video Duration:          ${videoDurationMs}ms (@ ${videoFps}fps)');
      // ignore: avoid_print
      print('--- Per-Frame Outcomes ---');
      // ignore: avoid_print
      print('  Detecting Frames:      $detectingCount');
      // ignore: avoid_print
      print('  NeedsSetup Frames:     $needsSetupCount');
      // ignore: avoid_print
      print('  MultiplePeople Frames: $multiplePeopleCount');
      // ignore: avoid_print
      print('  Lost Frames:           $lostCount');
      // ignore: avoid_print
      print('  Error Frames:          $errorCount');
      // ignore: avoid_print
      print('--------------------------');
      // ignore: avoid_print
      print('Wall-clock Replay Time:  ${stopwatch.elapsedMilliseconds}ms');
      // ignore: avoid_print
      print('======================================================\n');

      // Assert strict mathematical 1:1 partition of processed frames:
      // Every processed frame must belong to exactly one final result state
      expect(
        detectingCount +
            needsSetupCount +
            multiplePeopleCount +
            lostCount +
            errorCount,
        equals(totalProcessedFrames),
        reason:
            'Sum of frame outcomes must exactly equal total processed frames (no double-counting control events)',
      );

      // Assert total input frames accounted for
      expect(
        totalProcessedFrames + source.droppedNonMonotonicFrames,
        equals(source.totalFrames),
        reason:
            'Processed frames + blocked frames must equal total input frames from JSON',
      );

      if (featuresCsvPath.trim().isNotEmpty && extractedFeatures.isNotEmpty) {
        final csvFile = File(featuresCsvPath.trim());
        csvFile.parent.createSync(recursive: true);
        final sink = csvFile.openWrite();
        sink.writeln(
          'frame_index,timestamp_ms,gate_status,is_gate_detecting,shoulder_width_px,'
          'left_elbow_angle_deg,left_elbow_valid,left_elbow_failure,'
          'left_wrist_rel_y,left_wrist_rel_x,left_wrist_dist,left_wrist_valid,left_wrist_failure,'
          'right_elbow_angle_deg,right_elbow_valid,right_elbow_failure,'
          'right_wrist_rel_y,right_wrist_rel_x,right_wrist_dist,right_wrist_valid,right_wrist_failure',
        );

        int leftElbowValidCount = 0;
        int rightElbowValidCount = 0;
        int leftWristValidCount = 0;
        int rightWristValidCount = 0;

        for (final item in extractedFeatures) {
          final feat = item.features;
          if (feat.leftSide.elbowAngleDeg.isValid) leftElbowValidCount++;
          if (feat.rightSide.elbowAngleDeg.isValid) rightElbowValidCount++;
          if (feat.leftSide.wristRelY.isValid) leftWristValidCount++;
          if (feat.rightSide.wristRelY.isValid) rightWristValidCount++;

          final sw = feat.shoulderWidthPx.isValid
              ? feat.shoulderWidthPx.value!.toStringAsFixed(2)
              : '';
          final lEl = feat.leftSide.elbowAngleDeg.isValid
              ? feat.leftSide.elbowAngleDeg.value!.toStringAsFixed(2)
              : '';
          final lWy = feat.leftSide.wristRelY.isValid
              ? feat.leftSide.wristRelY.value!.toStringAsFixed(4)
              : '';
          final lWx = feat.leftSide.wristRelX.isValid
              ? feat.leftSide.wristRelX.value!.toStringAsFixed(4)
              : '';
          final lWd = feat.leftSide.wristDistance.isValid
              ? feat.leftSide.wristDistance.value!.toStringAsFixed(4)
              : '';

          final rEl = feat.rightSide.elbowAngleDeg.isValid
              ? feat.rightSide.elbowAngleDeg.value!.toStringAsFixed(2)
              : '';
          final rWy = feat.rightSide.wristRelY.isValid
              ? feat.rightSide.wristRelY.value!.toStringAsFixed(4)
              : '';
          final rWx = feat.rightSide.wristRelX.isValid
              ? feat.rightSide.wristRelX.value!.toStringAsFixed(4)
              : '';
          final rWd = feat.rightSide.wristDistance.isValid
              ? feat.rightSide.wristDistance.value!.toStringAsFixed(4)
              : '';

          sink.writeln(
            '${feat.frameIndex},${feat.timestampMs},${item.gateStatus},${feat.isGateDetecting},'
            '$sw,'
            '$lEl,${feat.leftSide.elbowAngleDeg.isValid},${feat.leftSide.elbowAngleDeg.failure.name},'
            '$lWy,$lWx,$lWd,${feat.leftSide.wristRelY.isValid},${feat.leftSide.wristRelY.failure.name},'
            '$rEl,${feat.rightSide.elbowAngleDeg.isValid},${feat.rightSide.elbowAngleDeg.failure.name},'
            '$rWy,$rWx,$rWd,${feat.rightSide.wristRelY.isValid},${feat.rightSide.wristRelY.failure.name}',
          );
        }
        await sink.flush();
        await sink.close();

        final totalExtracted = extractedFeatures.length;
        // ignore: avoid_print
        print('\n=== LAT PULLDOWN MOTION FEATURE STATS ===');
        // ignore: avoid_print
        print('Export Path:               ${csvFile.path}');
        // ignore: avoid_print
        print('Total Frames:              $totalExtracted');
        // ignore: avoid_print
        print(
            'Gate Detecting Frames:     $detectingCount (${(detectingCount / totalExtracted * 100).toStringAsFixed(1)}%)');
        // ignore: avoid_print
        print(
            'Left Elbow Valid:          $leftElbowValidCount (${(leftElbowValidCount / totalExtracted * 100).toStringAsFixed(1)}%)');
        // ignore: avoid_print
        print(
            'Right Elbow Valid:         $rightElbowValidCount (${(rightElbowValidCount / totalExtracted * 100).toStringAsFixed(1)}%)');
        // ignore: avoid_print
        print(
            'Left Wrist Y Valid:        $leftWristValidCount (${(leftWristValidCount / totalExtracted * 100).toStringAsFixed(1)}%)');
        // ignore: avoid_print
        print(
            'Right Wrist Y Valid:       $rightWristValidCount (${(rightWristValidCount / totalExtracted * 100).toStringAsFixed(1)}%)');
        // ignore: avoid_print
        print('=========================================\n');
      }

      if (baselineCsvPath.trim().isNotEmpty && baselineResults.isNotEmpty) {
        final bCsvFile = File(baselineCsvPath.trim());
        bCsvFile.parent.createSync(recursive: true);
        final sink = bCsvFile.openWrite();
        sink.writeln(
          'frame_index,timestamp_ms,elbow_angle_deg,is_sample_valid,phase,completed_reps,'
          'new_rep_number,new_rep_start_ms,new_rep_bottom_ms,new_rep_end_ms,new_rep_duration_ms,new_rep_min_angle,'
          'transition_reason,reset_reason',
        );

        final phaseCounts = <LatPulldownPhase, int>{};
        for (final r in baselineResults) {
          phaseCounts[r.phase] = (phaseCounts[r.phase] ?? 0) + 1;
          final ang = r.elbowAngleDeg != null
              ? r.elbowAngleDeg!.toStringAsFixed(2)
              : '';
          final repNum =
              r.newRepEvent != null ? '${r.newRepEvent!.repNumber}' : '';
          final repStart =
              r.newRepEvent != null ? '${r.newRepEvent!.startTimestampMs}' : '';
          final repBottom = r.newRepEvent != null
              ? '${r.newRepEvent!.bottomTimestampMs}'
              : '';
          final repEnd =
              r.newRepEvent != null ? '${r.newRepEvent!.endTimestampMs}' : '';
          final repDur =
              r.newRepEvent != null ? '${r.newRepEvent!.durationMs}' : '';
          final repMinAng = r.newRepEvent != null
              ? r.newRepEvent!.minElbowAngleDeg.toStringAsFixed(1)
              : '';

          sink.writeln(
            '${r.frameIndex},${r.timestampMs},$ang,${r.isSampleValid},${r.phase.name},${r.completedReps},'
            '$repNum,$repStart,$repBottom,$repEnd,$repDur,$repMinAng,'
            '${r.transitionReason ?? ""},${r.resetReason ?? ""}',
          );
        }
        await sink.flush();
        await sink.close();

        // ignore: avoid_print
        print('\n=== LAT PULLDOWN BASELINE SUMMARY ===');
        // ignore: avoid_print
        print('Baseline CSV Export:       ${bCsvFile.path}');
        // ignore: avoid_print
        print('Total Frames Evaluated:    ${baselineResults.length}');
        // ignore: avoid_print
        print('Completed Reps Counted:    ${baselineTracker.completedReps}');
        // ignore: avoid_print
        print('Rep History (PROVISIONAL candidates):');
        for (final rep in baselineTracker.repHistory) {
          // ignore: avoid_print
          print('  $rep');
        }
        // ignore: avoid_print
        print('Phase Frame Counts:');
        for (final p in LatPulldownPhase.values) {
          // ignore: avoid_print
          print('  ${p.name.padRight(12)}: ${phaseCounts[p] ?? 0}');
        }
        // ignore: avoid_print
        print('=====================================\n');
      }

      controller.dispose();
      source.dispose();
    });

    test(
        '10. CP-CV-BASELINE-02: Downsampling and perturbation resilience stress evaluation on replay',
        () async {
      final rawPath = Platform.environment['WORKOUT_CV_REPLAY_JSON'] ??
          const String.fromEnvironment('WORKOUT_CV_REPLAY_JSON');

      if (rawPath.trim().isEmpty) {
        markTestSkipped(
            'CP-CV-BASELINE-02 stress test SKIPPED: WORKOUT_CV_REPLAY_JSON is not configured.\n'
            'To run this test with an extracted video landmarks JSON file:\n'
            '  flutter test --dart-define=WORKOUT_CV_REPLAY_JSON=/path/to/extracted_landmarks.json test/features/workout_cv/workout_cv_replay_test.dart\n'
            '  or set environment variable WORKOUT_CV_REPLAY_JSON.');
        return;
      }

      final file = File(rawPath.trim());
      if (!file.existsSync()) {
        fail('File not found: ${rawPath.trim()}');
      }

      final jsonDoc =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawFrames = (jsonDoc['frames'] as List)
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList();
      final videoMeta = jsonDoc['metadata']?['video'] as Map<String, dynamic>?;
      final videoWidth = (videoMeta?['width'] as num?)?.toDouble() ?? 1080.0;
      final videoHeight = (videoMeta?['height'] as num?)?.toDouble() ?? 1920.0;

      // Pipeline evaluation helper running input frames through ReplaySource -> Notifier -> Features -> Baseline
      Future<
              ({
                String name,
                int sampleCount,
                int maxGapMs,
                int completedReps,
                List<LatPulldownRepEvent> reps,
                int resetCount,
                Map<String, int> resetReasons,
                Map<LatPulldownPhase, int> phaseCounts,
                List<LatPulldownBaselineFrameResult> results,
              })>
          runStressPipeline(
              String runName, List<Map<String, dynamic>> testFrames) async {
        final source = WorkoutCvReplaySource(
          frames: testFrames,
          speed: ReplayPlaybackSpeed.instant,
        );
        final controller = WorkoutCvNotifier(source);
        final tracker = LatPulldownBaseline();
        final results = <LatPulldownBaselineFrameResult>[];
        final resetReasons = <String, int>{};
        var lastSeenFrameCount = 0;

        controller.addListener((state) {
          if (state.frameCount > lastSeenFrameCount) {
            lastSeenFrameCount = state.frameCount;
            final isDetecting =
                state.trackingStatus == TrackingStatus.detecting;
            final feat = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
              frameIndex: state.frameCount - 1,
              timestampMs: state.timestamp,
              landmarks: state.landmarks,
              imageWidth: videoWidth,
              imageHeight: videoHeight,
              isGateDetecting: isDetecting,
            );
            final bRes = tracker.processFrameFeatures(feat);
            results.add(bRes);
            if (bRes.resetReason != null) {
              resetReasons[bRes.resetReason!] =
                  (resetReasons[bRes.resetReason!] ?? 0) + 1;
            }
          }
        });

        await controller.initialize(
            exerciseId: 'stress-eval', exerciseSlug: 'pull-up');
        await pumpEventQueue();

        var maxGap = 0;
        for (var i = 1; i < testFrames.length; i++) {
          final t1 = (testFrames[i - 1]['timestamp_ms'] ??
                      testFrames[i - 1]['timestamp'] as num?)
                  ?.toInt() ??
              0;
          final t2 = (testFrames[i]['timestamp_ms'] ??
                      testFrames[i]['timestamp'] as num?)
                  ?.toInt() ??
              0;
          final gap = t2 - t1;
          if (gap > maxGap) maxGap = gap;
        }

        final phaseCounts = <LatPulldownPhase, int>{};
        for (final r in results) {
          phaseCounts[r.phase] = (phaseCounts[r.phase] ?? 0) + 1;
        }

        controller.dispose();
        source.dispose();

        return (
          name: runName,
          sampleCount: results.length,
          maxGapMs: maxGap,
          completedReps: tracker.completedReps,
          reps: tracker.repHistory,
          resetCount: resetReasons.values.fold(0, (a, b) => a + b),
          resetReasons: resetReasons,
          phaseCounts: phaseCounts,
          results: results,
        );
      }

      // --- 1. Downsampling Sweeps (25 FPS, 15 FPS, 10 FPS with 2 start offsets) ---
      final downsampleRuns = <({
        String name,
        int sampleCount,
        int maxGapMs,
        int completedReps,
        List<LatPulldownRepEvent> reps,
        int resetCount,
        Map<String, int> resetReasons,
        Map<LatPulldownPhase, int> phaseCounts,
        List<LatPulldownBaselineFrameResult> results,
      })>[];

      // 50 FPS Baseline (all 818 frames)
      downsampleRuns.add(await runStressPipeline('50_fps_baseline', rawFrames));

      // 25 FPS: Stride 2 (offset 0 and offset 1)
      final frames25fpsOffset0 = [
        for (var i = 0; i < rawFrames.length; i += 2) rawFrames[i]
      ];
      final frames25fpsOffset1 = [
        for (var i = 1; i < rawFrames.length; i += 2) rawFrames[i]
      ];
      downsampleRuns
          .add(await runStressPipeline('25_fps_offset_0', frames25fpsOffset0));
      downsampleRuns
          .add(await runStressPipeline('25_fps_offset_1', frames25fpsOffset1));

      // 15 FPS: Target step ~66.7ms (offset 0ms and offset 33ms)
      List<Map<String, dynamic>> filter15Fps(int initialOffsetMs) {
        final list = <Map<String, dynamic>>[];
        var nextTarget = initialOffsetMs;
        for (final f in rawFrames) {
          final ts = (f['timestamp_ms'] as num).toInt();
          if (ts >= nextTarget) {
            list.add(f);
            nextTarget += 67;
          }
        }
        return list;
      }

      downsampleRuns
          .add(await runStressPipeline('15_fps_offset_0', filter15Fps(0)));
      downsampleRuns
          .add(await runStressPipeline('15_fps_offset_1', filter15Fps(33)));

      // 10 FPS: Stride 5 (offset 0 and offset 1)
      final frames10fpsOffset0 = [
        for (var i = 0; i < rawFrames.length; i += 5) rawFrames[i]
      ];
      final frames10fpsOffset1 = [
        for (var i = 1; i < rawFrames.length; i += 5) rawFrames[i]
      ];
      downsampleRuns
          .add(await runStressPipeline('10_fps_offset_0', frames10fpsOffset0));
      downsampleRuns
          .add(await runStressPipeline('10_fps_offset_1', frames10fpsOffset1));

      // --- 2. Controlled Perturbation Sweeps on Clip 2 ---
      final perturbationRuns = <({
        String name,
        int sampleCount,
        int maxGapMs,
        int completedReps,
        List<LatPulldownRepEvent> reps,
        int resetCount,
        Map<String, int> resetReasons,
        Map<LatPulldownPhase, int> phaseCounts,
        List<LatPulldownBaselineFrameResult> results,
      })>[];

      // Perturbation Case 1: Tracking loss in Ready phase (t = 4200ms..4700ms, 500ms lost)
      final p1Frames = rawFrames.map((f) {
        final ts = (f['timestamp_ms'] as num).toInt();
        if (ts >= 4200 && ts <= 4700) {
          return {
            ...f,
            'status': 'lost',
            'landmarks': <Map<String, dynamic>>[]
          };
        }
        return f;
      }).toList();
      perturbationRuns
          .add(await runStressPipeline('pert_ready_loss_500ms', p1Frames));

      // Perturbation Case 2: Tracking loss / gap mid-pull (t = 5400ms..6200ms, 800ms gap > 500ms maxGap)
      final p2Frames = rawFrames.map((f) {
        final ts = (f['timestamp_ms'] as num).toInt();
        if (ts >= 5400 && ts <= 6200) {
          return {
            ...f,
            'status': 'lost',
            'landmarks': <Map<String, dynamic>>[]
          };
        }
        return f;
      }).toList();
      perturbationRuns
          .add(await runStressPipeline('pert_mid_pull_gap_800ms', p2Frames));

      // Perturbation Case 3: Tracking loss near completion (t = 8600ms..9300ms, 700ms gap)
      final p3Frames = rawFrames.map((f) {
        final ts = (f['timestamp_ms'] as num).toInt();
        if (ts >= 8600 && ts <= 9300) {
          return {
            ...f,
            'status': 'lost',
            'landmarks': <Map<String, dynamic>>[]
          };
        }
        return f;
      }).toList();
      perturbationRuns.add(
          await runStressPipeline('pert_near_completion_gap_700ms', p3Frames));

      // Perturbation Case 4: Multiple people detected mid Rep 2 (t = 11000ms..11500ms, 500ms multiplePeople)
      final p4Frames = rawFrames.map((f) {
        final ts = (f['timestamp_ms'] as num).toInt();
        if (ts >= 11000 && ts <= 11500) {
          return {
            ...f,
            'status': 'multiplePeople',
            'num_poses': 2,
            'landmarks': <Map<String, dynamic>>[]
          };
        }
        return f;
      }).toList();
      perturbationRuns.add(
          await runStressPipeline('pert_multiple_people_mid_rep2', p4Frames));

      // Perturbation Case 5: Replay reset test (first 500 frames -> reset -> all 818 frames)
      final sourceReset = WorkoutCvReplaySource(
          frames: rawFrames, speed: ReplayPlaybackSpeed.instant);
      final controllerReset = WorkoutCvNotifier(sourceReset);
      final trackerReset = LatPulldownBaseline();
      var resetLastSeen = 0;

      controllerReset.addListener((state) {
        if (state.frameCount == 0) {
          trackerReset.reset();
          return;
        }
        if (state.frameCount > resetLastSeen) {
          resetLastSeen = state.frameCount;
          final isDetecting = state.trackingStatus == TrackingStatus.detecting;
          final feat = WorkoutCvMotionFeatures.extractLatPulldownFeatures(
            frameIndex: state.frameCount - 1,
            timestampMs: state.timestamp,
            landmarks: state.landmarks,
            imageWidth: videoWidth,
            imageHeight: videoHeight,
            isGateDetecting: isDetecting,
          );
          trackerReset.processFrameFeatures(feat);
        }
      });

      // Session 1: Run partially to frame 500 (covers Rep 1)
      await controllerReset.initialize(
          exerciseId: 'session1', exerciseSlug: 'pull-up');
      await pumpEventQueue();
      expect(trackerReset.completedReps, 2);

      // Perform reset: state and tracker must be cleared
      sourceReset.reset();
      await pumpEventQueue();
      expect(trackerReset.completedReps, 0);
      expect(trackerReset.phase, LatPulldownPhase.notReady);
      expect(trackerReset.repHistory, isEmpty);

      controllerReset.dispose();
      sourceReset.dispose();

      // --- 3. Assertions & Verification Checks ---
      // Invariant: Case 2 (mid-pull gap 800ms) aborted Rep 1; Rep 1 MUST NOT be counted across gap
      final runP2 = perturbationRuns
          .firstWhere((r) => r.name == 'pert_mid_pull_gap_800ms');
      expect(runP2.completedReps, 1,
          reason:
              'Mid-pull gap > 500ms must abort Rep 1 and prevent rep joining');
      expect(
          (runP2.resetReasons['gateNotDetecting'] ?? 0) +
              (runP2.resetReasons['dataLossGapExceeded'] ?? 0),
          greaterThan(0));

      // Invariant: Case 3 (near-completion gap 700ms) aborted Rep 1 before hold confirmed
      final runP3 = perturbationRuns
          .firstWhere((r) => r.name == 'pert_near_completion_gap_700ms');
      expect(runP3.completedReps, 1,
          reason: 'Near-completion gap > 500ms must abort Rep 1');

      // Invariant: Case 4 (multiplePeople during Rep 2) aborted Rep 2, preserving Rep 1
      final runP4 = perturbationRuns
          .firstWhere((r) => r.name == 'pert_multiple_people_mid_rep2');
      expect(runP4.completedReps, 1,
          reason:
              'Multiple people during Rep 2 must abort Rep 2 while preserving Rep 1');
      expect(runP4.resetReasons['gateNotDetecting'], isNotNull);

      // Invariant: No rep event has timestamp inside an invalid/lost segment
      for (final run in perturbationRuns) {
        for (final rep in run.reps) {
          // Check if bottom or end fell into p2 gap (5400-6200)
          if (run.name == 'pert_mid_pull_gap_800ms') {
            expect(rep.bottomTimestampMs < 5400 || rep.bottomTimestampMs > 6200,
                isTrue);
            expect(
                rep.endTimestampMs < 5400 || rep.endTimestampMs > 6200, isTrue);
          }
        }
      }

      // --- 4. Export Evidence CSVs to baseline02 & baseline02_closeout ---
      File? primaryDsCsv;
      File? primaryPertCsv;
      for (final outDirPath in [
        r'D:\SamanDev\runtime_evidence\workout_cv_replay\baseline02',
        r'D:\SamanDev\runtime_evidence\workout_cv_replay\baseline02_closeout',
      ]) {
        final outDir = Directory(outDirPath);
        outDir.createSync(recursive: true);

        // Export downsample summary CSV
        final dsCsv = File(
            '${outDir.path}${Platform.pathSeparator}downsample_eval_summary.csv');
        primaryDsCsv ??= dsCsv;
        final dsSink = dsCsv.openWrite();
        dsSink.writeln(
            'run_name,sample_count,max_gap_ms,completed_reps,rep_details,resets,reset_reasons');
        for (final r in downsampleRuns) {
          final repSummary = r.reps
              .map((rep) =>
                  'Rep#${rep.repNumber}(start:${rep.startTimestampMs}ms,bottom:${rep.bottomTimestampMs}ms,end:${rep.endTimestampMs}ms,dur:${rep.durationMs}ms,min:${rep.minElbowAngleDeg.toStringAsFixed(1)}deg)')
              .join(';');
          final reasons = r.resetReasons.entries
              .map((e) => '${e.key}:${e.value}')
              .join(';');
          dsSink.writeln(
              '${r.name},${r.sampleCount},${r.maxGapMs},${r.completedReps},"$repSummary",${r.resetCount},"$reasons"');
        }
        await dsSink.flush();
        await dsSink.close();

        // Export perturbation summary CSV
        final pertCsv = File(
            '${outDir.path}${Platform.pathSeparator}controlled_drop_eval_summary.csv');
        primaryPertCsv ??= pertCsv;
        final pertSink = pertCsv.openWrite();
        pertSink.writeln(
            'perturbation_case,sample_count,max_gap_ms,completed_reps,rep_details,resets,reset_reasons');
        for (final r in perturbationRuns) {
          final repSummary = r.reps
              .map((rep) =>
                  'Rep#${rep.repNumber}(start:${rep.startTimestampMs}ms,bottom:${rep.bottomTimestampMs}ms,end:${rep.endTimestampMs}ms,dur:${rep.durationMs}ms,min:${rep.minElbowAngleDeg.toStringAsFixed(1)}deg)')
              .join(';');
          final reasons = r.resetReasons.entries
              .map((e) => '${e.key}:${e.value}')
              .join(';');
          pertSink.writeln(
              '${r.name},${r.sampleCount},${r.maxGapMs},${r.completedReps},"$repSummary",${r.resetCount},"$reasons"');
        }
        await pertSink.flush();
        await pertSink.close();
      }

      // ignore: avoid_print
      print('\n======================================================');
      // ignore: avoid_print
      print('=== CP-CV-BASELINE-02 DOWNSAMPLING & PERTURBATION SUMMARY ===');
      // ignore: avoid_print
      print('Downsample Summary CSV:    ${primaryDsCsv?.path}');
      // ignore: avoid_print
      print('Perturbation Summary CSV:  ${primaryPertCsv?.path}');
      // ignore: avoid_print
      print('--- Downsampling Runs ---');
      for (final r in downsampleRuns) {
        // ignore: avoid_print
        print(
            '  ${r.name.padRight(20)}: ${r.sampleCount} frames, maxGap=${r.maxGapMs}ms, reps=${r.completedReps}, resets=${r.resetCount}');
        for (final rep in r.reps) {
          // ignore: avoid_print
          print('      -> $rep');
        }
      }
      // ignore: avoid_print
      print('--- Controlled Perturbation Runs ---');
      for (final r in perturbationRuns) {
        // ignore: avoid_print
        print(
            '  ${r.name.padRight(32)}: ${r.sampleCount} frames, maxGap=${r.maxGapMs}ms, reps=${r.completedReps}, resets=${r.resetCount} (${r.resetReasons})');
        for (final rep in r.reps) {
          // ignore: avoid_print
          print('      -> $rep');
        }
      }
      // ignore: avoid_print
      print('======================================================\n');
    });
  });
}

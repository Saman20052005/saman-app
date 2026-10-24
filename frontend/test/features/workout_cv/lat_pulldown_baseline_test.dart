import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/lat_pulldown_baseline.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_motion_features.dart';

void main() {
  group('LatPulldownBaseline Causal FSM Unit Tests', () {
    late LatPulldownBaseline tracker;

    setUp(() {
      tracker = LatPulldownBaseline();
    });

    // Helper to feed a ramp of angle values over a specified time duration
    List<LatPulldownBaselineFrameResult> feedRamp({
      required LatPulldownBaseline targetTracker,
      required int startTimestampMs,
      required int endTimestampMs,
      required int stepMs,
      required double startAngle,
      required double endAngle,
      required int startingFrameIndex,
    }) {
      final results = <LatPulldownBaselineFrameResult>[];
      final totalSteps = ((endTimestampMs - startTimestampMs) / stepMs).round();
      for (var i = 0; i <= totalSteps; i++) {
        final t = startTimestampMs + i * stepMs;
        final frac = totalSteps > 0 ? i / totalSteps : 1.0;
        final angle = startAngle + (endAngle - startAngle) * frac;
        final fIdx = startingFrameIndex + i;

        final res = targetTracker.processSample(
          frameIndex: fIdx,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
          isGateDetecting: true,
        );
        results.add(res);
      }
      return results;
    }

    test(
        '1. Full cycle test: 2 complete clean reps transition properly through all 5 phases',
        () {
      // Step A: Setup hold in extended zone (115 deg) for 250ms -> transitions from notReady to extended
      var t = 0;
      var f = 0;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 0);

      // REP 1:
      // Pull down from 115 deg to 45 deg over 1000ms
      t = 300;
      f = 12;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 1000,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 45.0,
        startingFrameIndex: f,
      );
      expect(tracker.phase, LatPulldownPhase.flexed);

      // Hold bottom for 200ms
      t = 1325;
      f = 53;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 200,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 45.0,
        startingFrameIndex: f,
      );
      expect(tracker.phase, LatPulldownPhase.flexed);

      // Return from 45 deg to 115 deg over 1000ms
      t = 1550;
      f = 62;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 1000,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      // Hold in extension for minExtendedHoldMs (200ms)
      t = 2575;
      f = 103;
      final holdRes1 = feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 200,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      expect(tracker.completedReps, 1);
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.repHistory.length, 1);
      final rep1 = tracker.repHistory.first;
      expect(rep1.repNumber, 1);
      expect(rep1.status, 'PROVISIONAL');
      expect(rep1.minElbowAngleDeg, closeTo(45.0, 1.0));
      expect(holdRes1.any((r) => r.hasNewRep), isTrue);

      // REP 2:
      // Pull down to 40 deg
      t = 2800;
      f = 112;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 900,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 40.0,
        startingFrameIndex: f,
      );
      expect(tracker.phase, LatPulldownPhase.flexed);

      // Return to 115 deg and hold 200ms
      t = 3725;
      f = 149;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 900,
        stepMs: 25,
        startAngle: 40.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      t = 4650;
      f = 186;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 200,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      expect(tracker.completedReps, 2);
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.repHistory.length, 2);
      expect(tracker.repHistory[1].repNumber, 2);
    });

    test(
        '2. Opening in the middle of a rep does not count a partial initial rep',
        () {
      // Sequence begins already pulled down at bottom (45 deg) without previous extended phase
      var t = 0;
      var f = 0;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 300,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 45.0,
        startingFrameIndex: f,
      );
      expect(tracker.phase, LatPulldownPhase.notReady);

      // Return up to extension
      t = 325;
      f = 13;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 800,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      // Hold in extension for 250ms
      t = 1150;
      f = 46;
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      // Should become ready (extended) now, but completedReps MUST BE 0!
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 0);
      expect(tracker.repHistory, isEmpty);
    });

    test(
        '3. Incomplete pull (aborted rep before flexed zone) does not count rep and returns to extended',
        () {
      // Setup into extended
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );
      expect(tracker.phase, LatPulldownPhase.extended);

      // Pulls down only to 75 deg (fails to reach <= 55 deg flexedEnterDeg)
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 300,
        endTimestampMs: 800,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 75.0,
        startingFrameIndex: 11,
      );
      expect(tracker.phase, LatPulldownPhase.pulling);

      // Hesitates and goes back up to 115 deg
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 825,
        endTimestampMs: 1400,
        stepMs: 25,
        startAngle: 75.0,
        endAngle: 115.0,
        startingFrameIndex: 32,
      );

      // Hold in extension
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 1425,
        endTimestampMs: 1700,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 56,
      );

      // Must have returned to extended without counting any rep
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 0);
      expect(tracker.repHistory, isEmpty);
    });

    test(
        '4. Ending in the middle of a rep only counts the finished rep, not the cut-off rep',
        () {
      // Clean rep 1
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 300,
        endTimestampMs: 1200,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 45.0,
        startingFrameIndex: 11,
      );
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 1225,
        endTimestampMs: 2200,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 115.0,
        startingFrameIndex: 48,
      );
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 2225,
        endTimestampMs: 2450,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 88,
      );
      expect(tracker.completedReps, 1);

      // Rep 2 starts pulling down to 45 deg, starts returning to 70 deg, then clip ends:
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 2500,
        endTimestampMs: 3400,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 45.0,
        startingFrameIndex: 98,
      );
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 3425,
        endTimestampMs: 3800,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 70.0,
        startingFrameIndex: 135,
      );

      // Stream terminates while in returning phase
      expect(tracker.phase, LatPulldownPhase.returning);
      expect(tracker.completedReps, 1); // Strictly 1, not 2!
    });

    test(
        '5. Oscillations/jitter around thresholds and standing rest do not produce spurious reps',
        () {
      // Setup
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );
      expect(tracker.phase, LatPulldownPhase.extended);

      // Jitter around pullingEnterDeg (95 deg): oscillate between 93 and 98 deg 20 times
      var t = 300;
      var f = 11;
      for (var i = 0; i < 20; i++) {
        final angle = (i % 2 == 0) ? 93.0 : 98.0;
        tracker.processSample(
          frameIndex: f++,
          timestampMs: t,
          elbowAngleDeg: angle,
          isSampleValid: true,
        );
        t += 30;
      }
      expect(tracker.completedReps, 0);

      // Stand/rest at 115 deg for 5 seconds
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 5000,
        stepMs: 50,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );
      expect(tracker.completedReps, 0);
      expect(tracker.phase, LatPulldownPhase.extended);
    });

    test(
        '6. Data gap / invalid samples exceeding maxAllowedGapMs aborts in-progress cycle and prevents rep joining',
        () {
      // Setup
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );

      // Pull down to bottom (45 deg)
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 300,
        endTimestampMs: 1200,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 45.0,
        startingFrameIndex: 11,
      );
      expect(tracker.phase, LatPulldownPhase.flexed);

      // Long invalid gap of 1500ms (> maxAllowedGapMs = 500ms)
      var t = 1250;
      var f = 48;
      for (var i = 0; i < 10; i++) {
        final res = tracker.processSample(
          frameIndex: f++,
          timestampMs: t,
          elbowAngleDeg: null,
          isSampleValid: false,
        );
        t += 150;
        if (i > 3) {
          expect(res.resetReason, isNotNull);
        }
      }
      expect(tracker.phase, LatPulldownPhase.notReady);

      // Resumes directly at 115 deg
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: t,
        endTimestampMs: t + 300,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: f,
      );

      // Gap must NOT join bottom pull with post-gap extension: reps MUST be 0!
      expect(tracker.completedReps, 0);
    });

    test(
        '7. Decreasing/non-monotonic timestamps are blocked and do not advance phase or rep count',
        () {
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );
      expect(tracker.phase, LatPulldownPhase.extended);

      // Next frame has backwards timestamp (150ms <= 250ms)
      final res = tracker.processSample(
        frameIndex: 12,
        timestampMs: 150,
        elbowAngleDeg: 50.0,
        isSampleValid: true,
      );

      expect(tracker.droppedNonMonotonicFrames, 1);
      expect(res.resetReason, 'droppedNonMonotonicTimestamp');
      expect(tracker.phase,
          LatPulldownPhase.extended); // Phase did not change to flexed
      expect(tracker.completedReps, 0);
    });

    test(
        '8. Sampling rate independence: 50 FPS, 25 FPS, and 10 FPS detect identical reps on continuous motion',
        () {
      // Generate synthetic sinusoidal movement for 2 full reps over 6 seconds
      // angle(t) = 80 + 35 * cos(2 * pi * t / 3.0)
      // At t=0s, 3s, 6s -> cos=1 -> angle=115 deg (peak extension)
      // At t=1.5s, 4.5s -> cos=-1 -> angle=45 deg (bottom pull)
      double syntheticAngle(double sec) {
        return 80.0 + 35.0 * math.cos(2 * math.pi * sec / 3.0);
      }

      int runSimulation(int stepMs) {
        final simTracker = LatPulldownBaseline();
        var fIdx = 0;
        const totalDurationMs = 6500;

        for (var t = 0; t <= totalDurationMs; t += stepMs) {
          final sec = t / 1000.0;
          final angle = syntheticAngle(sec);
          simTracker.processSample(
            frameIndex: fIdx++,
            timestampMs: t,
            elbowAngleDeg: angle,
            isSampleValid: true,
          );
        }
        return simTracker.completedReps;
      }

      final reps50fps = runSimulation(20); // 50 fps
      final reps25fps = runSimulation(40); // 25 fps
      final reps10fps = runSimulation(100); // 10 fps

      expect(reps50fps, 2);
      expect(reps25fps, 2);
      expect(reps10fps, 2);
    });

    test(
        '9. Prefix test (Strict Causality): Result at time t is invariant to whether frames after t are present',
        () {
      // Generate 200 synthetic frames
      final frames = List.generate(200, (i) {
        final t = i * 30; // 30ms step
        final sec = t / 1000.0;
        final angle = 80.0 + 35.0 * math.cos(2 * math.pi * sec / 2.5);
        return (fIdx: i, tMs: t, angle: angle);
      });

      // Target evaluation point: frame index 120 (t = 3600ms)
      const targetIdx = 120;

      // Run A: evaluate strictly up to targetIdx (prefix of 121 frames)
      final trackerPrefix = LatPulldownBaseline();
      for (var i = 0; i <= targetIdx; i++) {
        trackerPrefix.processSample(
          frameIndex: frames[i].fIdx,
          timestampMs: frames[i].tMs,
          elbowAngleDeg: frames[i].angle,
          isSampleValid: true,
        );
      }
      final prefixPhase = trackerPrefix.phase;
      final prefixReps = trackerPrefix.completedReps;

      // Run B: evaluate all 200 frames, but capture state right after processing frame targetIdx
      final trackerFull = LatPulldownBaseline();
      LatPulldownPhase? fullPhaseAtTarget;
      int? fullRepsAtTarget;

      for (var i = 0; i < frames.length; i++) {
        trackerFull.processSample(
          frameIndex: frames[i].fIdx,
          timestampMs: frames[i].tMs,
          elbowAngleDeg: frames[i].angle,
          isSampleValid: true,
        );
        if (i == targetIdx) {
          fullPhaseAtTarget = trackerFull.phase;
          fullRepsAtTarget = trackerFull.completedReps;
        }
      }

      // Assert prefix invariance: strictly causal!
      expect(prefixPhase, equals(fullPhaseAtTarget));
      expect(prefixReps, equals(fullRepsAtTarget));
    });

    test(
        '10. Invalid samples during ready hold or extended rep hold reset candidate timer, preventing blind hold accumulation',
        () {
      // Case A: Ready hold
      // Start in extended zone at t=1000ms with minReadyHoldMs=200ms
      tracker.processSample(
          frameIndex: 0,
          timestampMs: 1000,
          elbowAngleDeg: 115.0,
          isSampleValid: true);
      tracker.processSample(
          frameIndex: 1,
          timestampMs: 1080,
          elbowAngleDeg: 115.0,
          isSampleValid: true);
      expect(tracker.phase, LatPulldownPhase.notReady); // 80ms < 200ms

      // Frame at t=1100ms is INVALID (e.g. low visibility or tracking glitch)
      tracker.processSample(
          frameIndex: 2,
          timestampMs: 1100,
          elbowAngleDeg: null,
          isSampleValid: false);
      expect(tracker.phase, LatPulldownPhase.notReady);

      // Next valid frame at t=1220ms (120ms after invalid, but 220ms after 1000ms)
      tracker.processSample(
          frameIndex: 3,
          timestampMs: 1220,
          elbowAngleDeg: 115.0,
          isSampleValid: true);
      // Because frame 2 was invalid, the ready timer MUST have reset, so at t=1220ms it must NOT be ready yet!
      expect(tracker.phase, LatPulldownPhase.notReady);

      // Must hold continuously for 200ms after t=1220ms (i.e. until t=1420ms)
      tracker.processSample(
          frameIndex: 4,
          timestampMs: 1350,
          elbowAngleDeg: 115.0,
          isSampleValid: true);
      expect(tracker.phase, LatPulldownPhase.notReady);

      tracker.processSample(
          frameIndex: 5,
          timestampMs: 1420,
          elbowAngleDeg: 115.0,
          isSampleValid: true);
      expect(
          tracker.phase,
          LatPulldownPhase
              .extended); // Satisfied 200ms of uninterrupted valid observation!

      // Case B: Extended rep confirmation hold
      // Pull down to flexed:
      // t=1500ms: angle drops to 80.0 deg -> enters pulling
      tracker.processSample(
          frameIndex: 6,
          timestampMs: 1500,
          elbowAngleDeg: 80.0,
          isSampleValid: true);
      expect(tracker.phase, LatPulldownPhase.pulling);
      // t=1550ms: angle reaches 45.0 deg -> enters flexed
      tracker.processSample(
          frameIndex: 7,
          timestampMs: 1550,
          elbowAngleDeg: 45.0,
          isSampleValid: true);
      expect(tracker.phase, LatPulldownPhase.flexed);

      // Return toward extended: at t=1800ms, angle reaches 75.0 (enters returning)
      tracker.processSample(
          frameIndex: 8,
          timestampMs: 1800,
          elbowAngleDeg: 75.0,
          isSampleValid: true);
      expect(tracker.phase, LatPulldownPhase.returning);
      expect(tracker.completedReps, 0);

      // Reaches extended zone (110.0 deg) at t=2100ms (minExtendedHoldMs=150ms)
      tracker.processSample(
          frameIndex: 9,
          timestampMs: 2100,
          elbowAngleDeg: 110.0,
          isSampleValid: true);
      expect(tracker.phase, LatPulldownPhase.returning);
      expect(tracker.completedReps, 0);

      // Frame at t=2150ms is INVALID (breaks continuous hold candidate)
      tracker.processSample(
          frameIndex: 10,
          timestampMs: 2150,
          elbowAngleDeg: null,
          isSampleValid: false);
      expect(tracker.completedReps, 0);

      // Next valid frame at t=2200ms (100ms after 2100ms, but only 50ms after invalid)
      tracker.processSample(
          frameIndex: 11,
          timestampMs: 2200,
          elbowAngleDeg: 110.0,
          isSampleValid: true);
      // Must NOT confirm rep blindly!
      expect(tracker.completedReps, 0);

      // Must hold continuously for 150ms after t=2200ms (until t=2350ms)
      tracker.processSample(
          frameIndex: 12,
          timestampMs: 2300,
          elbowAngleDeg: 110.0,
          isSampleValid: true);
      expect(tracker.completedReps, 0);

      // At t=2360ms: hold = 160ms >= 150ms, duration = 2360 - 1500 = 860ms >= 800ms
      tracker.processSample(
          frameIndex: 13,
          timestampMs: 2360,
          elbowAngleDeg: 110.0,
          isSampleValid: true);
      expect(tracker.completedReps,
          1); // Rep confirmed after uninterrupted valid hold and valid duration!
    });

    test(
        '11. reset() clears session state, counters, and rep history cleanly without carrying forward state',
        () {
      // Run rep 1 to completion
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 0,
          endTimestampMs: 250,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 0);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 300,
          endTimestampMs: 1200,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 45.0,
          startingFrameIndex: 11);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 1225,
          endTimestampMs: 2200,
          stepMs: 25,
          startAngle: 45.0,
          endAngle: 115.0,
          startingFrameIndex: 48);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 2225,
          endTimestampMs: 2450,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 88);
      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.length, 1);

      // Reset for a fresh session
      tracker.reset();

      expect(tracker.completedReps, 0);
      expect(tracker.phase, LatPulldownPhase.notReady);
      expect(tracker.repHistory, isEmpty);
      expect(tracker.droppedNonMonotonicFrames, 0);

      // Verify fresh session starts at rep 1, not rep 2
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 0,
          endTimestampMs: 250,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 0);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 300,
          endTimestampMs: 1200,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 45.0,
          startingFrameIndex: 11);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 1225,
          endTimestampMs: 2200,
          stepMs: 25,
          startAngle: 45.0,
          endAngle: 115.0,
          startingFrameIndex: 48);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 2225,
          endTimestampMs: 2450,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 88);
      expect(tracker.completedReps, 1);
      expect(tracker.repHistory.length, 1);
      expect(tracker.repHistory.first.repNumber, 1);
    });

    test(
        '12. Quality gate not detecting (lost, multiplePeople, needsSetup) aborts in-progress cycle while preserving completed reps',
        () {
      // Complete rep 1
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 0,
          endTimestampMs: 250,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 0);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 300,
          endTimestampMs: 1200,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 45.0,
          startingFrameIndex: 11);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 1225,
          endTimestampMs: 2200,
          stepMs: 25,
          startAngle: 45.0,
          endAngle: 115.0,
          startingFrameIndex: 48);
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 2225,
          endTimestampMs: 2450,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 88);
      expect(tracker.completedReps, 1);

      // Start rep 2: pulling down to bottom (45 deg)
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 2500,
          endTimestampMs: 3400,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 45.0,
          startingFrameIndex: 98);
      expect(tracker.phase, LatPulldownPhase.flexed);

      // External quality gate fails (e.g. multiple people entered or tracking lost)
      final gateFailRes = tracker.processSample(
        frameIndex: 135,
        timestampMs: 3450,
        elbowAngleDeg: 45.0,
        isSampleValid: true,
        isGateDetecting: false, // Quality gate failed
      );

      // In-progress rep must be aborted, state must reset to notReady, completed rep 1 preserved!
      expect(gateFailRes.resetReason, 'gateNotDetecting');
      expect(tracker.phase, LatPulldownPhase.notReady);
      expect(tracker.completedReps, 1); // Preserved rep 1

      // Resume in extended zone
      feedRamp(
          targetTracker: tracker,
          startTimestampMs: 3500,
          endTimestampMs: 3750,
          stepMs: 25,
          startAngle: 115.0,
          endAngle: 115.0,
          startingFrameIndex: 136);

      // Must be extended, but still 1 rep
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 1);
    });

    test(
        '13. Single-frame spike into flexed zone followed by immediate return to extended does not create spurious rep without shortcut',
        () {
      // 1. Establish steady extended ready state
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 0);

      // 2. An isolated 1-frame anomaly/spike where angle suddenly jumps to 40 deg at t=400ms
      final spikeRes = tracker.processSample(
        frameIndex: 11,
        timestampMs: 400,
        elbowAngleDeg: 40.0,
        isSampleValid: true,
      );
      // Without shortcut, this enters pulling (since 40 < 95.0), but NOT flexed!
      expect(tracker.phase, LatPulldownPhase.pulling);
      expect(spikeRes.transitionReason, 'pullingStarted');
      expect(tracker.completedReps, 0);

      // 3. Immediately next frame at t=425ms returns to extended zone (115 deg)
      final returnRes = tracker.processSample(
        frameIndex: 12,
        timestampMs: 425,
        elbowAngleDeg: 115.0,
        isSampleValid: true,
      );
      // Aborts the pull safely back to extended without ever reaching flexed!
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(returnRes.transitionReason, 'incompletePullReturnedToExtended');
      expect(tracker.completedReps, 0);

      // 4. Continued holding at 115 deg for 300ms (t=450..750ms)
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 450,
        endTimestampMs: 750,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 13,
      );

      // Verify ZERO reps were counted despite the extreme single-frame spike to 40 deg
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 0);
      expect(tracker.repHistory, isEmpty);
    });

    test(
        '14. Non-finite angle sample (NaN / Infinity) is safely treated as invalid sample without advancing phase',
        () {
      tracker.processSample(
        frameIndex: 0,
        timestampMs: 100,
        elbowAngleDeg: 120.0,
        isSampleValid: true,
      );

      final nanRes = tracker.processSample(
        frameIndex: 1,
        timestampMs: 200,
        elbowAngleDeg: double.nan,
        isSampleValid: true,
      );

      expect(nanRes.isSampleValid, isFalse);
      expect(nanRes.elbowAngleDeg, isNull);
      expect(tracker.phase, LatPulldownPhase.notReady);

      final infRes = tracker.processSample(
        frameIndex: 2,
        timestampMs: 300,
        elbowAngleDeg: double.infinity,
        isSampleValid: true,
      );

      expect(infRes.isSampleValid, isFalse);
      expect(infRes.elbowAngleDeg, isNull);
      expect(tracker.phase, LatPulldownPhase.notReady);
    });

    test(
        '15. Rep duration boundary: pull cycle completing under minRepDurationMs (800ms) ignores rep',
        () {
      // Setup ready hold: 250ms at 115 deg
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 0,
        endTimestampMs: 250,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 0,
      );
      expect(tracker.phase, LatPulldownPhase.extended);

      // Fast pull down from 115 to 45 in 200ms (t = 300..500)
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 300,
        endTimestampMs: 500,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 45.0,
        startingFrameIndex: 11,
      );
      expect(tracker.phase, LatPulldownPhase.flexed);

      // Fast return from 45 to 115 in 200ms (t = 525..725)
      feedRamp(
        targetTracker: tracker,
        startTimestampMs: 525,
        endTimestampMs: 725,
        stepMs: 25,
        startAngle: 45.0,
        endAngle: 115.0,
        startingFrameIndex: 20,
      );
      expect(tracker.phase, LatPulldownPhase.returning);

      // Hold in extended for 150ms (t = 750..900)
      // Total rep duration from start (300ms) to end (900ms) = 600ms < 800ms config.minRepDurationMs!
      final holdResults = feedRamp(
        targetTracker: tracker,
        startTimestampMs: 750,
        endTimestampMs: 900,
        stepMs: 25,
        startAngle: 115.0,
        endAngle: 115.0,
        startingFrameIndex: 29,
      );

      expect(holdResults.any((r) => r.transitionReason == 'repTooShortIgnored'),
          isTrue);
      expect(tracker.phase, LatPulldownPhase.extended);
      expect(tracker.completedReps, 0);
      expect(tracker.repHistory, isEmpty);
    });

    test(
        '16. processFrameFeatures integrates seamlessly with LatPulldownFrameFeatures container',
        () {
      final validSide = LatPulldownSideFeatures(
        sideKey: 'model_left_11_13_15',
        shoulderId: 11,
        elbowId: 13,
        wristId: 15,
        elbowAngleDeg: const MotionMeasurement.valid(110.0),
        wristRelY: const MotionMeasurement.valid(0.2),
        wristRelX: const MotionMeasurement.valid(0.1),
        wristDistance: const MotionMeasurement.valid(0.5),
      );
      final dummyRightSide = LatPulldownSideFeatures(
        sideKey: 'model_right_12_14_16',
        shoulderId: 12,
        elbowId: 14,
        wristId: 16,
        elbowAngleDeg: const MotionMeasurement.invalid(
            MotionMetricFailure.missingLandmark),
        wristRelY: const MotionMeasurement.invalid(
            MotionMetricFailure.missingLandmark),
        wristRelX: const MotionMeasurement.invalid(
            MotionMetricFailure.missingLandmark),
        wristDistance: const MotionMeasurement.invalid(
            MotionMetricFailure.missingLandmark),
      );

      final frameFeatures = LatPulldownFrameFeatures(
        frameIndex: 0,
        timestampMs: 100,
        isGateDetecting: true,
        shoulderWidthPx: const MotionMeasurement.valid(200.0),
        leftSide: validSide,
        rightSide: dummyRightSide,
      );

      final result = tracker.processFrameFeatures(frameFeatures);
      expect(result.frameIndex, 0);
      expect(result.timestampMs, 100);
      expect(result.elbowAngleDeg, closeTo(110.0, 1e-4));
      expect(result.isSampleValid, isTrue);
    });
  });
}

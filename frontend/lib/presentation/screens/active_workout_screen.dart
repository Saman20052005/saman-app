import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/exercise.dart';
import '../../features/workout/domain/entities/workout_plan.dart' as domain;
import '../providers/active_workout_providers.dart';
import '../providers/active_workout_state.dart';
import '../tokens/saman_workout_tokens.dart';
import '../providers/exercise_providers.dart';
import '../widgets/exercise_thumbnail.dart';
import 'workout_review_screen.dart';
import 'workout_complete_screen.dart';

/// Active Workout Screen matching Stitch 04 Calm Athleticism specification
class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  final domain.WorkoutPlan? workoutPlan;
  final String heroTag;
  final bool autoTick;
  final List<Exercise>? exercises;
  final String title;

  const ActiveWorkoutScreen({
    super.key,
    this.workoutPlan,
    this.heroTag = 'hero_default',
    this.autoTick = true,
    this.exercises,
    this.title = 'Custom Workout',
  });

  /// Keep exercise IDs, prescriptions and media intact at the entry boundary.
  factory ActiveWorkoutScreen.fromExercises({
    Key? key,
    required List<Exercise> exercises,
    String heroTag = 'hero_default',
    String title = 'Custom Workout',
  }) {
    return ActiveWorkoutScreen(
      key: key,
      exercises: exercises,
      title: title,
      heroTag: heroTag,
    );
  }
  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  Timer? _autoTickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSessionIfNeeded();
    });

    if (widget.autoTick) {
      _autoTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          ref.read(activeWorkoutSessionProvider.notifier).tick();
        }
      });
    }
  }

  void _initSessionIfNeeded() {
    if (!mounted) return;
    final notifier = ref.read(activeWorkoutSessionProvider.notifier);
    if (widget.exercises != null) {
      notifier.startSession(widget.exercises!, title: widget.title);
    } else if (widget.workoutPlan != null) {
      notifier.startSessionFromPlan(widget.workoutPlan!);
    }
  }
  @override
  void dispose() {
    _autoTickTimer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeWorkoutSessionProvider);
    final notifier = ref.read(activeWorkoutSessionProvider.notifier);
    final currentEx = session.currentExercise;

    if (currentEx == null) {
      return const Scaffold(
        backgroundColor: SamanWorkoutTokens.canvas,
        body: Center(
          child: CircularProgressIndicator(
            color: SamanWorkoutTokens.emeraldAccent,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Sticky In-Session Top Chrome
            _buildTopChrome(session, notifier),

            // Scrollable workout content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Horizon Progress
                    _buildHorizonProgress(session, currentEx),
                    const SizedBox(height: 16),

                    // Current Exercise Anchor Card
                    _buildCurrentExerciseAnchor(currentEx),
                    const SizedBox(height: 16),

                    // Compact Rest Strip (Only when resting)
                    if (session.isResting) ...[
                      _buildRestStrip(session, notifier),
                      const SizedBox(height: 16),
                    ],

                    // Scannable Set List Table
                    _buildSetListTable(currentEx, notifier),
                    const SizedBox(height: 20),

                    // Secondary Up Next Queue
                    _buildUpNextQueue(session),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildFooterDock(session, currentEx, notifier),
    );
  }

  Widget _buildTopChrome(
    ActiveWorkoutSessionState session,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: SamanWorkoutTokens.canvas,
        border: Border(
          bottom: BorderSide(
            color: SamanWorkoutTokens.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimize button
          InkWell(
            key: const ValueKey('active_workout_minimize_button'),
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusPill),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: SamanWorkoutTokens.borderSubtle),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: SamanWorkoutTokens.textSecondary,
                size: 20,
              ),
            ),
          ),

          // Center Session Title & Chronometer
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SamanWorkoutTokens.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: session.isPaused
                          ? SamanWorkoutTokens.amberAccent
                          : SamanWorkoutTokens.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(session.elapsedSeconds),
                    key: const ValueKey('active_workout_timer_text'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.emeraldAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (session.isPaused) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.amberAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              SamanWorkoutTokens.amberAccent.withOpacity(0.4),
                        ),
                      ),
                      child: const Text(
                        'PAUSED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: SamanWorkoutTokens.amberAccent,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

          // Finish pill button
          InkWell(
            key: const ValueKey('active_workout_finish_button'),
            onTap: () => _showReviewScreen(context),
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusPill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                border: Border.all(color: SamanWorkoutTokens.borderSubtle),
              ),
              child: const Text(
                'Finish',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: SamanWorkoutTokens.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizonProgress(
    ActiveWorkoutSessionState session,
    ActiveExerciseInfo currentEx,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Exercise ${session.currentExerciseNumber} of ${session.exerciseCount}',
                style: const TextStyle(
                  fontSize: 12,
                  color: SamanWorkoutTokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${currentEx.completedSetsCount} of ${currentEx.totalSetsCount} sets completed',
                style: const TextStyle(
                  fontSize: 12,
                  color: SamanWorkoutTokens.emeraldAccent,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(session.exerciseCount, (index) {
            final exercise = session.exercises[index];
            final double fillFraction = exercise.totalSetsCount > 0
                ? exercise.completedSetsCount / exercise.totalSetsCount : 0.0;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index < session.exerciseCount - 1 ? 6.0 : 0.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF262930),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fillFraction.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.emeraldAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCurrentExerciseAnchor(ActiveExerciseInfo currentEx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image card with overlay buttons
        Container(
          width: double.infinity,
          height: 176,
          decoration: BoxDecoration(
            color: SamanWorkoutTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: SamanWorkoutTokens.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExerciseThumbnail(
                source: exercisePosterSource(currentEx.imageUrl),
                fit: BoxFit.contain,
                showUnavailableLabel: true,
              ),
              // Bottom gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      SamanWorkoutTokens.canvas.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Floating Buttons on Image
              Positioned(
                left: 10,
                bottom: 10,
                child: InkWell(
                  key: const ValueKey('active_workout_form_check_badge'),
                  onTap: () => _showFormCheckModal(context),
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0C0D0E),
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 14,
                          color: SamanWorkoutTokens.emeraldAccent,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Form Check',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: SamanWorkoutTokens.emeraldAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: InkWell(
                  key: const ValueKey('active_workout_video_guide_button'),
                  onTap: () => _showVideoGuideModal(context, currentEx),
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0C0D0E),
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow,
                          size: 15,
                          color: SamanWorkoutTokens.emeraldAccent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Video Guide',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          currentEx.name,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: SamanWorkoutTokens.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          currentEx.subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: SamanWorkoutTokens.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildRestStrip(
    ActiveWorkoutSessionState session,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(
          color: SamanWorkoutTokens.emeraldAccent.withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: session.currentExercise != null &&
                              session.currentExercise!.restSeconds > 0
                          ? session.restSecondsLeft /
                              session.currentExercise!.restSeconds
                          : 0.0,
                      strokeWidth: 3,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        SamanWorkoutTokens.emeraldAccent,
                      ),
                      backgroundColor: const Color(0xFF262930),
                    ),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: SamanWorkoutTokens.emeraldAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'REST',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    _formatTime(session.restSecondsLeft),
                    key: const ValueKey('active_workout_rest_timer_text'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              InkWell(
                key: const ValueKey('active_workout_rest_add_30s'),
                onTap: () => notifier.addRestSeconds(30),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: SamanWorkoutTokens.borderSubtle),
                  ),
                  child: const Text(
                    '+30s',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('active_workout_rest_skip'),
                onTap: () => notifier.skipRest(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.emeraldBadgeBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: SamanWorkoutTokens.emeraldBadgeBorder,
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SamanWorkoutTokens.emeraldAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSetListTable(
    ActiveExerciseInfo currentEx,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column headers
        if (currentEx.unit == SetUnit.seconds)
          const _TimedSetHeader()
        else const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'SET',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: SamanWorkoutTokens.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  'KG',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: SamanWorkoutTokens.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'REPS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: SamanWorkoutTokens.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'STATUS',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: SamanWorkoutTokens.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Set Rows
        ...currentEx.sets.map((set) {
          if (set.unit == SetUnit.seconds) {
            return _TimedSetRow(
              key: ValueKey('${currentEx.id}_${set.setNumber}'),
              set: set,
              isActive: identical(set, currentEx.activeSet),
              draftSeconds: currentEx.draftSeconds,
              onSecondsChanged: notifier.setDraftSeconds,
            );
          }
          if (set.isCompleted) {
            return _buildCompletedSetRow(set);
          } else if (set.isActive) {
            return _buildActiveSetCard(set, currentEx, notifier);
          } else {
            return _buildUpcomingSetRow(set);
          }
        }),

        const SizedBox(height: 10),

        // Add set button
        InkWell(
          key: const ValueKey('active_workout_add_set_button'),
          onTap: () => notifier.addSet(),
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
              border: Border.all(
                color: SamanWorkoutTokens.borderSubtle,
                style: BorderStyle.solid,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add,
                  size: 15,
                  color: SamanWorkoutTokens.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  'Add set',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedSetRow(ActiveWorkoutSetInfo set) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: SamanWorkoutTokens.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              set.setNumber.toString(),
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: SamanWorkoutTokens.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${set.weightKg?.toStringAsFixed(0) ?? set.targetWeightKg.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: SamanWorkoutTokens.textPrimary,
                  ),
                ),
                const SizedBox(width: 3),
                const Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 11,
                    color: SamanWorkoutTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${set.reps ?? set.targetReps}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: SamanWorkoutTokens.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.emeraldBadgeBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SamanWorkoutTokens.emeraldBadgeBorder,
                  ),
                ),
                child: const Icon(
                  Icons.check,
                  size: 13,
                  color: SamanWorkoutTokens.emeraldAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSetCard(
    ActiveWorkoutSetInfo set,
    ActiveExerciseInfo currentEx,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: const Color(0xFF2E323A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of active set
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: SamanWorkoutTokens.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SET ' + set.setNumber.toString() + ' (ACTIVE)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TARGET: ' + set.targetWeightKg.toStringAsFixed(0) + ' KG × ' + set.targetReps.toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: SamanWorkoutTokens.textSecondary,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Steppers
          Row(
            children: [
              // Weight Stepper
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262930),
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: SamanWorkoutTokens.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const ValueKey('active_workout_weight_minus'),
                        onTap: () => notifier.adjustDraftWeight(-1),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Text(
                            '−',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  currentEx.draftWeightKg.toStringAsFixed(0),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Text(
                                  'kg',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: SamanWorkoutTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('active_workout_weight_plus'),
                        onTap: () => notifier.adjustDraftWeight(1),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Text(
                            '+',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Reps Stepper
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262930),
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: SamanWorkoutTokens.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const ValueKey('active_workout_reps_minus'),
                        onTap: () => notifier.adjustDraftReps(-1),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Text(
                            '−',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${currentEx.draftReps}',
                            key: const ValueKey('active_workout_draft_reps'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Text(
                            'reps',
                            style: TextStyle(
                              fontSize: 11,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                          ),
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('active_workout_reps_plus'),
                        onTap: () => notifier.adjustDraftReps(1),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Text(
                            '+',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingSetRow(ActiveWorkoutSetInfo set) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface.withOpacity(0.2),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(
          color: SamanWorkoutTokens.borderSubtle.withOpacity(0.4),
        ),
      ),
      child: Opacity(
        opacity: 0.5,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                set.setNumber.toString(),
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: SamanWorkoutTokens.textMuted,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    set.targetWeightKg.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    'kg',
                    style: TextStyle(
                      fontSize: 11,
                      color: SamanWorkoutTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                '${set.targetReps}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  color: SamanWorkoutTokens.textMuted,
                ),
              ),
            ),
            const Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '—',
                  style: TextStyle(
                    fontSize: 14,
                    color: SamanWorkoutTokens.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpNextQueue(ActiveWorkoutSessionState session) {
    final next = session.nextExercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'UP NEXT',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: SamanWorkoutTokens.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: InkWell(
                onTap: () => _showExerciseQueue(context, session),
                child: Text(
                'View all ${session.exerciseCount} exercises →',
                style: const TextStyle(
                  fontSize: 12,
                  color: SamanWorkoutTokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SamanWorkoutTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: SamanWorkoutTokens.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SamanWorkoutTokens.borderSubtle),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  size: 18,
                  color: SamanWorkoutTokens.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next?.name ?? 'No upcoming exercise',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SamanWorkoutTokens.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      next?.subtitle ?? 'All exercises completed',
                      style: const TextStyle(
                        fontSize: 11,
                        color: SamanWorkoutTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: SamanWorkoutTokens.textMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooterDock(
    ActiveWorkoutSessionState session,
    ActiveExerciseInfo currentEx,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    final activeSetNumber =
        currentEx.activeSet?.setNumber ?? (currentEx.completedSetsCount + 1);

    return Container(
      color: SamanWorkoutTokens.canvas,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary Action: Log Set N
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const ValueKey('active_workout_log_set_button'),
              onPressed: currentEx.activeSet != null
                  ? (currentEx.canLogSet ? notifier.logActiveSet : null)
                  : session.nextExercise != null
                      ? notifier.nextExercise
                      : () => _showReviewScreen(context),
              icon: const Icon(
                Icons.check,
                size: 18,
                color: SamanWorkoutTokens.buttonPrimaryText,
              ),
              label: Text(
                currentEx.activeSet != null ? 'Log Set $activeSetNumber'
                    : session.nextExercise != null ? 'Next exercise' : 'Review session',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: SamanWorkoutTokens.buttonPrimaryText,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanWorkoutTokens.buttonPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Secondary Action: Pause/Resume workout
          if (!session.isPaused)
            InkWell(
              key: const ValueKey('active_workout_pause_button'),
              onTap: () => notifier.pauseWorkout(),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pause,
                      size: 15,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Pause workout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            InkWell(
              key: const ValueKey('active_workout_resume_button'),
              onTap: () => notifier.resumeWorkout(),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow,
                      size: 16,
                      color: SamanWorkoutTokens.emeraldAccent,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Resume workout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SamanWorkoutTokens.emeraldAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showExerciseQueue(BuildContext context, ActiveWorkoutSessionState session) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(child: ListView.builder(
        shrinkWrap: true,
        itemCount: session.exerciseCount,
        itemBuilder: (_, index) => ListTile(
          title: Text(session.exercises[index].name),
          selected: index == session.currentExerciseIndex,
          onTap: () {
            ref.read(activeWorkoutSessionProvider.notifier).selectExercise(index);
            Navigator.of(sheetContext).pop();
          },
        ),
      )),
    );
  }

  Future<void> _showReviewScreen(BuildContext context) async {
    final notifier = ref.read(activeWorkoutSessionProvider.notifier);
    final wasPaused = ref.read(activeWorkoutSessionProvider).isPaused;
    notifier.pauseWorkout();
    final savedSessionId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const WorkoutReviewScreen(),
      ),
    );
    if (!context.mounted) return;
    if (savedSessionId != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WorkoutCompleteScreen(sessionId: savedSessionId),
        ),
      );
    } else if (!wasPaused) {
      notifier.resumeWorkout();
    }
  }
  void _showVideoGuideModal(
    BuildContext context,
    ActiveExerciseInfo currentEx,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SamanWorkoutTokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${currentEx.name} — Video Guide',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: SamanWorkoutTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Video Demo in Preparation · Verified Form Cues Active',
                style: TextStyle(
                  fontSize: 12,
                  color: SamanWorkoutTokens.emeraldAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Key Movement Cues:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SamanWorkoutTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: SamanWorkoutTokens.emeraldAccent, fontSize: 14)),
                    Expanded(
                      child: Text(
                        'Keep your feet firmly planted on the floor',
                        style: TextStyle(fontSize: 13, color: SamanWorkoutTokens.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: SamanWorkoutTokens.emeraldAccent, fontSize: 14)),
                    Expanded(
                      child: Text(
                        'Retract your shoulder blades and maintain a slight natural arch',
                        style: TextStyle(fontSize: 13, color: SamanWorkoutTokens.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: SamanWorkoutTokens.emeraldAccent, fontSize: 14)),
                    Expanded(
                      child: Text(
                        'Control the eccentric descent down to chest level',
                        style: TextStyle(fontSize: 13, color: SamanWorkoutTokens.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  key: const ValueKey(
                      'active_workout_video_guide_close_button'),
                  onPressed: () => Navigator.of(modalCtx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SamanWorkoutTokens.surfaceElevated,
                    foregroundColor: SamanWorkoutTokens.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      side: const BorderSide(
                          color: SamanWorkoutTokens.borderSubtle),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFormCheckModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SamanWorkoutTokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: SamanWorkoutTokens.amberAccent,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Live Form Check (Deferred)',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Computer Vision Form Check is planned for a future release (deferred checkpoint). No camera feed has been activated and no reps will be auto-logged.',
                style: TextStyle(
                  fontSize: 13,
                  color: SamanWorkoutTokens.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  key: const ValueKey(
                      'active_workout_form_check_close_button'),
                  onPressed: () => Navigator.of(modalCtx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SamanWorkoutTokens.surfaceElevated,
                    foregroundColor: SamanWorkoutTokens.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      side: const BorderSide(
                          color: SamanWorkoutTokens.borderSubtle),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimedSetHeader extends StatelessWidget {
  const _TimedSetHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
    child: Row(children: [
      Expanded(child: Text('SET', style: TextStyle(color: SamanWorkoutTokens.textMuted))),
      Expanded(flex: 3, child: Text('SECONDS', style: TextStyle(color: SamanWorkoutTokens.textMuted))),
      Text('STATUS', style: TextStyle(color: SamanWorkoutTokens.textMuted)),
    ]),
  );
}

class _TimedSetRow extends StatelessWidget {
  const _TimedSetRow({
    super.key, required this.set, required this.isActive, required this.draftSeconds,
    required this.onSecondsChanged,
  });

  final ActiveWorkoutSetInfo set;
  final bool isActive;
  final int? draftSeconds;
  final ValueChanged<int?> onSecondsChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsetsDirectional.only(bottom: 6),
    padding: const EdgeInsetsDirectional.all(12),
    decoration: BoxDecoration(
      color: SamanWorkoutTokens.cardSurface,
      borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
      border: Border.all(color: isActive
          ? SamanWorkoutTokens.emeraldAccent : SamanWorkoutTokens.borderSubtle),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(
          isActive ? 'SET ${set.setNumber} (ACTIVE)' : 'SET ${set.setNumber}',
          style: const TextStyle(color: SamanWorkoutTokens.textSecondary),
        )),
        Text(isActive ? 'TARGET: ${set.targetSeconds} s'
            : '${set.isCompleted ? set.seconds : set.targetSeconds} s',
          style: const TextStyle(color: SamanWorkoutTokens.textPrimary)),
        const SizedBox(width: 8),
        if (set.isCompleted) const Icon(Icons.check,
          color: SamanWorkoutTokens.emeraldAccent, size: 18),
      ]),
      if (isActive) ...[
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('active_workout_seconds_input'),
          initialValue: draftSeconds?.toString() ?? '',
          keyboardType: TextInputType.number,
          style: const TextStyle(color: SamanWorkoutTokens.textPrimary),
          cursorColor: SamanWorkoutTokens.emeraldAccent,
          decoration: const InputDecoration(
            labelText: 'Seconds', suffixText: 's', helperText: 'Enter 1-999 seconds',
            filled: true,
            fillColor: SamanWorkoutTokens.surfaceElevated,
            labelStyle: TextStyle(color: SamanWorkoutTokens.textSecondary),
            floatingLabelStyle: TextStyle(color: SamanWorkoutTokens.emeraldAccent),
            helperStyle: TextStyle(color: SamanWorkoutTokens.textSecondary),
            suffixStyle: TextStyle(color: SamanWorkoutTokens.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(SamanWorkoutTokens.radiusMd)),
              borderSide: BorderSide(color: SamanWorkoutTokens.textSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(SamanWorkoutTokens.radiusMd)),
              borderSide: BorderSide(color: SamanWorkoutTokens.emeraldAccent, width: 1.5),
            ),
          ),
          onChanged: (value) => onSecondsChanged(
            RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null),
        ),
      ],
    ]),
  );
}

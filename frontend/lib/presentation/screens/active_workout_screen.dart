import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/workout_cv/presentation/screens/workout_cv_screen.dart';

import '../../data/models/exercise.dart';
import '../../features/workout/domain/entities/workout_plan.dart' as domain;
import '../providers/active_workout_providers.dart';
import '../providers/active_workout_state.dart';
import '../tokens/saman_workout_tokens.dart';
import '../providers/exercise_providers.dart';
import '../providers/workout_history_providers.dart';
import '../../features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import '../../features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import '../widgets/exercise_thumbnail.dart';
import 'workout_review_screen.dart';
import 'workout_complete_screen.dart';
import '../../features/journey/presentation/providers/journey_providers.dart';
import '../../features/journey/domain/models/journey_models.dart';

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
    final session = ref.read(activeWorkoutSessionProvider);
    if (widget.exercises != null) {
      notifier.startSession(widget.exercises!, title: widget.title);
    } else if (widget.workoutPlan != null) {
      notifier.startSessionFromPlan(widget.workoutPlan!);
    } else if (session.isFinished) {
      notifier.startScheduledSession();
    }
    _loadLastPerformanceHints();
  }

  Future<void> _loadLastPerformanceHints() async {
    try {
      final ids = ref
          .read(activeWorkoutSessionProvider)
          .exercises
          .map((e) => e.slug.isNotEmpty ? e.slug : e.id)
          .toList();
      if (ids.isEmpty) return;
      final hints = await ref
          .read(workoutSessionRepositoryProvider)
          .getLastPerformances(ids);
      if (mounted && hints.isNotEmpty) {
        ref
            .read(activeWorkoutSessionProvider.notifier)
            .applyLastPerformanceHints(hints);
      }
    } catch (_) {
      // Fail-silent: hints are optional (offline/test).
    }
  }

  String _formatWeight(double w) =>
      w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
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
    final t = SamanWorkoutTokens.of(context);
    final session = ref.watch(activeWorkoutSessionProvider);
    final notifier = ref.read(activeWorkoutSessionProvider.notifier);
    final currentEx = session.currentExercise;

    if (currentEx == null) {
      return Scaffold(
        backgroundColor: t.canvas,
        body: Center(
          child: CircularProgressIndicator(
            color: t.emeraldAccent,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Sticky In-Session Top Chrome
            _buildTopChrome(session, notifier, t),

            // Scrollable workout content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Horizon Progress
                    _buildHorizonProgress(session, currentEx, t),
                    const SizedBox(height: 16),

                    // Current Exercise Anchor Card
                    _buildCurrentExerciseAnchor(currentEx, t),
                    const SizedBox(height: 16),

                    // Compact Rest Strip (Only when resting)
                    if (session.isResting) ...[
                      _buildRestStrip(session, notifier, t),
                      const SizedBox(height: 16),
                    ],

                    // Scannable Set List Table
                    _buildSetListTable(currentEx, notifier, t),
                    const SizedBox(height: 20),

                    // Secondary Up Next Queue
                    _buildUpNextQueue(session, t),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildFooterDock(session, currentEx, notifier, t),
    );
  }

  Widget _buildTopChrome(
    ActiveWorkoutSessionState session,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: t.canvas,
        border: Border(
          bottom: BorderSide(
            color: t.borderSubtle,
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
                color: t.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: t.borderSubtle),
              ),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: t.textSecondary,
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
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
                          ? t.amberAccent
                          : t.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(session.elapsedSeconds),
                    key: const ValueKey('active_workout_timer_text'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                      color: t.emeraldAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (session.isPaused) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.amberAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: t.amberAccent.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        'PAUSED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: t.amberAccent,
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
                color: t.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                border: Border.all(color: t.borderSubtle),
              ),
              child: Text(
                'Finish',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.textPrimary,
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
    SamanWorkoutPalette t,
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
                style: TextStyle(
                  fontSize: 12,
                  color: t.textSecondary,
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
                style: TextStyle(
                  fontSize: 12,
                  color: t.emeraldAccent,
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
                  color: t.isDark ? const Color(0xFF262930) : t.border,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fillFraction.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.emeraldAccent,
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

  Widget _buildCurrentExerciseAnchor(
      ActiveExerciseInfo currentEx, SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image card with overlay buttons
        Container(
          width: double.infinity,
          height: 176,
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: t.borderSubtle),
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
              // Bottom gradient (keeps contrast behind floating dark pills)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFF0C0D0E).withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Floating Buttons on Image (dark translucent pills preserved across Light/Dark)
              Positioned(
                left: 10,
                bottom: 10,
                child: InkWell(
                  key: const ValueKey('active_workout_form_check_badge'),
                  onTap: () => _handleFormCheckTap(context, currentEx),
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0C0D0E),
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                      border: Border.all(color: const Color(0xFF26282F)),
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
                      border: Border.all(color: const Color(0xFF26282F)),
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
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: t.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          currentEx.subtitle,
          style: TextStyle(
            fontSize: 12,
            color: t.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildRestStrip(
    ActiveWorkoutSessionState session,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(
          color: t.emeraldAccent.withOpacity(0.35),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        t.emeraldAccent,
                      ),
                      backgroundColor:
                          t.isDark ? const Color(0xFF262930) : t.border,
                    ),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: t.emeraldAccent,
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
                  Text(
                    'REST',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: t.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    _formatTime(session.restSecondsLeft),
                    key: const ValueKey('active_workout_rest_timer_text'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: t.textPrimary,
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
                    color: t.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Text(
                    '+30s',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: t.textPrimary,
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
                    color: t.emeraldBadgeBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: t.emeraldBadgeBorder,
                    ),
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.emeraldAccent,
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
    SamanWorkoutPalette t,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column headers
        if (currentEx.unit == SetUnit.seconds)
          const _TimedSetHeader()
        else Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'SET',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: t.textMuted,
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
                    color: t.textMuted,
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
                    color: t.textMuted,
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
                    color: t.textMuted,
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
            return _buildCompletedSetRow(set, t);
          } else if (set.isActive) {
            return _buildActiveSetCard(set, currentEx, notifier, t);
          } else {
            return _buildUpcomingSetRow(set, t);
          }
        }),

        const SizedBox(height: 10),

        // Add set button
        InkWell(
          key: const ValueKey('active_workout_add_set_button'),
          onTap: notifier.isSavePendingConfirmation ? null : () => notifier.addSet(),
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
              border: Border.all(
                color: t.borderSubtle,
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add,
                  size: 15,
                  color: t.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Add set',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedSetRow(
      ActiveWorkoutSetInfo set, SamanWorkoutPalette t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.cardSurface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              set.setNumber.toString(),
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatWeight(set.weightKg ?? set.targetWeightKg),
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 11,
                    color: t.textMuted,
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
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: t.textPrimary,
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
                  color: t.emeraldBadgeBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: t.emeraldBadgeBorder,
                  ),
                ),
                child: Icon(
                  Icons.check,
                  size: 13,
                  color: t.emeraldAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastPerformancePill(
    ActiveExerciseInfo currentEx,
    LastExercisePerformance hint,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          notifier.setDraftWeight(hint.suggestedWeightKg);
          notifier.setDraftReps(
            hint.suggestedReps > 0 ? hint.suggestedReps : currentEx.draftReps,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.cardSurface,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: t.textSecondary,
              ),
              children: [
                TextSpan(
                  text:
                      'Lần trước: ${_formatWeight(hint.lastWeightKg)}kg × ${hint.lastReps} • ',
                ),
                TextSpan(
                  text: 'Gợi ý: ${_formatWeight(hint.suggestedWeightKg)}kg',
                  style: TextStyle(color: t.emeraldAccent),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSetCard(
    ActiveWorkoutSetInfo set,
    ActiveExerciseInfo currentEx,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    final stepperBg = t.isDark ? t.border : t.cardSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: t.borderHover),
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
                    decoration: BoxDecoration(
                      color: t.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SET ' + set.setNumber.toString() + ' (ACTIVE)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TARGET: ' + _formatWeight(set.targetWeightKg) + ' KG × ' + set.targetReps.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: t.textSecondary,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (currentEx.lastPerformance != null) ...[
            const SizedBox(height: 8),
            _buildLastPerformancePill(
                currentEx, currentEx.lastPerformance!, notifier, t),
          ],
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
                    color: stepperBg,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const ValueKey('active_workout_weight_minus'),
                        onTap: () => notifier.adjustDraftWeight(-1),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Text(
                            '−',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: t.textSecondary,
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
                                  _formatWeight(currentEx.draftWeightKg),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: t.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'kg',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: t.textSecondary,
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Text(
                            '+',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: t.textSecondary,
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
                    color: stepperBg,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const ValueKey('active_workout_reps_minus'),
                        onTap: () => notifier.adjustDraftReps(-1),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Text(
                            '−',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: t.textSecondary,
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
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'reps',
                            style: TextStyle(
                              fontSize: 11,
                              color: t.textSecondary,
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Text(
                            '+',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: t.textSecondary,
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

  Widget _buildUpcomingSetRow(
      ActiveWorkoutSetInfo set, SamanWorkoutPalette t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.cardSurface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(
          color: t.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              set.setNumber.toString(),
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatWeight(set.targetWeightKg),
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 11,
                    color: t.textMuted,
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
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '—',
                style: TextStyle(
                  fontSize: 14,
                  color: t.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpNextQueue(
      ActiveWorkoutSessionState session, SamanWorkoutPalette t) {
    final next = session.nextExercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'UP NEXT',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: t.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: InkWell(
                onTap: () => _showExerciseQueue(context, session),
                child: Text(
                'View all ${session.exerciseCount} exercises →',
                style: TextStyle(
                  fontSize: 12,
                  color: t.textSecondary,
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
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.borderSubtle),
                ),
                child: Icon(
                  Icons.fitness_center,
                  size: 18,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next?.name ?? 'No upcoming exercise',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      next?.subtitle ?? 'All exercises completed',
                      style: TextStyle(
                        fontSize: 11,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: t.textMuted,
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
    SamanWorkoutPalette t,
  ) {
    final activeSetNumber =
        currentEx.activeSet?.setNumber ?? (currentEx.completedSetsCount + 1);

    return Container(
      decoration: BoxDecoration(
        color: t.canvas,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
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
                  ? ((currentEx.canLogSet && !notifier.isSavePendingConfirmation) ? notifier.logActiveSet : null)
                  : session.nextExercise != null
                      ? notifier.nextExercise
                      : () => _showReviewScreen(context),
              icon: Icon(
                Icons.check,
                size: 18,
                color: t.buttonPrimaryText,
              ),
              label: Text(
                currentEx.activeSet != null ? 'Log Set $activeSetNumber'
                    : session.nextExercise != null ? 'Next exercise' : 'Review session',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: t.buttonPrimaryText,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.buttonPrimary,
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
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pause,
                      size: 15,
                      color: t.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Pause workout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: t.textSecondary,
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
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow,
                      size: 16,
                      color: t.emeraldAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Resume workout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.emeraldAccent,
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
    final t = SamanWorkoutTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.cardSurface,
      builder: (sheetContext) => SafeArea(child: ListView.builder(
        shrinkWrap: true,
        itemCount: session.exerciseCount,
        itemBuilder: (_, index) => ListTile(
          textColor: t.textPrimary,
          selectedColor: t.emeraldAccent,
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
      await ref.read(journeyControllerProvider.notifier).onActivityCompleted(
        type: JourneyTaskType.workout,
        activityId: savedSessionId,
      );
      if (!context.mounted) return;
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
    final t = SamanWorkoutTokens.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.cardSurface,
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
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Video Demo in Preparation · Verified Form Cues Active',
                style: TextStyle(
                  fontSize: 12,
                  color: t.emeraldAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Key Movement Cues:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: t.emeraldAccent, fontSize: 14)),
                    Expanded(
                      child: Text(
                        'Keep your feet firmly planted on the floor',
                        style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: t.emeraldAccent, fontSize: 14)),
                    Expanded(
                      child: Text(
                        'Retract your shoulder blades and maintain a slight natural arch',
                        style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: t.emeraldAccent, fontSize: 14)),
                    Expanded(
                      child: Text(
                        'Control the eccentric descent down to chest level',
                        style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.4),
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
                    backgroundColor: t.surfaceElevated,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      side: BorderSide(color: t.borderSubtle),
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

  Future<void> _handleFormCheckTap(
    BuildContext context,
    ActiveExerciseInfo currentEx,
  ) async {
    final t = SamanWorkoutTokens.of(context);
    // 1. Strictly verify exercise ID or slug (not display name, not ex_1/ex_2, not slug || cvSupported)
    final id = currentEx.id.toLowerCase().trim();
    final slug = currentEx.slug.toLowerCase().trim();
    final isSupported = WorkoutCvExerciseRegistry.isSupported(
      id: id,
      slug: slug,
    );

    // 2. Only active on Android platform for supported exercises
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    const bypassCheck = bool.fromEnvironment('BYPASS_CV_CHECK', defaultValue: false);
    if (!bypassCheck && (!isSupported || !isAndroid)) {
      _showFormCheckModal(context, cameraUnavailable: isSupported && !isAndroid);
      return;
    }

    final mode = await _showFormCheckSourceSheet(context);
    if (mode == null || !context.mounted) return;

    String? selectedVideoPath;
    if (mode == 'upload') {
      try {
        final XFile? picked =
            await ImagePicker().pickVideo(source: ImageSource.gallery);
        if (picked == null || picked.path.isEmpty) return;
        selectedVideoPath = picked.path;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to pick video: $e'),
              backgroundColor: t.surfaceElevated,
            ),
          );
        }
        return;
      }
    } else if (mode == 'realtime') {
      selectedVideoPath = null;
    }

    if (!context.mounted) return;

    // 3. Capture wasPaused and sessionId before opening CV
    final sessionNotifier = ref.read(activeWorkoutSessionProvider.notifier);
    final wasPaused = ref.read(activeWorkoutSessionProvider).isPaused;
    final currentSessionId = sessionNotifier.sessionId;

    // 4. Pause workout timer
    sessionNotifier.pauseWorkout();

    // 5. Navigate to WorkoutCvScreen
    final result = await Navigator.of(context).push<CvFormSummary>(
      MaterialPageRoute<CvFormSummary>(
        builder: (_) => WorkoutCvScreen(
          exerciseId: currentEx.id,
          exerciseSlug:
              currentEx.slug.isNotEmpty ? currentEx.slug : currentEx.id,
          exerciseName: currentEx.name,
          videoPath: selectedVideoPath,
        ),
      ),
    );

    if (!context.mounted) return;

    if (result != null &&
        result.totalReps > 0 &&
        sessionNotifier.sessionId == currentSessionId) {
      sessionNotifier.attachCvFormSummary(currentEx.id, result.toJson());
    }

    // 6. Resume ONLY if workout was active before opening and remains in the same unfinished session
    final currentSession = ref.read(activeWorkoutSessionProvider);
    if (sessionNotifier.sessionId == currentSessionId &&
        !currentSession.isFinished &&
        !wasPaused) {
      sessionNotifier.resumeWorkout();
    }
  }

  Future<String?> _showFormCheckSourceSheet(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: t.border, width: 1),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Header Area
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.border),
                          ),
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 20,
                            color: t.emeraldAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Form Check Mode',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                color: t.textPrimary,
                                letterSpacing: -0.2,
                                fontFamily: 'Space Grotesk',
                                fontFamilyFallback: const [
                                  'Manrope',
                                  'Inter',
                                  'sans-serif',
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'COMPUTER VISION ANALYSIS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: t.textSecondary,
                                letterSpacing: 1.0,
                                fontFamily: 'JetBrains Mono',
                                fontFamilyFallback: const [
                                  'monospace',
                                  'Courier New',
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: t.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: t.emeraldAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'AI VERIFIED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: t.textSub,
                              letterSpacing: 1.0,
                              fontFamily: 'JetBrains Mono',
                              fontFamilyFallback: const [
                                'monospace',
                                'Courier New',
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Criteria / Info Row
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: t.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.border),
                            ),
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: t.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'SELECT INPUT SOURCE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: t.textSecondary,
                              letterSpacing: 1.0,
                              fontFamily: 'JetBrains Mono',
                              fontFamilyFallback: const [
                                'monospace',
                                'Courier New',
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Pose AI · 30 FPS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary,
                          fontFamily: 'JetBrains Mono',
                          fontFamilyFallback: const [
                            'monospace',
                            'Courier New',
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Mode Selection Container (2 options)
                Container(
                  decoration: BoxDecoration(
                    color: t.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Option 1 — Record Real-time
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const ValueKey('form_check_mode_realtime'),
                          onTap: () => Navigator.of(modalCtx).pop('realtime'),
                          splashColor: t.surfaceElevated.withOpacity(0.2),
                          highlightColor: t.surfaceElevated.withOpacity(0.12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: t.surfaceElevated,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: t.border,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.videocam_outlined,
                                    size: 24,
                                    color: t.emeraldAccent,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Record Real-time',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary,
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'Manrope',
                                            'sans-serif',
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Use camera for live pose & rep tracking',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                          color: t.textSecondary,
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'Manrope',
                                            'sans-serif',
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.surfaceElevated,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: t.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: t.emeraldAccent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'LIVE',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: t.textSub,
                                              letterSpacing: 0.8,
                                              fontFamily: 'JetBrains Mono',
                                              fontFamilyFallback: const [
                                                'monospace',
                                                'Courier New',
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: t.textSecondary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: t.border,
                      ),
                      // Option 2 — Upload from Device
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const ValueKey('form_check_mode_upload'),
                          onTap: () => Navigator.of(modalCtx).pop('upload'),
                          splashColor: t.surfaceElevated.withOpacity(0.2),
                          highlightColor: t.surfaceElevated.withOpacity(0.12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: t.surfaceElevated,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: t.border,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.video_library_outlined,
                                    size: 24,
                                    color: t.textSub,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Upload from Device',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary,
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'Manrope',
                                            'sans-serif',
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Select an .mp4 workout video from gallery',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                          color: t.textSecondary,
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'Manrope',
                                            'sans-serif',
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.surfaceElevated,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: t.border,
                                        ),
                                      ),
                                      child: Text(
                                        'MP4',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: t.textSub,
                                          letterSpacing: 0.8,
                                          fontFamily: 'JetBrains Mono',
                                          fontFamilyFallback: const [
                                            'monospace',
                                            'Courier New',
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: t.textSecondary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Footer: Cancel Button
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: t.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('form_check_mode_cancel_button'),
                      onTap: () => Navigator.of(modalCtx).pop(),
                      splashColor: t.surfaceElevated.withOpacity(0.2),
                      highlightColor: t.surfaceElevated.withOpacity(0.12),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.textSub,
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['Manrope', 'sans-serif'],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFormCheckModal(BuildContext context, {bool cameraUnavailable = false}) {
    final t = SamanWorkoutTokens.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.cardSurface,
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
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: t.amberAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Form Check (Deferred)',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                cameraUnavailable
                    ? 'Camera CV chỉ hỗ trợ Android. Web/iOS chưa có replay landmarks được đóng gói để demo. Không gọi camera native, không tự ghi rep vào buổi tập.'
                    : 'Computer Vision Form Check is planned for a future release (deferred checkpoint). No camera feed has been activated and no reps will be auto-logged.',
                style: TextStyle(
                  fontSize: 13,
                  color: t.textSecondary,
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
                    backgroundColor: t.surfaceElevated,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      side: BorderSide(color: t.borderSubtle),
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
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Expanded(child: Text('SET', style: TextStyle(color: t.textMuted))),
        Expanded(flex: 3, child: Text('SECONDS', style: TextStyle(color: t.textMuted))),
        Text('STATUS', style: TextStyle(color: t.textMuted)),
      ]),
    );
  }
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
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 6),
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: isActive ? t.emeraldAccent : t.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(
            isActive ? 'SET ${set.setNumber} (ACTIVE)' : 'SET ${set.setNumber}',
            style: TextStyle(color: t.textSecondary),
          )),
          Text(isActive ? 'TARGET: ${set.targetSeconds} s'
              : '${set.isCompleted ? set.seconds : set.targetSeconds} s',
            style: TextStyle(color: t.textPrimary)),
          const SizedBox(width: 8),
          if (set.isCompleted) Icon(Icons.check,
            color: t.emeraldAccent, size: 18),
        ]),
        if (isActive) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('active_workout_seconds_input'),
            initialValue: draftSeconds?.toString() ?? '',
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.textPrimary),
            cursorColor: t.emeraldAccent,
            decoration: InputDecoration(
              labelText: 'Seconds', suffixText: 's', helperText: 'Enter 1-999 seconds',
              filled: true,
              fillColor: t.surfaceElevated,
              labelStyle: TextStyle(color: t.textSecondary),
              floatingLabelStyle: TextStyle(color: t.emeraldAccent),
              helperStyle: TextStyle(color: t.textSecondary),
              suffixStyle: TextStyle(color: t.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(SamanWorkoutTokens.radiusMd)),
                borderSide: BorderSide(color: t.textSecondary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(SamanWorkoutTokens.radiusMd)),
                borderSide: BorderSide(color: t.emeraldAccent, width: 1.5),
              ),
            ),
            onChanged: (value) => onSecondsChanged(
              RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null),
          ),
        ],
      ]),
    );
  }
}

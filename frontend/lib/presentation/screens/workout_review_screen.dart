import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/active_workout_providers.dart';
import '../providers/active_workout_state.dart';
import '../providers/workout_history_providers.dart';
import '../tokens/saman_workout_tokens.dart';

/// Checkpoint 06: Review & Save Screen (Standalone Pre-Save Screen)
/// Calm Athleticism obsidian visual hierarchy matching approved screen.png / code.html
class WorkoutReviewScreen extends ConsumerStatefulWidget {
  const WorkoutReviewScreen({super.key});

  @override
  ConsumerState<WorkoutReviewScreen> createState() =>
      _WorkoutReviewScreenState();
}

class _WorkoutReviewScreenState extends ConsumerState<WorkoutReviewScreen> {
  bool _isSubmitting = false;
  bool _saveError = false;

  String _formatWeight(double weight) {
    if (weight % 1 == 0) {
      return weight.toInt().toString();
    }
    return weight.toStringAsFixed(1);
  }

  String _formatVolume(double volume) {
    if (volume % 1 == 0) {
      return NumberFormat('#,##0').format(volume.toInt());
    }
    return NumberFormat('#,##0.#').format(volume);
  }

  Future<void> _handleSave() async {
    if (_isSubmitting) return;
    final active = ref.read(activeWorkoutSessionProvider);
    if (active.completedSetsCount == 0) return;

    setState(() {
      _isSubmitting = true;
      _saveError = false;
    });

    final notifier = ref.read(activeWorkoutSessionProvider.notifier);
    final sessionId = notifier.sessionId;
    final saver = ref.read(activeSessionSaverProvider.notifier);

    final success = await saver.saveCurrentSession();
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(sessionId);
    } else {
      setState(() {
        _saveError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeWorkoutSessionProvider);
    final saverState = ref.watch(activeSessionSaverProvider);
    final isSaving = _isSubmitting || saverState.isLoading;
    final hasError = _saveError || saverState.hasError;

    final performedExercises = session.exercises.where((exercise) {
      return exercise.sets.any((set) => set.isCompleted);
    }).toList();

    double totalVolume = 0.0;
    for (final exercise in performedExercises) {
      for (final set in exercise.sets.where((s) => s.isCompleted)) {
        final w = set.weightKg ?? 0.0;
        final r = set.reps ?? 0;
        totalVolume += w * r;
      }
    }

    final startedAtVn = ref
        .read(activeWorkoutSessionProvider.notifier)
        .startedAt
        .toUtc()
        .add(const Duration(hours: 7));
    final nowVn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final isToday = nowVn.year == startedAtVn.year &&
        nowVn.month == startedAtVn.month &&
        nowVn.day == startedAtVn.day;
    final dateStr = DateFormat('MMM d, yyyy').format(startedAtVn);
    final timeStr = DateFormat('h:mm a').format(startedAtVn);
    final sessionDateText =
        '${isToday ? 'Today • ' : ''}$dateStr • Started $timeStr';

    final activeDurationMinutes = session.elapsedSeconds ~/ 60;
    final canSave = session.completedSetsCount > 0 && !isSaving;

    return PopScope(
      canPop: !isSaving,
      child: Scaffold(
        backgroundColor: SamanWorkoutTokens.canvas,
        appBar: AppBar(
          backgroundColor: SamanWorkoutTokens.canvas,
          elevation: 0,
          scrolledUnderElevation: 0,
          leadingWidth: 160,
          leading: InkWell(
            key: const ValueKey('workout_review_back_button'),
            onTap: isSaving ? null : () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsetsDirectional.only(start: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Review session',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: Text(
                  'v2.4 LOCAL',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stage Tag
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SamanWorkoutTokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusXs),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 3,
                              backgroundColor: SamanWorkoutTokens.amberAccent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'STAGE • PENDING CONFIRMATION',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: SamanWorkoutTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sessionDateText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gym Editorial Banner
                  Container(
                    height: 144,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.cardSurface,
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      border: Border.all(color: SamanWorkoutTokens.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/home_workout_upper.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: SamanWorkoutTokens.cardSurface,
                            child: const Center(
                              child: Icon(
                                Icons.fitness_center,
                                size: 48,
                                color: SamanWorkoutTokens.border,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                SamanWorkoutTokens.canvas.withOpacity(0.9),
                                SamanWorkoutTokens.canvas.withOpacity(0.4),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  session.title.toUpperCase(),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: SamanWorkoutTokens.textSub,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.motion_photos_on,
                                    size: 14,
                                    color: SamanWorkoutTokens.emeraldAccent,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'READY TO SAVE',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                      color: SamanWorkoutTokens.emeraldAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Telemetry Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.cardSurface,
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      border: Border.all(color: SamanWorkoutTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TOTAL VOLUME',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: SamanWorkoutTokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      _formatVolume(totalVolume),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -1,
                                        color: SamanWorkoutTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'kg',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: SamanWorkoutTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'ACTIVE DURATION',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: SamanWorkoutTokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      activeDurationMinutes == 0
                                          ? '<1'
                                          : '$activeDurationMinutes',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.5,
                                        color: SamanWorkoutTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'min',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: SamanWorkoutTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(
                          color: SamanWorkoutTokens.border,
                          height: 1,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 3,
                              backgroundColor: SamanWorkoutTokens.emeraldAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${session.completedSetsCount} ${session.completedSetsCount == 1 ? 'set' : 'sets'} logged • ${performedExercises.length} ${performedExercises.length == 1 ? 'exercise' : 'exercises'}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SamanWorkoutTokens.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Movement Breakdown Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'RECORDED MOVEMENTS',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                      Text(
                        '${performedExercises.length} ITEMS',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Exercise Cards
                  for (final exercise in performedExercises) ...[
                    _buildExerciseCard(exercise),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 4),

                  // Pre-Save Session Notice
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.cardSurface,
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      border: Border.all(color: SamanWorkoutTokens.border),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Demo only. This workout will be kept in memory and will disappear when the app restarts. It is not synced.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Fixed Bottom Action Dock
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.canvas.withOpacity(0.95),
                  border: const Border(
                    top: BorderSide(color: SamanWorkoutTokens.border),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasError)
                        Container(
                          key: const ValueKey('save_error_banner'),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                SamanWorkoutTokens.crimsonAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(
                                SamanWorkoutTokens.radiusSm),
                            border: Border.all(
                                color: SamanWorkoutTokens.crimsonAccent),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: SamanWorkoutTokens.crimsonAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Failed to save session. Please retry.',
                                  style: TextStyle(
                                    color: SamanWorkoutTokens.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey('save_session_retry_button'),
                                onPressed: isSaving ? null : _handleSave,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(
                                    color: SamanWorkoutTokens.crimsonAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (session.completedSetsCount == 0)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'At least 1 completed set required to save',
                            style: TextStyle(
                              color: SamanWorkoutTokens.amberAccent,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          key: const ValueKey('save_session_button'),
                          onPressed: canSave ? _handleSave : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: SamanWorkoutTokens.buttonPrimary,
                            foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
                            disabledBackgroundColor:
                                SamanWorkoutTokens.surfaceElevated,
                            disabledForegroundColor:
                                SamanWorkoutTokens.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  SamanWorkoutTokens.radiusMd),
                            ),
                            elevation: 0,
                          ),
                          child: isSaving
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                SamanWorkoutTokens.canvas),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Committing log...',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Save session',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        key: const ValueKey('keep_training_button'),
                        onPressed:
                            isSaving ? null : () => Navigator.of(context).pop(),
                        child: const Text(
                          'Keep training',
                          style: TextStyle(
                            fontSize: 14,
                            color: SamanWorkoutTokens.textSecondary,
                          ),
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
    );
  }

  Widget _buildExerciseCard(ActiveExerciseInfo exercise) {
    final completedSets =
        exercise.sets.where((s) => s.isCompleted).toList();
    double exerciseVolume = 0.0;
    for (final s in completedSets) {
      final w = s.weightKg ?? 0.0;
      final r = s.reps ?? 0;
      exerciseVolume += w * r;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.surfaceElevated,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/workout.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.fitness_center,
                    color: SamanWorkoutTokens.textSecondary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            exercise.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: SamanWorkoutTokens.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Text(
                              _formatVolume(exerciseVolume),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: SamanWorkoutTokens.emeraldAccent,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'kg',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: SamanWorkoutTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (exercise.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        exercise.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sets Ledger
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: SamanWorkoutTokens.surfaceElevated,
              borderRadius:
                  BorderRadius.circular(SamanWorkoutTokens.radiusSm),
            ),
            child: Column(
              children: [
                for (int i = 0; i < completedSets.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      color: SamanWorkoutTokens.border,
                      height: 12,
                    ),
                  _buildSetRow(completedSets[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetRow(ActiveWorkoutSetInfo set) {
    final w = set.weightKg ?? 0.0;
    final r = set.reps ?? 0;
    final setVolume = w * r;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  'SET ${set.setNumber}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  '${_formatWeight(w)} kg × $r reps',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: SamanWorkoutTokens.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_formatVolume(setVolume)} kg',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: SamanWorkoutTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

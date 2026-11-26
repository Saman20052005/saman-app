import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_translations.dart';
import '../../features/workout_cv/presentation/screens/workout_cv_screen.dart';

import '../../data/models/exercise.dart';
import '../../features/workout/domain/entities/workout_plan.dart' as domain;
import '../providers/active_workout_providers.dart';
import '../providers/active_workout_state.dart';
import '../tokens/saman_workout_tokens.dart';
import '../providers/exercise_providers.dart';
import '../providers/workout_history_providers.dart';
import '../../features/workout_cv/data/services/workout_cv_quota_client.dart';
import '../../features/workout_cv/domain/services/cv_form_summary_calculator.dart';
import '../../features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import '../../features/membership/domain/models/membership_plan.dart';
import '../../features/membership/presentation/screens/plan_detail_screen.dart';
import '../../features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import '../widgets/exercise_thumbnail.dart';
import '../widgets/plate_calculator_sheet.dart';
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

  String _formatRpe(double rpe) =>
      rpe == rpe.roundToDouble() ? rpe.toInt().toString() : rpe.toStringAsFixed(1);

  String _tr(BuildContext context, String key) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return AppTranslations.text(key, locale);
  }

  bool _isVi(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return locale.languageCode == 'vi';
  }

  String _trOr(BuildContext context, String key, String en, String vi) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    final val = AppTranslations.text(key, locale);
    if (val != key) return val;
    return locale.languageCode == 'vi' ? vi : en;
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
    final t = SamanWorkoutTokens.of(context);
    ref.listen<ActiveWorkoutSessionState>(
      activeWorkoutSessionProvider,
      (prev, next) {
        if (prev != null && prev.restFinishedCount != next.restFinishedCount) {
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
          final messenger = ScaffoldMessenger.maybeOf(context);
          if (mounted && messenger != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    _tr(context, 'rest_finished_cue'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  backgroundColor: t.surfaceElevated,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
          }
        }
      },
    );

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
                    _buildCurrentExerciseAnchor(session, currentEx, notifier, t),
                    const SizedBox(height: 16),

                    // Compact Rest Strip (Only when resting)
                    if (session.isResting) ...[
                      _buildRestStrip(session, notifier, t),
                      const SizedBox(height: 16),
                    ],

                    // Scannable Set List Table
                    _buildSetListTable(session, currentEx, notifier, t),
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
                    fontFamily: 'Manrope',
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
                        _isVi(context) ? 'TẠM DỪNG' : 'PAUSED',
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
                _trOr(context, 'finish_btn', 'Finish', 'Hoàn thành'),
                style: TextStyle(
                  fontFamily: 'Manrope',
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
    final isVi = _isVi(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                isVi
                    ? 'Bài ${session.currentExerciseNumber} / ${session.exerciseCount}'
                    : 'Exercise ${session.currentExerciseNumber} of ${session.exerciseCount}',
                style: TextStyle(
                  fontFamily: 'Manrope',
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
                isVi
                    ? 'Đã xong ${currentEx.completedSetsCount}/${currentEx.totalSetsCount} hiệp'
                    : '${currentEx.completedSetsCount} of ${currentEx.totalSetsCount} sets completed',
                style: TextStyle(
                  fontFamily: 'Manrope',
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
    ActiveWorkoutSessionState session,
    ActiveExerciseInfo currentEx,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    final exIdx = session.currentExerciseIndex;
    final supersetBadge = session.supersetBadgeLabel(exIdx);
    final hasNext = exIdx + 1 < session.exerciseCount;
    final isLinkedWithNext = hasNext &&
        currentEx.supersetGroupId != null &&
        currentEx.supersetGroupId == session.nextExercise?.supersetGroupId;

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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt_outlined,
                          size: 14,
                          color: SamanWorkoutTokens.emeraldAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isVi(context) ? 'Kiểm tra Form' : 'Form Check',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          size: 15,
                          color: SamanWorkoutTokens.emeraldAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isVi(context) ? 'Video hướng dẫn' : 'Video Guide',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
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
        if (supersetBadge != null) ...[
          Container(
            key: const ValueKey('active_workout_superset_badge'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: t.tealAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusXs),
              border: Border.all(color: t.tealAccent.withOpacity(0.45)),
            ),
            child: Text(
              '${_tr(context, 'superset_label')} $supersetBadge',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: t.tealLightAccent,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          currentEx.name,
          style: TextStyle(
            fontFamily: 'Manrope',
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
            fontFamily: 'Manrope',
            fontSize: 12,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            InkWell(
              key: const ValueKey('active_workout_note_button'),
              onTap: () => _showExerciseNoteSheet(
                context,
                exIdx,
                currentEx.note,
                notifier,
              ),
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.cardSurface,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                  border: Border.all(
                    color: currentEx.note.trim().isNotEmpty
                        ? t.emeraldBadgeBorder
                        : t.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 15,
                      color: currentEx.note.trim().isNotEmpty
                          ? t.emeraldAccent
                          : t.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        currentEx.note.trim().isNotEmpty
                            ? currentEx.note.trim()
                            : _tr(context, 'exercise_note_hint'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: currentEx.note.trim().isNotEmpty
                              ? t.textPrimary
                              : t.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasNext)
              InkWell(
                key: const ValueKey('active_workout_toggle_superset_button'),
                onTap: () => notifier.toggleSupersetWithNext(exIdx),
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLinkedWithNext
                        ? t.tealAccent.withOpacity(0.15)
                        : t.cardSurface,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                    border: Border.all(
                      color: isLinkedWithNext
                          ? t.tealAccent.withOpacity(0.45)
                          : t.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLinkedWithNext ? Icons.link_off : Icons.link,
                        size: 14,
                        color: isLinkedWithNext
                            ? t.tealLightAccent
                            : t.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _tr(
                          context,
                          isLinkedWithNext
                              ? 'superset_unlink'
                              : 'superset_link',
                        ),
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isLinkedWithNext
                              ? t.tealLightAccent
                              : t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
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
                    _isVi(context) ? 'NGHỈ' : 'REST',
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
                    _isVi(context) ? 'Bỏ qua' : 'Skip',
                    style: TextStyle(
                      fontFamily: 'Manrope',
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
    ActiveWorkoutSessionState session,
    ActiveExerciseInfo currentEx,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    final exIdx = session.currentExerciseIndex;
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
                  _isVi(context) ? 'HIỆP' : 'SET',
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
                  _isVi(context) ? 'TRẠNG THÁI' : 'STATUS',
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
        for (var setIdx = 0; setIdx < currentEx.sets.length; setIdx++)
          Builder(
            builder: (_) {
              final set = currentEx.sets[setIdx];
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
                return _buildCompletedSetRow(exIdx, setIdx, set, notifier, t);
              } else if (set.isActive) {
                return _buildActiveSetCard(
                  exIdx,
                  setIdx,
                  set,
                  currentEx,
                  notifier,
                  t,
                );
              } else {
                return _buildUpcomingSetRow(exIdx, setIdx, set, notifier, t);
              }
            },
          ),

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
                  _isVi(context) ? 'Thêm hiệp' : 'Add set',
                  style: TextStyle(
                    fontFamily: 'Manrope',
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
    int exIdx,
    int setIdx,
    ActiveWorkoutSetInfo set,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: t.cardSurface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(
          color: set.isPr ? t.amberAccent.withOpacity(0.45) : t.borderSubtle,
        ),
      ),
      child: InkWell(
        key: ValueKey('completed_set_row_$setIdx'),
        onTap: () => _showEditCompletedSetSheet(
          context,
          exIdx,
          setIdx,
          set,
          notifier,
        ),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SetTypeBadge(
                        key: ValueKey('set_type_badge_${exIdx}_$setIdx'),
                        setType: set.setType,
                        setNumber: set.setNumber,
                        palette: t,
                        onTap: () => _showSetTypePicker(
                          context,
                          exIdx,
                          setIdx,
                          set.setType,
                          notifier,
                        ),
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
              if (set.isPr || set.rpe != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (set.isPr)
                      Container(
                        key: ValueKey('set_pr_badge_$setIdx'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: t.amberAccent.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusXs,
                          ),
                          border: Border.all(
                            color: t.amberAccent.withOpacity(0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              size: 12,
                              color: t.amberAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _tr(context, 'pr_badge'),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: t.amberAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (set.rpe != null)
                      Container(
                        key: ValueKey('set_rpe_badge_$setIdx'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: t.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusXs,
                          ),
                          border: Border.all(color: t.borderSubtle),
                        ),
                        child: Text(
                          '${_tr(context, 'rpe_label')} ${_formatRpe(set.rpe!)}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastPerformancePill(
    ActiveExerciseInfo currentEx,
    LastExercisePerformance hint,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    final lastWeight = _formatWeight(hint.lastWeightKg);
    final suggestedWeight = _formatWeight(hint.suggestedWeightKg);
    final targetReps =
        hint.suggestedReps > 0 ? hint.suggestedReps : currentEx.draftReps;
    final score = hint.cvFormScore;
    final Color? scoreColor = score == null
        ? null
        : (score >= 85
            ? t.emeraldAccent
            : (score < 70 ? t.amberAccent : t.tealLightAccent));

    String? cvSuggestionText;
    Color suggestionColor = t.emeraldAccent;
    switch (hint.suggestionReason) {
      case 'cv_form_verified_add_weight':
        cvSuggestionText =
            '${_tr(context, 'cv_overload_add_weight')} → ${suggestedWeight}kg × $targetReps';
        suggestionColor = t.emeraldAccent;
        break;
      case 'cv_form_verified_add_rep':
        cvSuggestionText =
            '${_tr(context, 'cv_overload_add_rep')} → $targetReps reps';
        suggestionColor = t.emeraldAccent;
        break;
      case 'cv_form_refine_technique':
        cvSuggestionText =
            '${_tr(context, 'cv_overload_refine_form')} (${lastWeight}kg × ${hint.lastReps})';
        suggestionColor = t.amberAccent;
        break;
      default:
        cvSuggestionText = null;
    }

    void applyOverload() {
      notifier.setDraftWeight(hint.suggestedWeightKg);
      notifier.setDraftReps(targetReps);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.cardSurface,
        border: Border.all(
          color: scoreColor != null ? scoreColor.withOpacity(0.35) : t.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (cvSuggestionText != null)
                      Text(
                        _isVi(context)
                            ? 'Lần trước: ${lastWeight}kg × ${hint.lastReps}'
                            : 'Last: ${lastWeight}kg × ${hint.lastReps}',
                        softWrap: true,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: t.textSecondary,
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isVi(context)
                                ? 'Lần trước: ${lastWeight}kg × ${hint.lastReps}'
                                : 'Last: ${lastWeight}kg × ${hint.lastReps}',
                            softWrap: true,
                            maxLines: 2,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: t.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isVi(context)
                                ? 'Gợi ý: ${suggestedWeight}kg'
                                : 'Suggested: ${suggestedWeight}kg',
                            softWrap: true,
                            maxLines: 2,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: t.emeraldAccent,
                            ),
                          ),
                        ],
                      ),
                    if (score != null && scoreColor != null)
                      Container(
                        key: const ValueKey(
                          'active_workout_cv_form_score_badge',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scoreColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusXs,
                          ),
                          border: Border.all(
                            color: scoreColor.withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          '${_tr(context, 'cv_form_score_badge')}: $score%',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: scoreColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('active_workout_apply_overload_button'),
                  onTap: applyOverload,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.emeraldBadgeBg,
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                      border: Border.all(color: t.emeraldBadgeBorder),
                    ),
                    child: Text(
                      _tr(context, 'apply_btn'),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.emeraldAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (cvSuggestionText != null) ...[
            const SizedBox(height: 5),
            Text(
              cvSuggestionText,
              key: const ValueKey('active_workout_cv_overload_suggestion_text'),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: suggestionColor,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveSetCard(
    int exIdx,
    int setIdx,
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
                  _SetTypeBadge(
                    key: ValueKey('set_type_badge_${exIdx}_$setIdx'),
                    setType: set.setType,
                    setNumber: set.setNumber,
                    palette: t,
                    onTap: () => _showSetTypePicker(
                      context,
                      exIdx,
                      setIdx,
                      set.setType,
                      notifier,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: t.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isVi(context)
                        ? 'HIỆP ${set.setNumber} (ĐANG TẬP)'
                        : 'SET ${set.setNumber} (ACTIVE)',
                    style: TextStyle(
                      fontFamily: 'Manrope',
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
                  _isVi(context)
                      ? 'MỤC TIÊU: ${_formatWeight(set.targetWeightKg)} KG × ${set.targetReps}'
                      : 'TARGET: ${_formatWeight(set.targetWeightKg)} KG × ${set.targetReps}',
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
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                key: const ValueKey('active_workout_rpe_button'),
                onTap: () => _showRpePicker(
                  context,
                  exIdx,
                  setIdx,
                  set.rpe,
                  notifier,
                ),
                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: set.rpe != null
                        ? t.emeraldBadgeBg
                        : t.cardSurface,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                    border: Border.all(
                      color: set.rpe != null
                          ? t.emeraldBadgeBorder
                          : t.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 13,
                        color: set.rpe != null
                            ? t.emeraldAccent
                            : t.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        set.rpe != null
                            ? '${_tr(context, 'rpe_label')} ${_formatRpe(set.rpe!)}'
                            : _tr(context, 'rpe_label'),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: set.rpe != null
                              ? t.emeraldAccent
                              : t.textSecondary,
                        ),
                      ),
                    ],
                  ),
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

          // Steppers + Plate Calculator
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
                                  key: const ValueKey(
                                    'active_workout_draft_weight',
                                  ),
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
              const SizedBox(width: 6),

              // Plate Calculator button
              InkWell(
                key: const ValueKey('active_workout_plate_calc_button'),
                onTap: () => showPlateCalculatorSheet(
                  context,
                  initialWeightKg: currentEx.draftWeightKg,
                  onApplyWeight: (weight) => notifier.setDraftWeight(weight),
                ),
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                child: Container(
                  width: 38,
                  height: 46,
                  decoration: BoxDecoration(
                    color: stepperBg,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Icon(
                    Icons.calculate_outlined,
                    size: 18,
                    color: t.emeraldAccent,
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
    int exIdx,
    int setIdx,
    ActiveWorkoutSetInfo set,
    ActiveWorkoutSessionNotifier notifier,
    SamanWorkoutPalette t,
  ) {
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SetTypeBadge(
                key: ValueKey('set_type_badge_${exIdx}_$setIdx'),
                setType: set.setType,
                setNumber: set.setNumber,
                palette: t,
                onTap: () => _showSetTypePicker(
                  context,
                  exIdx,
                  setIdx,
                  set.setType,
                  notifier,
                ),
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
    final isVi = _isVi(context);
    final next = session.nextExercise;
    final nextSupersetBadge = next != null
        ? session.supersetBadgeLabel(session.currentExerciseIndex + 1)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isVi ? 'TIẾP THEO' : 'UP NEXT',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: t.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    key: const ValueKey('active_workout_reorder_button'),
                    onTap: () => _showExerciseQueue(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: t.cardSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: t.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_vert_rounded,
                            size: 13,
                            color: t.emeraldAccent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _tr(context, 'reorder_short'),
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: InkWell(
                      key: const ValueKey('active_workout_open_queue_button'),
                      onTap: () => _showExerciseQueue(context),
                      child: Text(
                        isVi
                            ? 'Xem tất cả ${session.exerciseCount} bài tập →'
                            : 'View all ${session.exerciseCount} ${session.exerciseCount == 1 ? 'exercise' : 'exercises'} →',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          color: t.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showExerciseQueue(context),
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
          child: Container(
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
                      Row(
                        children: [
                          if (nextSupersetBadge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: t.tealAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: t.tealAccent.withOpacity(0.45),
                                ),
                              ),
                              child: Text(
                                nextSupersetBadge,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: t.tealLightAccent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              next?.name ??
                                  (isVi
                                      ? 'Không còn bài tập tiếp theo'
                                      : 'No upcoming exercise'),
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: t.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        next?.subtitle ??
                            (isVi
                                ? 'Đã hoàn thành tất cả bài tập'
                                : 'All exercises completed'),
                        style: TextStyle(
                          fontFamily: 'Manrope',
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
                currentEx.activeSet != null
                    ? (_isVi(context)
                        ? 'Ghi hiệp $activeSetNumber'
                        : 'Log Set $activeSetNumber')
                    : session.nextExercise != null
                        ? (_isVi(context)
                            ? 'Bài tập tiếp theo'
                            : 'Next exercise')
                        : _trOr(
                            context,
                            'review_session_title',
                            'Review session',
                            'Xem lại buổi tập',
                          ),
                style: TextStyle(
                  fontFamily: 'Manrope',
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
                      _isVi(context) ? 'Tạm dừng buổi tập' : 'Pause workout',
                      style: TextStyle(
                        fontFamily: 'Manrope',
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
                      _isVi(context) ? 'Tiếp tục buổi tập' : 'Resume workout',
                      style: TextStyle(
                        fontFamily: 'Manrope',
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

  void _showExerciseQueue(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SamanWorkoutTokens.radiusXl),
            ),
            border: Border(
              top: BorderSide(color: t.border),
              left: BorderSide(color: t.border),
              right: BorderSide(color: t.border),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Consumer(
              builder: (ctx, consumerRef, _) {
                final liveSession =
                    consumerRef.watch(activeWorkoutSessionProvider);
                final notifier =
                    consumerRef.read(activeWorkoutSessionProvider.notifier);

                // Generate stable unique keys even if an exercise id appears twice.
                final seenIds = <String, int>{};
                final itemKeys = liveSession.exercises.map((ex) {
                  final count = seenIds[ex.id] ?? 0;
                  seenIds[ex.id] = count + 1;
                  return ValueKey('queue_ex_${ex.id}_$count');
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: t.borderHover,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _tr(ctx, 'exercise_queue_title'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('queue_close_button'),
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: Icon(
                                  Icons.close,
                                  color: t.textSecondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: t.border),
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        itemCount: liveSession.exerciseCount,
                        onReorder: notifier.reorderExercises,
                        itemBuilder: (_, index) {
                          final ex = liveSession.exercises[index];
                          final isCurrent =
                              index == liveSession.currentExerciseIndex;
                          final badge = liveSession.supersetBadgeLabel(index);
                          final inSuperset =
                              liveSession.isInSuperset(index) || badge != null;
                          final hasNext = index + 1 < liveSession.exerciseCount;
                          final isLinkedToNext = hasNext &&
                              ex.supersetGroupId != null &&
                              ex.supersetGroupId ==
                                  liveSession
                                      .exercises[index + 1].supersetGroupId;

                          return Container(
                            key: itemKeys[index],
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? t.emeraldBadgeBg
                                  : t.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                SamanWorkoutTokens.radiusMd,
                              ),
                              border: Border.all(
                                color: isCurrent
                                    ? t.emeraldBadgeBorder
                                    : t.borderSubtle,
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  if (inSuperset)
                                    Container(
                                      key: ValueKey(
                                        'queue_superset_bar_$index',
                                      ),
                                      width: 4,
                                      decoration: BoxDecoration(
                                        color: t.tealAccent,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                          left: Radius.circular(
                                            SamanWorkoutTokens.radiusMd,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        notifier.selectExercise(index);
                                        Navigator.of(sheetContext).pop();
                                      },
                                      borderRadius: BorderRadius.circular(
                                        SamanWorkoutTokens.radiusMd,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      if (badge != null) ...[
                                                        Container(
                                                          key: ValueKey(
                                                            'queue_superset_badge_$index',
                                                          ),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: t.tealAccent
                                                                .withOpacity(
                                                                    0.16),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                            border: Border.all(
                                                              color: t.tealAccent
                                                                  .withOpacity(
                                                                      0.45),
                                                            ),
                                                          ),
                                                          child: Text(
                                                            badge,
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  'monospace',
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: t
                                                                  .tealLightAccent,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                      ],
                                                      Expanded(
                                                        child: Text(
                                                          ex.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontFamily:
                                                                'Manrope',
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isCurrent
                                                                ? t
                                                                    .emeraldAccent
                                                                : t.textPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    _isVi(ctx)
                                                        ? '${ex.completedSetsCount}/${ex.totalSetsCount} hiệp'
                                                        : '${ex.completedSetsCount}/${ex.totalSetsCount} ${ex.totalSetsCount == 1 ? 'set' : 'sets'}',
                                                    style: TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 11,
                                                      color: t.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (hasNext)
                                              IconButton(
                                                key: ValueKey(
                                                  'queue_superset_toggle_$index',
                                                ),
                                                tooltip: _tr(
                                                  ctx,
                                                  isLinkedToNext
                                                      ? 'superset_unlink'
                                                      : 'superset_link',
                                                ),
                                                onPressed: () => notifier
                                                    .toggleSupersetWithNext(
                                                        index),
                                                icon: Icon(
                                                  isLinkedToNext
                                                      ? Icons.link_off
                                                      : Icons.link,
                                                  size: 18,
                                                  color: isLinkedToNext
                                                      ? t.tealLightAccent
                                                      : t.textSecondary,
                                                ),
                                              ),
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.drag_handle,
                                                  key: ValueKey(
                                                    'queue_drag_handle_$index',
                                                  ),
                                                  size: 20,
                                                  color: t.textMuted,
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
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showSetTypePicker(
    BuildContext context,
    int exIdx,
    int setIdx,
    SetType currentType,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    final t = SamanWorkoutTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SamanWorkoutTokens.radiusXl),
            ),
            border: Border(
              top: BorderSide(color: t.border),
              left: BorderSide(color: t.border),
              right: BorderSide(color: t.border),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.borderHover,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _tr(sheetContext, 'set_type_title'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final type in SetType.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        key: ValueKey('set_type_option_${type.name}'),
                        onTap: () {
                          notifier.setSetType(exIdx, setIdx, type);
                          Navigator.of(sheetContext).pop();
                        },
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: currentType == type
                                ? t.emeraldBadgeBg
                                : t.surfaceElevated,
                            borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusMd,
                            ),
                            border: Border.all(
                              color: currentType == type
                                  ? t.emeraldBadgeBorder
                                  : t.borderSubtle,
                            ),
                          ),
                          child: Row(
                            children: [
                              _SetTypeBadge(
                                setType: type,
                                setNumber: setIdx + 1,
                                palette: t,
                                onTap: () {
                                  notifier.setSetType(exIdx, setIdx, type);
                                  Navigator.of(sheetContext).pop();
                                },
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _labelForSetType(sheetContext, type),
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                              if (currentType == type)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: t.emeraldAccent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _labelForSetType(BuildContext context, SetType type) {
    switch (type) {
      case SetType.warmup:
        return _tr(context, 'warmup');
      case SetType.normal:
        return _tr(context, 'normal');
      case SetType.drop:
        return _tr(context, 'drop_set');
      case SetType.failure:
        return _tr(context, 'failure_set');
    }
  }

  void _showRpePicker(
    BuildContext context,
    int exIdx,
    int setIdx,
    double? currentRpe,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    const rpeValues = <double>[
      6.0,
      6.5,
      7.0,
      7.5,
      8.0,
      8.5,
      9.0,
      9.5,
      10.0,
    ];
    final t = SamanWorkoutTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SamanWorkoutTokens.radiusXl),
            ),
            border: Border(
              top: BorderSide(color: t.border),
              left: BorderSide(color: t.border),
              right: BorderSide(color: t.border),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.borderHover,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _tr(sheetContext, 'rpe_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      if (currentRpe != null)
                        TextButton(
                          key: const ValueKey('rpe_option_clear'),
                          onPressed: () {
                            notifier.setSetRpe(exIdx, setIdx, null);
                            Navigator.of(sheetContext).pop();
                          },
                          child: Text(
                            _tr(sheetContext, 'rpe_clear'),
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.crimsonAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: rpeValues.map((val) {
                      final isSelected = currentRpe != null &&
                          (currentRpe - val).abs() < 0.05;
                      return InkWell(
                        key: ValueKey('rpe_option_${_formatRpe(val)}'),
                        onTap: () {
                          notifier.setSetRpe(exIdx, setIdx, val);
                          Navigator.of(sheetContext).pop();
                        },
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                        child: Container(
                          width: 68,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? t.emeraldBadgeBg
                                : t.surfaceElevated,
                            borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusMd,
                            ),
                            border: Border.all(
                              color: isSelected
                                  ? t.emeraldBadgeBorder
                                  : t.borderSubtle,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _formatRpe(val),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? t.emeraldAccent
                                    : t.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showExerciseNoteSheet(
    BuildContext context,
    int exIdx,
    String initialNote,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseNoteSheet(
        initialNote: initialNote,
        onSave: (note) => notifier.setExerciseNote(exIdx, note),
      ),
    );
  }

  void _showEditCompletedSetSheet(
    BuildContext context,
    int exIdx,
    int setIdx,
    ActiveWorkoutSetInfo set,
    ActiveWorkoutSessionNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCompletedSetSheet(
        setInfo: set,
        onSave: (weightKg, reps, rpe, setType) {
          notifier.updateCompletedSet(
            setIndex: setIdx,
            weightKg: weightKg,
            reps: reps,
            rpe: rpe,
            setType: setType,
          );
        },
      ),
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
        final isVi = _isVi(modalCtx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isVi
                    ? '${currentEx.name} — Video hướng dẫn'
                    : '${currentEx.name} — Video Guide',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isVi
                    ? 'Video minh họa đang chuẩn bị · Hướng dẫn kỹ thuật đã kích hoạt'
                    : 'Video Demo in Preparation · Verified Form Cues Active',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: t.emeraldAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isVi ? 'Lưu ý kỹ thuật chính:' : 'Key Movement Cues:',
                style: TextStyle(
                  fontFamily: 'Manrope',
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
                        isVi
                            ? 'Giữ bàn chân đặt chắc chắn trên sàn'
                            : 'Keep your feet firmly planted on the floor',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          color: t.textSecondary,
                          height: 1.4,
                        ),
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
                        isVi
                            ? 'Khép chặt xương bả vai và giữ độ cong lưng tự nhiên'
                            : 'Retract your shoulder blades and maintain a slight natural arch',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          color: t.textSecondary,
                          height: 1.4,
                        ),
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
                        isVi
                            ? 'Kiểm soát nhịp hạ tạ xuống ngang ngực'
                            : 'Control the eccentric descent down to chest level',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          color: t.textSecondary,
                          height: 1.4,
                        ),
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
                  child: Text(
                    _tr(modalCtx, 'close'),
                    style: const TextStyle(fontFamily: 'Manrope'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openWorkoutCvPaywall(BuildContext context) async {
    final selectedTier = await showUpgradeBottomSheet(
      context,
      tier: MembershipTier.pro,
    );
    if (!context.mounted || selectedTier == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings:
            RouteSettings(name: '/membership/detail/${selectedTier.name}'),
        builder: (_) => PlanDetailScreen(tier: selectedTier),
      ),
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
              content: Text(
                _isVi(context)
                    ? 'Không thể chọn video: $e'
                    : 'Failed to pick video: $e',
              ),
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

    final authResult = await ref.read(workoutCvQuotaClientProvider).authorize(
          exerciseSlug:
              currentEx.slug.isNotEmpty ? currentEx.slug : currentEx.id,
          sourceMode: mode == 'upload' ? 'video_upload' : 'realtime',
        );
    if (!context.mounted) return;

    if (!authResult.allowed) {
      if (authResult.isQuotaExhausted || authResult.isUpgradeRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authResult.message ??
                  'Bạn đã dùng hết lượt Form Check AI trong tuần. Nâng cấp Pro để dùng không giới hạn.',
            ),
            backgroundColor: t.surfaceElevated,
          ),
        );
        await _openWorkoutCvPaywall(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authResult.message ??
                  'Không thể kiểm tra hạn mức Form Check AI lúc này. Vui lòng thử lại.',
            ),
            backgroundColor: t.surfaceElevated,
          ),
        );
      }
      return;
    }

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
      sessionNotifier.attachCvFormSummary(
        currentEx.id,
        result.toJson(),
        repTimeline: result.repTimeline,
        videoStoryId: result.videoStoryId,
      );
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
        final isVi = _isVi(modalCtx);
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
                              isVi ? 'Chế độ Kiểm tra Form' : 'Form Check Mode',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                color: t.textPrimary,
                                letterSpacing: -0.2,
                                fontFamily: 'Manrope',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isVi
                                  ? 'PHÂN TÍCH COMPUTER VISION'
                                  : 'COMPUTER VISION ANALYSIS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: t.textSecondary,
                                letterSpacing: 1.0,
                                fontFamily: 'monospace',
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
                            isVi ? 'AI XÁC THỰC' : 'AI VERIFIED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: t.textSub,
                              letterSpacing: 1.0,
                              fontFamily: 'monospace',
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
                            isVi ? 'CHỌN NGUỒN VIDEO' : 'SELECT INPUT SOURCE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: t.textSecondary,
                              letterSpacing: 1.0,
                              fontFamily: 'monospace',
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
                          fontFamily: 'monospace',
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
                                        isVi
                                            ? 'Quay trực tiếp'
                                            : 'Record Real-time',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary,
                                          fontFamily: 'Manrope',
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isVi
                                            ? 'Dùng camera để đếm rep & chấm form trực tiếp'
                                            : 'Use camera for live pose & rep tracking',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                          color: t.textSecondary,
                                          fontFamily: 'Manrope',
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
                                              fontFamily: 'monospace',
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
                                        isVi
                                            ? 'Tải video từ máy'
                                            : 'Upload from Device',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary,
                                          fontFamily: 'Manrope',
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isVi
                                            ? 'Chọn video tập luyện .mp4 từ thư viện'
                                            : 'Select an .mp4 workout video from gallery',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                          color: t.textSecondary,
                                          fontFamily: 'Manrope',
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
                                          fontFamily: 'monospace',
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
                          _tr(modalCtx, 'cancel'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.textSub,
                            fontFamily: 'Manrope',
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
        final isVi = _isVi(modalCtx);
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
                  Expanded(
                    child: Text(
                      isVi
                          ? 'Kiểm tra Form trực tiếp (Chưa hỗ trợ)'
                          : 'Live Form Check (Deferred)',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                cameraUnavailable
                    ? (isVi
                        ? 'Camera CV chỉ hỗ trợ Android. Web/iOS chưa có replay landmarks được đóng gói để demo. Không gọi camera native, không tự ghi rep vào buổi tập.'
                        : 'CV Camera is only supported on Android. Web/iOS does not include packaged demo landmarks. Native camera is not opened and no reps are auto-logged.')
                    : (isVi
                        ? 'Tính năng Kiểm tra Form bằng Computer Vision đang được lên kế hoạch cho phiên bản tới. Camera chưa được kích hoạt và không có rep nào được tự động ghi.'
                        : 'Computer Vision Form Check is planned for a future release (deferred checkpoint). No camera feed has been activated and no reps will be auto-logged.'),
                style: TextStyle(
                  fontFamily: 'Manrope',
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
                  child: Text(
                    _tr(modalCtx, 'close'),
                    style: const TextStyle(fontFamily: 'Manrope'),
                  ),
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
    final isVi =
        (Localizations.maybeLocaleOf(context)?.languageCode ?? 'en') == 'vi';
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Expanded(child: Text(isVi ? 'HIỆP' : 'SET', style: TextStyle(color: t.textMuted))),
        Expanded(flex: 3, child: Text(isVi ? 'GIÂY' : 'SECONDS', style: TextStyle(color: t.textMuted))),
        Text(isVi ? 'TRẠNG THÁI' : 'STATUS', style: TextStyle(color: t.textMuted)),
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
    final isVi =
        (Localizations.maybeLocaleOf(context)?.languageCode ?? 'en') == 'vi';
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
            isActive
                ? (isVi ? 'HIỆP ${set.setNumber} (ĐANG TẬP)' : 'SET ${set.setNumber} (ACTIVE)')
                : (isVi ? 'HIỆP ${set.setNumber}' : 'SET ${set.setNumber}'),
            style: TextStyle(fontFamily: 'Manrope', color: t.textSecondary),
          )),
          Text(
            isActive
                ? (isVi ? 'MỤC TIÊU: ${set.targetSeconds} s' : 'TARGET: ${set.targetSeconds} s')
                : '${set.isCompleted ? set.seconds : set.targetSeconds} s',
            style: TextStyle(fontFamily: 'monospace', color: t.textPrimary),
          ),
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
              labelText: isVi ? 'Số giây' : 'Seconds',
              suffixText: 's',
              helperText: isVi ? 'Nhập 1-999 giây' : 'Enter 1-999 seconds',
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

class _SetTypeBadge extends StatelessWidget {
  const _SetTypeBadge({
    super.key,
    required this.setType,
    required this.setNumber,
    required this.palette,
    required this.onTap,
  });

  final SetType setType;
  final int setNumber;
  final SamanWorkoutPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color fg;
    final Color bg;
    final Color border;

    switch (setType) {
      case SetType.warmup:
        label = 'W';
        fg = palette.amberAccent;
        bg = palette.amberAccent.withOpacity(0.15);
        border = palette.amberAccent.withOpacity(0.38);
      case SetType.normal:
        label = setNumber.toString();
        fg = palette.textSecondary;
        bg = palette.surfaceElevated;
        border = palette.borderSubtle;
      case SetType.drop:
        label = 'D';
        fg = const Color(0xFF818CF8);
        bg = const Color(0xFF818CF8).withOpacity(0.15);
        border = const Color(0xFF818CF8).withOpacity(0.38);
      case SetType.failure:
        label = 'F';
        fg = palette.crimsonAccent;
        bg = palette.crimsonAccent.withOpacity(0.15);
        border = palette.crimsonAccent.withOpacity(0.38);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: Container(
            constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseNoteSheet extends StatefulWidget {
  const _ExerciseNoteSheet({
    required this.initialNote,
    required this.onSave,
  });

  final String initialNote;
  final ValueChanged<String> onSave;

  @override
  State<_ExerciseNoteSheet> createState() => _ExerciseNoteSheetState();
}

class _ExerciseNoteSheetState extends State<_ExerciseNoteSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _tr(BuildContext context, String key) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return AppTranslations.text(key, locale);
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SamanWorkoutTokens.radiusXl),
        ),
        border: Border(
          top: BorderSide(color: t.border),
          left: BorderSide(color: t.border),
          right: BorderSide(color: t.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.borderHover,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _tr(context, 'exercise_note_title'),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('active_workout_note_input'),
                controller: _controller,
                maxLines: 3,
                autofocus: true,
                cursorColor: t.emeraldAccent,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: t.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: _tr(context, 'exercise_note_hint'),
                  hintStyle: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    color: t.textMuted,
                  ),
                  filled: true,
                  fillColor: t.surfaceElevated,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      SamanWorkoutTokens.radiusMd,
                    ),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      SamanWorkoutTokens.radiusMd,
                    ),
                    borderSide: BorderSide(color: t.emeraldAccent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  key: const ValueKey('active_workout_note_save_button'),
                  onPressed: () {
                    widget.onSave(_controller.text.trim());
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.buttonPrimary,
                    foregroundColor: t.buttonPrimaryText,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        SamanWorkoutTokens.radiusMd,
                      ),
                    ),
                  ),
                  child: Text(
                    _tr(context, 'save_note'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.buttonPrimaryText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditCompletedSetSheet extends StatefulWidget {
  const _EditCompletedSetSheet({
    required this.setInfo,
    required this.onSave,
  });

  final ActiveWorkoutSetInfo setInfo;
  final void Function(
    double weightKg,
    int reps,
    double? rpe,
    SetType setType,
  ) onSave;

  @override
  State<_EditCompletedSetSheet> createState() => _EditCompletedSetSheetState();
}

class _EditCompletedSetSheetState extends State<_EditCompletedSetSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late SetType _setType;
  double? _rpe;

  static const List<double> _rpeChoices = [
    6.0,
    6.5,
    7.0,
    7.5,
    8.0,
    8.5,
    9.0,
    9.5,
    10.0,
  ];

  @override
  void initState() {
    super.initState();
    final weight = widget.setInfo.weightKg ?? widget.setInfo.targetWeightKg;
    final reps = widget.setInfo.reps ?? widget.setInfo.targetReps;
    _weightController = TextEditingController(
      text: weight == weight.roundToDouble()
          ? weight.toInt().toString()
          : weight.toStringAsFixed(1),
    );
    _repsController = TextEditingController(text: reps.toString());
    _setType = widget.setInfo.setType;
    _rpe = widget.setInfo.rpe;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  String _tr(BuildContext context, String key) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return AppTranslations.text(key, locale);
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SamanWorkoutTokens.radiusXl),
        ),
        border: Border(
          top: BorderSide(color: t.border),
          left: BorderSide(color: t.border),
          right: BorderSide(color: t.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.borderHover,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_tr(context, 'edit_completed_set')} #${widget.setInfo.setNumber}',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('edit_completed_weight_input'),
                      controller: _weightController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                      decoration: InputDecoration(
                        labelText: 'KG',
                        filled: true,
                        fillColor: t.surfaceElevated,
                        labelStyle: TextStyle(color: t.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusMd,
                          ),
                          borderSide: BorderSide(color: t.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusMd,
                          ),
                          borderSide:
                              BorderSide(color: t.emeraldAccent, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('edit_completed_reps_input'),
                      controller: _repsController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                      decoration: InputDecoration(
                        labelText: 'REPS',
                        filled: true,
                        fillColor: t.surfaceElevated,
                        labelStyle: TextStyle(color: t.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusMd,
                          ),
                          borderSide: BorderSide(color: t.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusMd,
                          ),
                          borderSide:
                              BorderSide(color: t.emeraldAccent, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _tr(context, 'rpe_label'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final val in _rpeChoices)
                    ChoiceChip(
                      label: Text(
                        val == val.roundToDouble()
                            ? val.toInt().toString()
                            : val.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: _rpe == val ? t.emeraldAccent : t.textPrimary,
                        ),
                      ),
                      selected: _rpe != null && (_rpe! - val).abs() < 0.05,
                      selectedColor: t.emeraldBadgeBg,
                      backgroundColor: t.surfaceElevated,
                      side: BorderSide(
                        color: _rpe != null && (_rpe! - val).abs() < 0.05
                            ? t.emeraldBadgeBorder
                            : t.borderSubtle,
                      ),
                      onSelected: (selected) {
                        setState(() => _rpe = selected ? val : null);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  key: const ValueKey('edit_completed_save_button'),
                  onPressed: () {
                    final parsedWeight = double.tryParse(
                          _weightController.text.replaceAll(',', '.'),
                        ) ??
                        (widget.setInfo.weightKg ??
                            widget.setInfo.targetWeightKg);
                    final parsedReps = int.tryParse(_repsController.text) ??
                        (widget.setInfo.reps ?? widget.setInfo.targetReps);
                    widget.onSave(
                      parsedWeight.clamp(0.0, 500.0),
                      parsedReps.clamp(1, 999),
                      _rpe,
                      _setType,
                    );
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.buttonPrimary,
                    foregroundColor: t.buttonPrimaryText,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        SamanWorkoutTokens.radiusMd,
                      ),
                    ),
                  ),
                  child: Text(
                    _tr(context, 'save_note'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.buttonPrimaryText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

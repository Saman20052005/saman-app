import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/exercise_providers.dart';
import '../providers/session_detail_providers.dart';
import '../providers/workout_history_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import '../widgets/exercise_set_log_card.dart';
import '../../data/models/exercise.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionDetailProvider(sessionId));

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      appBar: AppBar(
        backgroundColor: SamanWorkoutTokens.canvas,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.cardSurface,
                        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                        border: Border.all(color: SamanWorkoutTokens.border),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        title: const Text(
          'Session Summary',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: SamanWorkoutTokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: sessionAsync.when(
        data: (session) {
          final metrics = SessionDetailMetrics.compute(session);
          final date = toVietnamTime(session.startedAt);
          final formattedDateTime = DateFormat('MMM d, yyyy · HH:mm').format(date);

          final durationText = metrics.durationSeconds == null
              ? '—'
              : metrics.durationSeconds == 0
                  ? '<1 min'
                  : '${metrics.durationSeconds! ~/ 60} min';

          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: SamanWorkoutTokens.spacingLg,
              vertical: SamanWorkoutTokens.spacingMd,
            ),
            itemCount: metrics.exerciseGroups.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                // Hero Header Card + Summary
                final primaryExerciseId = metrics.exerciseGroups.isNotEmpty
                    ? metrics.exerciseGroups.first.exerciseId
                    : null;
                final resolvedPrimaryId = primaryExerciseId == 'ex_1'
                    ? 'db-bench-press'
                    : primaryExerciseId;

                Exercise? primaryExercise;
                if (resolvedPrimaryId != null) {
                  for (final ex in curatedExerciseLibrary) {
                    if (ex.id == resolvedPrimaryId || ex.slug == resolvedPrimaryId) {
                      primaryExercise = ex;
                      break;
                    }
                  }
                }

                String? heroImagePath;
                if (primaryExercise != null) {
                  heroImagePath = primaryExercise.thumbnailUrl.replaceAll('-thumb.jpg', '-poster.jpg');
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero Image Card
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      height: 180,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                        border: Border.all(color: SamanWorkoutTokens.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildHeroImage(heroImagePath),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  SamanWorkoutTokens.cardSurface,
                                  SamanWorkoutTokens.cardSurface.withOpacity(0.6),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          // Top Badges
                          Positioned(
                            top: 10,
                            left: 10,
                            right: 10,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  constraints: const BoxConstraints(maxWidth: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: SamanWorkoutTokens.canvas.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                                    border: Border.all(color: SamanWorkoutTokens.border),
                                  ),
                                  child: Text(
                                    formattedDateTime,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: SamanWorkoutTokens.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: SamanWorkoutTokens.emeraldBadgeBg,
                                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                                    border: Border.all(color: SamanWorkoutTokens.emeraldBadgeBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: SamanWorkoutTokens.emeraldAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      const Text(
                                        'Completed',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: SamanWorkoutTokens.emeraldAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Bottom Title
                          Positioned(
                            bottom: 12,
                            left: 16,
                            right: 16,
                            child: Text(
                              'Session: ${session.planName.isEmpty ? "Workout" : session.planName}',
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: SamanWorkoutTokens.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Metrics Row Card
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.cardSurface,
                        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                        border: Border.all(color: SamanWorkoutTokens.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Icon(Icons.fitness_center, size: 18, color: SamanWorkoutTokens.textSecondary),
                                const SizedBox(height: 4),
                                Text(
                                  '${metrics.completedExercisesCount}',
                                  style: const TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: SamanWorkoutTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'EXERCISES',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    color: SamanWorkoutTokens.textSecondary,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 36, color: SamanWorkoutTokens.border),
                          Expanded(
                            child: Column(
                              children: [
                                const Icon(Icons.timer_outlined, size: 18, color: SamanWorkoutTokens.textSecondary),
                                const SizedBox(height: 4),
                                Text(
                                  durationText,
                                  style: const TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: SamanWorkoutTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'DURATION',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    color: SamanWorkoutTokens.textSecondary,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 36, color: SamanWorkoutTokens.border),
                          Expanded(
                            child: Column(
                              children: [
                                const Icon(Icons.scale, size: 18, color: SamanWorkoutTokens.textSecondary),
                                const SizedBox(height: 4),
                                Text(
                                  metrics.totalVolumeKg == 0 ? '—' : '${_formatVolume(metrics.totalVolumeKg)} kg',
                                  style: const TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: SamanWorkoutTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'VOLUME',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    color: SamanWorkoutTokens.textSecondary,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Diagnostic Summary Text (Preserved for compatibility)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
                      child: Text(
                        'Session: ${session.planName}\n'
                        '${metrics.completedExercisesCount} exercises / ${metrics.completedSetsCount} completed sets\n'
                        '${metrics.totalReps} total reps / ${metrics.totalTimedSeconds} timed seconds\n'
                        '${_formatVolume(metrics.totalVolumeKg)} kg external load volume / '
                        '${metrics.durationSeconds == null ? "Unknown duration" : "${metrics.durationSeconds} s session duration"}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SamanWorkoutTokens.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ),

                    // Section Heading
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10, left: 2),
                      child: Text(
                        'EXERCISES PERFORMED',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: SamanWorkoutTokens.textSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (index == metrics.exerciseGroups.length + 1) {
                return const SizedBox(height: 32);
              }

              final group = metrics.exerciseGroups[index - 1];
              final exerciseId = group.exerciseId;
              final logs = group.sets;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.cardSurface,
                  borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                  border: Border.all(color: SamanWorkoutTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: SamanWorkoutTokens.textPrimary,
                      ),
                      child: _SessionExerciseName(
                        key: ValueKey(exerciseId),
                        exerciseId: exerciseId,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Table Header Row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 2,
                            child: Text(
                              'Set',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: SamanWorkoutTokens.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: Text(
                              logs.every((log) => log.effectiveUnit == SetUnit.seconds)
                                  ? 'Seconds'
                                  : logs.every((log) => log.effectiveUnit == SetUnit.reps)
                                      ? 'Reps'
                                      : 'Reps / Seconds',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: SamanWorkoutTokens.textSecondary,
                              ),
                            ),
                          ),
                          if (logs.any((log) => log.effectiveUnit == SetUnit.reps)) ...[
                            const SizedBox(width: 8),
                            const Expanded(
                              flex: 3,
                              child: Text(
                                'Weight (kg)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: SamanWorkoutTokens.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Set log cards
                    ...logs.asMap().entries.map((entry) {
                      return ExerciseSetLogCard(
                        log: entry.value,
                        index: entry.key,
                      );
                    }),
                    const SizedBox(height: 8),
                    // Total volume for exercise
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total volume: ${_formatVolume(group.totalVolumeKg)} kg',
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: SamanWorkoutTokens.textPrimary,
                        ),
                      ),
                    ),
                    if (!group.hasExternalLoad)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'External load only; timed sets and bodyweight add no kg volume.',
                          style: TextStyle(
                            fontSize: 11,
                            color: SamanWorkoutTokens.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: SamanWorkoutTokens.emeraldAccent),
        ),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 40, color: SamanWorkoutTokens.crimsonAccent),
              const SizedBox(height: 12),
              const Text(
                'Không tải được buổi tập',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SamanWorkoutTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(sessionDetailProvider(sessionId)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SamanWorkoutTokens.buttonPrimary,
                  foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                  ),
                ),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroImage(String? imagePath) {
    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: imagePath,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallbackHero(),
        );
      }
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackHero(),
      );
    }
    return _fallbackHero();
  }

  Widget _fallbackHero() {
    return Image.asset(
      'assets/images/home_workout_upper.jpg',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: SamanWorkoutTokens.surfaceElevated,
        child: const Center(
          child: Icon(Icons.fitness_center, size: 48, color: SamanWorkoutTokens.border),
        ),
      ),
    );
  }

  String _formatVolume(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _SessionExerciseName extends ConsumerStatefulWidget {
  const _SessionExerciseName({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<_SessionExerciseName> createState() =>
      _SessionExerciseNameState();
}

class _SessionExerciseNameState extends ConsumerState<_SessionExerciseName> {
  late Future<Exercise> _exercise;

  @override
  void initState() {
    super.initState();
    _exercise = _loadExercise();
  }

  @override
  void didUpdateWidget(covariant _SessionExerciseName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exerciseId != widget.exerciseId) {
      _exercise = _loadExercise();
    }
  }

  Future<Exercise> _loadExercise() {
    // The default demo workout uses a legacy ID for this library exercise.
    final libraryId =
        widget.exerciseId == 'ex_1' ? 'db-bench-press' : widget.exerciseId;
    return ref.read(exerciseRepositoryProvider).getExerciseById(libraryId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Exercise>(
      future: _exercise,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Text(
            'Đang tải tên bài tập…',
            style: TextStyle(
              fontSize: 14,
              color: SamanWorkoutTokens.textSecondary,
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final notFound = error is StateError ||
              (error is DioException && error.response?.statusCode == 404);
          if (notFound) {
            return const Text(
              'Bài tập không còn trong thư viện',
              style: TextStyle(
                fontSize: 14,
                color: SamanWorkoutTokens.textSecondary,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Không tải được tên bài tập',
                style: TextStyle(
                  fontSize: 14,
                  color: SamanWorkoutTokens.crimsonAccent,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  final exercise = _loadExercise();
                  setState(() {
                    _exercise = exercise;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: SamanWorkoutTokens.emeraldAccent,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Thử lại'),
              ),
            ],
          );
        }
        final exercise = snapshot.data!;
        final name = exercise.name.trim();
        final muscles = exercise.targetMuscles.isNotEmpty
            ? exercise.targetMuscles.join(', ')
            : exercise.muscleGroup.trim();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.surfaceElevated,
                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                border: Border.all(color: SamanWorkoutTokens.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildThumb(exercise.thumbnailUrl),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Bài tập không có tên' : name,
                    style: const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    muscles.isEmpty
                        ? 'Muscle information unavailable'
                        : 'Muscles: $muscles',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThumb(String url) {
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.fitness_center, size: 18, color: SamanWorkoutTokens.textSecondary),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.fitness_center, size: 18, color: SamanWorkoutTokens.textSecondary),
      ),
    );
  }
}

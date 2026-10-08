import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/exercise.dart';
import '../providers/active_workout_providers.dart';
import '../providers/exercise_providers.dart';
import '../providers/session_detail_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import 'workout_history_screen.dart';

/// Checkpoint 07: Workout Complete Screen (Standalone Post-Save Screen)
/// Calm Athleticism obsidian visual hierarchy matching approved screen.png / code.html
class WorkoutCompleteScreen extends ConsumerWidget {
  final String sessionId;

  const WorkoutCompleteScreen({
    super.key,
    required this.sessionId,
  });

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionDetailProvider(sessionId));

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      appBar: AppBar(
        backgroundColor: SamanWorkoutTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 120,
        leading: InkWell(
          key: const ValueKey('workout_complete_back_button'),
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsetsDirectional.only(start: 16),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: SamanWorkoutTokens.textSecondary,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Workout',
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
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.emeraldBadgeBg,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                  border: Border.all(
                    color: SamanWorkoutTokens.emeraldBadgeBorder,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: SamanWorkoutTokens.emeraldAccent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'SESSION COMPLETE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: SamanWorkoutTokens.emeraldAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: sessionAsync.when(
        data: (session) {
          final activeSession = ref.watch(activeWorkoutSessionProvider);
          final nameMap = <String, String>{};
          final categoryMap = <String, String>{};
          for (final ex in activeSession.exercises) {
            nameMap[ex.id] = ex.name;
            if (ex.slug.isNotEmpty) nameMap[ex.slug] = ex.name;
            if (ex.subtitle.isNotEmpty) categoryMap[ex.id] = ex.subtitle;
          }
          for (final ex in curatedExerciseLibrary) {
            nameMap.putIfAbsent(ex.id, () => ex.name);
            if (ex.slug.isNotEmpty) nameMap.putIfAbsent(ex.slug, () => ex.name);
            if (ex.muscleGroup.isNotEmpty) {
              categoryMap.putIfAbsent(ex.id, () => ex.muscleGroup);
            }
          }

          String resolveName(String id, String slug) {
            if (nameMap.containsKey(id)) return nameMap[id]!;
            if (nameMap.containsKey(slug)) return nameMap[slug]!;
            if (slug.isNotEmpty && slug != id) {
              return slug
                  .replaceAll('-', ' ')
                  .split(' ')
                  .map((w) =>
                      w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                  .join(' ');
            }
            return id
                .replaceAll('-', ' ')
                .replaceAll('_', ' ')
                .split(' ')
                .map((w) =>
                    w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                .join(' ');
          }

          String? resolveCategory(String id, String slug) {
            if (categoryMap.containsKey(id)) return categoryMap[id];
            for (final ex in curatedExerciseLibrary) {
              if (ex.id == id || ex.slug == slug) {
                return ex.muscleGroup;
              }
            }
            return null;
          }

          final groupedLogs = <String, List<ExerciseSetLog>>{};
          final exerciseVolumes = <String, double>{};
          double totalVolume = 0.0;

          for (final log in session.exerciseLogs) {
            groupedLogs.putIfAbsent(log.exerciseId, () => []).add(log);
            final vol = log.volumeKg;
            exerciseVolumes[log.exerciseId] =
                (exerciseVolumes[log.exerciseId] ?? 0.0) + vol;
            totalVolume += vol;
          }

          if (totalVolume == 0.0 && session.totalVolumeKg > 0 &&
              !session.exerciseLogs.any((log) => log.effectiveUnit == SetUnit.seconds)) {
            totalVolume = session.totalVolumeKg.toDouble();
          }

          final distinctExerciseCount = groupedLogs.keys.length;
          final durationVal = session.totalDurationMinutes;
          final durationText = durationVal == null
              ? '—'
              : durationVal == 0 ? '<1' : '$durationVal';

          final startedVn =
              session.startedAt.toUtc().add(const Duration(hours: 7));
          final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(startedVn);

          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 164 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photographic Cinematic Hero
                    Container(
                      height: 190,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.cardSurface,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusLg),
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
                                  size: 56,
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
                                  SamanWorkoutTokens.canvas.withOpacity(0.95),
                                  SamanWorkoutTokens.canvas.withOpacity(0.6),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: SamanWorkoutTokens.emeraldAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: SamanWorkoutTokens.textSub,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Workout complete',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                    color: SamanWorkoutTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  session.planName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: SamanWorkoutTokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'A solid session in the books.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: SamanWorkoutTokens.emeraldAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Primary Metric Ledger Card
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
                                    'VOLUME LIFTED',
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
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -1,
                                          color:
                                              SamanWorkoutTokens.emeraldAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'kg',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          color:
                                              SamanWorkoutTokens.textSecondary,
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
                                        durationText,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 32,
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
                                          color:
                                              SamanWorkoutTokens.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(
                            color: SamanWorkoutTokens.border,
                            height: 1,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 3,
                                backgroundColor:
                                    SamanWorkoutTokens.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${session.exerciseLogs.length} ${session.exerciseLogs.length == 1 ? 'set' : 'sets'} logged • $distinctExerciseCount ${distinctExerciseCount == 1 ? 'exercise' : 'exercises'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
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

                    // Header for What You Trained
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'WHAT YOU TRAINED',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: SamanWorkoutTokens.textSecondary,
                          ),
                        ),
                        Text(
                          '$distinctExerciseCount ${distinctExerciseCount == 1 ? 'exercise' : 'exercises'}',
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

                    // Exercise Journal Cards
                    for (final entry in groupedLogs.entries) ...[
                      _buildJournalCard(
                        exerciseId: entry.key,
                        logs: entry.value,
                        exerciseVolume: exerciseVolumes[entry.key] ?? 0.0,
                        name: resolveName(
                            entry.key, entry.value.first.exerciseSlug),
                        category: resolveCategory(
                            entry.key, entry.value.first.exerciseSlug),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Volume by Exercise breakdown (only if total volume > 0)
                    if (totalVolume > 0 && groupedLogs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildVolumeBreakdown(
                        groupedLogs: groupedLogs,
                        exerciseVolumes: exerciseVolumes,
                        totalVolume: totalVolume,
                        resolveName: resolveName,
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Memory persistence demo notice
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
                              'Demo only. This workout is kept in memory and disappears when the app restarts. It is not synced.',
                              style: TextStyle(
                                fontSize: 13,
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
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            key: const ValueKey('view_workout_history_button'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const WorkoutHistoryScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SamanWorkoutTokens.buttonPrimary,
                              foregroundColor:
                                  SamanWorkoutTokens.buttonPrimaryText,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    SamanWorkoutTokens.radiusMd),
                              ),
                              elevation: 0,
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'View workout history',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          key: const ValueKey('workout_complete_done_button'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Back to Workout',
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
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation<Color>(SamanWorkoutTokens.emeraldAccent),
          ),
        ),
        error: (err, stack) => Center(
          child: Text(
            'Failed to load session: $err',
            style: const TextStyle(color: SamanWorkoutTokens.crimsonAccent),
          ),
        ),
      ),
    );
  }

  Widget _buildJournalCard({
    required String exerciseId,
    required List<ExerciseSetLog> logs,
    required double exerciseVolume,
    required String name,
    required String? category,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: SamanWorkoutTokens.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (category != null && category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        category,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${logs.length} ${logs.length == 1 ? 'set' : 'sets'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Text(
                    _formatVolume(exerciseVolume),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: SamanWorkoutTokens.emeraldAccent,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    'kg total',
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
          const SizedBox(height: 12),

          // Sets Ledger
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: SamanWorkoutTokens.surfaceElevated,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
            ),
            child: Column(
              children: [
                for (int i = 0; i < logs.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      color: SamanWorkoutTokens.border,
                      height: 12,
                    ),
                  Builder(
                    builder: (context) {
                      final log = logs[i];
                      final setVolume = log.volumeKg;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    'SET ${log.setNumber}',
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
                                    log.effectiveUnit == SetUnit.seconds ? '${log.secondsCompleted} s'
                                        : '${_formatWeight(log.weightKg)} kg × ${log.repsCompleted} reps',
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
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeBreakdown({
    required Map<String, List<ExerciseSetLog>> groupedLogs,
    required Map<String, double> exerciseVolumes,
    required double totalVolume,
    required String Function(String id, String slug) resolveName,
  }) {
    final entries = groupedLogs.entries
        .where((entry) => (exerciseVolumes[entry.key] ?? 0) > 0).toList();
    const segmentColors = [
      SamanWorkoutTokens.tealAccent,
      SamanWorkoutTokens.emeraldAccent,
      SamanWorkoutTokens.tealLightAccent,
      SamanWorkoutTokens.amberAccent,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'VOLUME BY EXERCISE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: SamanWorkoutTokens.textSecondary,
                ),
              ),
              Text(
                '${_formatVolume(totalVolume)} kg total',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: SamanWorkoutTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Multi-segment progress bar
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusPill),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                for (int i = 0; i < entries.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final exVol = exerciseVolumes[entries[i].key] ?? 0.0;
                      final flex = ((exVol / totalVolume) * 1000).round();
                      final color = segmentColors[i % segmentColors.length];
                      return Expanded(
                        flex: flex > 0 ? flex : 1,
                        child: Container(color: color),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Legend
          Column(
            children: [
              for (int i = 0; i < entries.length; i++) ...[
                Builder(
                  builder: (context) {
                    final key = entries[i].key;
                    final exName =
                        resolveName(key, entries[i].value.first.exerciseSlug);
                    final exVol = exerciseVolumes[key] ?? 0.0;
                    final pct = (exVol / totalVolume) * 100;
                    final color = segmentColors[i % segmentColors.length];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 4,
                                  backgroundColor: color,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    exName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: SamanWorkoutTokens.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatVolume(exVol)} kg (${pct.toStringAsFixed(1)}%)',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: SamanWorkoutTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

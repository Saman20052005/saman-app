import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/app_translations.dart';
import '../../data/models/exercise.dart';
import '../../features/community/domain/models/community_post.dart';
import '../../features/community/domain/models/post_attachment_snapshot.dart';
import '../../features/community/presentation/providers/community_composer_provider.dart';
import '../../features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import '../../features/community/presentation/widgets/community_create_story_sheet.dart';
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

  bool _isVi(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return locale.languageCode == 'vi';
  }

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

  Future<void> _showShareSheet({
    required BuildContext context,
    required WidgetRef ref,
    required WorkoutSession session,
    required String dateStr,
    required int? durationMinutes,
    required int distinctExerciseCount,
    required List<String> exerciseNames,
  }) async {
    final t = SamanWorkoutTokens.of(context);
    final title = session.planName.trim().isNotEmpty
        ? session.planName.trim()
        : 'Saman Workout';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final isVi = _isVi(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetContext.tr('workout_share_sheet_title'),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sheetContext.tr('workout_share_sheet_subtitle'),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const ValueKey('workout_share_post_option'),
                  minVerticalPadding: 10,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    backgroundColor: t.emeraldBadgeBg,
                    child: Icon(Icons.post_add_outlined, color: t.emeraldAccent),
                  ),
                  title: Text(
                    sheetContext.tr('workout_share_post_title'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    sheetContext.tr('workout_share_post_subtitle'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final snapshot = PostAttachmentSnapshot(
                      type: AttachmentType.workout,
                      id: session.id,
                      title: title,
                      dateFormatted: dateStr,
                      category: 'Saman Kinetic',
                      includeDuration: durationMinutes != null,
                      includeExercisesOrFoods: exerciseNames.isNotEmpty,
                      includeLoadOrMacros: false,
                      durationFormatted: durationMinutes != null
                          ? (isVi ? '$durationMinutes phút' : '$durationMinutes min')
                          : null,
                      exerciseCount: distinctExerciseCount,
                      exercises: exerciseNames
                          .map((name) => ExerciseThumbnailPreview(title: name))
                          .toList(),
                      sharedSnapshot: <String, dynamic>{
                        if (durationMinutes != null)
                          'duration_minutes': durationMinutes,
                        if (distinctExerciseCount > 0)
                          'exercise_count': distinctExerciseCount,
                        if (exerciseNames.isNotEmpty)
                          'exercises': exerciseNames
                              .map((name) => <String, dynamic>{'name': name})
                              .toList(),
                      },
                    ).sanitize();

                    final composerNotifier =
                        ref.read(communityComposerProvider.notifier);
                    if (!ref
                        .read(communityComposerProvider)
                        .hasPendingSubmission) {
                      composerNotifier.reset();
                    }
                    composerNotifier.setAttachment(snapshot);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PostComposePublishScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const ValueKey('workout_share_story_option'),
                  minVerticalPadding: 10,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    backgroundColor: t.emeraldBadgeBg,
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      color: t.emeraldAccent,
                    ),
                  ),
                  title: Text(
                    sheetContext.tr('workout_share_story_title'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    sheetContext.tr('workout_share_story_subtitle'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final prefill = context
                        .tr('workout_share_story_prefill')
                        .replaceAll('{title}', title);
                    CommunityCreateStorySheet.show(
                      context,
                      initialCaption: prefill,
                      initialPrivacy: 'followers_only',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SamanWorkoutTokens.of(context);
    final isVi = _isVi(context);
    final sessionAsync = ref.watch(sessionDetailProvider(sessionId));

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        backgroundColor: t.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 120,
        leading: InkWell(
          key: const ValueKey('workout_complete_back_button'),
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: t.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr('workout_title'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: t.textSecondary,
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
                  color: t.emeraldBadgeBg,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                  border: Border.all(
                    color: t.emeraldBadgeBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: t.emeraldAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isVi ? 'HOÀN THÀNH BUỔI TẬP' : 'SESSION COMPLETE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: t.emeraldAccent,
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

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photographic Cinematic Hero (dark scrim preserved across Light/Dark)
                      Container(
                        height: 190,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: t.cardSurface,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                          border: Border.all(color: t.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/images/home_workout_upper.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: t.cardSurface,
                                child: Center(
                                  child: Icon(
                                    Icons.fitness_center,
                                    size: 56,
                                    color: t.border,
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
                                    const Color(0xFF0C0D0E).withOpacity(0.95),
                                    const Color(0xFF0C0D0E).withOpacity(0.6),
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
                                  Text(
                                    isVi
                                        ? 'Hoàn thành buổi tập'
                                        : 'Workout complete',
                                    style: const TextStyle(
                                      fontFamily: 'Manrope',
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
                                      fontFamily: 'Manrope',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: SamanWorkoutTokens.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isVi
                                        ? 'Một buổi tập tuyệt vời đã được ghi lại.'
                                        : 'A solid session in the books.',
                                    style: const TextStyle(
                                      fontFamily: 'Manrope',
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
                          color: t.cardSurface,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                          border: Border.all(color: t.border),
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
                                    Text(
                                      isVi ? 'TỔNG KHỐI LƯỢNG' : 'VOLUME LIFTED',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                        color: t.textSecondary,
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
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -1,
                                            color: t.emeraldAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'kg',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            color: t.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      isVi
                                          ? 'THỜI GIAN TẬP'
                                          : 'ACTIVE DURATION',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                        color: t.textSecondary,
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
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.5,
                                            color: t.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isVi ? 'phút' : 'min',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            color: t.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Divider(
                              color: t.border,
                              height: 1,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 3,
                                  backgroundColor: t.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isVi
                                        ? 'Đã ghi ${session.exerciseLogs.length} hiệp • $distinctExerciseCount bài tập'
                                        : '${session.exerciseLogs.length} ${session.exerciseLogs.length == 1 ? 'set' : 'sets'} logged • $distinctExerciseCount ${distinctExerciseCount == 1 ? 'exercise' : 'exercises'}',
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: t.textSecondary,
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
                          Text(
                            isVi ? 'CÁC BÀI ĐÃ TẬP' : 'WHAT YOU TRAINED',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: t.textSecondary,
                            ),
                          ),
                          Text(
                            isVi
                                ? '$distinctExerciseCount bài tập'
                                : '$distinctExerciseCount ${distinctExerciseCount == 1 ? 'exercise' : 'exercises'}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Exercise Journal Cards
                      for (final entry in groupedLogs.entries) ...[
                        _buildJournalCard(
                          t: t,
                          isVi: isVi,
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
                          t: t,
                          isVi: isVi,
                          groupedLogs: groupedLogs,
                          exerciseVolumes: exerciseVolumes,
                          totalVolume: totalVolume,
                          resolveName: resolveName,
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Session history guidance
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: t.cardSurface,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                          border: Border.all(color: t.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: t.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isVi
                                    ? 'Xem buổi tập này trong lịch sử tập luyện của bạn.'
                                    : 'View this session in your workout history.',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 13,
                                  height: 1.4,
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Opaque Grounded Bottom Action Dock
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: t.canvas,
                  border: Border(
                    top: BorderSide(color: t.borderSubtle),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('workout_complete_share_button'),
                        onPressed: () {
                          final exerciseNames = groupedLogs.keys
                              .map((exId) {
                                final logs = groupedLogs[exId]!;
                                final slug = logs.isNotEmpty
                                    ? logs.first.exerciseSlug
                                    : '';
                                return resolveName(exId, slug);
                              })
                              .toList();
                          _showShareSheet(
                            context: context,
                            ref: ref,
                            session: session,
                            dateStr: dateStr,
                            durationMinutes: durationVal,
                            distinctExerciseCount: distinctExerciseCount,
                            exerciseNames: exerciseNames,
                          );
                        },
                        icon: Icon(
                          Icons.share_outlined,
                          size: 18,
                          color: t.textPrimary,
                        ),
                        label: Text(
                          context.tr('workout_share_community_cta'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: t.textPrimary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          backgroundColor: t.cardSurface,
                          side: BorderSide(color: t.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                SamanWorkoutTokens.radiusMd),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        key: const ValueKey('view_workout_history_button'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WorkoutHistoryScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          backgroundColor: t.buttonPrimary,
                          foregroundColor: t.buttonPrimaryText,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                SamanWorkoutTokens.radiusMd),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.history,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isVi
                                    ? 'Xem lịch sử tập luyện'
                                    : 'View workout history',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 15,
                                  height: 1.2,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        key: const ValueKey('workout_complete_done_button'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          context.tr('back_to_workout'),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(t.emeraldAccent),
          ),
        ),
        error: (err, stack) => Center(
          child: Text(
            isVi
                ? 'Không thể tải buổi tập: $err'
                : 'Failed to load session: $err',
            style: TextStyle(fontFamily: 'Manrope', color: t.crimsonAccent),
          ),
        ),
      ),
    );
  }

  Widget _buildJournalCard({
    required SamanWorkoutPalette t,
    required bool isVi,
    required String exerciseId,
    required List<ExerciseSetLog> logs,
    required double exerciseVolume,
    required String name,
    required String? category,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: t.border),
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
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (category != null && category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        category,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      isVi
                          ? '${logs.length} hiệp'
                          : '${logs.length} ${logs.length == 1 ? 'set' : 'sets'}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: t.textSecondary,
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
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: t.emeraldAccent,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    isVi ? 'kg tổng' : 'kg total',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: t.textSecondary,
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
              color: t.surfaceElevated,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
            ),
            child: Column(
              children: [
                for (int i = 0; i < logs.length; i++) ...[
                  if (i > 0)
                    Divider(
                      color: t.border,
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
                                  width: 52,
                                  child: Text(
                                    isVi
                                        ? 'HIỆP ${log.setNumber}'
                                        : 'SET ${log.setNumber}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: t.textSecondary,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    log.effectiveUnit == SetUnit.seconds ? '${log.secondsCompleted} s'
                                        : '${_formatWeight(log.weightKg)} kg × ${log.repsCompleted} reps',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: t.textPrimary,
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
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: t.textSecondary,
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
    required SamanWorkoutPalette t,
    required bool isVi,
    required Map<String, List<ExerciseSetLog>> groupedLogs,
    required Map<String, double> exerciseVolumes,
    required double totalVolume,
    required String Function(String id, String slug) resolveName,
  }) {
    final entries = groupedLogs.entries
        .where((entry) => (exerciseVolumes[entry.key] ?? 0) > 0).toList();
    final segmentColors = [
      t.tealAccent,
      t.emeraldAccent,
      t.tealLightAccent,
      t.amberAccent,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isVi ? 'KHỐI LƯỢNG THEO BÀI TẬP' : 'VOLUME BY EXERCISE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isVi
                    ? '${_formatVolume(totalVolume)} kg tổng'
                    : '${_formatVolume(totalVolume)} kg total',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t.textPrimary,
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
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: t.textSecondary,
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

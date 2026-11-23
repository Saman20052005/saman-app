import 'package:flutter/material.dart';

import '../../../../config/app_translations.dart';
import '../../domain/models/community_post.dart';
import '../../domain/models/post_attachment_snapshot.dart';
import '../tokens/saman_ig_tokens.dart';

/// Compact Saman Workout mini-card / sticker formatted for the Instagram feed.
/// Respects Privacy-by-Design by omitting zeroed/redacted exercise or set counts.
class IgPostWorkoutSticker extends StatelessWidget {
  final PostWorkoutAttachment attachment;
  final VoidCallback? onViewWorkout;

  const IgPostWorkoutSticker({
    super.key,
    required this.attachment,
    this.onViewWorkout,
  });

  String _privacySafeSummary() {
    final parts = <String>[
      if (attachment.durationFormatted.trim().isNotEmpty)
        attachment.durationFormatted.trim(),
      if (attachment.exerciseCount > 0) '${attachment.exerciseCount} bài tập',
      if (attachment.setCount > 0) '${attachment.setCount} hiệp tập',
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final summary = _privacySafeSummary();
    final isLargeText = MediaQuery.textScalerOf(context).scale(14) > 19;

    final headerInfo = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUỔI TẬP ĐÃ HOÀN THÀNH',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ig.caption(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ig.primaryAction,
            ).copyWith(letterSpacing: 0.4),
          ),
          const SizedBox(height: 1),
          Text(
            attachment.title,
            maxLines: isLargeText ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: ig.username(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    final ctaLink = _StickerCtaLink(
      label: 'Xem buổi tập',
      onTap: onViewWorkout,
      ig: ig,
    );

    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StickerIconBadge(icon: Icons.fitness_center_rounded, ig: ig),
                const SizedBox(width: 10),
                headerInfo,
                if (!isLargeText) ...[
                  const SizedBox(width: 8),
                  ctaLink,
                ],
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ig.caption(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ig.textSecondary,
                ),
              ),
            ],
            if (attachment.exercises.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: attachment.exercises.take(3).map((exercise) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ig.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ig.border, width: 0.5),
                    ),
                    child: Text(
                      exercise.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ig.caption(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: ig.textPrimary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (isLargeText) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ctaLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact Saman Nutrition / Meal mini-card / sticker formatted for Instagram.
/// Respects Privacy-by-Design: never prints raw calories or macros when hidden.
class IgPostNutritionSticker extends StatelessWidget {
  final PostNutritionInfo nutritionInfo;
  final VoidCallback? onViewMacros;

  const IgPostNutritionSticker({
    super.key,
    required this.nutritionInfo,
    this.onViewMacros,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final hasPublicEnergy =
        nutritionInfo.calories > 0 || nutritionInfo.proteinGrams > 0;
    final primaryLabel = hasPublicEnergy
        ? nutritionInfo.defaultBadge
        : (nutritionInfo.badgeLabel ?? 'Bữa ăn cân bằng');
    final isLargeText = MediaQuery.textScalerOf(context).scale(14) > 19;

    final ctaLink = _StickerCtaLink(
      label: 'Chi tiết Macro',
      onTap: onViewMacros,
      ig: ig,
    );

    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StickerIconBadge(icon: Icons.restaurant_rounded, ig: ig),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DINH DƯỠNG SAMAN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.caption(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: ig.textSecondary,
                        ).copyWith(letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        primaryLabel,
                        maxLines: isLargeText ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.username(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLargeText) ...[
                  const SizedBox(width: 8),
                  ctaLink,
                ],
              ],
            ),
            if (isLargeText) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ctaLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Privacy-by-Design IG sticker for `PostAttachmentSnapshot`.
/// Displays only `displayFields` (or explicitly permitted snapshot fields) and
/// never exposes load/sets/calories/macros unless authorized.
class IgPostSnapshotSticker extends StatelessWidget {
  final PostAttachmentSnapshot snapshot;
  final VoidCallback? onOpenDetail;

  const IgPostSnapshotSticker({
    super.key,
    required this.snapshot,
    this.onOpenDetail,
  });

  List<String> _permittedDetails(BuildContext context) {
    final fields = snapshot.displayFields;
    if (fields.isNotEmpty) {
      return fields
          .map((f) => '${context.tr('community_attachment_${f.key}')}: ${f.value}')
          .toList();
    }
    final items = <String>[];
    if (snapshot.includeDuration &&
        snapshot.durationFormatted != null &&
        snapshot.durationFormatted!.isNotEmpty) {
      items.add(snapshot.durationFormatted!);
    }
    if (snapshot.includeExercisesOrFoods) {
      if (snapshot.exerciseCount != null && snapshot.exerciseCount! > 0) {
        items.add('${snapshot.exerciseCount} bài tập');
      }
      if (snapshot.exercises.isNotEmpty) {
        items.add(snapshot.exercises.map((e) => e.title).join(', '));
      }
    }
    if (snapshot.includeLoadOrMacros) {
      if (snapshot.setCount != null && snapshot.setCount! > 0) {
        items.add('${snapshot.setCount} hiệp');
      }
      if (snapshot.loadSummaryFormatted != null &&
          snapshot.loadSummaryFormatted!.isNotEmpty) {
        items.add(snapshot.loadSummaryFormatted!);
      }
      if (snapshot.macrosSummaryFormatted != null &&
          snapshot.macrosSummaryFormatted!.isNotEmpty) {
        items.add(snapshot.macrosSummaryFormatted!);
      } else if (snapshot.calories != null && snapshot.calories! > 0) {
        items.add('${snapshot.calories} kcal');
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final isWorkout = snapshot.type == AttachmentType.workout;
    final details = _permittedDetails(context);
    final isLargeText = MediaQuery.textScalerOf(context).scale(14) > 19;

    final ctaLink = _StickerCtaLink(
      label: isWorkout ? 'Xem buổi tập' : 'Chi tiết Macro',
      onTap: onOpenDetail,
      ig: ig,
    );

    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StickerIconBadge(
                  icon: isWorkout
                      ? Icons.fitness_center_rounded
                      : Icons.restaurant_rounded,
                  ig: ig,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snapshot.title,
                        maxLines: isLargeText ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.username(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${snapshot.category} • ${snapshot.dateFormatted}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.caption(
                          fontSize: 11.5,
                          color: ig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLargeText) ...[
                  const SizedBox(width: 8),
                  ctaLink,
                ],
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final line in details)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ig.caption(
                      fontSize: 12,
                      color: ig.textSecondary,
                    ),
                  ),
                ),
            ],
            if (isLargeText) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ctaLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StickerIconBadge extends StatelessWidget {
  final IconData icon;
  final SamanIgTokens ig;

  const _StickerIconBadge({
    required this.icon,
    required this.ig,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Icon(
        icon,
        size: 17,
        color: ig.primaryAction,
      ),
    );
  }
}

class _StickerCtaLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final SamanIgTokens ig;

  const _StickerCtaLink({
    required this.label,
    required this.onTap,
    required this.ig,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SamanIgTokens.minTouchTarget,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              style: ig.buttonLabel(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ig.primaryAction,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

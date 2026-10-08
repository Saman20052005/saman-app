import 'package:flutter/material.dart';
import 'exercise_thumbnail.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/models/exercise.dart';
import '../../config/app_theme.dart';

class ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onTap;
  final Widget? trailing;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.onTap,
    this.trailing,
  });

  Color _getDifficultyColor(
    String diff,
    ColorScheme colors,
    AppThemeExtension extension,
  ) {
    switch (diff) {
      case 'beginner':
        return colors.primary;
      case 'intermediate':
        return extension.warning;
      case 'advanced':
        return colors.error;
      default:
        return colors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extension = Theme.of(context).extension<AppThemeExtension>()!;
    final difficultyColor = _getDifficultyColor(
      exercise.difficulty,
      colors,
      extension,
    );

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail với Hero và CachedNetworkImage
                Hero(
                  tag: 'exercise_${exercise.slug}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: ExerciseThumbnail(
                      source: exercise.thumbnailUrl,
                      width: 80,
                      height: 80,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        exercise.nameVi,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Difficulty badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: difficultyColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              exercise.difficulty.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: difficultyColor,
                              ),
                            ),
                          ),

                          // CV badge
                          if (exercise.cvSupported)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.trackColor,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                'CV',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                          // Sets x Reps
                          Text(
                            '${exercise.defaultSets} sets × ${exercise.defaultReps}',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                // Optional trailing widget
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

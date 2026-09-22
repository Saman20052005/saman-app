import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_shadows.dart';
import '../../data/models/muscle_group.dart';

class MuscleGroupCard extends StatelessWidget {
  final MuscleGroup group;
  final VoidCallback onTap;
  final String heroTag;

  const MuscleGroupCard({
    super.key,
    required this.group,
    required this.onTap,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusXl),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
            border: Border.all(color: scheme.outline.withOpacity(0.6)),
            boxShadow: AppShadows.subtle(context),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerHighest.withOpacity(0.55),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: heroTag,
                  child: _Icon(
                    assetPath: group.icon,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: AppDimens.spacingSm),
                Text(
                  group.nameVi,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppDimens.spacingXs),
                Text(
                  '${group.exerciseCount} ${AppStrings.exercisesUnit}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  final String assetPath;
  final Color color;

  const _Icon({required this.assetPath, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimens.iconContainerSize,
      height: AppDimens.iconContainerSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      alignment: Alignment.center,
      child: assetPath.endsWith('.svg')
          ? SvgPicture.asset(
              assetPath,
              width: AppDimens.iconSize,
              height: AppDimens.iconSize,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          : Icon(Icons.fitness_center, size: AppDimens.iconSize, color: color),
    );
  }
}

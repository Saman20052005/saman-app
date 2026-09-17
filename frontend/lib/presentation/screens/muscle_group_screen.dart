import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/muscle_group.dart';
import '../providers/muscle_group_providers.dart';
import '../widgets/muscle_group_card.dart';
import 'exercise_list_screen.dart';

class MuscleGroupScreen extends ConsumerWidget {
  final void Function(MuscleGroup group)? onSelect;

  const MuscleGroupScreen({
    super.key,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muscleGroupsAsync = ref.watch(muscleGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.muscleGroupsTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppDimens.screenPadding),
        child: muscleGroupsAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return const _EmptyState();
            }
            return _Grid(
              groups: groups,
              onTap: (group) {
                final cb = onSelect;
                if (cb != null) {
                  cb(group);
                } else {
                  // Default navigation to exercise list
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExerciseListScreen(
                        muscleGroupSlug: group.slug,
                        muscleGroupName: group.nameVi,
                      ),
                    ),
                  );
                }
              },
            );
          },
          loading: () => const _SkeletonGrid(),
          error: (error, _) => _ErrorState(
            errorText: error.toString(),
            onRetry: () => ref.invalidate(muscleGroupsProvider),
          ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<MuscleGroup> groups;
  final void Function(MuscleGroup group) onTap;

  const _Grid({
    required this.groups,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.25,
        crossAxisSpacing: AppDimens.gridCrossAxisSpacing,
        mainAxisSpacing: AppDimens.gridMainAxisSpacing,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final heroTag = 'muscle_group_${group.slug}_${group.id}';

        return MuscleGroupCard(
          group: group,
          heroTag: heroTag,
          onTap: () => onTap(group),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String errorText;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.errorText,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 44, color: scheme.error),
            const SizedBox(height: AppDimens.spacingSm),
            Text(
              AppStrings.errorTitle,
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.spacingXs),
            Text(
              errorText,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.75),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.spacingLg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(AppStrings.retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center_outlined,
              size: 56,
              color: scheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: AppDimens.spacingSm),
            Text(
              AppStrings.emptyMuscleGroupsTitle,
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.spacingXs),
            Text(
              AppStrings.emptyMuscleGroupsSubtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.75),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.25,
        crossAxisSpacing: AppDimens.gridCrossAxisSpacing,
        mainAxisSpacing: AppDimens.gridMainAxisSpacing,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return const _SkeletonCard();
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: scheme.outline.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
            ),
            const SizedBox(height: AppDimens.spacingSm),
            Container(
              height: 14,
              width: 90,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: AppDimens.spacingXs),
            Container(
              height: 12,
              width: 70,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

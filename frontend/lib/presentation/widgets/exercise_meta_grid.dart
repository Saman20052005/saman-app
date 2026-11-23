import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';
import '../../core/constants/app_dimens.dart';

class ExerciseMetaGrid extends StatelessWidget {
  final Exercise exercise;

  const ExerciseMetaGrid({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.8,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _MetaItem(
          icon: Icons.fitness_center,
          label: 'Nhóm cơ',
          value: exercise.muscleGroup.toUpperCase(),
        ),
        _MetaItem(
          icon: Icons.timer,
          label: 'Nghỉ giữa set',
          value: '${exercise.restSeconds}s',
        ),
        _MetaItem(
          icon: Icons.repeat,
          label: 'Mặc định',
          value: '${exercise.defaultSets} sets × ${exercise.defaultReps}',
        ),
        _MetaItem(
          icon: Icons.sports_gymnastics,
          label: 'Thiết bị',
          value: exercise.equipment.join(', '),
        ),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusM),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: colorScheme.secondary),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

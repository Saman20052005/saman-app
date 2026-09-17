import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';
import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_colors.dart';

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(AppDimens.radiusM),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
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

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class NutritionSectionHeader extends StatelessWidget {
  const NutritionSectionHeader({
    super.key,
    required this.label,
    this.trailing,
  });

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppThemeExtension>()!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label.toUpperCase(), style: tokens.labelCaps),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class NutritionMetricCard extends StatelessWidget {
  const NutritionMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppThemeExtension>()!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: tokens.inkMuted),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(label, style: tokens.labelCaps),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: tokens.statValue),
          if (unit != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(unit!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class NutritionMacroProgress extends StatelessWidget {
  const NutritionMacroProgress({
    super.key,
    required this.label,
    required this.consumed,
    required this.target,
    required this.progress,
    this.remaining,
  });

  final String label;
  final String consumed;
  final String target;
  final double progress;
  final String? remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppThemeExtension>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              '$consumed / $target',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: AppSpacing.sm,
            backgroundColor: tokens.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
        if (remaining != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(remaining!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

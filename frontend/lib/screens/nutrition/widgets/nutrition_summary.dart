import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../theme/nutrition_home_theme.dart';

import '../../../../models/nutrition_model.dart';
import '../../../../providers/profile_provider.dart';

class NutritionSummary extends ConsumerWidget {
  final NutritionPlan plan;
  final ProfileState profile;

  const NutritionSummary({
    super.key,
    required this.plan,
    required this.profile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasCalTarget =
        profile.isProfileValid && profile.targetCalories > 0;
    final int targetCalories = hasCalTarget ? profile.targetCalories : 0;

    final bool hasProteinTarget =
        profile.isProfileValid && profile.targetProtein > 0;
    final double targetProtein =
        hasProteinTarget ? profile.targetProtein.toDouble() : 0.0;

    final bool hasCarbsTarget =
        profile.isProfileValid && profile.targetCarbs > 0;
    final double targetCarbs =
        hasCarbsTarget ? profile.targetCarbs.toDouble() : 0.0;

    final bool hasFatTarget = profile.isProfileValid && profile.targetFat > 0;
    final double targetFat = hasFatTarget ? profile.targetFat.toDouble() : 0.0;

    final int actualCalories = plan.totalCaloriesConsumed;
    final double actualProtein = plan.totalProteinConsumed.toDouble();
    final double actualCarbs = plan.totalCarbsConsumed.toDouble();
    final double actualFat = plan.totalFatConsumed.toDouble();

    final int remainCal = targetCalories - actualCalories;
    final bool isCalOver = remainCal < 0;
    final double calProgress =
        hasCalTarget ? (actualCalories / targetCalories).clamp(0.0, 1.0) : 0.0;
    final double calPercentage =
        hasCalTarget ? (actualCalories / targetCalories * 100) : 0.0;

    final numberFormat = NumberFormat('#,###');

    final style = NutritionHomeStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
          color: style.surface,
          borderRadius: style.cardRadius,
          border: Border.all(color: style.border)),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text("TODAY'S INTAKE", style: style.label),
                    Text('LOGGED INTAKE', style: style.label),
                  ]),
              const SizedBox(height: 10),
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(numberFormat.format(actualCalories),
                        style: style.calories),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                            hasCalTarget
                                ? '/ ${numberFormat.format(targetCalories)} kcal'
                                : '/ — kcal',
                            style: style.caption)),
                  ]),
              if (!hasCalTarget) Text('CONSUMED', style: style.label),
              const SizedBox(height: 6),
              Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                        hasCalTarget
                            ? (isCalOver
                                ? '${numberFormat.format(remainCal.abs())} kcal over'
                                : '${numberFormat.format(remainCal)} kcal remaining')
                            : 'Set profile goal',
                        style: style.caption.copyWith(
                            color: isCalOver ? style.carbs : style.accent)),
                    Text(
                        hasCalTarget
                            ? '${calPercentage.toStringAsFixed(1)}% of goal'
                            : 'No target configured',
                        style: style.caption),
                  ]),
              if (hasCalTarget) ...[
                const SizedBox(height: 12),
                ClipRRect(
                    borderRadius: style.pillRadius,
                    child: LinearProgressIndicator(
                      value: calProgress,
                      minHeight: 6,
                      color: isCalOver ? style.carbs : style.accent,
                      backgroundColor: style.track,
                      semanticsLabel: 'Daily calories',
                      semanticsValue:
                          '${calPercentage.toStringAsFixed(1)}% of goal',
                    )),
              ],
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: style.border)),
              LayoutBuilder(builder: (context, box) {
                final tiles = [
                  _MacroTile(
                      label: 'Protein',
                      color: style.accent,
                      actual: actualProtein,
                      target: targetProtein,
                      hasTarget: hasProteinTarget),
                  _MacroTile(
                      label: 'Carbs',
                      color: style.carbs,
                      actual: actualCarbs,
                      target: targetCarbs,
                      hasTarget: hasCarbsTarget),
                  _MacroTile(
                      label: 'Fat',
                      color: style.fat,
                      actual: actualFat,
                      target: targetFat,
                      hasTarget: hasFatTarget),
                ];
                return box.maxWidth < 340 &&
                        MediaQuery.textScalerOf(context).scale(14) > 20
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: tiles)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            for (final tile in tiles) Expanded(child: tile)
                          ]);
              }),
            ],
          )),
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile(
      {required this.label,
      required this.color,
      required this.actual,
      required this.target,
      required this.hasTarget});
  final String label;
  final Color color;
  final double actual, target;
  final bool hasTarget;
  @override
  Widget build(BuildContext context) {
    final double progress =
        (hasTarget && target > 0) ? (actual / target).clamp(0.0, 1.0) : 0.0;
    final int diff = hasTarget ? (target - actual).round() : 0;
    final bool isOver = diff < 0;
    final style = NutritionHomeStyle.of(context);
    return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              DecoratedBox(
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: const SizedBox(width: 5, height: 5)),
              const SizedBox(width: 5),
              Flexible(child: Text(label, style: style.caption)),
            ]),
            const SizedBox(height: 5),
            Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 3,
                children: [
                  Text('${actual.toInt()}g', style: style.strong),
                  Text(hasTarget ? '/ ${target.toInt()}g' : '/ —',
                      style: style.caption),
                ]),
            if (hasTarget) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: color,
                  backgroundColor: style.track,
                  semanticsLabel: label),
              const SizedBox(height: 4),
              Text(isOver ? '${diff.abs()}g over' : '${diff}g left',
                  style: style.caption),
            ] else
              Text('No target', style: style.caption),
          ],
        ));
  }
}

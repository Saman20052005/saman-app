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
    final dynamicTarget = plan.dynamicTarget;
    final bool useDynamicTarget =
        dynamicTarget != null && dynamicTarget.calories > 0;

    final bool hasCalTarget = useDynamicTarget
        ? true
        : (profile.isProfileValid && profile.targetCalories > 0);
    final int targetCalories = useDynamicTarget
        ? dynamicTarget.calories
        : (hasCalTarget ? profile.targetCalories : 0);

    final bool hasProteinTarget = useDynamicTarget
        ? true
        : (profile.isProfileValid && profile.targetProtein > 0);
    final double targetProtein = useDynamicTarget
        ? dynamicTarget.protein.toDouble()
        : (hasProteinTarget ? profile.targetProtein.toDouble() : 0.0);

    final bool hasCarbsTarget = useDynamicTarget
        ? true
        : (profile.isProfileValid && profile.targetCarbs > 0);
    final double targetCarbs = useDynamicTarget
        ? dynamicTarget.carbs.toDouble()
        : (hasCarbsTarget ? profile.targetCarbs.toDouble() : 0.0);

    final bool hasFatTarget = useDynamicTarget
        ? true
        : (profile.isProfileValid && profile.targetFat > 0);
    final double targetFat = useDynamicTarget
        ? dynamicTarget.fat.toDouble()
        : (hasFatTarget ? profile.targetFat.toDouble() : 0.0);

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

    final bool isTraining = plan.dayMode == 'training';
    final int delta = dynamicTarget?.calorieDelta ?? 0;
    final String chipText;
    if (isTraining) {
      chipText = (dynamicTarget != null && delta > 0)
          ? 'TRAINING DAY (+$delta kcal)'
          : 'TRAINING DAY';
    } else {
      chipText = (dynamicTarget != null && delta < 0)
          ? 'REST DAY ($delta kcal)'
          : 'REST DAY';
    }
    final style = NutritionHomeStyle.of(context);
    final Color dotColor = isTraining
        ? (style.isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
        : (style.isDark ? const Color(0xFF94979E) : style.muted);

    final numberFormat = NumberFormat('#,###');

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
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text("TODAY'S INTAKE", style: style.label),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: style.isDark
                            ? const Color(0xFF212328)
                            : style.track,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: style.isDark
                              ? const Color(0xFF26282F)
                              : style.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(chipText, style: style.label),
                        ],
                      ),
                    ),
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
                    hasCalTarget
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                numberFormat.format(isCalOver
                                    ? remainCal.abs()
                                    : remainCal),
                                style: style.caption.copyWith(
                                    color:
                                        isCalOver ? style.carbs : style.accent),
                              ),
                              Text(
                                isCalOver
                                    ? ' kcal over'
                                    : ' kcal remaining',
                                style: style.caption.copyWith(
                                    color:
                                        isCalOver ? style.carbs : style.accent),
                              ),
                            ],
                          )
                        : Text('Set profile goal',
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

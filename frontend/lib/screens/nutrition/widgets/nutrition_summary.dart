import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
    final bool hasCalTarget = profile.isProfileValid && profile.targetCalories > 0;
    final int targetCalories = hasCalTarget ? profile.targetCalories : 0;

    final bool hasProteinTarget = profile.isProfileValid && profile.targetProtein > 0;
    final double targetProtein = hasProteinTarget ? profile.targetProtein.toDouble() : 0.0;

    final bool hasCarbsTarget = profile.isProfileValid && profile.targetCarbs > 0;
    final double targetCarbs = hasCarbsTarget ? profile.targetCarbs.toDouble() : 0.0;

    final bool hasFatTarget = profile.isProfileValid && profile.targetFat > 0;
    final double targetFat = hasFatTarget ? profile.targetFat.toDouble() : 0.0;

    final int actualCalories = plan.totalCaloriesConsumed;
    final double actualProtein = plan.totalProteinConsumed.toDouble();
    final double actualCarbs = plan.totalCarbsConsumed.toDouble();
    final double actualFat = plan.totalFatConsumed.toDouble();

    final int remainCal = targetCalories - actualCalories;
    final bool isCalOver = remainCal < 0;
    final double calProgress = hasCalTarget
        ? (actualCalories / targetCalories).clamp(0.0, 1.0)
        : 0.0;
    final double calPercentage = hasCalTarget
        ? (actualCalories / targetCalories * 100)
        : 0.0;

    final numberFormat = NumberFormat('#,###');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Micro labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  "TODAY'S INTAKE",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'LOGGED INTAKE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF9CA3AF).withOpacity(0.8),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Calorie Headline Comparison
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            numberFormat.format(actualCalories),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF9FAFB),
                              letterSpacing: -0.8,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasCalTarget
                                ? '/ ${numberFormat.format(targetCalories)} kcal'
                                : '/ — kcal',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasCalTarget
                          ? 'CONSUMED / DAILY TARGET'
                          : 'CONSUMED',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasCalTarget) ...[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          isCalOver
                              ? '${numberFormat.format(remainCal.abs())} kcal over'
                              : '${numberFormat.format(remainCal)} kcal remaining',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isCalOver
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${calPercentage.toStringAsFixed(1)}% of goal',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ] else ...[
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Set profile goal',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'No target configured',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Clean 6px Progress Bar (hidden if no target)
          if (hasCalTarget) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 6,
                width: double.infinity,
                color: const Color(0xFF26282F),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: calProgress,
                  child: Container(
                    color: isCalOver
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 4. Macro Telemetry Grid (3 columns)
          Container(
            padding: EdgeInsets.only(top: hasCalTarget ? 12 : 6),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFF26282F)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MacroTile(
                    label: 'Protein',
                    color: const Color(0xFF10B981),
                    actual: actualProtein,
                    target: targetProtein,
                    hasTarget: hasProteinTarget,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroTile(
                    label: 'Carbs',
                    color: const Color(0xFFF59E0B),
                    actual: actualCarbs,
                    target: targetCarbs,
                    hasTarget: hasCarbsTarget,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroTile(
                    label: 'Fat',
                    color: const Color(0xFFA855F7),
                    actual: actualFat,
                    target: targetFat,
                    hasTarget: hasFatTarget,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  final String label;
  final Color color;
  final double actual;
  final double target;
  final bool hasTarget;

  const _MacroTile({
    required this.label,
    required this.color,
    required this.actual,
    required this.target,
    this.hasTarget = true,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = (hasTarget && target > 0)
        ? (actual / target).clamp(0.0, 1.0)
        : 0.0;
    final int diff = hasTarget ? (target - actual).round() : 0;
    final bool isOver = diff < 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF121316),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26282F).withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with dot
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFF3F4F6),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Values
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${actual.toInt()}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF3F4F6),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  hasTarget ? '/ ${target.toInt()}g' : '/ —',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Progress bar or spacer & diff
          if (hasTarget) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 4,
                width: double.infinity,
                color: const Color(0xFF26282F),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(color: color),
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                isOver ? '${diff.abs()}g over' : '${diff}g left',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'No target',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

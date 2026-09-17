// lib/screens/nutrition/widgets/nutrition_summary.dart
// REDESIGN: Monochrome Performance — loại bỏ neon green / blue / orange / red
// Logic: giữ nguyên 100% (macroTargetsProvider fallback chain, calOver, proProgress...)

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/nutrition_model.dart';
import '../../../../providers/profile_provider.dart';
import '../../../../providers/nutrition_provider.dart';
import '../../../../config/app_theme.dart';

class NutritionSummary extends ConsumerWidget {
  final NutritionPlan plan;
  final ProfileState profile;

  const NutritionSummary(
      {super.key, required this.plan, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targets = (ref.watch(macroTargetsProvider) as MacroTargets?) ??
        MacroTargets.defaultTargets;

    // ✅ Logic giữ nguyên: ưu tiên profile → macroTargetsProvider → fallback
    final targetCalories = (profile.targetCalories > 0)
        ? profile.targetCalories
        : (targets.calories > 0
            ? targets.calories
            : plan.totalCaloriesConsumed);
    final targetProtein = ((profile.targetProtein > 0)
            ? profile.targetProtein
            : (targets.protein > 0 ? targets.protein : 0))
        .toDouble();
    final targetCarbs = ((profile.targetCarbs > 0)
            ? profile.targetCarbs
            : (targets.carbs > 0 ? targets.carbs : 0))
        .toDouble();
    final targetFat = ((profile.targetFat > 0)
            ? profile.targetFat
            : (targets.fat > 0 ? targets.fat : 0))
        .toDouble();

    final actualCalories = plan.totalCaloriesConsumed.toDouble();
    final actualProtein = plan.totalProteinConsumed.toDouble();
    final actualCarbs = plan.totalCarbsConsumed.toDouble();
    final actualFat = plan.totalFatConsumed.toDouble();

    final int remainCal = targetCalories - actualCalories.toInt();
    final bool isCalOver = remainCal < 0;
    final double calProgress = targetCalories > 0
        ? (actualCalories / targetCalories).clamp(0.0, 1.0)
        : 0.0;
    final double proProgress = targetProtein > 0
        ? (actualProtein / targetProtein).clamp(0.0, 1.0)
        : 0.0;

    // ✅ REDESIGN: monochrome — không còn neon green / red / blue
    // Chỉ dùng: onSurface (dark fill) và trackColor (light bg)
    final Color ringFill = isCalOver
        ? (isDark ? const Color(0xFFCF6679) : const Color(0xFFB00020)) // danger
        : colors.onSurface;
    final Color ringTrack = context.trackColor;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [context.cardShadow],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Ring chart (calories) ───────────────────────────
              SizedBox(
                height: 96,
                width: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Track
                    CircularProgressIndicator(
                      value: 1,
                      color: ringTrack,
                      strokeWidth: 9,
                    ),
                    // Fill
                    CircularProgressIndicator(
                      value: calProgress,
                      color: ringFill,
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                    ),
                    // Center label
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isCalOver ? '${remainCal.abs()}' : '$remainCal',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            letterSpacing: -0.5,
                            height: 1,
                          ),
                        ),
                        Text(
                          isCalOver ? 'over' : 'left',
                          style: TextStyle(
                            color: colors.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              // ── Right column ────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label
                    Text(
                      'Daily Target',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.secondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Calories fraction
                    Text(
                      '${actualCalories.toInt()} / $targetCalories kcal',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Protein bar (single prominent bar) ─────────
                    _LabeledBar(
                      label: 'Protein',
                      actual: actualProtein,
                      target: targetProtein,
                      progress: proProgress,
                      barHeight: 6,
                      colors: colors,
                      isDark: isDark,
                    ),

                    const SizedBox(height: 14),

                    // ── 3 mini macro bars ───────────────────────────
                    Row(
                      children: [
                        _MacroBar(
                          label: 'Protein',
                          actual: actualProtein,
                          target: targetProtein,
                          colors: colors,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _MacroBar(
                          label: 'Carbs',
                          actual: actualCarbs,
                          target: targetCarbs,
                          colors: colors,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _MacroBar(
                          label: 'Fat',
                          actual: actualFat,
                          target: targetFat,
                          colors: colors,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06);
  }
}

// ── Prominent labeled progress bar (e.g. Protein row) ─────────────────────
class _LabeledBar extends StatelessWidget {
  final String label;
  final double actual;
  final double target;
  final double progress;
  final double barHeight;
  final ColorScheme colors;
  final bool isDark;

  const _LabeledBar({
    required this.label,
    required this.actual,
    required this.target,
    required this.progress,
    required this.barHeight,
    required this.colors,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            Text(
              '${actual.toInt()} / ${target.toInt()}g',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(barHeight),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: barHeight,
            backgroundColor:
                isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8),
            valueColor: AlwaysStoppedAnimation<Color>(colors.onSurface),
          ),
        ),
      ],
    );
  }
}

// ── Mini macro bar (3-column row) ─────────────────────────────────────────
class _MacroBar extends StatelessWidget {
  final String label;
  final double actual;
  final double target;
  final ColorScheme colors;
  final bool isDark;

  const _MacroBar({
    required this.label,
    required this.actual,
    required this.target,
    required this.colors,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;

    // Monochrome opacity tiers so 3 bars look distinct without color
    final barColor = colors.onSurface.withOpacity(
      label == 'Protein'
          ? 1.0
          : label == 'Carbs'
              ? 0.65
              : 0.4,
    );

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.secondary,
                ),
              ),
              Text(
                '${actual.toInt()}/${target.toInt()}g',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor:
                  isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

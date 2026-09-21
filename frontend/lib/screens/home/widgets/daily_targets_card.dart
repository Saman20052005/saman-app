import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Unified Daily Targets (Nutrition & Hydration) module for Saman Home.
///
/// Final visual truth: `design/saman-home/home-screen.png`
/// Displays:
/// - Section header with "DAILY TARGETS", "2 on track" badge, and "Nutrition details →"
/// - Calorie intake gauge with percentage indicator
/// - 3-column macro split (Protein, Carbs, Fat) with dedicated semantic accents
/// - Water / Hydration progress line
class DailyTargetsCard extends StatelessWidget {
  const DailyTargetsCard({
    super.key,
    this.caloriesConsumed = 1850,
    this.caloriesTarget = 2500,
    this.proteinConsumed = 120.0,
    this.proteinTarget = 160.0,
    this.carbsConsumed = 210.0,
    this.carbsTarget = 260.0,
    this.fatConsumed = 55.0,
    this.fatTarget = 70.0,
    this.waterConsumedLiters = 1.8,
    this.waterTargetLiters = 2.5,
    this.onTrackBadgeText = '2 on track',
    this.onNutritionDetailsTap,
  });

  final int caloriesConsumed;
  final int caloriesTarget;
  final double proteinConsumed;
  final double proteinTarget;
  final double carbsConsumed;
  final double carbsTarget;
  final double fatConsumed;
  final double fatTarget;
  final double waterConsumedLiters;
  final double waterTargetLiters;
  final String onTrackBadgeText;
  final VoidCallback? onNutritionDetailsTap;

  @override
  Widget build(BuildContext context) {
    final caloriePercent = caloriesTarget > 0
        ? (caloriesConsumed / caloriesTarget).clamp(0.0, 1.0)
        : 0.0;
    final proteinPercent = proteinTarget > 0
        ? (proteinConsumed / proteinTarget).clamp(0.0, 1.0)
        : 0.0;
    final carbsPercent = carbsTarget > 0
        ? (carbsConsumed / carbsTarget).clamp(0.0, 1.0)
        : 0.0;
    final fatPercent =
        fatTarget > 0 ? (fatConsumed / fatTarget).clamp(0.0, 1.0) : 0.0;
    final waterPercent = waterTargetLiters > 0
        ? (waterConsumedLiters / waterTargetLiters).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Container(
        padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
        decoration: BoxDecoration(
          color: SamanHomeTokens.cardSurface,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXl),
          border: Border.all(
            color: SamanHomeTokens.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header Row ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'DAILY TARGETS',
                  style: SamanHomeTokens.sectionHeader,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: SamanHomeTokens.greenBadgeBg,
                            borderRadius: BorderRadius.circular(
                              SamanHomeTokens.radiusPill,
                            ),
                            border: Border.all(
                              color: SamanHomeTokens.greenBadgeBorder,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            onTrackBadgeText,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: SamanHomeTokens.greenAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onNutritionDetailsTap,
                            borderRadius:
                                BorderRadius.circular(SamanHomeTokens.radiusSm),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Nutrition details',
                                    style: SamanHomeTokens.linkText,
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 13,
                                    color: SamanHomeTokens.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SamanHomeTokens.spacingLg),

            // ─── Calories Row ────────────────────────────────────────
            _MetricHeaderValueRow(
              title: 'Calories',
              currentText: caloriesConsumed.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => '${m[1]},',
                  ),
              targetUnitText: ' / ${caloriesTarget.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => '${m[1]},',
                  )} kcal',
              percentageText: '${(caloriePercent * 100).round()}%',
            ),
            const SizedBox(height: 6),
            _SlimProgressBar(
              value: caloriePercent,
              fillColor: SamanHomeTokens.calorieFill,
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            const Divider(
              color: SamanHomeTokens.divider,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            // ─── 3-Column Macro Split ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _MacroColumn(
                    name: 'PROTEIN',
                    percentage: '${(proteinPercent * 100).round()}%',
                    percentColor: SamanHomeTokens.greenAccent,
                    currentAmount: '${proteinConsumed.round()}g',
                    targetAmount: ' / ${proteinTarget.round()}g',
                    progressValue: proteinPercent,
                    progressColor: SamanHomeTokens.greenAccent,
                  ),
                ),
                const SizedBox(width: SamanHomeTokens.spacingMd),
                Expanded(
                  child: _MacroColumn(
                    name: 'CARBS',
                    percentage: '${(carbsPercent * 100).round()}%',
                    percentColor: SamanHomeTokens.carbsAmber,
                    currentAmount: '${carbsConsumed.round()}g',
                    targetAmount: ' / ${carbsTarget.round()}g',
                    progressValue: carbsPercent,
                    progressColor: SamanHomeTokens.carbsAmber,
                  ),
                ),
                const SizedBox(width: SamanHomeTokens.spacingMd),
                Expanded(
                  child: _MacroColumn(
                    name: 'FAT',
                    percentage: '${(fatPercent * 100).round()}%',
                    percentColor: SamanHomeTokens.fatViolet,
                    currentAmount: '${fatConsumed.round()}g',
                    targetAmount: ' / ${fatTarget.round()}g',
                    progressValue: fatPercent,
                    progressColor: SamanHomeTokens.fatViolet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            const Divider(
              color: SamanHomeTokens.divider,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            // ─── Water Row ───────────────────────────────────────────
            _MetricHeaderValueRow(
              title: 'Water',
              currentText: '${waterConsumedLiters.toStringAsFixed(1)}L',
              targetUnitText: ' / ${waterTargetLiters.toStringAsFixed(1)}L',
              percentageText: '${(waterPercent * 100).round()}%',
            ),
            const SizedBox(height: 6),
            _SlimProgressBar(
              value: waterPercent,
              fillColor: SamanHomeTokens.waterFill,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricHeaderValueRow extends StatelessWidget {
  const _MetricHeaderValueRow({
    required this.title,
    required this.currentText,
    required this.targetUnitText,
    required this.percentageText,
  });

  final String title;
  final String currentText;
  final String targetUnitText;
  final String percentageText;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: SamanHomeTokens.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
                Text(
                  targetUnitText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: SamanHomeTokens.textSecondary,
                  ),
                ),
                const Text(
                  ' · ',
                  style: TextStyle(
                    fontSize: 12,
                    color: SamanHomeTokens.textMuted,
                  ),
                ),
                Text(
                  percentageText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SamanHomeTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MacroColumn extends StatelessWidget {
  const _MacroColumn({
    required this.name,
    required this.percentage,
    required this.percentColor,
    required this.currentAmount,
    required this.targetAmount,
    required this.progressValue,
    required this.progressColor,
  });

  final String name;
  final String percentage;
  final Color percentColor;
  final String currentAmount;
  final String targetAmount;
  final double progressValue;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: SamanHomeTokens.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              percentage,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: percentColor,
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentAmount,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SamanHomeTokens.textWhite,
                ),
              ),
              Text(
                targetAmount,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                  color: SamanHomeTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        _SlimProgressBar(
          value: progressValue,
          fillColor: progressColor,
        ),
      ],
    );
  }
}

class _SlimProgressBar extends StatelessWidget {
  const _SlimProgressBar({
    required this.value,
    required this.fillColor,
  });

  final double value;
  final Color fillColor;
  static const double _barHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final fillWidth = (totalWidth * value).clamp(0.0, totalWidth);

        return Container(
          width: totalWidth,
          height: _barHeight,
          decoration: BoxDecoration(
            color: SamanHomeTokens.progressTrack,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill),
          ),
          alignment: Alignment.centerLeft,
          child: Container(
            width: fillWidth,
            height: _barHeight,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill),
            ),
          ),
        );
      },
    );
  }
}

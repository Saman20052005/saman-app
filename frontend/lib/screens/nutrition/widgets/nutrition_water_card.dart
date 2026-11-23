import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_theme.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Tactile water card with 8-segment ratio meter & +250ml quick action.
class NutritionWaterCard extends StatelessWidget {
  final int currentWater;
  final int targetWater;
  final bool hasTarget;
  final bool isUpdating;
  final VoidCallback? onAddWater;

  const NutritionWaterCard({
    super.key,
    required this.currentWater,
    required this.targetWater,
    this.hasTarget = true,
    this.isUpdating = false,
    this.onAddWater,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final tokens = SamanHomeTokens.of(context);
    final isDark = palette.isDark;
    final cardBg = isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderCol = isDark ? const Color(0xFF26282F) : tokens.border;
    final pillBg = isDark ? const Color(0xFF212328) : tokens.cardSurfaceElevated;
    final waterAccent = isDark ? const Color(0xFF4EDEAF) : tokens.waterCyan;
    final inkPrimary = isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final inkMuted = isDark ? const Color(0xFF9CA3AF) : tokens.textSecondary;
    final inkRemaining = isDark ? const Color(0xFFCBD5E1) : tokens.textSecondary;
    final emptySegment = isDark ? const Color(0xFF26282F) : tokens.progressTrack;

    final bool isTargetValid = hasTarget && targetWater > 0;
    final int remaining = isTargetValid ? targetWater - currentWater : 0;
    final bool goalReached = isTargetValid && remaining <= 0;
    final double fraction = isTargetValid
        ? (currentWater / targetWater).clamp(0.0, 1.0)
        : 0.0;
    final int percentage = isTargetValid
        ? (currentWater / targetWater * 100).round()
        : 0;
    final numberFormat = NumberFormat('#,###');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.water_drop_rounded,
                    size: 18,
                    color: waterAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'WATER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: inkMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isTargetValid
                      ? (goalReached
                          ? 'Goal reached!'
                          : '${numberFormat.format(remaining)} ml remaining')
                      : 'Set hydration target',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isTargetValid && goalReached
                        ? waterAccent
                        : inkRemaining,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Middle Row: Value comparison & +250 ml button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                            numberFormat.format(currentWater),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: inkPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isTargetValid
                                ? '/ ${numberFormat.format(targetWater)} ml'
                                : '/ — ml',
                            style: TextStyle(
                              fontSize: 12,
                              color: inkMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTargetValid
                          ? '$percentage% of daily hydration'
                          : 'Hydration goal not set',
                      style: TextStyle(
                        fontSize: 11,
                        color: inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Tactile +250 ml button with double-tap prevention
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isUpdating ? null : onAddWater,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderCol),
                    ),
                    child: Center(
                      child: isUpdating
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: waterAccent,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 16,
                                  color: waterAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '250 ml',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: inkPrimary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. 8-segment progress strip
          Row(
            children: List.generate(8, (index) {
              final double startThreshold = index / 8.0;
              final double endThreshold = (index + 1) / 8.0;

              final bool isFullyFilled = fraction >= endThreshold;
              final bool isPartiallyFilled =
                  !isFullyFilled && fraction > startThreshold;

              Color segmentColor;
              BoxBorder? border;

              if (isFullyFilled) {
                segmentColor = waterAccent;
              } else if (isPartiallyFilled) {
                segmentColor = waterAccent.withOpacity(0.25);
                border = Border.all(
                  color: waterAccent.withOpacity(0.6),
                );
              } else {
                segmentColor = emptySegment;
              }

              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(
                    right: index == 7 ? 0 : 5,
                  ),
                  decoration: BoxDecoration(
                    color: segmentColor,
                    borderRadius: BorderRadius.circular(999),
                    border: border,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

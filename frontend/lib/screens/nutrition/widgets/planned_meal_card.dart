import 'package:flutter/material.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_translations.dart';
import '../../../../models/nutrition_model.dart';

/// Card displaying the next suggested planned meal matching Calm Athleticism spec:
/// Header: MEAL PLAN + PLANNED badge + Time
/// Content: Next suggested meal + Title + Macros | Review & log button
class PlannedMealCard extends StatelessWidget {
  final Meal meal;
  final VoidCallback onReview;

  const PlannedMealCard({
    super.key,
    required this.meal,
    required this.onReview,
  });

  String _formatMealHeader() {
    final type = meal.mealType.isNotEmpty ? meal.mealType : 'Meal';
    return type[0].toUpperCase() + type.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final isDark = palette.isDark;
    final cardBg = isDark ? const Color(0xFF16171B) : palette.surface;
    final pillBg = isDark ? const Color(0xFF212328) : palette.surfaceElevated;
    final borderCol = isDark ? const Color(0xFF26282F) : palette.border;
    final inkPrimary = isDark ? const Color(0xFFF3F4F6) : palette.textPrimary;
    final inkMuted = isDark ? const Color(0xFF9CA3AF) : palette.textSecondary;
    final accentCol = isDark ? const Color(0xFF10B981) : palette.accent;

    final headerType = _formatMealHeader();
    final timeStr = headerType;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isCompact = constraints.maxWidth < 280;

          final reviewButton = Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onReview,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderCol),
                ),
                child: Center(
                  child: Text(
                    context.tr('review_and_log'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: inkPrimary,
                    ),
                  ),
                ),
              ),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr('meal_plan_heading'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: inkMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: accentCol.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              context.tr('planned_badge'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: accentCol,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      timeStr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Content: Adaptive column if compact, or row if standard
              if (isCompact) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('suggested_meal'),
                      style: TextStyle(
                        fontSize: 12,
                        color: inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$headerType: ${meal.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: inkPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${meal.calories} kcal · ${meal.protein.toInt()}g pro · ${meal.carbs.toInt()}g carb · ${meal.fat.toInt()}g fat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: inkMuted,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: reviewButton,
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('suggested_meal'),
                            style: TextStyle(
                              fontSize: 12,
                              color: inkMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$headerType: ${meal.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: inkPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${meal.calories} kcal · ${meal.protein.toInt()}g pro · ${meal.carbs.toInt()}g carb · ${meal.fat.toInt()}g fat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: inkMuted,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    reviewButton,
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

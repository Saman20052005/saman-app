import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/ai_analysis_result.dart';
import '../../../providers/nutrition_provider.dart';
import '../tokens/saman_chat_tokens.dart';

/// Structured Meal Estimate card for Saman Chat Food Photo Result (State 03).
///
/// Displays:
/// - "Meal estimate" header with "Estimated from photo"
/// - Food name and estimated calories
/// - Three-column macro grid (Protein, Carbs, Fat) with calibrated semantic dots
/// - Real remaining target context (only if real user nutrition targets are active)
/// - "Log meal →" action button
class SamanMealEstimateCard extends ConsumerWidget {
  final AIAnalysisResult result;
  final bool isMealLogged;
  final VoidCallback onLogMeal;

  const SamanMealEstimateCard({
    super.key,
    required this.result,
    this.isMealLogged = false,
    required this.onLogMeal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read real nutrition context if available
    final macroTargets = ref.watch(macroTargetsProvider);
    final nutritionPlanAsync = ref.watch(nutritionProvider);

    int? remainingCalories;
    int? remainingProtein;

    if (macroTargets != null &&
        macroTargets.calories > 0 &&
        nutritionPlanAsync.hasValue &&
        nutritionPlanAsync.value != null) {
      final plan = nutritionPlanAsync.value!;
      final remCal = macroTargets.calories - plan.totalCaloriesConsumed;
      final remProt = (macroTargets.protein - plan.totalProteinConsumed).round();
      remainingCalories = remCal.clamp(0, 99999);
      remainingProtein = remProt.clamp(0, 99999);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380.0),
      decoration: BoxDecoration(
        color: SamanChatTokens.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Header bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Meal estimate',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SamanChatTokens.textWhite,
                ),
              ),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  'ESTIMATED FROM PHOTO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                    color: SamanChatTokens.textMuted.withOpacity(0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8.0),
          const Divider(
            color: SamanChatTokens.borderSubtle,
            height: 1.0,
          ),
          const SizedBox(height: 10.0),

          // 2. Food name & Calories
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  result.foodName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SamanChatTokens.textWhite,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8.0),
              Text(
                '~${result.calories.round()} kcal',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SamanChatTokens.greenAccent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10.0),

          // 3. Three-column macro grid
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: SamanChatTokens.canvas,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: SamanChatTokens.borderSubtle,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                _MacroColumn(
                  dotColor: SamanChatTokens.greenAccent,
                  label: 'PROTEIN',
                  grams: result.protein.round(),
                ),
                _MacroColumn(
                  dotColor: SamanChatTokens.amberAccent,
                  label: 'CARBS',
                  grams: result.carbs.round(),
                ),
                _MacroColumn(
                  dotColor: SamanChatTokens.violetAccent,
                  label: 'FAT',
                  grams: result.fat.round(),
                ),
              ],
            ),
          ),

          // 4. Remaining targets context (strictly only when real data exists)
          if (remainingCalories != null && remainingProtein != null) ...[
            const SizedBox(height: 10.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '~$remainingProtein g protein remaining',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SamanChatTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    '~$remainingCalories kcal remaining',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SamanChatTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10.0),
          const Divider(
            color: SamanChatTokens.borderSubtle,
            height: 1.0,
          ),
          const SizedBox(height: 6.0),

          // 5. Action Row: Log meal ->
          InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: isMealLogged ? null : onLogMeal,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMealLogged ? '✓ Meal logged' : 'Log meal',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isMealLogged
                          ? SamanChatTokens.textMuted
                          : SamanChatTokens.greenAccent,
                    ),
                  ),
                  if (!isMealLogged) ...[
                    const SizedBox(width: 4.0),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
                      color: SamanChatTokens.greenAccent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroColumn extends StatelessWidget {
  final Color dotColor;
  final String label;
  final int grams;

  const _MacroColumn({
    required this.dotColor,
    required this.label,
    required this.grams,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6.0,
                height: 6.0,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5.0),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: SamanChatTokens.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            '${grams}g',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
            ),
          ),
        ],
      ),
    );
  }
}

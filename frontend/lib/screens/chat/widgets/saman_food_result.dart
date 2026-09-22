import 'package:flutter/material.dart';
import '../../../models/ai_analysis_result.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';
import 'saman_meal_estimate_card.dart';

/// State 03 presentation: Food Photo Result.
///
/// Combines:
/// - Saman assistant identity header
/// - Natural conversational overview
/// - Structured SamanMealEstimateCard
class SamanFoodResult extends StatelessWidget {
  final AIAnalysisResult result;
  final bool isMealLogged;
  final VoidCallback onLogMeal;

  const SamanFoodResult({
    super.key,
    required this.result,
    this.isMealLogged = false,
    required this.onLogMeal,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Assistant identity header
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SamanMonogram.chat(),
                SizedBox(width: 8.0),
                Text(
                  'Saman',
                  style: SamanChatTokens.assistantName,
                ),
              ],
            ),
            const SizedBox(height: 8.0),

            // Conversational lead-in
            Text(
              'This looks like ${result.foodName.toLowerCase()}. Here is the estimated nutrition profile based on the portion size.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: SamanChatTokens.textWhite,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12.0),

            // Structured Meal Estimate Card
            SamanMealEstimateCard(
              result: result,
              isMealLogged: isMealLogged,
              onLogMeal: onLogMeal,
            ),
          ],
        ),
      ),
    );
  }
}

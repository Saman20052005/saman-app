import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// Approved State 06 presentation: Food Photo Analysis Loading.
///
/// Features:
/// - Saman monogram + "Saman" identity header
/// - "Looking at your meal..." natural status text
/// - Three pulsing animation dots
/// - "Checking the portion and main ingredients..." guidance line
/// - Strictly NO premature macros, NO bounding boxes, NO CV jargon
class SamanFoodAnalysisLoading extends StatefulWidget {
  const SamanFoodAnalysisLoading({super.key});

  @override
  State<SamanFoodAnalysisLoading> createState() =>
      _SamanFoodAnalysisLoadingState();
}

class _SamanFoodAnalysisLoadingState extends State<SamanFoodAnalysisLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Assistant identity header
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SamanMonogram.chat(),
                const SizedBox(width: 8.0),
                Text(
                  'Saman',
                  style: t.assistantName,
                ),
              ],
            ),
            const SizedBox(height: 8.0),

            // Looking at your meal title
            Text(
              'Looking at your meal...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: t.textWhite,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8.0),

            // Subtle pulsing dot indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: t.borderSubtle,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _dotController,
                    builder: (context, child) {
                      final delay = i * 0.2;
                      final progress = (_dotController.value - delay) % 1.0;
                      final opacity = disableAnimations
                          ? 0.7
                          : (0.3 + 0.7 * (1.0 - (progress - 0.5).abs() * 2.0))
                              .clamp(0.2, 1.0);
                      return Container(
                        margin: EdgeInsets.only(right: i < 2 ? 6.0 : 0.0),
                        width: 6.0,
                        height: 6.0,
                        decoration: BoxDecoration(
                          color: t.textSecondary.withOpacity(opacity),
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
            const SizedBox(height: 8.0),

            // Helper text
            Text(
              'Checking the portion and main ingredients...',
              style: TextStyle(
                fontSize: 12,
                color: t.textMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

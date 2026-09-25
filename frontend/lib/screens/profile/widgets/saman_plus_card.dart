import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Understated premium membership opportunity card for Saman+.
///
/// Features:
/// - Subtle elevated charcoal container with hairline border
/// - Micro indicator dot with emerald accent (• SAMAN+)
/// - Title: "Unlock more with Saman+"
/// - Description: "Adaptive plans, deeper insights and more personalized coaching."
/// - Benefits: "Advanced reports · Body trends · More Saman Coach"
/// - Restrained action: "Explore Saman+ →"
///
/// Guardrails:
/// - Strictly free of pricing, sale banners, countdowns, gold VIP badges, or checkout dialogs.
class SamanPlusCard extends StatelessWidget {
  const SamanPlusCard({
    super.key,
    this.onExploreTap,
  });

  final VoidCallback? onExploreTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
      decoration: BoxDecoration(
        color: SamanHomeTokens.cardSurfaceElevated,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(
          color: SamanHomeTokens.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Green Accent Dot and Label
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SamanHomeTokens.greenAccent,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'SAMAN+',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.greenAccent,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: SamanHomeTokens.spacingSm),

          // Title
          const Text(
            'Unlock more with Saman+',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),

          // Description
          const Text(
            'Adaptive plans, deeper insights and more personalized coaching.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: SamanHomeTokens.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: SamanHomeTokens.spacingSm),

          // Benefits
          const Text(
            'Advanced reports · Body trends · More Saman Coach',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: SamanHomeTokens.textMuted,
            ),
          ),
          const SizedBox(height: SamanHomeTokens.spacingMd),

          // CTA Link
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onExploreTap,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXs),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Explore Saman+',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SamanHomeTokens.greenAccent,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

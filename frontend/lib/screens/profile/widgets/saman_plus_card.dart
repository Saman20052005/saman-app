import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Understated premium membership opportunity card for Saman+.
///
/// Features:
/// - Subtle elevated charcoal container with hairline border
/// - Micro indicator dot with emerald accent (• SAMAN+)
/// - Customizable title, description, and benefits
/// - Actionable CTA link when callback is present; static label or omitted when null.
///
/// Guardrails:
/// - Strictly free of pricing, sale banners, countdowns, gold VIP badges, or checkout dialogs.
/// - When [onExploreTap] is null, renders no enabled button, chevron, or InkWell.
class SamanPlusCard extends StatelessWidget {
  const SamanPlusCard({
    super.key,
    this.onExploreTap,
    this.badgeLabel = 'SAMAN+',
    this.title = 'Unlock more with Saman+',
    this.description = 'Adaptive plans, deeper insights and more personalized coaching.',
    this.benefits = 'Advanced reports · Body trends · More Saman Coach',
    this.exploreLabel = 'Explore Saman+',
    this.comingSoonLabel,
  });

  final VoidCallback? onExploreTap;
  final String badgeLabel;
  final String title;
  final String description;
  final String? benefits;
  final String exploreLabel;
  final String? comingSoonLabel;

  @override
  Widget build(BuildContext context) {
    final isActionable = onExploreTap != null;
    final hasComingSoon = !isActionable && comingSoonLabel != null && comingSoonLabel!.trim().isNotEmpty;

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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row with Green Accent Dot and Label
          if (badgeLabel.isNotEmpty) ...[
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
                Expanded(
                  child: Text(
                    badgeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SamanHomeTokens.spacingSm),
          ],

          // Title
          if (title.isNotEmpty) ...[
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
          ],

          // Description
          if (description.isNotEmpty) ...[
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: SamanHomeTokens.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: SamanHomeTokens.spacingSm),
          ],

          // Benefits
          if (benefits != null && benefits!.trim().isNotEmpty) ...[
            Text(
              benefits!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: SamanHomeTokens.textMuted,
              ),
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),
          ],

          // CTA or Coming Soon
          if (isActionable)
            Semantics(
              button: true,
              enabled: true,
              label: exploreLabel,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onExploreTap,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXs),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              exploreLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: SamanHomeTokens.greenAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: SamanHomeTokens.greenAccent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (hasComingSoon)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                comingSoonLabel!.trim(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: SamanHomeTokens.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

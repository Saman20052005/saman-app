import 'package:flutter/material.dart';

import '../localization/shop_translations.dart';
import '../theme/shop_theme.dart';

/// Asymmetrical editorial hero banner for Saman Shop Landing.
///
/// Specs from design:
/// - Height: ~185px, border-radius 16px.
/// - Surface: #16171B.
/// - Left 55%: Editorial title, subtitle, and interactive "Khám phá →" link.
/// - Right 45%: Studio boutique photography with smooth inner gradient blend.
class ShopEditorialHero extends StatelessWidget {
  const ShopEditorialHero({
    super.key,
    required this.onExploreTap,
  });

  final VoidCallback onExploreTap;

  static const String _heroAsset = 'assets/images/shop/shop_hero_lifestyle.jpg';

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 185),
      decoration: BoxDecoration(
        color: ShopTheme.surfaceCard,
        borderRadius: BorderRadius.circular(ShopTheme.radiusXl),
        border: Border.all(
          color: ShopTheme.borderSubtle,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left editorial content
            Expanded(
              flex: 55,
              child: Padding(
                padding: const EdgeInsets.all(ShopTheme.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ShopTranslations.of(context, 'hero_title'),
                          style: ShopTheme.heroTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ShopTranslations.of(context, 'hero_subtitle'),
                          style: ShopTheme.heroSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                    onTap: onExploreTap,
                    borderRadius: BorderRadius.circular(ShopTheme.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              ShopTranslations.of(context, 'hero_explore'),
                              style: ShopTheme.heroAction,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: ShopTheme.textPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right lifestyle studio image
          Expanded(
            flex: 45,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  _heroAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: ShopTheme.surfaceElevated,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.fitness_center_rounded,
                      size: 28,
                      color: ShopTheme.textMuted,
                    ),
                  ),
                ),
                // Inner gradient blend from surfaceCard to transparent
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          ShopTheme.surfaceCard,
                          ShopTheme.surfaceCard.withOpacity(0.5),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.25, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}

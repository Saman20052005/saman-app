import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Data class representing a curated pick card (Journal guide or Shop essential).
class SamanPickItem {
  const SamanPickItem({
    required this.id,
    required this.categoryTag,
    required this.tagColor,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.imageAssetPath,
    this.onTap,
  });

  final String id;
  final String categoryTag;
  final Color tagColor;
  final String title;
  final String description;
  final String actionLabel;
  final String imageAssetPath;
  final VoidCallback? onTap;
}

/// Saman Picks (Contextual Editorial & Ecosystem Surface).
///
/// Final visual truth: `design/saman-home/home-screen.png`
/// Displays:
/// - Section header ("SAMAN PICKS", "Useful for your training today", "Explore →")
/// - Horizontally swipeable snap carousel:
///   1. SAMAN JOURNAL (athletic recovery guide with thumbnail)
///   2. SAMAN SHOP (recovery essentials without prices or checkout clutter)
class SamanPicksCarousel extends StatelessWidget {
  const SamanPicksCarousel({
    super.key,
    this.picks,
    this.onExploreTap,
  });

  final List<SamanPickItem>? picks;
  final VoidCallback? onExploreTap;

  static const List<SamanPickItem> _defaultPicks = [
    SamanPickItem(
      id: 'journal_recovery',
      categoryTag: 'SAMAN JOURNAL',
      tagColor: SamanHomeTokens.greenAccent,
      title: 'Recover better after Leg Day',
      description: 'Three simple habits to support tomorrow’s session.',
      actionLabel: 'Read guide',
      imageAssetPath: 'assets/images/home_journal_recovery.jpg',
    ),
    SamanPickItem(
      id: 'shop_recovery',
      categoryTag: 'SAMAN SHOP',
      tagColor: SamanHomeTokens.textSecondary,
      title: 'Recovery essentials, picked for your plan',
      description: 'Curated to support your current training week.',
      actionLabel: 'Explore picks',
      imageAssetPath: 'assets/images/home_shop_essentials.jpg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = (picks != null && picks!.isNotEmpty) ? picks! : _defaultPicks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SamanHomeTokens.spacingLg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAMAN PICKS',
                      style: SamanHomeTokens.sectionHeader,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Useful for your training today',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: SamanHomeTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onExploreTap,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Explore',
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
        const SizedBox(height: SamanHomeTokens.spacingMd),

        // ─── Horizontal Snap Track ───────────────────────────────────
        SizedBox(
          height: 146,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: SamanHomeTokens.spacingLg,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return _SamanPickCard(item: item);
            },
          ),
        ),
      ],
    );
  }
}

class _SamanPickCard extends StatelessWidget {
  const _SamanPickCard({required this.item});

  final SamanPickItem item;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    // Responsive width: ~84% on phone, constrained on wider devices
    final cardWidth = (screenWidth * 0.84).clamp(280.0, 360.0);

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
      decoration: BoxDecoration(
        color: SamanHomeTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXl),
        border: Border.all(
          color: SamanHomeTokens.borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left text details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.categoryTag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                    color: item.tagColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: SamanHomeTokens.textWhite,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: SamanHomeTokens.textSecondary,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: item.onTap,
                    borderRadius:
                        BorderRadius.circular(SamanHomeTokens.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.actionLabel,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: SamanHomeTokens.textWhite,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 12,
                            color: SamanHomeTokens.textWhite,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Right thumbnail image
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: SamanHomeTokens.iconContainerBg,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              border: Border.all(
                color: SamanHomeTokens.border,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              item.imageAssetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_outlined,
                size: 24,
                color: SamanHomeTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

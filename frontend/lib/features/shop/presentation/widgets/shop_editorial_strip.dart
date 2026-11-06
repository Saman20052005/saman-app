import 'package:flutter/material.dart';

import '../../domain/entities/shop_collection.dart';
import '../localization/shop_translations.dart';
import '../theme/shop_theme.dart';

/// Editorial strip for Curated Collections embedded cleanly into the catalog flow.
///
/// Specs from design:
/// - Surface: #16171B, rounded-2xl (16px), subtle border #23252B.
/// - Left: Small "BỘ SƯU TẬP" badge, collection title, and brief description.
/// - Right: Minimalist "Xem →" action button.
/// - Tapping toggles collection filter on the product catalog.
class ShopEditorialStrip extends StatelessWidget {
  const ShopEditorialStrip({
    super.key,
    required this.collection,
    required this.isSelected,
    required this.onTap,
  });

  final ShopCollection collection;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? ShopTheme.surfaceElevated : ShopTheme.surfaceCard,
        borderRadius: BorderRadius.circular(ShopTheme.radiusXl),
        border: Border.all(
          color: isSelected ? ShopTheme.emerald : ShopTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ShopTheme.radiusXl),
          child: Padding(
            padding: const EdgeInsets.all(ShopTheme.spacingLg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            ShopTranslations.of(
                                context, 'collection_section_label'),
                            style: ShopTheme.collectionBadge,
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: ShopTheme.emerald.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Đang lọc',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: ShopTheme.emerald,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        collection.title,
                        style: ShopTheme.collectionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        collection.description,
                        style: ShopTheme.collectionSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isSelected
                          ? ShopTranslations.of(context, 'clear_filter')
                          : ShopTranslations.of(context, 'collection_action'),
                      style: ShopTheme.fontManrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? ShopTheme.emerald
                            : ShopTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      isSelected
                          ? Icons.close_rounded
                          : Icons.arrow_forward_rounded,
                      size: 13,
                      color: isSelected
                          ? ShopTheme.emerald
                          : ShopTheme.textPrimary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

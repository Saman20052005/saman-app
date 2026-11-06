import 'package:flutter/material.dart';

import '../../domain/entities/shop_product.dart';
import '../localization/shop_translations.dart';
import '../theme/shop_theme.dart';

/// Modal bottom sheet explaining curated demo items without OS browser dispatch.
/// Keeps clean boutique UI without exposing internal technical provenance or evidence paths.
class ShopDemoExplanationSheet extends StatelessWidget {
  const ShopDemoExplanationSheet({
    super.key,
    required this.product,
  });

  final ShopProduct product;

  static Future<void> show(BuildContext context, ShopProduct product) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: ShopTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShopTheme.radiusXl),
        ),
      ),
      isScrollControlled: true,
      builder: (_) => ShopDemoExplanationSheet(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ShopTheme.paddingPage,
          12.0,
          ShopTheme.paddingPage,
          24.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Center top drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ShopTheme.textMuted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header title
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: ShopTheme.emerald,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ShopTranslations.of(context, 'demo_sheet_title'),
                    style: ShopTheme.headerTitle.copyWith(fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              ShopTranslations.of(context, 'demo_sheet_description'),
              style: ShopTheme.fontManrope(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: ShopTheme.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),

            // Off-white primary close button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShopTheme.ctaSurface,
                  foregroundColor: ShopTheme.ctaText,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                  ),
                ),
                child: Text(
                  ShopTranslations.of(context, 'demo_sheet_close'),
                  style: ShopTheme.ctaButtonText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

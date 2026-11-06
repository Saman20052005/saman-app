import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/routes.dart';
import '../localization/shop_translations.dart';
import '../providers/shop_landing_providers.dart';
import '../theme/shop_theme.dart';

/// Clean minimalist boutique header for Saman Shop Landing.
///
/// Features:
/// - Left: Back navigation icon button.
/// - Center: Centered "Saman Shop" title in Manrope 20px.
/// - Right: Wishlist bookmark icon displaying real saved count badge.
///   Tapping navigates to the Saved Items screen.
class ShopHeader extends ConsumerWidget {
  const ShopHeader({
    super.key,
    this.onBackTap,
    this.onBookmarkTap,
  });

  final VoidCallback? onBackTap;
  final VoidCallback? onBookmarkTap;

  static bool _isNavigating = false;

  static Future<void> _navigateToSaved(BuildContext context) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.of(context).pushNamed(AppRoutes.shopSaved);
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedCount = ref.watch(savedProductsCountProvider);

    return Container(
      color: ShopTheme.canvas,
      padding: const EdgeInsets.symmetric(
        horizontal: ShopTheme.paddingPage,
        vertical: 10.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back button
          SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                onPressed: onBackTap ?? () => Navigator.maybePop(context),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: ShopTheme.textPrimary,
                ),
                splashRadius: 20,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            ),
          ),

          // Centered title
          Expanded(
            child: Text(
              ShopTranslations.of(context, 'shop_title'),
              textAlign: TextAlign.center,
              style: ShopTheme.headerTitle,
            ),
          ),

          // Right bookmark icon with reactive saved count
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  onPressed: onBookmarkTap ?? () => _navigateToSaved(context),
                  icon: Icon(
                    savedCount > 0
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    size: 20,
                    color: savedCount > 0
                        ? ShopTheme.emerald
                        : ShopTheme.textSecondary,
                  ),
                  splashRadius: 20,
                  tooltip: ShopTranslations.of(context, 'saved_title'),
                ),
                if (savedCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: const BoxDecoration(
                        color: ShopTheme.emerald,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        '$savedCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: ShopTheme.canvas,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


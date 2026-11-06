import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../config/routes.dart';
import '../../domain/entities/shop_product.dart';
import '../localization/shop_translations.dart';
import '../providers/shop_landing_providers.dart';
import '../providers/shop_providers.dart';
import '../theme/shop_theme.dart';

/// Curated product card designed for the 2-column boutique catalog grid.
///
/// Features:
/// - 4:5 image container on dark studio slate #1C1D22.
/// - Floating bookmark action button with reactive wishlist state.
/// - Max 2-line title, reference VND price (or "Xem giá trên Shopee" if null).
/// - Discrete "Dữ liệu minh họa" badge for mock/demo products.
/// - Tapping product card opens Product Detail Screen.
class ShopProductCard extends ConsumerWidget {
  const ShopProductCard({
    super.key,
    required this.product,
    this.onTap,
  });

  final ShopProduct product;
  final VoidCallback? onTap;

  static final _currencyFormat = NumberFormat('#,###', 'vi_VN');
  static bool _isNavigating = false;

  static Future<void> _navigateToDetail(
      BuildContext context, String productId) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.of(context).pushNamed(
        AppRoutes.shopDetail,
        arguments: productId,
      );
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = ref.watch(isProductSavedProvider(product.id));

    return GestureDetector(
      onTap: onTap ?? () => _navigateToDetail(context, product.id),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Studio Image Box ───────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: ShopTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                border: Border.all(
                  color: ShopTheme.borderSubtle,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProductImageView(imagePath: product.heroImageUrl),

                  // Discrete demo badge in top-left of image
                  if (product.isDemo)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ShopTranslations.of(context, 'demo_badge'),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),

                  // Floating Bookmark Action
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          ref
                              .read(shopWishlistRepositoryProvider)
                              .toggle(product.id);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_outline_rounded,
                            size: 15,
                            color: isSaved
                                ? ShopTheme.emerald
                                : Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Out of stock / Discontinued badge overlay if unavailable
                  if (product.availability != ProductAvailability.available)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.availability ==
                                  ProductAvailability.discontinued
                              ? 'Ngừng phân phối'
                              : 'Tạm hết hàng',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: ShopTheme.warningAmber,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // ─── Product Name (Max 2 lines) ──────────────────────────────────
          Text(
            product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ShopTheme.productTitle,
          ),
          const SizedBox(height: 4),

          // ─── Reference Price ─────────────────────────────────────────────
          Text(
            _formatPrice(context, product.priceVnd),
            style: product.priceVnd != null
                ? ShopTheme.productPrice
                : ShopTheme.fontManrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ShopTheme.textSecondary,
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatPrice(BuildContext context, int? price) {
    if (price == null) {
      return ShopTranslations.of(context, 'view_price_on_shopee');
    }
    final formatted = _currencyFormat.format(price);
    final pattern = ShopTranslations.of(context, 'price_approx_format');
    return pattern.replaceAll('{price}', formatted);
  }
}

class _ProductImageView extends StatelessWidget {
  const _ProductImageView({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    if (imagePath.startsWith('assets/')) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackContainer(),
      );
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackContainer(),
      );
    }

    return _fallbackContainer();
  }

  Widget _fallbackContainer() {
    return Container(
      color: ShopTheme.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.inventory_2_outlined,
        size: 26,
        color: ShopTheme.textMuted,
      ),
    );
  }
}

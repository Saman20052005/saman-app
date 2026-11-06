import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../config/routes.dart';
import '../controllers/shop_saved_controller.dart';
import '../controllers/shop_saved_state.dart';
import '../localization/shop_translations.dart';
import '../providers/shop_saved_providers.dart';
import '../theme/shop_theme.dart';

/// Screen displaying the user's bookmarked products with real-time sync,
/// batch loading, and graceful handling of unlisted items.
class ShopSavedScreen extends ConsumerStatefulWidget {
  const ShopSavedScreen({super.key});

  @override
  ConsumerState<ShopSavedScreen> createState() => _ShopSavedScreenState();
}

class _ShopSavedScreenState extends ConsumerState<ShopSavedScreen> {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');
  bool _isNavigating = false;

  Future<void> _navigateToDetail(String productId) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.of(context).pushNamed(
        AppRoutes.shopDetail,
        arguments: productId,
      );
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopSavedControllerProvider);
    final controller = ref.read(shopSavedControllerProvider.notifier);

    return Scaffold(
      backgroundColor: ShopTheme.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top boutique header
            _buildHeader(context, state),

            // Main body
            Expanded(
              child: _buildBody(context, state, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ShopSavedState state) {
    final count = state.items.length;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: ShopTheme.paddingPage),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ShopTheme.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: ShopTheme.borderSubtle, width: 1),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: ShopTheme.textPrimary,
              ),
            ),
          ),

          // Title
          Text(
            ShopTranslations.of(context, 'saved_title'),
            style: ShopTheme.headerTitle,
          ),

          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ShopTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
              border: Border.all(color: ShopTheme.borderSubtle, width: 1),
            ),
            child: Text(
              '$count',
              style: ShopTheme.fontManrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: count > 0 ? ShopTheme.emerald : ShopTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ShopSavedState state,
    ShopSavedController controller,
  ) {
    switch (state.status) {
      case ShopSavedStatus.initialLoading:
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(ShopTheme.emerald),
          ),
        );

      case ShopSavedStatus.error:
        return _buildErrorView(context, state, controller);

      case ShopSavedStatus.loaded:
        if (state.isEmpty) {
          return _buildEmptyView(context);
        }
        return _buildListView(context, state, controller);
    }
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ShopTheme.paddingPage),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: ShopTheme.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: ShopTheme.borderSubtle, width: 1),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.bookmark_outline_rounded,
                size: 32,
                color: ShopTheme.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              ShopTranslations.of(context, 'saved_empty_title'),
              style: ShopTheme.headerTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              ShopTranslations.of(context, 'saved_empty_subtitle'),
              style: ShopTheme.fontManrope(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: ShopTheme.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final canPop = Navigator.of(context).canPop();
                if (canPop) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushReplacementNamed(AppRoutes.shop);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ShopTheme.ctaSurface,
                foregroundColor: ShopTheme.ctaText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: Text(
                ShopTranslations.of(context, 'explore_catalog_action'),
                style: ShopTheme.ctaButtonText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    ShopSavedState state,
    ShopSavedController controller,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ShopTheme.paddingPage),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: ShopTheme.errorRed,
            ),
            const SizedBox(height: 16),
            Text(
              ShopTranslations.of(context, 'first_page_error_title'),
              style: ShopTheme.headerTitle,
              textAlign: TextAlign.center,
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                state.errorMessage!,
                style: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: ShopTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: controller.retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: ShopTheme.surfaceElevated,
                foregroundColor: ShopTheme.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                ),
              ),
              child: Text(
                ShopTranslations.of(context, 'retry'),
                style: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ShopTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(
    BuildContext context,
    ShopSavedState state,
    ShopSavedController controller,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        ShopTheme.paddingPage,
        12.0,
        ShopTheme.paddingPage,
        32.0,
      ),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = state.items[index];
        return _buildSavedItemCard(context, item, controller);
      },
    );
  }

  Widget _buildSavedItemCard(
    BuildContext context,
    SavedItemRecord item,
    ShopSavedController controller,
  ) {
    final product = item.product;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: product != null ? () => _navigateToDetail(product.id) : null,
        borderRadius: BorderRadius.circular(ShopTheme.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ShopTheme.surfaceCard,
            borderRadius: BorderRadius.circular(ShopTheme.radiusLg),
            border: Border.all(color: ShopTheme.borderSubtle, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Thumbnail Image (72x72)
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ShopTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                  border: Border.all(color: ShopTheme.borderSubtle, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: product != null
                    ? _buildThumbnailWidget(product.heroImageUrl)
                    : const Icon(
                        Icons.inventory_2_outlined,
                        size: 28,
                        color: ShopTheme.textMuted,
                      ),
              ),
              const SizedBox(width: 14),

              // 2. Title & Price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product != null
                          ? product.title
                          : ShopTranslations.of(
                              context, 'missing_product_in_catalog'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ShopTheme.fontManrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: product != null
                            ? ShopTheme.textPrimary
                            : ShopTheme.textMuted,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product != null
                          ? _formatPrice(context, product.priceVnd)
                          : ShopTranslations.of(context, 'missing_product_id')
                              .replaceAll('{id}', item.productId),
                      style: product?.priceVnd != null
                          ? ShopTheme.productPrice
                          : ShopTheme.fontManrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: ShopTheme.textSecondary,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 3. Remove / Unsave Action Button
              IconButton(
                onPressed: () => controller.unsave(item.productId),
                icon: const Icon(
                  Icons.bookmark_remove_outlined,
                  size: 20,
                  color: ShopTheme.emerald,
                ),
                tooltip: ShopTranslations.of(context, 'unsave_product'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailWidget(String imagePath) {
    if (imagePath.startsWith('assets/')) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackThumbnail(),
      );
    }
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackThumbnail(),
      );
    }
    return _fallbackThumbnail();
  }

  Widget _fallbackThumbnail() {
    return Container(
      color: ShopTheme.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.fitness_center_rounded,
        size: 22,
        color: ShopTheme.textMuted,
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

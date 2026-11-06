import 'package:flutter/material.dart';

import '../localization/shop_translations.dart';
import '../theme/shop_theme.dart';

/// Skeleton placeholder for the 2-column product grid during initial loading.
class ShopSkeletonLoadingView extends StatelessWidget {
  const ShopSkeletonLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Container(
              decoration: BoxDecoration(
                color: ShopTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: ShopTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 80,
            decoration: BoxDecoration(
              color: ShopTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// View rendered when the unfiltered catalog contains zero items.
class ShopEmptyCatalogView extends StatelessWidget {
  const ShopEmptyCatalogView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: ShopTheme.surfaceCard,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_outlined,
              size: 26,
              color: ShopTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ShopTranslations.of(context, 'empty_catalog_title'),
            style: ShopTheme.fontManrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ShopTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            ShopTranslations.of(context, 'empty_catalog_subtitle'),
            style: ShopTheme.fontManrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: ShopTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// View rendered when user's search query or filters match zero products.
class ShopNoResultsView extends StatelessWidget {
  const ShopNoResultsView({
    super.key,
    required this.onResetFilters,
  });

  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: ShopTheme.surfaceCard,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 24,
              color: ShopTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ShopTranslations.of(context, 'no_results_title'),
            style: ShopTheme.fontManrope(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ShopTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            ShopTranslations.of(context, 'no_results_subtitle'),
            style: ShopTheme.fontManrope(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: ShopTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onResetFilters,
            style: OutlinedButton.styleFrom(
              foregroundColor: ShopTheme.textPrimary,
              side: const BorderSide(color: ShopTheme.borderSubtle),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: Text(
              ShopTranslations.of(context, 'reset_filters'),
              style: ShopTheme.fontManrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: ShopTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// View rendered when initial catalog fetch fails.
class ShopFirstPageErrorView extends StatelessWidget {
  const ShopFirstPageErrorView({
    super.key,
    required this.onRetry,
    this.errorMessage,
  });

  final VoidCallback onRetry;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ShopTheme.errorRed.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 26,
              color: ShopTheme.errorRed,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ShopTranslations.of(context, 'first_page_error_title'),
            style: ShopTheme.fontManrope(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ShopTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            errorMessage ??
                ShopTranslations.of(context, 'first_page_error_subtitle'),
            style: ShopTheme.fontManrope(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: ShopTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: ShopTheme.ctaSurface,
              foregroundColor: ShopTheme.ctaText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            ),
            child: Text(
              ShopTranslations.of(context, 'retry'),
              style: ShopTheme.fontManrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ShopTheme.ctaText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Load-more pagination footer widget.
class ShopLoadMoreFooter extends StatelessWidget {
  const ShopLoadMoreFooter({
    super.key,
    required this.isLoadingMore,
    required this.hasError,
    required this.onRetry,
  });

  final bool isLoadingMore;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(ShopTheme.textMuted),
            ),
          ),
        ),
      );
    }

    if (hasError) {
      return InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.refresh_rounded,
                size: 16,
                color: ShopTheme.warningAmber,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  ShopTranslations.of(context, 'load_more_error'),
                  textAlign: TextAlign.center,
                  style: ShopTheme.fontManrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ShopTheme.warningAmber,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox(height: 16);
  }
}

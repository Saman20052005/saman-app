import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/shop_product.dart';
import '../../domain/services/shop_launcher_contract.dart';
import '../controllers/shop_detail_controller.dart';
import '../controllers/shop_detail_state.dart';
import '../localization/shop_translations.dart';
import '../providers/shop_detail_providers.dart';
import '../theme/shop_theme.dart';
import '../widgets/shop_demo_explanation_sheet.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';

/// Screen displaying comprehensive curated product details, provenance,
/// specifications, and demo CTA launch.
class ShopDetailScreen extends ConsumerStatefulWidget {
  const ShopDetailScreen({
    super.key,
    required this.productId,
  });

  final String? productId;

  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final t = ShopTheme.of(context);
    final state = ref.watch(shopDetailControllerProvider(widget.productId));
    final controller =
        ref.read(shopDetailControllerProvider(widget.productId).notifier);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top persistent navigation bar
            _buildTopBar(context, t, state, controller),

            // Main body based on load state
            Expanded(
              child: _buildBody(context, t, state, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    ShopPalette t,
    ShopDetailState state,
    ShopDetailController controller,
  ) {
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
                color: t.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: t.borderSubtle, width: 1),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: t.textPrimary,
              ),
            ),
          ),

          // Bookmark button (visible when product is loaded)
          if (state.status == ShopDetailStatus.loaded)
            InkWell(
              onTap: controller.toggleWishlist,
              borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: state.isSaved
                        ? t.emerald.withOpacity(0.5)
                        : t.borderSubtle,
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  state.isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  size: 18,
                  color: state.isSaved ? t.emerald : t.textSecondary,
                ),
              ),
            )
          else
            const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ShopPalette t,
    ShopDetailState state,
    ShopDetailController controller,
  ) {
    switch (state.status) {
      case ShopDetailStatus.initialLoading:
        return Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(t.emerald),
          ),
        );

      case ShopDetailStatus.notFound:
        return _buildNotFoundView(context, t);

      case ShopDetailStatus.error:
        return _buildErrorView(context, t, state, controller);

      case ShopDetailStatus.loaded:
        return _buildLoadedContent(context, t, state, controller);
    }
  }

  Widget _buildNotFoundView(BuildContext context, ShopPalette t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ShopTheme.paddingPage),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: t.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              ShopTranslations.of(context, 'product_not_found_title'),
              style: t.headerTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              ShopTranslations.of(context, 'product_not_found_subtitle'),
              style: ShopTheme.fontManrope(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: t.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textPrimary,
                side: BorderSide(color: t.borderSubtle),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                ),
              ),
              child: Text(
                ShopTranslations.of(context, 'back_to_catalog'),
                style: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: t.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    ShopPalette t,
    ShopDetailState state,
    ShopDetailController controller,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ShopTheme.paddingPage),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: t.errorRed,
            ),
            const SizedBox(height: 16),
            Text(
              ShopTranslations.of(context, 'error_loading_product'),
              style: t.headerTitle,
              textAlign: TextAlign.center,
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                state.errorMessage!,
                style: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: t.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: controller.retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.surfaceElevated,
                foregroundColor: t.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                ),
              ),
              child: Text(
                ShopTranslations.of(context, 'retry'),
                style: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    ShopPalette t,
    ShopDetailState state,
    ShopDetailController controller,
  ) {
    final product = state.product!;

    return Column(
      children: [
        // Scrollable content stream
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              ShopTheme.paddingPage,
              8.0,
              ShopTheme.paddingPage,
              24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 1. Hero Image Container ──────────────────────────────
                _buildProductHeroImage(t, product),
                const SizedBox(height: 20),

                // ─── 2. Product Title & Seller ────────────────────────────
                Text(
                  product.title,
                  style: ShopTheme.fontManrope(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    height: 1.25,
                  ),
                ),
                if (product.sellerName != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    ShopTranslations.of(context, 'seller_prefix')
                        .replaceAll('{seller}', product.sellerName!),
                    style: ShopTheme.fontManrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: t.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // ─── 3. Reference Price & Update Time ─────────────────────
                _buildPriceSection(context, t, product),
                const SizedBox(height: 20),

                // ─── 4. "Vì sao Saman chọn" (Editorial Note) ──────────────
                _buildWhySamanPicked(context, t, product),
                const SizedBox(height: 24),

                // ─── 5. Specifications Table ──────────────────────────────
                if (product.specifications.isNotEmpty)
                  _buildSpecificationsSection(context, t, product),
              ],
            ),
          ),
        ),

        // Sticky Bottom CTA Bar
        _buildStickyCtaBar(context, t, state, controller),
      ],
    );
  }

  Widget _buildProductHeroImage(ShopPalette t, ShopProduct product) {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: t.surfaceCard,
        borderRadius: BorderRadius.circular(ShopTheme.radiusXl),
        border: Border.all(color: t.borderSubtle, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildHeroImageWidget(t, product.heroImageUrl),

          // Top-left Discrete Demo Badge (floating over photo -> keep dark scrim & bright text)
          if (product.isDemo)
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.14),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: ShopTheme.emerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      ShopTranslations.of(context, 'demo_badge'),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF3F4F6),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Out-of-stock badge overlay if unavailable
          if (product.availability != ProductAvailability.available)
            Positioned(
              bottom: 14,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                  border: Border.all(
                    color: ShopTheme.warningAmber.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  product.availability == ProductAvailability.discontinued
                      ? ShopTranslations.of(context, 'cta_discontinued')
                      : ShopTranslations.of(context, 'cta_unavailable'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ShopTheme.warningAmber,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroImageWidget(ShopPalette t, String imagePath) {
    if (imagePath.startsWith('assets/')) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackHeroContainer(t),
      );
    }
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackHeroContainer(t),
      );
    }
    return _fallbackHeroContainer(t);
  }

  Widget _fallbackHeroContainer(ShopPalette t) {
    return Container(
      color: t.surfaceElevated,
      alignment: Alignment.center,
      child: Icon(
        Icons.fitness_center_rounded,
        size: 48,
        color: t.textMuted,
      ),
    );
  }

  Widget _buildPriceSection(
    BuildContext context,
    ShopPalette t,
    ShopProduct product,
  ) {
    final hasPrice = product.priceVnd != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPrice)
          Text.rich(
            TextSpan(
              text: '~${_currencyFormat.format(product.priceVnd)}',
              style: ShopTheme.fontManrope(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
                letterSpacing: -0.5,
              ),
              children: [
                TextSpan(
                  text: ' đ',
                  style: ShopTheme.fontManrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            ShopTranslations.of(context, 'view_price_on_shopee'),
            style: ShopTheme.fontManrope(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
        if (product.priceUpdatedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            ShopTranslations.of(context, 'price_updated_at').replaceAll(
              '{date}',
              _dateFormat.format(product.priceUpdatedAt!),
            ),
            style: ShopTheme.fontManrope(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: t.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWhySamanPicked(
    BuildContext context,
    ShopPalette t,
    ShopProduct product,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: t.emerald,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                ShopTranslations.of(context, 'curation_why_saman'),
                style: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          product.editorialNote,
          style: ShopTheme.fontManrope(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: t.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSpecificationsSection(
      BuildContext context, ShopPalette t, ShopProduct product) {
    final specs = product.specifications.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ShopTranslations.of(context, 'specifications_header'),
          style: t.sectionHeaderCaps,
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: t.surfaceCard,
            borderRadius: BorderRadius.circular(ShopTheme.radiusLg),
            border: Border.all(color: t.borderSubtle, width: 1),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: specs.length,
            separatorBuilder: (_, __) => Divider(
              color: t.borderDivider,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final entry = specs[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShopTheme.spacingLg,
                  vertical: 12.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        entry.key,
                        style: ShopTheme.fontManrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: Text(
                        entry.value,
                        style: ShopTheme.fontManrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleCtaLaunch(
    ShopDetailController controller,
    ShopProduct product,
  ) async {
    final result = await controller.launchCta();
    if (!mounted || result == null) return;

    if (result.type == LauncherResultType.demo) {
      ShopDemoExplanationSheet.show(context, product);
    } else if (result.type == LauncherResultType.failed) {
      final t = ShopTheme.of(context);
      SamanFeedbackSnackBar.show(
        context,
        message: result.message ??
            ShopTranslations.of(context, 'launcher_error_message'),
        type: FeedbackType.error,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: ShopTranslations.of(context, 'launcher_retry'),
          textColor: t.emerald,
          onPressed: () {
            _handleCtaLaunch(controller, product);
          },
        ),
      );
    }
  }

  Widget _buildStickyCtaBar(
    BuildContext context,
    ShopPalette t,
    ShopDetailState state,
    ShopDetailController controller,
  ) {
    final product = state.product!;
    final isAvailable = product.availability == ProductAvailability.available;

    String ctaLabel;
    if (!isAvailable) {
      ctaLabel = product.availability == ProductAvailability.discontinued
          ? ShopTranslations.of(context, 'cta_discontinued')
          : ShopTranslations.of(context, 'cta_unavailable');
    } else if (product.isDemo) {
      ctaLabel = ShopTranslations.of(context, 'cta_view_on_shopee_demo');
    } else {
      ctaLabel = ShopTranslations.of(context, 'cta_view_on_shopee');
    }

    // Commercial Disclosure (CP-SHOP-08):
    // Disclosure ONLY appears for non-demo items that genuinely have an affiliate mechanism.
    // Suppressed unconditionally for demo items and non-affiliate items (never display merely because isDemo == false).
    final String? disclosureText;
    if (!product.isDemo &&
        product.sourceType == ProductSourceType.affiliatePartner) {
      disclosureText = ShopTranslations.of(context, 'disclosure_affiliate');
    } else {
      disclosureText = null;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
        ShopTheme.paddingPage,
        14.0,
        ShopTheme.paddingPage,
        14.0,
      ),
      decoration: BoxDecoration(
        color: t.canvas,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (isAvailable && !state.isLaunching)
                    ? () => _handleCtaLaunch(controller, product)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isAvailable ? t.ctaSurface : t.surfaceElevated,
                  foregroundColor: isAvailable ? t.ctaText : t.textMuted,
                  disabledBackgroundColor: t.surfaceElevated,
                  disabledForegroundColor: t.textMuted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ShopTheme.radiusMd),
                  ),
                ),
                child: state.isLaunching
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(t.ctaText),
                        ),
                      )
                    : Text(
                        ctaLabel,
                        style: t.ctaButtonText.copyWith(
                          color: isAvailable ? t.ctaText : t.textMuted,
                        ),
                      ),
              ),
            ),
            if (disclosureText != null) ...[
              const SizedBox(height: 6),
              Text(
                disclosureText,
                style: ShopTheme.fontManrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: t.textMuted,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

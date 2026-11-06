import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/shop_collection.dart';
import '../controllers/shop_landing_controller.dart';
import '../controllers/shop_landing_state.dart';
import '../localization/shop_translations.dart';
import '../providers/shop_landing_providers.dart';
import '../theme/shop_theme.dart';
import '../widgets/shop_category_tabs.dart';
import '../widgets/shop_editorial_hero.dart';
import '../widgets/shop_editorial_strip.dart';
import '../widgets/shop_header.dart';
import '../widgets/shop_product_card.dart';
import '../widgets/shop_search_bar.dart';
import '../widgets/shop_state_views.dart';

/// Full native Flutter implementation of the Saman Shop Landing screen.
///
/// Implements the verified boutique aesthetic:
/// - Dark slate studio canvas (#0C0D0E) with #16171B surfaces.
/// - Minimalist sticky boutique header.
/// - Charcoal instant search pill with clear button.
/// - Asymmetrical editorial hero with smooth scroll-to-catalog affordance.
/// - Horizontal category text tabs with 1.5px solid underline indicator.
/// - Curated 2-column product grid with 4:5 image ratio and wishlist bookmarking.
/// - Mid-catalog embedded editorial collections acting as active catalog filters.
/// - Epoch-guarded cursor pagination and resilient error recovery.
class ShopLandingScreen extends ConsumerStatefulWidget {
  const ShopLandingScreen({super.key});

  @override
  ConsumerState<ShopLandingScreen> createState() => _ShopLandingScreenState();
}

class _ShopLandingScreenState extends ConsumerState<ShopLandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _catalogSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger load-more when 200px before scroll bottom
    if (currentScroll >= maxScroll - 200) {
      ref.read(shopLandingControllerProvider.notifier).loadMore();
    }
  }

  void _scrollToCatalog() {
    final context = _catalogSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else if (_scrollController.hasClients) {
      _scrollController.animateTo(
        260.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopLandingControllerProvider);
    final controller = ref.read(shopLandingControllerProvider.notifier);

    return Scaffold(
      backgroundColor: ShopTheme.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top boutique header
            const ShopHeader(),

            // Scrollable catalog stream
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  controller.resetFilters();
                },
                color: ShopTheme.emerald,
                backgroundColor: ShopTheme.surfaceCard,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // Search Bar
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ShopTheme.paddingPage,
                          vertical: 6.0,
                        ),
                        child: ShopSearchBar(
                          initialQuery: state.query.query,
                          onQueryChanged: controller.onSearchQueryChanged,
                          onClear: controller.clearSearchQuery,
                        ),
                      ),
                    ),

                    // Asymmetrical Editorial Hero Banner
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          ShopTheme.paddingPage,
                          8.0,
                          ShopTheme.paddingPage,
                          14.0,
                        ),
                        child: ShopEditorialHero(
                          onExploreTap: _scrollToCatalog,
                        ),
                      ),
                    ),

                    // Category Text Tabs
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ShopTheme.paddingPage,
                        ),
                        child: ShopCategoryTabs(
                          categories: state.categories,
                          selectedCategoryId: state.query.categoryId,
                          onCategorySelected: controller.onCategorySelected,
                        ),
                      ),
                    ),

                    // Section Header: "TUYỂN CHỌN" & Count
                    SliverToBoxAdapter(
                      key: _catalogSectionKey,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          ShopTheme.paddingPage,
                          18.0,
                          ShopTheme.paddingPage,
                          12.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  ShopTranslations.of(context, 'curated_header'),
                                  style: ShopTheme.sectionHeaderCaps,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _buildItemCountLabel(context, state),
                                    style: ShopTheme.sectionCount,
                                    textAlign: TextAlign.end,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (state.activeCollection != null) ...[
                              const SizedBox(height: 8),
                              _ActiveFilterBadge(
                                label: ShopTranslations.of(
                                        context, 'active_collection_filter')
                                    .replaceAll('{title}',
                                        state.activeCollection!.title),
                                onClear: () =>
                                    controller.onCollectionSelected(null),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Main Catalog View based on State
                    ..._buildCatalogSlivers(context, state, controller),

                    // Safe Bottom Inset Padding
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 32),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildItemCountLabel(BuildContext context, ShopLandingState state) {
    if (state.status == ShopCatalogStatus.initialLoading) {
      return '';
    }
    final count = state.products.length;
    final format = count <= 4
        ? ShopTranslations.of(context, 'featured_products_count')
        : ShopTranslations.of(context, 'products_count');
    return format.replaceAll('{count}', '$count');
  }

  List<Widget> _buildCatalogSlivers(
    BuildContext context,
    ShopLandingState state,
    ShopLandingController controller,
  ) {
    switch (state.status) {
      case ShopCatalogStatus.initialLoading:
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ShopTheme.paddingPage),
              child: ShopSkeletonLoadingView(),
            ),
          ),
        ];

      case ShopCatalogStatus.firstPageError:
        return [
          SliverToBoxAdapter(
            child: ShopFirstPageErrorView(
              onRetry: controller.retryFirstPage,
              errorMessage: state.error?.message,
            ),
          ),
        ];

      case ShopCatalogStatus.emptyCatalog:
        return const [
          SliverToBoxAdapter(
            child: ShopEmptyCatalogView(),
          ),
        ];

      case ShopCatalogStatus.noSearchResults:
        return [
          SliverToBoxAdapter(
            child: ShopNoResultsView(
              onResetFilters: controller.resetFilters,
            ),
          ),
        ];

      case ShopCatalogStatus.loaded:
      case ShopCatalogStatus.loadingMore:
      case ShopCatalogStatus.loadMoreError:
        return _buildProductStreamWithEditorial(context, state, controller);
    }
  }

  List<Widget> _buildProductStreamWithEditorial(
    BuildContext context,
    ShopLandingState state,
    ShopLandingController controller,
  ) {
    final products = state.products;
    final collections = state.collections;
    final slivers = <Widget>[];

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final cardAspectRatio =
        textScale > 1.4 ? 0.48 : (textScale > 1.1 ? 0.54 : 0.58);

    // If we have more than 4 products and available collections, embed the
    // curated collection strip between the 4th and 5th products.
    final splitIndex = products.length > 4 ? 4 : products.length;
    final firstBatch = products.take(splitIndex).toList();
    final secondBatch = products.skip(splitIndex).toList();

    // 1. First batch of products
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: ShopTheme.paddingPage),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 20,
            childAspectRatio: cardAspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => ShopProductCard(product: firstBatch[index]),
            childCount: firstBatch.length,
          ),
        ),
      ),
    );

    // 2. Editorial collection strip if collections exist
    if (collections.isNotEmpty) {
      final featuredCollection = _resolveFeaturedCollection(state);
      if (featuredCollection != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ShopTheme.paddingPage,
                vertical: 16.0,
              ),
              child: ShopEditorialStrip(
                collection: featuredCollection,
                isSelected:
                    state.query.collectionId == featuredCollection.id,
                onTap: () =>
                    controller.onCollectionSelected(featuredCollection.id),
              ),
            ),
          ),
        );
      }
    }

    // 3. Second batch of products (if any)
    if (secondBatch.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: ShopTheme.paddingPage),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 20,
              childAspectRatio: cardAspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ShopProductCard(product: secondBatch[index]),
              childCount: secondBatch.length,
            ),
          ),
        ),
      );
    }

    // 4. Load-more pagination footer
    slivers.add(
      SliverToBoxAdapter(
        child: ShopLoadMoreFooter(
          isLoadingMore: state.status == ShopCatalogStatus.loadingMore,
          hasError: state.status == ShopCatalogStatus.loadMoreError,
          onRetry: controller.retryLoadMore,
        ),
      ),
    );

    return slivers;
  }

  ShopCollection? _resolveFeaturedCollection(ShopLandingState state) {
    if (state.collections.isEmpty) return null;
    // If active collection is set, show that one
    if (state.activeCollection != null) {
      return state.activeCollection;
    }
    // Otherwise show the first collection ("Bắt đầu tập tại nhà")
    return state.collections.first;
  }
}

class _ActiveFilterBadge extends StatelessWidget {
  const _ActiveFilterBadge({
    required this.label,
    required this.onClear,
  });

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ShopTheme.surfaceCard,
        borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
        border: Border.all(color: ShopTheme.emerald.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: ShopTheme.emerald,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onClear,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: ShopTheme.emerald,
            ),
          ),
        ],
      ),
    );
  }
}

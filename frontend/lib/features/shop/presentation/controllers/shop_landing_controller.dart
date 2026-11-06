import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/failures/shop_failure.dart';
import '../../domain/repositories/shop_repository.dart';
import 'shop_landing_state.dart';

/// StateNotifier controlling catalog exploration, instant debounced search,
/// category/collection filtering, and cursor pagination with epoch guarding.
class ShopLandingController extends StateNotifier<ShopLandingState> {
  ShopLandingController({
    required ShopRepository repository,
    Duration debounceDuration = const Duration(milliseconds: 300),
  })  : _repository = repository,
        _debounceDuration = debounceDuration,
        super(ShopLandingState.initial()) {
    _init();
  }

  final ShopRepository _repository;
  final Duration _debounceDuration;

  Timer? _debounceTimer;
  int _epoch = 0;
  bool _isDisposed = false;

  void _init() {
    loadMetadata();
    _fetchFirstPage(_epoch);
  }

  /// Loads category and collection metadata for filter headers and strips.
  Future<void> loadMetadata() async {
    state = state.copyWith(isMetadataLoading: true, clearMetadataError: true);
    try {
      final categories = await _repository.getCategories();
      final collections = await _repository.getCollections();
      if (!_isDisposed) {
        state = state.copyWith(
          categories: categories,
          collections: collections,
          isMetadataLoading: false,
        );
      }
    } catch (e) {
      if (!_isDisposed) {
        final failure = e is ShopFailure
            ? e
            : const ShopCatalogLoadFailure('Không thể tải thông tin danh mục');
        state = state.copyWith(
          isMetadataLoading: false,
          metadataError: failure,
        );
      }
    }
  }

  /// Retries metadata loading if previously failed.
  Future<void> retryMetadata() => loadMetadata();

  /// Triggered whenever search input changes. Debounces 300ms before querying.
  void onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    final normalized = trimmed.isEmpty ? null : trimmed;

    if (state.query.query == normalized) return;

    _debounceTimer = Timer(_debounceDuration, () {
      if (_isDisposed) return;
      _epoch++;
      final currentEpoch = _epoch;
      state = state.copyWith(
        query: state.query.copyWith(
          query: normalized,
          cursor: null,
        ),
      );
      _fetchFirstPage(currentEpoch);
    });
  }

  /// Instantly clears the search query without debounce delay.
  void clearSearchQuery() {
    _debounceTimer?.cancel();
    if (state.query.query == null) return;

    _epoch++;
    final currentEpoch = _epoch;
    state = state.copyWith(
      query: state.query.copyWith(
        query: null,
        cursor: null,
      ),
    );
    _fetchFirstPage(currentEpoch);
  }

  /// Switches active category tab. Pass `null` for "Tất cả" (All).
  void onCategorySelected(String? categoryId) {
    _debounceTimer?.cancel();
    if (state.query.categoryId == categoryId) return;

    _epoch++;
    final currentEpoch = _epoch;
    state = state.copyWith(
      query: state.query.copyWith(
        categoryId: categoryId,
        cursor: null,
      ),
    );
    _fetchFirstPage(currentEpoch);
  }

  /// Toggles or selects a collection filter. Tapping an active collection deselects it.
  void onCollectionSelected(String? collectionId) {
    _debounceTimer?.cancel();
    final targetId =
        (state.query.collectionId == collectionId) ? null : collectionId;

    _epoch++;
    final currentEpoch = _epoch;
    state = state.copyWith(
      query: state.query.copyWith(
        collectionId: targetId,
        cursor: null,
      ),
    );
    _fetchFirstPage(currentEpoch);
  }

  /// Resets all filters (query, category, and collection) back to initial catalog state.
  void resetFilters() {
    _debounceTimer?.cancel();
    _epoch++;
    final currentEpoch = _epoch;
    state = state.copyWith(
      query: state.query.resetAll(),
    );
    _fetchFirstPage(currentEpoch);
  }

  /// Fetches the first page of products matching current query and filters.
  Future<void> _fetchFirstPage(int requestEpoch) async {
    state = state.copyWith(
      status: ShopCatalogStatus.initialLoading,
      clearError: true,
    );

    try {
      final page = await _repository.getProducts(state.query.toFirstPage());

      // Discard stale response if filter changed or controller disposed
      if (_isDisposed || requestEpoch != _epoch) return;

      if (page.items.isEmpty) {
        final hasActiveFilter = state.query.query != null ||
            state.query.categoryId != null ||
            state.query.collectionId != null;

        state = state.copyWith(
          status: hasActiveFilter
              ? ShopCatalogStatus.noSearchResults
              : ShopCatalogStatus.emptyCatalog,
          products: const [],
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          hasMore: page.hasMore,
        );
      } else {
        state = state.copyWith(
          status: ShopCatalogStatus.loaded,
          products: page.items,
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          hasMore: page.hasMore,
        );
      }
    } catch (e) {
      if (_isDisposed || requestEpoch != _epoch) return;

      final failure = e is ShopFailure
          ? e
          : const ShopCatalogLoadFailure('Lỗi tải danh mục sản phẩm');

      state = state.copyWith(
        status: ShopCatalogStatus.firstPageError,
        error: failure,
      );
    }
  }

  /// Retries first page query after an initial error.
  Future<void> retryFirstPage() {
    _debounceTimer?.cancel();
    _epoch++;
    return _fetchFirstPage(_epoch);
  }

  /// Loads next cursor page with duplicate request prevention and epoch checking.
  Future<void> loadMore() async {
    // Guard: Prevent duplicate load-more while already loading or during first page fetch
    if (state.status == ShopCatalogStatus.loadingMore ||
        state.status == ShopCatalogStatus.initialLoading) {
      return;
    }

    if (!state.hasMore || state.nextCursor == null) return;

    final requestEpoch = _epoch;
    state = state.copyWith(
      status: ShopCatalogStatus.loadingMore,
      clearError: true,
    );

    try {
      final nextPageQuery = state.query.copyWith(cursor: state.nextCursor);
      final page = await _repository.getProducts(nextPageQuery);

      // Discard if filter changed while request was in-flight
      if (_isDisposed || requestEpoch != _epoch) return;

      state = state.copyWith(
        status: ShopCatalogStatus.loaded,
        products: [...state.products, ...page.items],
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        hasMore: page.hasMore,
      );
    } catch (e) {
      if (_isDisposed || requestEpoch != _epoch) return;

      final failure = e is ShopFailure
          ? e
          : const ShopCatalogLoadFailure('Lỗi tải thêm sản phẩm');

      // Preserve existing products on load more error, update status for footer retry
      state = state.copyWith(
        status: ShopCatalogStatus.loadMoreError,
        error: failure,
      );
    }
  }

  /// Retries the failed load-more page using the retained nextCursor.
  Future<void> retryLoadMore() {
    if (state.status != ShopCatalogStatus.loadMoreError) return Future.value();
    return loadMore();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}

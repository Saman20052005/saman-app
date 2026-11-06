import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/failures/shop_failure.dart';
import '../../domain/repositories/shop_repository.dart';
import '../../domain/repositories/shop_wishlist_repository.dart';
import 'shop_saved_state.dart';

/// Controller coordinating saved wishlist items, batch loading from catalog,
/// and reactive updates.
class ShopSavedController extends StateNotifier<ShopSavedState> {
  ShopSavedController({
    required ShopRepository repository,
    required ShopWishlistRepository wishlistRepository,
  })  : _repository = repository,
        _wishlistRepository = wishlistRepository,
        super(const ShopSavedState()) {
    _init();
  }

  final ShopRepository _repository;
  final ShopWishlistRepository _wishlistRepository;
  StreamSubscription<List<String>>? _wishlistSub;

  void _init() {
    _subscribeWishlist();
    loadSavedItems();
  }

  void _subscribeWishlist() {
    _wishlistSub?.cancel();
    _wishlistSub = _wishlistRepository.watchSavedProductIds().listen(
      (savedIds) {
        if (!mounted) return;
        _syncWithSavedIds(savedIds);
      },
      onError: (_) {},
    );
  }

  /// Loads all saved items from storage and populates catalog details.
  Future<void> loadSavedItems() async {
    state = state.copyWith(
      status: ShopSavedStatus.initialLoading,
      clearError: true,
    );

    try {
      final savedIds = await _wishlistRepository.getSavedProductIds();
      await _syncWithSavedIds(savedIds);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: ShopSavedStatus.error,
        errorMessage: e is ShopFailure
            ? e.message
            : 'Không thể tải danh sách mục đã lưu',
      );
    }
  }

  Future<void> _syncWithSavedIds(List<String> savedIds) async {
    if (savedIds.isEmpty) {
      if (mounted) {
        state = state.copyWith(
          status: ShopSavedStatus.loaded,
          items: const [],
        );
      }
      return;
    }

    try {
      // Batch fetch products corresponding to saved IDs
      final products = await _repository.getProductsByIds(savedIds);

      final records = <SavedItemRecord>[];
      for (int i = 0; i < savedIds.length; i++) {
        final id = savedIds[i];
        final product = (i < products.length) ? products[i] : null;
        records.add(SavedItemRecord(productId: id, product: product));
      }

      if (!mounted) return;
      state = state.copyWith(
        status: ShopSavedStatus.loaded,
        items: records,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: ShopSavedStatus.error,
        errorMessage: e is ShopFailure ? e.message : 'Lỗi đồng bộ danh mục',
      );
    }
  }

  /// Removes an item from the wishlist with optimistic update and rollback on failure.
  Future<void> unsave(String productId) async {
    final previousItems = state.items;

    // Optimistic UI update
    final updatedItems =
        previousItems.where((item) => item.productId != productId).toList();
    state = state.copyWith(items: updatedItems);

    try {
      await _wishlistRepository.remove(productId);
    } catch (e) {
      // Rollback on storage failure
      if (mounted) {
        state = state.copyWith(items: previousItems);
      }
    }
  }

  /// Retries loading saved items.
  void retry() {
    loadSavedItems();
  }

  @override
  void dispose() {
    _wishlistSub?.cancel();
    super.dispose();
  }
}

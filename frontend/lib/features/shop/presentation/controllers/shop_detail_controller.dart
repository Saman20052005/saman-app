import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/shop_product.dart';
import '../../domain/failures/shop_failure.dart';
import '../../domain/repositories/shop_repository.dart';
import '../../domain/repositories/shop_wishlist_repository.dart';
import '../../domain/services/shop_launcher_contract.dart';
import 'shop_detail_state.dart';

/// Controller coordinating data fetching, wishlist bookmarking, and external/demo CTA dispatch
/// for the Product Detail screen.
class ShopDetailController extends StateNotifier<ShopDetailState> {
  ShopDetailController({
    required ShopRepository repository,
    required ShopWishlistRepository wishlistRepository,
    required ShopLauncherContract launcher,
    required String? productId,
  })  : _repository = repository,
        _wishlistRepository = wishlistRepository,
        _launcher = launcher,
        _productId = productId,
        super(const ShopDetailState()) {
    _init();
  }

  final ShopRepository _repository;
  final ShopWishlistRepository _wishlistRepository;
  final ShopLauncherContract _launcher;
  final String? _productId;
  StreamSubscription<List<String>>? _wishlistSub;

  void _init() {
    _subscribeWishlist();
    loadProduct(_productId);
  }

  void _subscribeWishlist() {
    _wishlistSub?.cancel();
    _wishlistSub = _wishlistRepository.watchSavedProductIds().listen(
      (savedIds) {
        if (!mounted || _productId == null) return;
        final currentlySaved = savedIds.contains(_productId);
        if (state.isSaved != currentlySaved) {
          state = state.copyWith(isSaved: currentlySaved);
        }
      },
      onError: (_) {
        // Stream errors should not crash the UI
      },
    );
  }

  /// Loads the product details by ID using the central `ShopRepository`.
  Future<void> loadProduct(String? id) async {
    if (id == null || id.trim().isEmpty) {
      state = state.copyWith(
        status: ShopDetailStatus.notFound,
        clearProduct: true,
      );
      return;
    }

    state = state.copyWith(
      status: ShopDetailStatus.initialLoading,
      clearError: true,
    );

    try {
      final product = await _repository.getProductById(id);
      final isSaved = await _wishlistRepository.isSaved(id);

      if (!mounted) return;
      state = state.copyWith(
        status: ShopDetailStatus.loaded,
        product: product,
        isSaved: isSaved,
      );
    } on ShopNotFoundFailure {
      if (!mounted) return;
      state = state.copyWith(
        status: ShopDetailStatus.notFound,
        clearProduct: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: ShopDetailStatus.error,
        errorMessage: e is ShopFailure ? e.message : 'Lỗi tải chi tiết sản phẩm',
      );
    }
  }

  /// Retries loading the current product.
  void retry() {
    loadProduct(_productId);
  }

  /// Toggles wishlist status with optimistic state update and rollback on failure.
  Future<void> toggleWishlist() async {
    final product = state.product;
    if (product == null) return;

    final previousSaved = state.isSaved;
    final optimisticSaved = !previousSaved;

    // Optimistic UI update
    state = state.copyWith(isSaved: optimisticSaved);

    try {
      final newSaved = await _wishlistRepository.toggle(product.id);
      if (mounted) {
        state = state.copyWith(isSaved: newSaved);
      }
    } catch (e) {
      // Rollback on storage failure
      if (mounted) {
        state = state.copyWith(isSaved: previousSaved);
      }
    }
  }

  /// Dispatches the CTA via the injected `ShopLauncherContract`.
  Future<LauncherResult?> launchCta() async {
    final product = state.product;
    if (product == null || state.isLaunching) return null;

    // Unavailable / discontinued products cannot be dispatched
    if (product.availability != ProductAvailability.available) {
      return null;
    }

    state = state.copyWith(
      isLaunching: true,
      clearLauncherError: true,
    );

    try {
      final result = await _launcher.launch(product);
      if (mounted) {
        state = state.copyWith(isLaunching: false);
      }
      return result;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isLaunching: false,
          launcherErrorMessage:
              e is ShopFailure ? e.message : 'Không thể thực hiện kết nối',
        );
      }
      return LauncherResult.failed(
        product.shopeeUrl,
        e is ShopFailure ? e.message : 'Lỗi kết nối',
      );
    }
  }

  @override
  void dispose() {
    _wishlistSub?.cancel();
    super.dispose();
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/shop_landing_controller.dart';
import '../controllers/shop_landing_state.dart';
import 'shop_providers.dart';

/// Provider for the Shop Landing controller and state machine.
final shopLandingControllerProvider =
    StateNotifierProvider<ShopLandingController, ShopLandingState>((ref) {
  final repository = ref.watch(shopRepositoryProvider);
  return ShopLandingController(repository: repository);
});

/// Reactive provider for the total count of saved wishlist products.
final savedProductsCountProvider = Provider<int>((ref) {
  final savedIdsAsync = ref.watch(savedProductIdsStreamProvider);
  return savedIdsAsync.value?.length ?? 0;
});

/// Family provider checking if a specific product ID is bookmarked in wishlist.
final isProductSavedProvider = Provider.family<bool, String>((ref, productId) {
  final savedIdsAsync = ref.watch(savedProductIdsStreamProvider);
  final ids = savedIdsAsync.value ?? const [];
  return ids.contains(productId);
});


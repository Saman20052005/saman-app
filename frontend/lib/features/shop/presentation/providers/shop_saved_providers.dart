import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/shop_saved_controller.dart';
import '../controllers/shop_saved_state.dart';
import 'shop_providers.dart';

/// Provider for `ShopSavedController` managing the user's wishlist screen.
final shopSavedControllerProvider =
    StateNotifierProvider.autoDispose<ShopSavedController, ShopSavedState>(
  (ref) {
    final repository = ref.watch(shopRepositoryProvider);
    final wishlistRepository = ref.watch(shopWishlistRepositoryProvider);

    return ShopSavedController(
      repository: repository,
      wishlistRepository: wishlistRepository,
    );
  },
);

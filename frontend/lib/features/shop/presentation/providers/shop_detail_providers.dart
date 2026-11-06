import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/shop_detail_controller.dart';
import '../controllers/shop_detail_state.dart';
import 'shop_providers.dart';

/// Scoped StateNotifierProvider family creating a dedicated `ShopDetailController`
/// per `productId`.
final shopDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ShopDetailController, ShopDetailState, String?>(
  (ref, productId) {
    final repository = ref.watch(shopRepositoryProvider);
    final wishlistRepository = ref.watch(shopWishlistRepositoryProvider);
    final launcher = ref.watch(shopLauncherProvider);

    return ShopDetailController(
      repository: repository,
      wishlistRepository: wishlistRepository,
      launcher: launcher,
      productId: productId,
    );
  },
);

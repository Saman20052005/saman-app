/// Contract for local wishlist persistence.
abstract interface class ShopWishlistRepository {
  /// Retrieves ordered list of saved product IDs (newest saved at index 0).
  Future<List<String>> getSavedProductIds();

  /// Checks whether a specific product ID is currently saved.
  Future<bool> isSaved(String productId);

  /// Saves a product ID at the head of the wishlist (idempotent).
  Future<void> save(String productId);

  /// Removes a product ID from the wishlist (idempotent).
  Future<void> remove(String productId);

  /// Toggles saved state. Returns `true` if saved, `false` if removed.
  Future<bool> toggle(String productId);

  /// Reactive stream broadcasting the latest ordered list of saved product IDs.
  Stream<List<String>> watchSavedProductIds();
}


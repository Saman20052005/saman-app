import 'package:flutter/foundation.dart';
import '../../domain/entities/shop_product.dart';

/// Status of the Saved Items screen.
enum ShopSavedStatus {
  initialLoading,
  loaded,
  error,
}

/// Record representing a saved item in the user's wishlist.
///
/// If a product has been unlisted or removed from the catalog, [product] will be
/// null while [isMissing] is true. The record and its [productId] are strictly preserved
/// in storage unless the user explicitly removes it.
@immutable
class SavedItemRecord {
  const SavedItemRecord({
    required this.productId,
    this.product,
  });

  final String productId;
  final ShopProduct? product;

  bool get isMissing => product == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedItemRecord &&
          runtimeType == other.runtimeType &&
          productId == other.productId &&
          product == other.product;

  @override
  int get hashCode => productId.hashCode ^ product.hashCode;
}

/// State representation for `ShopSavedScreen`.
@immutable
class ShopSavedState {
  const ShopSavedState({
    this.status = ShopSavedStatus.initialLoading,
    this.items = const [],
    this.errorMessage,
  });

  final ShopSavedStatus status;
  final List<SavedItemRecord> items;
  final String? errorMessage;

  bool get isEmpty => items.isEmpty;

  ShopSavedState copyWith({
    ShopSavedStatus? status,
    List<SavedItemRecord>? items,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ShopSavedState(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopSavedState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          listEquals(items, other.items) &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      status.hashCode ^ items.hashCode ^ errorMessage.hashCode;
}

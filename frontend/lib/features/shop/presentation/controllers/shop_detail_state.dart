import 'package:flutter/foundation.dart';
import '../../domain/entities/shop_product.dart';

/// Status of the Product Detail view.
enum ShopDetailStatus {
  initialLoading,
  loaded,
  notFound,
  error,
}

/// State representation for `ShopDetailScreen`.
@immutable
class ShopDetailState {
  const ShopDetailState({
    this.status = ShopDetailStatus.initialLoading,
    this.product,
    this.isSaved = false,
    this.isLaunching = false,
    this.errorMessage,
    this.launcherErrorMessage,
  });

  final ShopDetailStatus status;
  final ShopProduct? product;
  final bool isSaved;
  final bool isLaunching;
  final String? errorMessage;
  final String? launcherErrorMessage;

  ShopDetailState copyWith({
    ShopDetailStatus? status,
    ShopProduct? product,
    bool? isSaved,
    bool? isLaunching,
    String? errorMessage,
    String? launcherErrorMessage,
    bool clearProduct = false,
    bool clearError = false,
    bool clearLauncherError = false,
  }) {
    return ShopDetailState(
      status: status ?? this.status,
      product: clearProduct ? null : (product ?? this.product),
      isSaved: isSaved ?? this.isSaved,
      isLaunching: isLaunching ?? this.isLaunching,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      launcherErrorMessage: clearLauncherError
          ? null
          : (launcherErrorMessage ?? this.launcherErrorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopDetailState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          product == other.product &&
          isSaved == other.isSaved &&
          isLaunching == other.isLaunching &&
          errorMessage == other.errorMessage &&
          launcherErrorMessage == other.launcherErrorMessage;

  @override
  int get hashCode =>
      status.hashCode ^
      product.hashCode ^
      isSaved.hashCode ^
      isLaunching.hashCode ^
      errorMessage.hashCode ^
      launcherErrorMessage.hashCode;
}

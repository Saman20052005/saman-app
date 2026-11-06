import 'package:equatable/equatable.dart';

/// Sealed hierarchy of typed business failures in Saman Shop.
sealed class ShopFailure extends Equatable implements Exception {
  final String message;
  final String? code;

  const ShopFailure(this.message, [this.code]);

  @override
  List<Object?> get props => [message, code];

  @override
  String toString() =>
      '$runtimeType: $message${code != null ? ' ($code)' : ''}';
}

/// Occurs when an requested product ID does not exist in catalog.
class ShopNotFoundFailure extends ShopFailure {
  final String productId;

  const ShopNotFoundFailure(this.productId,
      [String message = 'Sản phẩm không tồn tại trong danh mục'])
      : super(message, 'NOT_FOUND');

  @override
  List<Object?> get props => [message, code, productId];
}

/// Occurs when a pagination cursor is malformed, corrupted, or mismatched with active filters.
class ShopInvalidCursorFailure extends ShopFailure {
  final String cursor;

  const ShopInvalidCursorFailure(this.cursor,
      [String message =
          'Cursor phân trang không hợp lệ hoặc không khớp bộ lọc'])
      : super(message, 'INVALID_CURSOR');

  @override
  List<Object?> get props => [message, code, cursor];
}

/// Occurs when query arguments violate business validation.
class ShopInvalidQueryFailure extends ShopFailure {
  const ShopInvalidQueryFailure(String message)
      : super(message, 'INVALID_QUERY');
}

/// Occurs when loading catalog data fails due to network, format, or server error.
class ShopCatalogLoadFailure extends ShopFailure {
  const ShopCatalogLoadFailure(
      [String message = 'Không thể tải danh mục sản phẩm Saman Shop'])
      : super(message, 'CATALOG_LOAD_ERROR');
}

/// Occurs when local wishlist read/write fails on storage layer.
class ShopStorageFailure extends ShopFailure {
  final Object? cause;

  const ShopStorageFailure(
      [String message = 'Lỗi lưu trữ danh sách yêu thích', this.cause])
      : super(message, 'STORAGE_ERROR');

  @override
  List<Object?> get props => [message, code, cause];
}

/// Occurs when external URL launch fails.
class ShopLauncherFailure extends ShopFailure {
  final String? url;

  const ShopLauncherFailure(this.url,
      [String message = 'Không thể khởi động ứng dụng mua sắm'])
      : super(message, 'LAUNCHER_ERROR');

  @override
  List<Object?> get props => [message, code, url];
}

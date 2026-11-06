import '../../domain/entities/product_query.dart';
import '../../domain/entities/shop_category.dart';
import '../../domain/entities/shop_collection.dart';
import '../../domain/entities/shop_product.dart';
import '../../domain/failures/shop_failure.dart';

/// Catalog status for the Shop Landing page state machine.
enum ShopCatalogStatus {
  initialLoading,
  loaded,
  emptyCatalog,
  noSearchResults,
  firstPageError,
  loadingMore,
  loadMoreError,
}

/// Immutable state model for the Saman Shop Landing catalog.
class ShopLandingState {
  const ShopLandingState({
    required this.status,
    required this.products,
    required this.query,
    this.nextCursor,
    required this.hasMore,
    this.error,
    this.categories = const [],
    this.collections = const [],
    this.isMetadataLoading = false,
    this.metadataError,
  });

  final ShopCatalogStatus status;
  final List<ShopProduct> products;
  final ProductQuery query;
  final String? nextCursor;
  final bool hasMore;
  final ShopFailure? error;

  final List<ShopCategory> categories;
  final List<ShopCollection> collections;
  final bool isMetadataLoading;
  final ShopFailure? metadataError;

  /// Returns the currently filtered collection if query.collectionId is set.
  ShopCollection? get activeCollection {
    if (query.collectionId == null) return null;
    try {
      return collections.firstWhere((c) => c.id == query.collectionId);
    } catch (_) {
      return null;
    }
  }

  /// Initial state factory.
  factory ShopLandingState.initial() {
    return ShopLandingState(
      status: ShopCatalogStatus.initialLoading,
      products: const [],
      query: ProductQuery(),
      hasMore: false,
      isMetadataLoading: true,
    );
  }

  ShopLandingState copyWith({
    ShopCatalogStatus? status,
    List<ShopProduct>? products,
    ProductQuery? query,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? hasMore,
    ShopFailure? error,
    bool clearError = false,
    List<ShopCategory>? categories,
    List<ShopCollection>? collections,
    bool? isMetadataLoading,
    ShopFailure? metadataError,
    bool clearMetadataError = false,
  }) {
    return ShopLandingState(
      status: status ?? this.status,
      products: products ?? this.products,
      query: query ?? this.query,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      categories: categories ?? this.categories,
      collections: collections ?? this.collections,
      isMetadataLoading: isMetadataLoading ?? this.isMetadataLoading,
      metadataError: clearMetadataError
          ? null
          : (metadataError ?? this.metadataError),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopLandingState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          query == other.query &&
          nextCursor == other.nextCursor &&
          hasMore == other.hasMore &&
          error == other.error &&
          isMetadataLoading == other.isMetadataLoading &&
          metadataError == other.metadataError &&
          products.length == other.products.length &&
          categories.length == other.categories.length &&
          collections.length == other.collections.length;

  @override
  int get hashCode => Object.hash(
        status,
        query,
        nextCursor,
        hasMore,
        error,
        isMetadataLoading,
        metadataError,
        products.length,
      );
}

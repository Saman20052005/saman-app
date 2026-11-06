import '../entities/shop_category.dart';
import '../entities/shop_collection.dart';
import '../entities/shop_product.dart';
import '../entities/product_query.dart';
import '../entities/product_page.dart';

/// Contract for catalog querying and product detail retrieval.
abstract interface class ShopRepository {
  /// Retrieves all available product categories.
  Future<List<ShopCategory>> getCategories();

  /// Retrieves all curated collections.
  Future<List<ShopCollection>> getCollections();

  /// Retrieves a paginated list of products matching the provided query.
  Future<ProductPage> getProducts(ProductQuery query);

  /// Retrieves single product detail by ID. Throws `ShopNotFoundFailure` if not found.
  Future<ShopProduct> getProductById(String id);

  /// Retrieves products for a list of IDs preserving the exact requested order.
  /// If an ID is missing or discontinued from the catalog, its index in the result
  /// will be `null` so the caller (e.g. Saved screen) can render a graceful placeholder.
  Future<List<ShopProduct?>> getProductsByIds(List<String> ids);
}


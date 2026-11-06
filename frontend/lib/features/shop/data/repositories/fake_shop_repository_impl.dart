import 'dart:convert';
import '../../domain/entities/product_page.dart';
import '../../domain/entities/product_query.dart';
import '../../domain/entities/shop_category.dart';
import '../../domain/entities/shop_collection.dart';
import '../../domain/entities/shop_product.dart';
import '../../domain/failures/shop_failure.dart';
import '../../domain/repositories/shop_repository.dart';
import '../datasources/fake_shop_local_data_source.dart';

enum FakeShopScenario {
  normal,
  empty,
  firstPageError,
  nextPageError,
  slow,
}

/// Fake implementation of `ShopRepository` with deterministic test controls.
class FakeShopRepositoryImpl implements ShopRepository {
  List<ShopProduct> _products;
  final List<ShopCategory> _categories;
  final List<ShopCollection> _collections;

  Duration defaultDelay;
  FakeShopScenario scenario;

  FakeShopRepositoryImpl({
    List<ShopProduct>? products,
    List<ShopCategory>? categories,
    List<ShopCollection>? collections,
    this.defaultDelay = const Duration(milliseconds: 500),
    this.scenario = FakeShopScenario.normal,
  })  : _products =
            products ?? FakeShopLocalDataSource.generateDefaultProducts(),
        _categories = categories ?? FakeShopLocalDataSource.defaultCategories,
        _collections =
            collections ?? FakeShopLocalDataSource.defaultCollections;

  /// Allows dynamically updating the product catalog in tests.
  void setProducts(List<ShopProduct> newProducts) {
    _products = List.from(newProducts);
  }

  @override
  Future<List<ShopCategory>> getCategories() async {
    await _applyDelay();
    _checkErrorState(isFirstPage: true);
    return List.unmodifiable(_categories);
  }

  @override
  Future<List<ShopCollection>> getCollections() async {
    await _applyDelay();
    _checkErrorState(isFirstPage: true);
    return List.unmodifiable(_collections);
  }

  @override
  Future<ProductPage> getProducts(ProductQuery query) async {
    await _applyDelay();

    final isFirstPage = query.cursor == null;
    _checkErrorState(isFirstPage: isFirstPage);

    if (scenario == FakeShopScenario.empty) {
      return ProductPage.empty();
    }

    // 1. Filter dataset by query, category, subcategory, and collection (AND logic)
    final filtered = _products.where((product) {
      // Category filter (supports canonical IDs and legacy aliases)
      if (query.categoryId != null && query.categoryId!.isNotEmpty) {
        final normalizedCategory =
            ShopCategory.normalizeCategoryId(query.categoryId!);
        if (product.categoryId != normalizedCategory &&
            product.categoryId != query.categoryId) {
          return false;
        }
      }

      // Subcategory filter
      if (query.subcategoryId != null && query.subcategoryId!.isNotEmpty) {
        if (product.subcategoryId != query.subcategoryId) return false;
      }

      // Collection filter (supports legacy col_recovery alias)
      if (query.collectionId != null && query.collectionId!.isNotEmpty) {
        final isLegacyRecovery =
            query.collectionId == ShopCollection.colRecoveryDesk;
        final matchesCollection =
            product.collectionIds.contains(query.collectionId) ||
                (isLegacyRecovery &&
                    (product.collectionIds
                            .contains(ShopCollection.colGymBag) ||
                        product.categoryId == ShopCategory.catRecoveryLifestyle));
        if (!matchesCollection) return false;
      }

      // Normalized text query filter
      if (query.query != null && query.query!.trim().isNotEmpty) {
        final normalizedSearch = _normalizeVietnamese(query.query!.trim());
        final normalizedTitle = _normalizeVietnamese(product.title);
        final normalizedSub = _normalizeVietnamese(product.subtitle);
        final normalizedDesc = _normalizeVietnamese(product.description);

        final matches = normalizedTitle.contains(normalizedSearch) ||
            normalizedSub.contains(normalizedSearch) ||
            normalizedDesc.contains(normalizedSearch);

        if (!matches) return false;
      }

      return true;
    }).toList();

    // 2. Stable sort by curatedOrder, tie-break by ID
    filtered.sort((a, b) {
      final orderCmp = a.curatedOrder.compareTo(b.curatedOrder);
      if (orderCmp != 0) return orderCmp;
      return a.id.compareTo(b.id);
    });

    // 3. Resolve pagination offset from cursor
    final querySignature = _computeQuerySignature(query);
    int startIndex = 0;

    if (query.cursor != null && query.cursor!.isNotEmpty) {
      final parsed = _decodeCursor(query.cursor!);
      if (parsed == null || parsed.signature != querySignature) {
        throw ShopInvalidCursorFailure(query.cursor!);
      }
      startIndex = parsed.offset;
      if (startIndex < 0 || startIndex > filtered.length) {
        throw ShopInvalidCursorFailure(query.cursor!);
      }
    }

    // 4. Slice current page
    final endIndex = (startIndex + query.pageSize).clamp(0, filtered.length);
    final pageItems = filtered.sublist(startIndex, endIndex);

    // 5. Compute next cursor
    String? nextCursor;
    bool hasMore = false;

    if (endIndex < filtered.length) {
      nextCursor = _encodeCursor(_CursorToken(
        signature: querySignature,
        offset: endIndex,
      ));
      hasMore = true;
    }

    return ProductPage(
      items: pageItems,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  @override
  Future<ShopProduct> getProductById(String id) async {
    await _applyDelay();
    _checkErrorState(isFirstPage: true);

    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      throw ShopNotFoundFailure(id);
    }
  }

  @override
  Future<List<ShopProduct?>> getProductsByIds(List<String> ids) async {
    await _applyDelay();
    _checkErrorState(isFirstPage: true);

    final productMap = {for (final p in _products) p.id: p};
    // Preserves the requested ID order; missing ID gets null slot
    return ids.map((id) => productMap[id]).toList();
  }

  // ─── PRIVATE HELPERS ───────────────────────────────────────────────

  Future<void> _applyDelay() async {
    if (scenario == FakeShopScenario.slow) {
      await Future<void>.delayed(defaultDelay * 3);
    } else if (defaultDelay > Duration.zero) {
      await Future<void>.delayed(defaultDelay);
    }
  }

  void _checkErrorState({required bool isFirstPage}) {
    if (isFirstPage && scenario == FakeShopScenario.firstPageError) {
      throw const ShopCatalogLoadFailure('Mô phỏng lỗi nạp danh mục trang đầu');
    }
    if (!isFirstPage && scenario == FakeShopScenario.nextPageError) {
      throw const ShopCatalogLoadFailure('Mô phỏng lỗi nạp thêm trang kế tiếp');
    }
  }

  String _computeQuerySignature(ProductQuery q) {
    final base = '${q.query ?? ''}|${q.categoryId ?? ''}|${q.collectionId ?? ''}';
    if (q.subcategoryId != null && q.subcategoryId!.isNotEmpty) {
      return '$base|${q.subcategoryId}';
    }
    return base;
  }

  String _encodeCursor(_CursorToken token) {
    final raw = 'v1:${token.signature}:${token.offset}';
    return base64Url.encode(utf8.encode(raw));
  }

  _CursorToken? _decodeCursor(String cursor) {
    try {
      final decoded = utf8.decode(base64Url.decode(cursor));
      final parts = decoded.split(':');
      if (parts.length < 3 || parts[0] != 'v1') return null;
      final offset = int.tryParse(parts.last);
      if (offset == null) return null;
      final signature = parts.sublist(1, parts.length - 1).join(':');
      return _CursorToken(signature: signature, offset: offset);
    } catch (_) {
      return null;
    }
  }

  /// Normalizes Vietnamese string by lowering, trimming, and stripping accents & 'đ/Đ'.
  static String _normalizeVietnamese(String text) {
    var result = text.toLowerCase().trim();
    result = result.replaceAll('đ', 'd').replaceAll('Đ', 'd');

    const withDiacritics =
        'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ';
    const withoutDiacritics =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyy';

    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result;
  }
}

class _CursorToken {
  final String signature;
  final int offset;

  const _CursorToken({required this.signature, required this.offset});
}

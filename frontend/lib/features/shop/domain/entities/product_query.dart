import 'package:equatable/equatable.dart';

/// Query parameters for fetching and filtering products in the catalog.
class ProductQuery extends Equatable {
  static const Object _sentinel = Object();

  final String? query;
  final String? categoryId;
  final String? collectionId;
  final String? subcategoryId;
  final int pageSize;
  final String? cursor;

  ProductQuery({
    this.query,
    this.categoryId,
    this.collectionId,
    this.subcategoryId,
    this.pageSize = 20,
    this.cursor,
  }) {
    if (pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'pageSize phải là số nguyên dương lớn hơn 0.',
      );
    }
  }

  /// Copies query with optional replacement.
  /// Supports explicitly passing `null` to clear a parameter (e.g., reset category or cursor).
  ProductQuery copyWith({
    Object? query = _sentinel,
    Object? categoryId = _sentinel,
    Object? collectionId = _sentinel,
    Object? subcategoryId = _sentinel,
    int? pageSize,
    Object? cursor = _sentinel,
  }) {
    final resolvedPageSize = pageSize ?? this.pageSize;
    if (resolvedPageSize <= 0) {
      throw ArgumentError.value(
        resolvedPageSize,
        'pageSize',
        'pageSize phải là số nguyên dương lớn hơn 0.',
      );
    }

    return ProductQuery(
      query: identical(query, _sentinel) ? this.query : query as String?,
      categoryId: identical(categoryId, _sentinel)
          ? this.categoryId
          : categoryId as String?,
      collectionId: identical(collectionId, _sentinel)
          ? this.collectionId
          : collectionId as String?,
      subcategoryId: identical(subcategoryId, _sentinel)
          ? this.subcategoryId
          : subcategoryId as String?,
      pageSize: resolvedPageSize,
      cursor: identical(cursor, _sentinel) ? this.cursor : cursor as String?,
    );
  }

  /// Creates a query for the first page while keeping current active filters.
  ProductQuery toFirstPage() => copyWith(cursor: null);

  /// Resets all filters and cursor to pristine initial state.
  ProductQuery resetAll() => ProductQuery(pageSize: pageSize);

  @override
  List<Object?> get props =>
      [query, categoryId, collectionId, subcategoryId, pageSize, cursor];
}

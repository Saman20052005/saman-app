import 'package:equatable/equatable.dart';
import 'shop_product.dart';

/// Paginated page of products with cursor-based navigation.
class ProductPage extends Equatable {
  final List<ShopProduct> items;
  final String? nextCursor;
  final bool hasMore;

  ProductPage({
    required List<ShopProduct> items,
    this.nextCursor,
    bool? hasMore,
  })  : items = List.unmodifiable(items),
        hasMore = nextCursor != null && (hasMore ?? true);

  factory ProductPage.empty() => ProductPage(
        items: const [],
        nextCursor: null,
        hasMore: false,
      );

  @override
  List<Object?> get props => [items, nextCursor, hasMore];
}


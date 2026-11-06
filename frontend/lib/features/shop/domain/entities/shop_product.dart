import 'package:equatable/equatable.dart';
import 'content_provenance.dart';
import 'typed_attributes.dart';

export 'typed_attributes.dart';

enum ProductSourceType {
  internalBrand,
  affiliatePartner,
  merchantPartner,
  manualCurated,
}

enum ProductAvailability {
  available,
  unavailable,
  discontinued,
  unknown,
}

/// Represents an item in the Saman Shop catalog.
class ShopProduct extends Equatable {
  final String id;
  final String title;
  final String subtitle;
  final String categoryId;
  final List<String> collectionIds;
  final String? productType;
  final String? subcategoryId;
  final String? badge;
  final String description;
  final String editorialNote;
  final int? priceVnd;
  final DateTime? priceUpdatedAt;
  final String? sellerName;
  final ProductSourceType sourceType;
  final bool isDemo;
  final ContentProvenance contentProvenance;
  final ProductAvailability availability;
  final String heroImageUrl;
  final List<String> galleryImageUrls;
  final Map<String, String> specifications;
  final String? shopeeUrl;
  final int curatedOrder;

  // Typed Attributes for different product categories
  final EquipmentAttributes? equipmentAttributes;
  final ApparelAttributes? apparelAttributes;
  final FoodAttributes? foodAttributes;
  final SupplementAttributes? supplementAttributes;
  final LifestyleAttributes? lifestyleAttributes;

  ShopProduct({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.categoryId,
    List<String> collectionIds = const [],
    this.productType,
    this.subcategoryId,
    this.badge,
    required this.description,
    required this.editorialNote,
    this.priceVnd,
    this.priceUpdatedAt,
    this.sellerName,
    required this.sourceType,
    this.isDemo = false,
    required this.contentProvenance,
    required this.availability,
    required this.heroImageUrl,
    List<String> galleryImageUrls = const [],
    Map<String, String> specifications = const {},
    this.shopeeUrl,
    this.curatedOrder = 0,
    this.equipmentAttributes,
    this.apparelAttributes,
    this.foodAttributes,
    this.supplementAttributes,
    this.lifestyleAttributes,
  })  : collectionIds = List.unmodifiable(collectionIds),
        galleryImageUrls = List.unmodifiable(galleryImageUrls),
        specifications = Map.unmodifiable(specifications) {
    if (priceVnd != null && priceVnd! <= 0) {
      throw ArgumentError.value(
        priceVnd,
        'priceVnd',
        'Giá tham khảo VND phải là số nguyên dương lớn hơn 0; không có giá để null.',
      );
    }
  }

  bool get hasShopeeUrl => shopeeUrl != null && shopeeUrl!.trim().isNotEmpty;
  bool get isAvailable => availability == ProductAvailability.available;
  bool get hasTypedAttributes =>
      equipmentAttributes != null ||
      apparelAttributes != null ||
      foodAttributes != null ||
      supplementAttributes != null ||
      lifestyleAttributes != null;

  @override
  List<Object?> get props => [
        id,
        title,
        subtitle,
        categoryId,
        collectionIds,
        productType,
        subcategoryId,
        badge,
        description,
        editorialNote,
        priceVnd,
        priceUpdatedAt,
        sellerName,
        sourceType,
        isDemo,
        contentProvenance,
        availability,
        heroImageUrl,
        galleryImageUrls,
        specifications,
        shopeeUrl,
        curatedOrder,
        equipmentAttributes,
        apparelAttributes,
        foodAttributes,
        supplementAttributes,
        lifestyleAttributes,
      ];
}

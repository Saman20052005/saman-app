import 'package:equatable/equatable.dart';

/// Represents a curated editorial collection grouping products.
/// Product-collection relation is canonically stored on `ShopProduct.collectionIds`.
class ShopCollection extends Equatable {
  // 6 Curated Collection IDs
  static const String colHomeStarter = 'col_home_starter';
  static const String colGymBag = 'col_gym_bag';
  static const String colQuickBreakfast = 'col_quick_breakfast';
  static const String colPortableSnacks = 'col_portable_snacks';
  static const String colMealPrep = 'col_meal_prep';
  static const String colActiveWear = 'col_active_wear';

  // Legacy Collection ID (CP-00)
  static const String colRecoveryDesk = 'col_recovery_desk';

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String bannerImageUrl;
  final bool isFeatured;
  final int sortOrder;

  const ShopCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.bannerImageUrl,
    this.isFeatured = false,
    this.sortOrder = 0,
  });

  @override
  List<Object?> get props => [
        id,
        title,
        subtitle,
        description,
        bannerImageUrl,
        isFeatured,
        sortOrder,
      ];
}

import 'package:equatable/equatable.dart';

/// Represents a distinct product category within Saman Shop.
class ShopCategory extends Equatable {
  // 5 Canonical Category IDs
  static const String catGear = 'cat_gear';
  static const String catApparel = 'cat_apparel';
  static const String catFoodBeverage = 'cat_food_beverage';
  static const String catSupplements = 'cat_supplements';
  static const String catRecoveryLifestyle = 'cat_recovery_lifestyle';

  // Legacy Category ID Aliases (for backward compatibility)
  static const String catTrainingGear = 'cat_training_gear';
  static const String catRecoveryTools = 'cat_recovery_tools';
  static const String catMealPrepHydration = 'cat_meal_prep_hydration';

  final String id;
  final String name;
  final String slug;
  final String iconAsset;
  final int sortOrder;

  const ShopCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.iconAsset,
    this.sortOrder = 0,
  });

  /// Resolves any legacy category ID into its canonical equivalent.
  static String normalizeCategoryId(String categoryId) {
    switch (categoryId.trim()) {
      case catTrainingGear:
        return catGear;
      case catRecoveryTools:
      case catMealPrepHydration:
        return catRecoveryLifestyle;
      default:
        return categoryId.trim();
    }
  }

  @override
  List<Object?> get props => [id, name, slug, iconAsset, sortOrder];
}

import 'package:flutter/material.dart';

import '../../domain/entities/shop_category.dart';
import '../localization/shop_translations.dart';
import '../theme/shop_theme.dart';

/// Clean minimalist text tabs for category selection with a thin underline indicator.
///
/// Specs from design:
/// - Horizontal scrollable without bulky pills or heavy backgrounds.
/// - Active: Off-white text (#F3F4F6) with 1.5px solid underline indicator.
/// - Inactive: Subtle text (#94979E) with smooth transition.
class ShopCategoryTabs extends StatelessWidget {
  const ShopCategoryTabs({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  final List<ShopCategory> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ShopTheme.borderDivider,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 2.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // "Tất cả" (All) tab
            _CategoryTabItem(
              label: ShopTranslations.of(context, 'category_all'),
              isSelected: selectedCategoryId == null,
              onTap: () => onCategorySelected(null),
            ),
            const SizedBox(width: 24),

            // Dynamic categories from repository
            for (int i = 0; i < categories.length; i++) ...[
              _CategoryTabItem(
                label: _getLocalizedCategoryName(context, categories[i]),
                isSelected: selectedCategoryId == categories[i].id,
                onTap: () => onCategorySelected(categories[i].id),
              ),
              if (i < categories.length - 1) const SizedBox(width: 24),
            ],
          ],
        ),
      ),
    );
  }

  String _getLocalizedCategoryName(BuildContext context, ShopCategory category) {
    switch (category.id) {
      case 'cat_training_gear':
        return ShopTranslations.of(context, 'category_training');
      case 'cat_recovery_tools':
        return ShopTranslations.of(context, 'category_recovery');
      case 'cat_meal_prep_hydration':
        return ShopTranslations.of(context, 'category_nutrition');
      default:
        return category.name;
    }
  }
}

class _CategoryTabItem extends StatelessWidget {
  const _CategoryTabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ShopTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: isSelected ? ShopTheme.tabActive : ShopTheme.tabInactive,
            ),
            const SizedBox(height: 6),
            Container(
              height: 1.5,
              width: isSelected ? 24 : 0,
              decoration: BoxDecoration(
                color: isSelected ? ShopTheme.textPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(1.0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


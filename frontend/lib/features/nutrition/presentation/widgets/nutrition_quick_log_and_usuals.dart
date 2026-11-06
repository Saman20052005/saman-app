import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_translations.dart';
import '../../../../theme/nutrition_home_theme.dart';
import '../../data/food_image_manifest.dart';
import '../providers/nutrition_usual_foods_provider.dart';

class NutritionQuickLogAndUsuals extends ConsumerWidget {
  const NutritionQuickLogAndUsuals({
    required this.selectedDate,
    required this.onQuickLog,
    required this.onReviewPortion,
    super.key,
  });

  final DateTime selectedDate;
  final void Function(String mealType) onQuickLog;
  final void Function(UsualFoodItem food) onReviewPortion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usualsState = ref.watch(usualFoodsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Quick Log Panel
        NutritionQuickLogCard(
          onQuickLog: onQuickLog,
        ),
        const SizedBox(height: 16),

        // 2. Your Usuals Panel
        NutritionYourUsualsCard(
          state: usualsState,
          onSwitchTab: (tab) =>
              ref.read(usualFoodsProvider.notifier).switchTab(tab),
          onToggleFavorite: (food) =>
              ref.read(usualFoodsProvider.notifier).toggleFavorite(food),
          onReviewPortion: onReviewPortion,
          onRetry: () => ref.read(usualFoodsProvider.notifier).retry(),
        ),
      ],
    );
  }
}

class NutritionQuickLogCard extends StatelessWidget {
  const NutritionQuickLogCard({
    required this.onQuickLog,
    super.key,
  });

  final void Function(String mealType) onQuickLog;

  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final isLargeText = textScaler.scale(14) > 18;

    final meals = [
      (
        key: 'Breakfast',
        label: context.tr('meal_type_breakfast'),
        icon: Icons.wb_twilight_rounded,
        iconKey: 'quick_log_breakfast',
      ),
      (
        key: 'Lunch',
        label: context.tr('meal_type_lunch'),
        icon: Icons.light_mode_outlined,
        iconKey: 'quick_log_lunch',
      ),
      (
        key: 'Dinner',
        label: context.tr('meal_type_dinner'),
        icon: Icons.nightlight_round,
        iconKey: 'quick_log_dinner',
      ),
      (
        key: 'Snack',
        label: context.tr('meal_type_snack'),
        icon: Icons.eco_outlined,
        iconKey: 'quick_log_snack',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('quick_log_title'),
          style: s.section.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: s.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.tr('quick_log_subtitle'),
          style: s.caption.copyWith(
            fontSize: 13,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isVeryNarrow = constraints.maxWidth < 360 || isLargeText;

            if (isVeryNarrow) {
              // 2x2 Grid for narrow widths or large text
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _QuickLogButton(
                          label: meals[0].label,
                          icon: meals[0].icon,
                          buttonKey: ValueKey(meals[0].iconKey),
                          onTap: () => onQuickLog(meals[0].key),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickLogButton(
                          label: meals[1].label,
                          icon: meals[1].icon,
                          buttonKey: ValueKey(meals[1].iconKey),
                          onTap: () => onQuickLog(meals[1].key),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickLogButton(
                          label: meals[2].label,
                          icon: meals[2].icon,
                          buttonKey: ValueKey(meals[2].iconKey),
                          onTap: () => onQuickLog(meals[2].key),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickLogButton(
                          label: meals[3].label,
                          icon: meals[3].icon,
                          buttonKey: ValueKey(meals[3].iconKey),
                          onTap: () => onQuickLog(meals[3].key),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            // Single row of 4 buttons
            return Row(
              children: [
                for (int i = 0; i < meals.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _QuickLogButton(
                      label: meals[i].label,
                      icon: meals[i].icon,
                      buttonKey: ValueKey(meals[i].iconKey),
                      onTap: () => onQuickLog(meals[i].key),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickLogButton extends StatelessWidget {
  const _QuickLogButton({
    required this.label,
    required this.icon,
    required this.buttonKey,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Key buttonKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF16171B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF26282F), width: 1),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: s.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NutritionYourUsualsCard extends StatelessWidget {
  const NutritionYourUsualsCard({
    required this.state,
    required this.onSwitchTab,
    required this.onToggleFavorite,
    required this.onReviewPortion,
    required this.onRetry,
    super.key,
  });

  final UsualFoodsState state;
  final void Function(UsualsTab tab) onSwitchTab;
  final void Function(UsualFoodItem food) onToggleFavorite;
  final void Function(UsualFoodItem food) onReviewPortion;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    final items =
        state.selectedTab == UsualsTab.recent ? state.recents : state.favorites;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with Tabs
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              context.tr('your_usuals_title'),
              style: s.section.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: s.ink,
                letterSpacing: -0.2,
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _TabButton(
                  title: context.tr('your_usuals_recent'),
                  isActive: state.selectedTab == UsualsTab.recent,
                  onTap: () => onSwitchTab(UsualsTab.recent),
                  key: const ValueKey('tab_usuals_recent'),
                ),
                _TabButton(
                  title: context.tr('your_usuals_favorites'),
                  isActive: state.selectedTab == UsualsTab.favorites,
                  onTap: () => onSwitchTab(UsualsTab.favorites),
                  key: const ValueKey('tab_usuals_favorites'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Content States
        if (state.isLoading)
          _buildLoadingSkeleton()
        else if (state.error != null)
          _buildErrorView(context)
        else if (items.isEmpty)
          _buildEmptyView(context)
        else
          _buildPopulatedList(items),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF16171B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF26282F)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF16171B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF26282F)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFF87171)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('your_usuals_error'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(48, 36),
            ),
            child: Text(context.tr('your_usuals_retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    final isRecent = state.selectedTab == UsualsTab.recent;
    final title = isRecent
        ? context.tr('your_usuals_empty_recent_title')
        : context.tr('your_usuals_empty_favorites_title');
    final desc = isRecent
        ? context.tr('your_usuals_empty_recent_desc')
        : context.tr('your_usuals_empty_favorites_desc');
    final icon = isRecent
        ? Icons.history_toggle_off_rounded
        : Icons.favorite_border_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE5E7EB),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopulatedList(List<UsualFoodItem> items) {
    final displayItems = items.take(2).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final isLargeText = textScaler.scale(14) > 18;
        final isNarrow = constraints.maxWidth < 360 || isLargeText;

        if (isNarrow) {
          // Vertical stack when space is very narrow or text is scaled up
          return Column(
            children: [
              for (int i = 0; i < displayItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _UsualFoodCard(
                  food: displayItems[i],
                  isFavorite: state.favoriteIds.contains(displayItems[i].id),
                  onTap: () => onReviewPortion(displayItems[i]),
                  onToggleFavorite: () => onToggleFavorite(displayItems[i]),
                ),
              ],
            ],
          );
        }

        // Side-by-side row of up to 2 items
        return Row(
          children: [
            for (int i = 0; i < displayItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _UsualFoodCard(
                  food: displayItems[i],
                  isFavorite: state.favoriteIds.contains(displayItems[i].id),
                  onTap: () => onReviewPortion(displayItems[i]),
                  onToggleFavorite: () => onToggleFavorite(displayItems[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.title,
    required this.isActive,
    required this.onTap,
    super.key,
  });

  final String title;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF10B981)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 2,
                width: 24,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF10B981) : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsualFoodCard extends StatelessWidget {
  const _UsualFoodCard({
    required this.food,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final UsualFoodItem food;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final imageAsset = foodImageAssetFor(food.name);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('usual_card_${food.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF16171B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF26282F), width: 1),
          ),
          child: Row(
            children: [
              // Food Thumbnail
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF212328),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF26282F)),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageAsset != null
                    ? Image.asset(
                        imageAsset,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.restaurant_outlined,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.restaurant_outlined,
                          size: 18,
                          color: Color(0xFF6B7280),
                        ),
                      ),
              ),
              const SizedBox(width: 8),

              // Title and Portion Review
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF9FAFB),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('your_usuals_review_portion'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),

              // Favorite Heart Icon Button
              IconButton(
                key: ValueKey('fav_btn_${food.id}'),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: isFavorite ? 'Bỏ yêu thích' : 'Yêu thích',
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite
                      ? const Color(0xFF10B981)
                      : const Color(0xFF6B7280),
                ),
                onPressed: onToggleFavorite,
              ),

              // Chevron Right
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: Color(0xFF6B7280),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

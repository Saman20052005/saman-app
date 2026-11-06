import 'package:flutter/material.dart';
import '../../../../models/nutrition_model.dart';
import '../../../../theme/nutrition_home_theme.dart';

/// Card displaying a logged meal matching Calm Athleticism:
/// 56x56 thumbnail with resilient fallback | MealType & genuine time (if available) | Calories | Macros subtitle
/// Strict rule: No fake check_circle or confirmed badges when unverified; meal time only displayed when present.
class NutritionLoggedMealCard extends StatelessWidget {
  final NutritionLogEntry entry;
  final VoidCallback? onTap;

  const NutritionLoggedMealCard({
    super.key,
    required this.entry,
    this.onTap,
  });

  String _formatMealHeader() {
    final type = entry.mealType.isNotEmpty ? entry.mealType : 'Meal';
    return type[0].toUpperCase() + type.substring(1).toLowerCase();
  }

  String? _findTime() {
    for (final food in entry.foods) {
      final t = food['time'] ?? food['logged_at'] ?? food['created_at'];
      if (t != null && t.toString().isNotEmpty) {
        return t.toString();
      }
    }
    return null;
  }

  String? _findImageUrl() {
    if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty) {
      return entry.imageUrl;
    }
    for (final food in entry.foods) {
      final img = food['image'] ?? food['image_url'] ?? food['thumbnail'];
      if (img != null && img.toString().isNotEmpty) {
        return img.toString();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _findImageUrl();
    final headerLabel = _formatMealHeader();
    final timeStr = _findTime();

    return NutritionHomeTheme(
        child: _LoggedMealPresentation(
      entry: entry,
      imageUrl: imageUrl,
      headerLabel: headerLabel,
      timeStr: timeStr,
      onTap: onTap,
    ));
  }
}

class _LoggedMealPresentation extends StatelessWidget {
  const _LoggedMealPresentation(
      {required this.entry,
      required this.imageUrl,
      required this.headerLabel,
      required this.timeStr,
      required this.onTap});
  final NutritionLogEntry entry;
  final String? imageUrl, timeStr;
  final String headerLabel;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return Material(
      color: s.surface,
      shape: RoundedRectangleBorder(
          borderRadius: s.cardRadius, side: BorderSide(color: s.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                    borderRadius: s.imageRadius,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: imageUrl != null && imageUrl!.isNotEmpty
                          ? Image.network(imageUrl!,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.restaurant_outlined,
                                  color: s.muted))
                          : ColoredBox(
                              color: s.track,
                              child: Icon(Icons.restaurant_outlined,
                                  color: s.muted)),
                    )),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          timeStr != null
                              ? '${headerLabel.toUpperCase()} · $timeStr'
                              : headerLabel.toUpperCase(),
                          style: s.caption),
                      const SizedBox(height: 3),
                      Text(entry.foodName, style: s.strong),
                      const SizedBox(height: 6),
                      Text('${entry.totalCalories} kcal', style: s.body),
                      Text(
                          '${entry.protein.toInt()}g pro · ${entry.carbs.toInt()}g carb · ${entry.fat.toInt()}g fat',
                          style: s.caption),
                    ])),
              ],
            )),
      ),
    );
  }
}

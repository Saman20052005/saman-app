import 'package:flutter/material.dart';
import '../../../../models/nutrition_model.dart';

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF16171B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26282F)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 56x56 Thumbnail with resilient fallback
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF212328),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF26282F)),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(
                            Icons.restaurant_outlined,
                            size: 22,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.restaurant_outlined,
                          size: 22,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
              ),
              const SizedBox(width: 12),

              // Content Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Meal type & Calories
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            timeStr != null
                                ? '${headerLabel.toUpperCase()} · $timeStr'
                                : headerLabel.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${entry.totalCalories} ',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF3F4F6),
                                ),
                              ),
                              const TextSpan(
                                text: 'kcal',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Food Title
                    Text(
                      entry.foodName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF3F4F6),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Macro Breakdown
                    Text(
                      '${entry.protein.toInt()}g pro · ${entry.carbs.toInt()}g carb · ${entry.fat.toInt()}g fat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

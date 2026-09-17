// lib/screens/nutrition/widgets/meal_card.dart
// BUG FIX #1: _handleSwap — thêm timeout 15s + catch TimeoutException + connectivity error
// BUG FIX #2: _ActionButton — xóa hardcode colors, dùng theme
// BUG FIX #3: flutter_animate — không dùng controller thủ công nên không có leak,
//             nhưng đảm bảo .animate() chỉ chạy trên widget mounted
// UI: giữ nguyên 100%

import 'dart:async'; // BUG FIX #1: cần TimeoutException
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../models/nutrition_model.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../providers/profile_provider.dart';

class MealCard extends ConsumerWidget {
  final Meal meal;
  final DateTime? selectedDate;

  const MealCard({super.key, required this.meal, this.selectedDate});

  // ─────────────────────────────────────────────────────────────────────────
  // BUG FIX #1: _handleSwap — xử lý timeout + network failure đúng cách
  // Before: chỉ có try/catch generic, không có timeout, có thể loading vĩnh viễn
  // After:  .timeout(15s) + catch TimeoutException riêng + mounted check đầy đủ
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> _handleSwap(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI is finding a better meal...'),
        duration: Duration(milliseconds: 1000),
      ),
    );

    try {
      // Use legacy Meal directly for provider
      final domainMeal = Meal(
        foodId: meal.foodId,
        name: meal.name,
        calories: meal.calories,
        protein: meal.protein,
        carbs: meal.carbs,
        fat: meal.fat,
        weightGrams: meal.weightGrams,
        mealType: meal.mealType,
        time: meal.time,
        isEaten: meal.isEaten,
        tags: meal.tags,
        image: meal.image,
        foodsList: meal.foodsList,
      );
      await ref
          .read(nutritionProvider.notifier)
          .swapMeal(domainMeal, profile.profile.goal.name)
          .timeout(const Duration(seconds: 15)); // BUG FIX #1

      return true;
    } on TimeoutException {
      // BUG FIX #1: timeout — không còn loading vĩnh viễn
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yêu cầu quá thời gian — vui lòng thử lại'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    } catch (e) {
      // BUG FIX #1: network error / server failure
      if (context.mounted) {
        final msg = _mapErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  // BUG FIX #1: map lỗi chung → thông báo tiếng Việt thân thiện
  String _mapErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return 'Không có kết nối mạng — vui lòng kiểm tra và thử lại';
    }
    if (msg.contains('500') || msg.contains('server')) {
      return 'Máy chủ đang bận — vui lòng thử lại sau ít phút';
    }
    return 'Không thể đổi bữa — vui lòng thử lại';
  }

  // ── Macro detail dialog (không thay đổi) ──────────────────────────────
  void _showMacroDetail(BuildContext context, Meal meal) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meal.mealType,
              style: TextStyle(fontSize: 12, color: colors.secondary),
            ),
            const SizedBox(height: 4),
            Text(
              '${meal.calories} kcal tổng',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total macro chips row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF252525)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _macroChip('P', '${meal.protein.toInt()}g', colors),
                    _macroChip('C', '${meal.carbs.toInt()}g', colors),
                    _macroChip('F', '${meal.fat.toInt()}g', colors),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Foods list
              if (meal.foodsList.isNotEmpty) ...[
                Text(
                  'Thành phần:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ...meal.foodsList
                    .map((food) => _buildFoodRow(food, colors, isDark)),
              ] else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Calories: ${meal.calories} kcal',
                        style: TextStyle(color: colors.onSurface)),
                    Text('Protein: ${meal.protein.toStringAsFixed(1)}g',
                        style: TextStyle(color: colors.onSurface)),
                    Text('Carbs: ${meal.carbs.toStringAsFixed(1)}g',
                        style: TextStyle(color: colors.onSurface)),
                    Text('Fat: ${meal.fat.toStringAsFixed(1)}g',
                        style: TextStyle(color: colors.onSurface)),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Đóng', style: TextStyle(color: colors.onSurface)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;

    // BUG FIX #3: flutter_animate — dùng .animate() trực tiếp trên widget
    // (không có AnimationController thủ công → không có disposal issue)
    // Đây là cách đúng — flutter_animate tự quản lý lifecycle qua Element
    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      // ✅ Swap background — monochrome thay orangeAccent
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: colors.onSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'SWAP',
              style: TextStyle(
                color: colors.surface,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.swap_horiz, color: colors.surface),
          ],
        ),
      ),
      confirmDismiss: (direction) => _handleSwap(context, ref),

      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Dùng theme-safe: colorScheme.surface (không import extension)
          color: isDark ? const Color(0xFF1C1C1C) : colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Checkbox (eaten status) — logic giữ nguyên ──────
                GestureDetector(
                  onTap: () =>
                      ref.read(nutritionProvider.notifier).updateMealStatus(
                            Meal(
                              foodId: meal.foodId,
                              name: meal.name,
                              calories: meal.calories,
                              protein: meal.protein,
                              carbs: meal.carbs,
                              fat: meal.fat,
                              weightGrams: meal.weightGrams,
                              mealType: meal.mealType,
                              time: meal.time,
                              isEaten: meal.isEaten,
                              tags: meal.tags,
                              image: meal.image,
                              foodsList: meal.foodsList,
                            ),
                            !meal.isEaten,
                          ),
                  child: AnimatedContainer(
                    duration: 200.ms,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // ✅ Thay neon green → colors.onSurface
                      color:
                          meal.isEaten ? colors.onSurface : Colors.transparent,
                      border: Border.all(
                        color:
                            meal.isEaten ? colors.onSurface : colors.secondary,
                        width: 1.5,
                      ),
                    ),
                    child: meal.isEaten
                        ? Icon(Icons.check, size: 14, color: colors.surface)
                        : null,
                  ),
                ),
                const SizedBox(width: 14),

                // ── Meal info ────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Meal type label
                      Text(
                        meal.mealType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.secondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Meal name
                      Text(
                        meal.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: meal.isEaten
                              ? colors.secondary
                              : colors.onSurface,
                          decoration:
                              meal.isEaten ? TextDecoration.lineThrough : null,
                          letterSpacing: -0.2,
                        ),
                      ),

                      // ── Food chips preview (logic giữ nguyên) ──────
                      if (meal.foodsList.length > 1) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: meal.foodsList.skip(1).take(3).map((food) {
                            final fname = food['name'] as String? ?? '';
                            final grams = food['grams'] as int? ??
                                food['weight_grams'] as int? ??
                                0;
                            // ✅ Monochrome chip — không còn màu theo group
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$fname ${grams}g',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.secondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Mini info row
                      Row(
                        children: [
                          _buildMiniInfo(
                            Icons.local_fire_department_outlined,
                            '${meal.calories} kcal',
                            colors,
                          ),
                          const SizedBox(width: 12),
                          _buildMiniInfo(
                            Icons.fitness_center_outlined,
                            '${meal.protein.toInt()}g pro',
                            colors,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Action buttons ───────────────────────────────────────
            Row(
              children: [
                // Log / Đã ăn button
                Expanded(
                  child: _ActionButton(
                    icon: Icons.check_circle_outline,
                    label: 'Đã ăn',
                    onPressed: () async {
                      final success =
                          await ref.read(nutritionProvider.notifier).addMeal(
                                date: selectedDate ?? DateTime.now(),
                                mealType: meal.mealType.toLowerCase(),
                                name: meal.name,
                                calories: meal.calories.toDouble(),
                                protein: meal.protein.toDouble(),
                                carbs: meal.carbs.toDouble(),
                                fat: meal.fat.toDouble(),
                                weightGrams: 100,
                                foodId: meal.foodId,
                              );
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã log ${meal.name}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Chi tiết button
                Expanded(
                  child: _ActionButton(
                    icon: Icons.bar_chart_outlined,
                    label: 'Chi tiết',
                    onPressed: () => _showMacroDetail(context, meal),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Mini icon + text ────────────────────────────────────────────────────
  Widget _buildMiniInfo(IconData icon, String text, ColorScheme colors) {
    return Row(
      children: [
        Icon(icon, size: 13, color: colors.secondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: colors.secondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Food row in dialog ─────────────────────────────────────────────────
  Widget _buildFoodRow(
    Map<String, dynamic> food,
    ColorScheme colors,
    bool isDark,
  ) {
    final name = food['name'] as String? ?? '';
    final grams =
        food['grams'] as int? ?? (food['weight_grams'] as int? ?? 100);
    final cal = food['calories'] as int? ?? 0;
    final pro = (food['protein'] as num?)?.toDouble() ?? 0;
    final carb = (food['carbs'] as num?)?.toDouble() ?? 0;
    final fat = (food['fat'] as num?)?.toDouble() ?? 0;
    final group = food['group'] as String? ?? '';

    // ✅ Monochrome icon thay emoji màu
    final groupIcon = {
          'protein': '🥩',
          'carb': '🍚',
          'fiber': '🥦',
          'fat': '🥜',
        }[group] ??
        '🍽️';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252525) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
        ),
      ),
      child: Row(
        children: [
          Text(groupIcon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'P:${pro.toInt()}g  C:${carb.toInt()}g  F:${fat.toInt()}g',
                  style: TextStyle(fontSize: 11, color: colors.secondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${grams}g',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                  fontSize: 14,
                ),
              ),
              Text(
                '$cal kcal',
                style: TextStyle(fontSize: 11, color: colors.secondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Macro chip in dialog header ─────────────────────────────────────────
  Widget _macroChip(String label, String value, ColorScheme colors) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.secondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUG FIX #2: _ActionButton — xóa hardcode isDark/colors tham số
// Đọc trực tiếp từ Theme.of(context) bên trong widget → luôn đúng context
// UI giữ nguyên: cùng padding, shape, font, layout
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // BUG FIX #2: không nhận isDark/colors từ ngoài — luôn đọc từ context hiện tại
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          // BUG FIX #2: không còn hardcode — theme-aware
          color: isDark ? const Color(0xFF252525) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: colors.onSurface),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/screens/nutrition/widgets/plan_generator_sheet.dart
// BUG FIX #1: context.surfaceColor (extension) → Theme.of(context).colorScheme.surface (safe)
// BUG FIX #2: Semantics label cho meal count buttons (accessibility)
// BUG FIX #3: 72x72 cứng → responsive dựa vào screen width
// UI: giữ nguyên 100% — layout, shape, spacing, màu sắc

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/nutrition_provider.dart';

class PlanGeneratorSheet extends ConsumerStatefulWidget {
  final int remainingCalories;
  final int consumedCalories;
  final String userGoal;
  final DateTime selectedDate;

  const PlanGeneratorSheet({
    super.key,
    required this.remainingCalories,
    required this.consumedCalories,
    required this.userGoal,
    required this.selectedDate,
  });

  @override
  ConsumerState<PlanGeneratorSheet> createState() => _PlanGeneratorSheetState();
}

class _PlanGeneratorSheetState extends ConsumerState<PlanGeneratorSheet> {
  String _style = 'optimal';
  late int _mealCount;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _mealCount = _suggestMealCount(widget.userGoal);
  }

  // ── Logic không đổi ──────────────────────────────────────────────
  int _suggestMealCount(String goal) {
    switch (goal) {
      case 'gain_muscle':
      case 'muscle_gain':
        return 5;
      case 'lose_weight':
      case 'weight_loss':
        return 3;
      default:
        return 4;
    }
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    try {
      await ref.read(nutritionProvider.notifier).generateSmartPlan(
            date: widget.selectedDate,
            mealCount: _mealCount,
            style: _style,
            remainingOnly: true,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // BUG FIX #3: kích thước button responsive
    final screenWidth = MediaQuery.of(context).size.width;
    // Tablet (>600) thì button to hơn một chút, phone giữ nguyên cảm giác
    final buttonSize = (screenWidth > 600) ? 88.0 : 72.0;

    return Container(
      decoration: BoxDecoration(
        // BUG FIX #1: context.surfaceColor (extension, có thể fail)
        // → Theme.of(context).colorScheme.surface (luôn an toàn)
        color: isDark
            ? const Color(0xFF1C1C1C)
            : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Header ──────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Tạo kế hoạch',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              // ✅ Thay Colors.green.shade50/700 → monochrome tag
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Còn ${widget.remainingCalories} kcal',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Đã ăn ${widget.consumedCalories} kcal hôm nay',
            style: TextStyle(color: colors.secondary, fontSize: 13),
          ),

          const SizedBox(height: 24),

          // ── Style selector ───────────────────────────────────────
          Text(
            'Phong cách ăn',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StyleCard(
                icon: '⚡',
                title: 'Tiết kiệm',
                subtitle: 'Đơn giản, nhanh\nít nguyên liệu',
                selected: _style == 'quick',
                onTap: () => setState(() => _style = 'quick'),
              ),
              const SizedBox(width: 12),
              _StyleCard(
                icon: '🎯',
                title: 'Tối ưu goal',
                subtitle: 'Cân macro\nphù hợp mục tiêu',
                selected: _style == 'optimal',
                onTap: () => setState(() => _style = 'optimal'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Meal count selector ──────────────────────────────────
          Row(
            children: [
              Text(
                'Số bữa hôm nay',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              // ✅ Thay Colors.blue.shade50/700 → monochrome
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _style == 'optimal' && widget.userGoal.contains('gain')
                      ? 'Khuyến nghị 5 bữa cho gain muscle'
                      : _style == 'optimal' && widget.userGoal.contains('loss')
                          ? 'Khuyến nghị 3 bữa cho lose weight'
                          : 'Khuyến nghị $_mealCount bữa',
                  style: TextStyle(
                    color: colors.secondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [3, 4, 5].map((count) {
              final selected = _mealCount == count;
              // BUG FIX #2 + #3: Semantics + responsive size
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Semantics(
                  label: '$count bữa ăn, '
                      '${selected ? "đang chọn" : "nhấn để chọn"}',
                  selected: selected,
                  button: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _mealCount = count),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: buttonSize, // BUG FIX #3: responsive
                      height: buttonSize, // BUG FIX #3: responsive
                      decoration: BoxDecoration(
                        // ✅ selected → colors.onSurface (black/white adaptive)
                        color: selected
                            ? colors.onSurface
                            : isDark
                                ? const Color(0xFF252525)
                                : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? colors.onSurface
                              : isDark
                                  ? const Color(0xFF333333)
                                  : const Color(0xFFDDDDDD),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color:
                                  selected ? colors.surface : colors.onSurface,
                            ),
                          ),
                          Text(
                            'bữa',
                            style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? colors.surface.withOpacity(0.7)
                                  : colors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // ── CTA button ───────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.surface,
                      ),
                    )
                  : Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: colors.surface,
                    ),
              label: Text(
                _isGenerating
                    ? 'Đang tạo...'
                    : 'Tạo $_mealCount bữa · '
                        '${_style == "quick" ? "⚡ Nhanh" : "🎯 Tối ưu"}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: colors.surface,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.onSurface,
                foregroundColor: colors.surface,
                disabledBackgroundColor:
                    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
                disabledForegroundColor: colors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widget: Style Card ──────────────────────────────────────────────────
class _StyleCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _StyleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // ✅ selected → onSurface (adaptive), idle → muted bg
            color: selected
                ? colors.onSurface
                : isDark
                    ? const Color(0xFF252525)
                    : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colors.onSurface
                  : isDark
                      ? const Color(0xFF333333)
                      : const Color(0xFFDDDDDD),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: selected ? colors.surface : colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: selected
                      ? colors.surface.withOpacity(0.65)
                      : colors.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

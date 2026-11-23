import 'package:flutter/material.dart';
import '../../../../config/app_theme.dart';

class ReportTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const ReportTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final containerBg = isDark ? const Color(0xFF131417) : p.surfaceElevated;
    final borderCol = isDark ? const Color(0xFF26282F) : p.border;
    final activePillBg = isDark ? const Color(0xFFF9FAFB) : p.surface;
    final activeTextCol = isDark ? const Color(0xFF0C0D0E) : p.textPrimary;
    final inactiveTextCol = isDark ? const Color(0xFFA1A1AA) : p.textSecondary;
    const tabs = ['Overview', 'Nutrition', 'Activity'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: containerBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol),
        ),
        child: Row(
          children: tabs.asMap().entries.map((entry) {
            final idx = entry.key;
            final title = entry.value;
            final isSelected = selectedIndex == idx;

            return Expanded(
              child: GestureDetector(
                onTap: () => onTabSelected(idx),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? activePillBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.12 : 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? activeTextCol : inactiveTextCol,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}


// lib/screens/nutrition/widgets/date_selector.dart
// BUG FIX #1: Colors.white (line 55 gốc) → theme-aware (colors.surface)
// BUG FIX #2: width 50px cứng → responsive dựa vào screen width
// UI: giữ nguyên 100% — pill shape, spacing, text style, today dot

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const DateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();

    // Logic giữ nguyên: Mon-based week
    final start = now.subtract(Duration(days: now.weekday - 1));
    final weekDays = List.generate(7, (i) => start.add(Duration(days: i)));

    // BUG FIX #2: tính width responsive thay vì hardcode 50px
    // Tổng padding ngang = 32, margin mỗi item = 10 (5*2), 7 items
    // pilWidth = (screenWidth - 32 - 70) / 7 nhưng clamp [42, 56]
    final screenWidth = MediaQuery.of(context).size.width;
    final pillWidth = ((screenWidth - 32 - 70) / 7).clamp(42.0, 56.0);

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final date = weekDays[index];
          final isSelected = date.day == selectedDate.day &&
              date.month == selectedDate.month &&
              date.year == selectedDate.year;
          final isToday = date.day == now.day &&
              date.month == now.month &&
              date.year == now.year;

          return GestureDetector(
            onTap: () => onDateSelected(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              // BUG FIX #2: dùng pillWidth responsive
              width: pillWidth,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
              decoration: BoxDecoration(
                // BUG FIX #1: light idle = colors.surface (không còn Colors.white)
                color: isSelected
                    ? colors.onSurface
                    : isDark
                        ? const Color(0xFF252525)
                        : colors.surface, // ← was Colors.white
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isSelected
                      ? colors.onSurface
                      : isToday
                          ? colors.secondary
                          : isDark
                              ? const Color(0xFF333333)
                              : const Color(0xFFE8E8E8),
                  width: isToday && !isSelected ? 1.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              // BUG FIX #2: FittedBox bảo vệ text overflow khi text scale lớn
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('E').format(date).substring(0, 3),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          // ✅ Thay Colors.white70/Colors.grey → theme-aware
                          color: isSelected
                              ? colors.surface.withOpacity(0.75)
                              : colors.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          // ✅ Thay Colors.white/Colors.black → theme-aware
                          color: isSelected ? colors.surface : colors.onSurface,
                        ),
                      ),
                      // Today dot
                      if (isToday) ...[
                        const SizedBox(height: 3),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? colors.surface.withOpacity(0.6)
                                : colors.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

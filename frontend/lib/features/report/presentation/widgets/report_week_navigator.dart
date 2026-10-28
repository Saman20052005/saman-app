import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReportWeekNavigator extends StatelessWidget {
  final DateTime weekMonday;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickDate;

  const ReportWeekNavigator({
    super.key,
    required this.weekMonday,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
  });

  bool get _isThisWeek {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(weekMonday.year, weekMonday.month, weekMonday.day);
    final sunday = monday.add(const Duration(days: 6));
    return !today.isBefore(monday) && !today.isAfter(sunday);
  }

  String _formatWeekRange() {
    final sunday = weekMonday.add(const Duration(days: 6));
    if (weekMonday.month == sunday.month && weekMonday.year == sunday.year) {
      final start = DateFormat('MMM dd').format(weekMonday);
      final end = DateFormat('dd, yyyy').format(sunday);
      return '$start – $end';
    } else if (weekMonday.year == sunday.year) {
      final start = DateFormat('MMM dd').format(weekMonday);
      final end = DateFormat('MMM dd, yyyy').format(sunday);
      return '$start – $end';
    } else {
      final start = DateFormat('MMM dd, yyyy').format(weekMonday);
      final end = DateFormat('MMM dd, yyyy').format(sunday);
      return '$start – $end';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoNext = onNext != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF16171A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF26282F)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Previous Week
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPrevious,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    color: Color(0xFFA1A1AA),
                    size: 20,
                  ),
                ),
              ),
            ),

            // Center: Date Range + Calendar
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: Color(0xFFA1A1AA),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _formatWeekRange(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                        ),
                        if (_isThisWeek) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '· This week',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF71717A),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Next Week
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onNext,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: canGoNext
                        ? const Color(0xFFA1A1AA)
                        : const Color(0xFF52525B),
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


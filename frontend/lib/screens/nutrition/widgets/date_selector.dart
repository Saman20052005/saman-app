import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../theme/nutrition_home_theme.dart';

/// Compact Date Navigator Pill matching Calm Athleticism design spec:
/// Left chevron (prev day) | Center calendar + date + Today badge + expand_more | Right chevron (next day)
class DateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const DateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10B981),
              onPrimary: Color(0xFF0C0D0E),
              surface: Color(0xFF16171B),
              onSurface: Color(0xFFF3F4F6),
            ),
            dialogBackgroundColor: const Color(0xFF16171B),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onDateSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = _isSameDay(selectedDate, now);
    final isFuture =
        selectedDate.isAfter(DateTime(now.year, now.month, now.day));

    final style = NutritionHomeStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
          color: style.surface,
          borderRadius: style.cardRadius,
          border: Border.all(color: style.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Row(children: [
          IconButton(
              tooltip: 'Previous day',
              onPressed: () => onDateSelected(
                  selectedDate.subtract(const Duration(days: 1))),
              icon: Icon(Icons.chevron_left, color: style.muted)),
          Expanded(
              child: TextButton(
            onPressed: () => _pickDate(context),
            child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 7,
                runSpacing: 4,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: style.muted),
                  Text(DateFormat('EEE, MMM d').format(selectedDate),
                      style: style.body),
                  if (isToday)
                    Text('TODAY',
                        style: style.label.copyWith(color: style.accent)),
                  Icon(Icons.expand_more, size: 16, color: style.accent),
                ]),
          )),
          IconButton(
              tooltip: 'Next day',
              onPressed: isFuture
                  ? null
                  : () =>
                      onDateSelected(selectedDate.add(const Duration(days: 1))),
              icon: Icon(Icons.chevron_right,
                  color: isFuture ? style.border : style.muted)),
        ]),
      ),
    );
  }
}

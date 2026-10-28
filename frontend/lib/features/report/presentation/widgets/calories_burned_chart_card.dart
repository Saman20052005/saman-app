import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import 'calories_consumed_chart_card.dart';

class CaloriesBurnedChartCard extends StatelessWidget {
  final List<DailyStats> days;
  final double avgCaloriesBurned;
  final int targetBurned;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;

  const CaloriesBurnedChartCard({
    super.key,
    required this.days,
    required this.avgCaloriesBurned,
    required this.targetBurned,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Calculate domain ceiling (maxY) with headroom encompassing max value & target
    double maxDataVal = 0;
    for (final d in days) {
      if (d.caloriesBurned > maxDataVal) {
        maxDataVal = d.caloriesBurned;
      }
    }
    double ceiling = maxDataVal > targetBurned ? maxDataVal : targetBurned.toDouble();
    if (ceiling < 300) ceiling = 300;
    // Add 15% breathing room, round up to nice tick (e.g. 650 -> 700)
    ceiling = (ceiling * 1.15).ceilToDouble();
    final double maxY = ((ceiling / 100).ceil() * 100).toDouble();

    // Selected day info
    final safeIndex = (selectedIndex >= 0 && selectedIndex < days.length)
        ? selectedIndex
        : 0;
    final selectedDay = days.isNotEmpty ? days[safeIndex] : null;

    final String selectedDateLabel = selectedDay != null
        ? DateFormat('EEEE, MMM dd').format(selectedDay.date)
        : '—';

    String selectedValLabel = '—';
    String deltaLabel = '';
    if (selectedDay != null) {
      if (selectedDay.hasWorkout && selectedDay.caloriesBurned > 0) {
        final val = selectedDay.caloriesBurned.round();
        selectedValLabel = '${NumberFormat('#,###').format(val)} kcal';
        if (targetBurned > 0) {
          final diff = val - targetBurned;
          if (diff > 0) {
            deltaLabel = '(+$diff over goal)';
          } else if (diff < 0) {
            deltaLabel = '($diff under goal)';
          } else {
            deltaLabel = '(Met exact goal)';
          }
        }
      } else if (selectedDay.isRestDay || (selectedDay.hasWorkout && selectedDay.caloriesBurned == 0)) {
        selectedValLabel = '0 kcal (Rest day)';
      } else if (selectedDay.isFuture) {
        selectedValLabel = 'Upcoming';
      } else {
        selectedValLabel = 'Unlogged';
      }
    }

    final dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'CALORIES BURNED',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          NumberFormat('#,###').format(avgCaloriesBurned.round()),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'kcal / day avg',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFA1A1AA),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'DAILY GOAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: Color(0xFF71717A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      targetBurned > 0
                          ? '${NumberFormat('#,###').format(targetBurned)} kcal'
                          : 'No goal set',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Chart Plot Area
          SizedBox(
            height: 140,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double plotHeight = 95;
                const double yAxisWidth = 32;
                final double plotWidth = constraints.maxWidth - yAxisWidth;

                // Ticks: maxY, maxY/2, 0
                final List<double> ticks = [maxY, maxY * 0.5, 0];
                final double goalY = targetBurned > 0
                    ? (1.0 - (targetBurned / maxY).clamp(0.0, 1.0)) * plotHeight
                    : -1;

                return Stack(
                  children: [
                    // Grid lines & Y-axis labels
                    Positioned.fill(
                      bottom: 24,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: ticks.map((val) {
                          return Row(
                            children: [
                              SizedBox(
                                width: yAxisWidth,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    val == 0 ? '0' : val.toInt().toString(),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF71717A),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: val == 0
                                      ? const Color(0xFF2D3039)
                                      : const Color(0xFF23252A),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),

                    // Dashed Amber Goal Line
                    if (goalY >= 0 && goalY <= plotHeight)
                      Positioned(
                        top: goalY,
                        left: yAxisWidth + 8,
                        right: 0,
                        child: CustomPaint(
                          size: Size(plotWidth, 1),
                          painter: DashedLinePainter(
                            color: const Color(0xFFF59E0B).withOpacity(0.6),
                          ),
                        ),
                      ),

                    // 7 Amber Bars
                    Positioned(
                      left: yAxisWidth + 8,
                      right: 0,
                      top: 0,
                      height: plotHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(7, (i) {
                          final day = i < days.length ? days[i] : null;
                          final isSelected = i == safeIndex;
                          final hasActive =
                              day != null && day.hasWorkout && day.caloriesBurned > 0;
                          final isRest = day != null &&
                              (day.isRestDay ||
                                  (day.hasWorkout && day.caloriesBurned == 0));
                          final double val = hasActive ? day.caloriesBurned : 0.0;
                          final double barHeight = hasActive
                              ? (val / maxY * plotHeight).clamp(4.0, plotHeight)
                              : 0.0;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () => onSelectIndex(i),
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (hasActive)
                                    Container(
                                      width: 16,
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFF59E0B)
                                            : const Color(0xFFF59E0B)
                                                .withOpacity(0.85),
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                        border: isSelected
                                            ? Border.all(
                                                color: Colors.white, width: 1)
                                            : null,
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: const Color(0xFFF59E0B)
                                                      .withOpacity(0.4),
                                                  blurRadius: 8,
                                                )
                                              ]
                                            : null,
                                      ),
                                    )
                                  else if (isRest)
                                    Container(
                                      width: 16,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4B3B22),
                                        borderRadius: BorderRadius.circular(2),
                                        border: isSelected
                                            ? Border.all(
                                                color: const Color(0xFFF59E0B),
                                                width: 1,
                                              )
                                            : null,
                                      ),
                                    )
                                  else
                                    Container(
                                      height: 20,
                                      alignment: Alignment.center,
                                      child: Text(
                                        day != null && day.isFuture ? '·' : '—',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontFamily: 'monospace',
                                          color: day != null && day.isFuture
                                              ? const Color(0xFF52525B)
                                              : const Color(0xFF71717A),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Day Labels (X-Axis)
                    Positioned(
                      left: yAxisWidth + 8,
                      right: 0,
                      bottom: 0,
                      height: 22,
                      child: Row(
                        children: List.generate(7, (i) {
                          final isSelected = i == safeIndex;
                          final day = i < days.length ? days[i] : null;
                          final isFuture = day != null && day.isFuture;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () => onSelectIndex(i),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: isSelected
                                    ? BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      )
                                    : null,
                                child: Text(
                                  dayLabels[i],
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? Colors.white
                                        : (isFuture
                                            ? const Color(0xFF52525B)
                                            : const Color(0xFFA1A1AA)),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Clarifying Legend (0 vs Missing)
          Container(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFF23252A), width: 1),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4B3B22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Rest (0 kcal)',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '—',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF71717A),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Unlogged',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Selected Date & Exact Value Footer
          Container(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      selectedDateLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFD1D5DB),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      selectedValLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    if (deltaLabel.isNotEmpty)
                      Text(
                        deltaLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFA1A1AA),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

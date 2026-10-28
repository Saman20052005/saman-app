import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';

class CaloriesConsumedChartCard extends StatelessWidget {
  final List<DailyStats> days;
  final double avgCalories;
  final int targetCalories;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;

  const CaloriesConsumedChartCard({
    super.key,
    required this.days,
    required this.avgCalories,
    required this.targetCalories,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Calculate domain ceiling (maxY) with headroom encompassing max value & target
    double maxDataVal = 0;
    for (final d in days) {
      if (d.isRecorded && d.caloriesIn > maxDataVal) {
        maxDataVal = d.caloriesIn;
      }
    }
    double ceiling = maxDataVal > targetCalories ? maxDataVal : targetCalories.toDouble();
    if (ceiling < 1000) ceiling = 1000;
    // Add 15% breathing room, round up to nice tick
    ceiling = (ceiling * 1.15).ceilToDouble();
    final double maxY = ((ceiling / 500).ceil() * 500).toDouble();

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
      if (selectedDay.isRecorded) {
        final val = selectedDay.caloriesIn.round();
        selectedValLabel = '${NumberFormat('#,###').format(val)} kcal';
        if (targetCalories > 0) {
          final diff = val - targetCalories;
          if (diff > 0) {
            deltaLabel = '(+$diff over goal)';
          } else if (diff < 0) {
            deltaLabel = '($diff under goal)';
          } else {
            deltaLabel = '(Met exact goal)';
          }
        }
      } else if (selectedDay.isFuture) {
        selectedValLabel = 'Upcoming';
      } else {
        selectedValLabel = 'No entry';
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
                            color: Color(0xFFE5E7EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'CALORIES CONSUMED',
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
                          NumberFormat('#,###').format(avgCalories.round()),
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
                      color: const Color(0xFF212329),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Text(
                      targetCalories > 0
                          ? '${NumberFormat('#,###').format(targetCalories)} kcal'
                          : 'No goal set',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE5E7EB),
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
            height: 180,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double yAxisWidth = 36;
                final double plotWidth = constraints.maxWidth - yAxisWidth;
                const double maxBarHeight = 110.0;

                // Ticks
                final List<double> ticks = [maxY, maxY * 0.66, maxY * 0.33, 0];
                final double goalY = targetCalories > 0
                    ? 156.0 - (targetCalories / maxY).clamp(0.0, 1.0) * maxBarHeight
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
                                    val == 0
                                        ? '0'
                                        : NumberFormat('#,###').format(val.toInt()),
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

                    // Dashed Goal Line
                    if (goalY >= 0 && goalY <= 156)
                      Positioned(
                        top: goalY - 7,
                        left: yAxisWidth + 8,
                        right: 0,
                        child: Row(
                          children: [
                            Expanded(
                              child: CustomPaint(
                                size: Size(plotWidth, 1),
                                painter: DashedLinePainter(
                                  color: const Color(0xFF71717A).withOpacity(0.6),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16171A),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'Goal',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFA1A1AA),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 7 Vertical Bars
                    Positioned(
                      left: yAxisWidth + 8,
                      right: 0,
                      top: 0,
                      bottom: 24,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(7, (i) {
                          final day = i < days.length ? days[i] : null;
                          final isSelected = i == safeIndex;
                          final isLogged = day != null && day.isRecorded;
                          final double val = isLogged ? day.caloriesIn : 0.0;
                          final double barHeight = isLogged
                              ? (val / maxY * maxBarHeight).clamp(4.0, maxBarHeight)
                              : 0.0;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () => onSelectIndex(i),
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isSelected && isLogged)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 4,
                                          )
                                        ],
                                      ),
                                      child: Text(
                                        NumberFormat('#,###').format(val.round()),
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  if (isLogged)
                                    Container(
                                      width: 18,
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFF3F4F6)
                                            : const Color(0xFF3A3D46),
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
                                                  color: Colors.white
                                                      .withOpacity(0.2),
                                                  blurRadius: 8,
                                                )
                                              ]
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
          const SizedBox(height: 12),

          // Selected Date & Value Footer
          Container(
            padding: const EdgeInsets.only(top: 10),
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
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
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
                        color: Colors.white,
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

class DashedLinePainter extends CustomPainter {
  final Color color;

  const DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

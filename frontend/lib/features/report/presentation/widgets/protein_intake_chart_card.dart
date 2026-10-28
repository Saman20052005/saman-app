import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';

class ProteinIntakeChartCard extends StatelessWidget {
  final List<DailyStats> days;
  final double avgProtein;
  final int targetProtein;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;

  const ProteinIntakeChartCard({
    super.key,
    required this.days,
    required this.avgProtein,
    required this.targetProtein,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Calculate domain ceiling (maxY) with headroom
    double maxDataVal = 0;
    for (final d in days) {
      if (d.isRecorded && d.protein > maxDataVal) {
        maxDataVal = d.protein;
      }
    }
    double ceiling = maxDataVal > targetProtein ? maxDataVal : targetProtein.toDouble();
    if (ceiling < 100) ceiling = 100;
    // Add 20% breathing room
    ceiling = (ceiling * 1.2).ceilToDouble();
    final double maxY = ((ceiling / 20).ceil() * 20).toDouble();

    // Selected day info
    final safeIndex = (selectedIndex >= 0 && selectedIndex < days.length)
        ? selectedIndex
        : 0;
    final selectedDay = days.isNotEmpty ? days[safeIndex] : null;

    final String selectedDateLabel = selectedDay != null
        ? DateFormat('EEEE, MMM dd').format(selectedDay.date)
        : '—';

    String selectedValLabel = '—';
    String pctGoalLabel = '';
    if (selectedDay != null) {
      if (selectedDay.isRecorded) {
        final val = selectedDay.protein.round();
        selectedValLabel = '$val g';
        if (targetProtein > 0) {
          final pct = (selectedDay.protein / targetProtein * 100).round();
          pctGoalLabel = '· $pct% goal';
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
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'PROTEIN INTAKE',
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${avgProtein.round()}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'g / day avg',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFFA1A1AA),
                            ),
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
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      targetProtein > 0 ? '$targetProtein g' : 'No goal set',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Painted Line Chart Area
          SizedBox(
            height: 135,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double plotHeight = 100;
                final double plotWidth = constraints.maxWidth;

                return Stack(
                  children: [
                    // Grid lines & Goal Line Custom Painter
                    CustomPaint(
                      size: Size(plotWidth, plotHeight),
                      painter: ProteinChartPainter(
                        days: days,
                        maxY: maxY,
                        targetProtein: targetProtein,
                        selectedIndex: safeIndex,
                      ),
                    ),

                    // Tap Overlay & Day Labels (X-Axis)
                    Positioned(
                      left: 0,
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
                              behavior: HitTestBehavior.opaque,
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

                    // Tap zones over the chart points
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: plotHeight,
                      child: Row(
                        children: List.generate(7, (i) {
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => onSelectIndex(i),
                              behavior: HitTestBehavior.translucent,
                              child: const SizedBox.expand(),
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
                        color: Color(0xFF10B981),
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
                        color: Color(0xFF10B981),
                      ),
                    ),
                    if (pctGoalLabel.isNotEmpty)
                      Text(
                        pctGoalLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
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

class ProteinChartPainter extends CustomPainter {
  final List<DailyStats> days;
  final double maxY;
  final int targetProtein;
  final int selectedIndex;

  ProteinChartPainter({
    required this.days,
    required this.maxY,
    required this.targetProtein,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double plotWidth = size.width;
    final double plotHeight = size.height;

    // 1. Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF23252A)
      ..strokeWidth = 1;

    for (double f = 0.25; f <= 1.0; f += 0.35) {
      final y = plotHeight * f;
      canvas.drawLine(Offset(0, y), Offset(plotWidth, y), gridPaint);
    }

    // 2. Draw Dashed Goal Line at targetProtein
    if (targetProtein > 0 && maxY > 0) {
      final goalY = (1.0 - (targetProtein / maxY).clamp(0.0, 1.0)) * plotHeight;
      if (goalY >= 0 && goalY <= plotHeight) {
        final goalPaint = Paint()
          ..color = const Color(0xFF10B981).withOpacity(0.5)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;

        const dashWidth = 4.0;
        const dashSpace = 3.0;
        double startX = 0;
        while (startX < plotWidth - 55) {
          canvas.drawLine(
            Offset(startX, goalY),
            Offset(startX + dashWidth, goalY),
            goalPaint,
          );
          startX += dashWidth + dashSpace;
        }

        // Draw goal label text
        final textSpan = TextSpan(
          text: '${targetProtein}g GOAL',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF10B981).withOpacity(0.85),
          ),
        );
        final tp = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(plotWidth - tp.width, goalY - tp.height / 2));
      }
    }

    // 3. Compute (x, y) point for each of the 7 days
    final slotWidth = plotWidth / 7;
    final List<Offset?> points = [];

    for (int i = 0; i < 7; i++) {
      final x = slotWidth * i + slotWidth / 2;
      final day = i < days.length ? days[i] : null;

      if (day != null && day.isRecorded && !day.isFuture) {
        final double y = (1.0 - (day.protein / maxY).clamp(0.0, 1.0)) * plotHeight;
        points.add(Offset(x, y.clamp(8.0, plotHeight - 4)));
      } else {
        points.add(null);
        // Draw missing / unlogged dash indicator
        final textSpan = TextSpan(
          text: day != null && day.isFuture ? '·' : '—',
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: day != null && day.isFuture
                ? const Color(0xFF52525B)
                : const Color(0xFF71717A),
          ),
        );
        final tp = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, plotHeight / 2 - tp.height / 2));
      }
    }

    // 4. Group contiguous recorded points into separate segments
    // (CRITICAL RULE: The line MUST NOT connect across missing days)
    List<List<Offset>> segments = [];
    List<Offset> currentSegment = [];

    for (final pt in points) {
      if (pt != null) {
        currentSegment.add(pt);
      } else {
        if (currentSegment.isNotEmpty) {
          segments.add(List.from(currentSegment));
          currentSegment.clear();
        }
      }
    }
    if (currentSegment.isNotEmpty) {
      segments.add(currentSegment);
    }

    // 5. Draw gradient area and line for each contiguous segment
    final linePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final seg in segments) {
      if (seg.isEmpty) continue;

      if (seg.length > 1) {
        // Build path
        final linePath = Path();
        linePath.moveTo(seg[0].dx, seg[0].dy);

        for (int i = 1; i < seg.length; i++) {
          final p0 = seg[i - 1];
          final p1 = seg[i];
          final midX = (p0.dx + p1.dx) / 2;
          linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
        }

        // Draw area fill
        final fillPath = Path.from(linePath);
        fillPath.lineTo(seg.last.dx, plotHeight);
        fillPath.lineTo(seg.first.dx, plotHeight);
        fillPath.close();

        final fillPaint = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x3810B981), // 22% opacity
              Color(0x0010B981),
            ],
          ).createShader(Rect.fromLTWH(
              seg.first.dx, 0, seg.last.dx - seg.first.dx, plotHeight))
          ..style = PaintingStyle.fill;

        canvas.drawPath(fillPath, fillPaint);
        canvas.drawPath(linePath, linePaint);
      }
    }

    // 6. Draw Data Points (circles)
    final nodeOuterPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final nodeInnerPaint = Paint()
      ..color = const Color(0xFF16171A)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      if (pt == null) continue;

      final isSelected = i == selectedIndex;

      if (isSelected) {
        // Selected node: outer emerald ring + white dot
        canvas.drawCircle(pt, 6, Paint()..color = const Color(0xFF16171A));
        canvas.drawCircle(
          pt,
          6,
          Paint()
            ..color = const Color(0xFF10B981)
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(pt, 3, Paint()..color = Colors.white);
      } else {
        // Regular node
        canvas.drawCircle(pt, 3.5, nodeInnerPaint);
        canvas.drawCircle(pt, 3.5, nodeOuterPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ProteinChartPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.maxY != maxY ||
      oldDelegate.targetProtein != targetProtein ||
      oldDelegate.selectedIndex != selectedIndex;
}

import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Weekly Consistency (Performance Chart Panel) for Saman Home.
///
/// Final visual truth: `design/saman-home/home-screen.png`
/// Displays:
/// - Trending header with active sessions count ("3 / 4 sessions")
/// - 3-column metric summary (Sessions, Completion %, Streak)
/// - Custom-painted dual-spline performance chart:
///   - Emerald actual activity line with data dots & active day halo
///   - Dashed target activity line
///   - 7-day horizontal X-axis (Mon - Sun) with today highlighted
/// - Next session preview with "View progress →" link
class WeeklyConsistencyCard extends StatelessWidget {
  const WeeklyConsistencyCard({
    super.key,
    this.completedSessions = 3,
    this.targetSessions = 4,
    this.completionPercentage = 75,
    this.streakDays = 3,
    this.activeDayIndex = 1, // 0 = Mon, 1 = Tue, etc.
    this.nextSessionTitle = 'Upper Hypertrophy',
    this.actualActivityPoints = const [0.35, 0.85, 0.45, 0.68, 0.28, 0.62, 0.50],
    this.targetActivityPoints = const [0.45, 0.60, 0.58, 0.72, 0.65, 0.75, 0.70],
    this.onViewProgressTap,
  });

  final int completedSessions;
  final int targetSessions;
  final int completionPercentage;
  final int streakDays;
  final int activeDayIndex;
  final String nextSessionTitle;
  final List<double> actualActivityPoints;
  final List<double> targetActivityPoints;
  final VoidCallback? onViewProgressTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Container(
        padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
        decoration: BoxDecoration(
          color: SamanHomeTokens.cardSurface,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXl),
          border: Border.all(
            color: SamanHomeTokens.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 1. Header Row ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        size: 16,
                        color: SamanHomeTokens.greenAccent,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'WEEKLY CONSISTENCY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SamanHomeTokens.sectionHeader,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$completedSessions / $targetSessions sessions',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            // ─── 2. 3-Column Summary Metrics ─────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: SamanHomeTokens.borderSubtle,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryMetricColumn(
                      label: 'SESSIONS',
                      value: '$completedSessions / $targetSessions',
                      valueColor: SamanHomeTokens.textWhite,
                      showRightBorder: true,
                    ),
                  ),
                  Expanded(
                    child: _SummaryMetricColumn(
                      label: 'COMPLETION',
                      value: '$completionPercentage%',
                      valueColor: SamanHomeTokens.greenAccent,
                      showRightBorder: true,
                    ),
                  ),
                  Expanded(
                    child: _SummaryMetricColumn(
                      label: 'STREAK',
                      value: '$streakDays days',
                      valueColor: SamanHomeTokens.textWhite,
                      showRightBorder: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            // ─── 3. Dual-Line Performance Chart ──────────────────────
            SizedBox(
              height: 72,
              width: double.infinity,
              child: CustomPaint(
                painter: _WeeklySplineChartPainter(
                  actualPoints: actualActivityPoints,
                  targetPoints: targetActivityPoints,
                  activeDayIndex: activeDayIndex,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // ─── 4. X-Axis Day Labels ────────────────────────────────
            _XAxisDayLabels(activeDayIndex: activeDayIndex),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            const Divider(
              color: SamanHomeTokens.borderSubtle,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: SamanHomeTokens.spacingMd),

            // ─── 5. Next Session Footer ──────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'NEXT SESSION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: SamanHomeTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nextSessionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: SamanHomeTokens.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onViewProgressTap,
                    borderRadius:
                        BorderRadius.circular(SamanHomeTokens.radiusSm),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View progress',
                            style: SamanHomeTokens.linkText,
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: SamanHomeTokens.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetricColumn extends StatelessWidget {
  const _SummaryMetricColumn({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.showRightBorder,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool showRightBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: showRightBorder
          ? const BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: SamanHomeTokens.borderSubtle,
                  width: 1,
                ),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: SamanHomeTokens.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _XAxisDayLabels extends StatelessWidget {
  const _XAxisDayLabels({required this.activeDayIndex});

  final int activeDayIndex;

  static const List<String> _days = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final cellWidth = totalWidth / _days.length;

        return SizedBox(
          width: totalWidth,
          child: Row(
            children: List.generate(_days.length, (index) {
              final isToday = index == activeDayIndex;
              return SizedBox(
                width: cellWidth,
                child: Center(
                  child: Text(
                    _days[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      color: isToday
                          ? SamanHomeTokens.textWhite
                          : SamanHomeTokens.textMuted,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Custom painter rendering smooth cubic Bézier splines for the Weekly Consistency chart.
class _WeeklySplineChartPainter extends CustomPainter {
  const _WeeklySplineChartPainter({
    required this.actualPoints,
    required this.targetPoints,
    required this.activeDayIndex,
  });

  final List<double> actualPoints;
  final List<double> targetPoints;
  final int activeDayIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final paddingHorizontal = size.width / 14;
    final usableWidth = size.width - (paddingHorizontal * 2);
    final count = actualPoints.length;

    // ─── 1. Background Grid Lines ─────────────────────────────────────
    final gridPaint = Paint()
      ..color = SamanHomeTokens.chartGrid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      _drawDashedLine(
        canvas: canvas,
        p1: Offset(paddingHorizontal, y),
        p2: Offset(size.width - paddingHorizontal, y),
        dashWidth: 3,
        dashSpace: 3,
        paint: gridPaint,
      );
    }

    if (count < 2) return;

    // Map 0..1 values to canvas coordinate points
    List<Offset> computeOffsets(List<double> values) {
      return List.generate(values.length, (i) {
        final x = paddingHorizontal + (i / (count - 1)) * usableWidth;
        final clamped = values[i].clamp(0.0, 1.0);
        // invert y: 1.0 is top (high activity), 0.0 is bottom
        final y = size.height - (clamped * (size.height - 16)) - 8;
        return Offset(x, y);
      });
    }

    final targetOffsets = computeOffsets(targetPoints);
    final actualOffsets = computeOffsets(actualPoints);

    // ─── 2. Target Spline (Dashed Gray Curve) ─────────────────────────
    final targetPath = _createSmoothSplinePath(targetOffsets);
    final targetPaint = Paint()
      ..color = SamanHomeTokens.chartTargetDashed
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    _drawDashedPath(canvas, targetPath, targetPaint, 3.5, 3.5);

    // ─── 3. Actual Spline (Solid Emerald Curve) ───────────────────────
    final actualPath = _createSmoothSplinePath(actualOffsets);
    final actualPaint = Paint()
      ..color = SamanHomeTokens.chartActualLine
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(actualPath, actualPaint);

    // ─── 4. Data Dots & Active Day Indicator ──────────────────────────
    final dotPaint = Paint()
      ..color = SamanHomeTokens.chartActualLine
      ..style = PaintingStyle.fill;

    for (int i = 0; i < actualOffsets.length; i++) {
      final point = actualOffsets[i];
      if (i == activeDayIndex) {
        // Outer halo
        final haloPaint = Paint()
          ..color = SamanHomeTokens.chartActualLine
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        final bgPaint = Paint()
          ..color = SamanHomeTokens.cardSurface
          ..style = PaintingStyle.fill;

        canvas.drawCircle(point, 5.0, bgPaint);
        canvas.drawCircle(point, 5.0, haloPaint);

        // Center white dot
        final centerDot = Paint()
          ..color = SamanHomeTokens.textWhite
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, 2.5, centerDot);
      } else {
        canvas.drawCircle(point, 3.0, dotPaint);
      }
    }
  }

  Path _createSmoothSplinePath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;

    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = (i < points.length - 2) ? points[i + 2] : p2;

      // Catmull-Rom to Cubic Bézier conversion
      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;

      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawDashedLine({
    required Canvas canvas,
    required Offset p1,
    required Offset p2,
    required double dashWidth,
    required double dashSpace,
    required Paint paint,
  }) {
    final max = (p2 - p1).distance;
    final normalized = (p2 - p1) / max;
    double current = 0;

    while (current < max) {
      final start = p1 + normalized * current;
      final end = p1 + normalized * ((current + dashWidth).clamp(0.0, max));
      canvas.drawLine(start, end, paint);
      current += dashWidth + dashSpace;
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path source,
    Paint paint,
    double dashWidth,
    double dashSpace,
  ) {
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = dashWidth.clamp(0.0, metric.length - distance);
        final extractPath = metric.extractPath(distance, distance + length);
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklySplineChartPainter oldDelegate) {
    return oldDelegate.actualPoints != actualPoints ||
        oldDelegate.targetPoints != targetPoints ||
        oldDelegate.activeDayIndex != activeDayIndex;
  }
}

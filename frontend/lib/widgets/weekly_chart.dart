// [File: lib/widgets/weekly_chart.dart]
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui; // ✅ IMPORT LẠI dart:ui để dùng cho TextPainter
import '../models/report_model.dart';

class WeeklyChart extends StatelessWidget {
  final List<DailyReportItem> data;
  final int targetValue;
  final String label;
  final Color color;

  const WeeklyChart({
    super.key,
    required this.data,
    required this.targetValue,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Tìm Max value
    double maxDataVal = data.fold(0.0, (max, item) {
      final val = (label.contains("Calories"))
          ? item.calories.toDouble()
          : item.protein;
      return val > max ? val : max;
    });

    // MaxScale logic
    double maxScale =
        maxDataVal > targetValue ? maxDataVal : targetValue.toDouble();
    if (maxScale == 0) maxScale = 100;
    maxScale = maxScale * 1.2;

    const double chartHeight = 180;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HEADER
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Row(
              children: [
                _buildLegend(Colors.red.shade300, "Goal", isDashed: true),
                const SizedBox(width: 12),
                _buildLegend(color, "Actual", isDashed: false),
              ],
            )
          ],
        ),
        const SizedBox(height: 20),

        // BODY
        SizedBox(
          height: chartHeight + 30,
          child: CustomPaint(
            size: const Size(double.infinity, chartHeight),
            painter: LineChartPainter(
              data: data,
              targetValue: targetValue,
              maxScale: maxScale,
              color: color,
              labelType: label.contains("Calories") ? "kcal" : "g",
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(Color color, String text, {required bool isDashed}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            border: isDashed
                ? Border(
                    bottom: BorderSide(
                        color: color, width: 2, style: BorderStyle.none))
                : null,
          ),
          child: isDashed
              ? CustomPaint(painter: LegendDashedPainter(color: color))
              : null,
        ),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// --- PAINTER CHÍNH ---
class LineChartPainter extends CustomPainter {
  final List<DailyReportItem> data;
  final int targetValue;
  final double maxScale;
  final Color color;
  final String labelType;

  LineChartPainter({
    required this.data,
    required this.targetValue,
    required this.maxScale,
    required this.color,
    required this.labelType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height - 30;

    // Dùng .withValues cho Flutter mới
    final Paint targetPaint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint dotPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final Paint dotBorderPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 1. VẼ ĐƯỜNG TARGET (GOAL)
    if (targetValue > 0) {
      final double targetY = h - (targetValue / maxScale * h);
      _drawDashedLine(
          canvas, targetPaint, Offset(0, targetY), Offset(w, targetY));

      final TextSpan span = TextSpan(
          style: TextStyle(color: Colors.red.shade300, fontSize: 10),
          text: "$targetValue");

      final TextPainter tp = TextPainter(
          text: span,
          textAlign: TextAlign.right,
          // ✅ FIX QUAN TRỌNG: Dùng ui.TextDirection
          textDirection: ui.TextDirection.ltr);

      tp.layout();
      tp.paint(canvas, Offset(w - tp.width, targetY - 12));
    }

    // 2. TÍNH TOÁN TỌA ĐỘ
    if (data.isEmpty) return;

    final double stepX = w / (data.length - 1 > 0 ? data.length - 1 : 1);

    List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final double val =
          (labelType == "kcal") ? item.calories.toDouble() : item.protein;

      final double x = i * stepX;
      final double y = h - (val / maxScale * h);
      points.add(Offset(x, y));

      // 3. VẼ NHÃN NGÀY
      DateTime d = DateTime.tryParse(item.date) ?? DateTime.now();
      String dayLabel = DateFormat('E').format(d);

      final TextSpan daySpan = TextSpan(
          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
          text: dayLabel);
      final TextPainter dayTp = TextPainter(
          text: daySpan,
          textAlign: TextAlign.center,
          // ✅ FIX QUAN TRỌNG: Dùng ui.TextDirection
          textDirection: ui.TextDirection.ltr);
      dayTp.layout();
      dayTp.paint(canvas, Offset(x - dayTp.width / 2, h + 10));
    }

    // 4. VẼ ĐƯỜNG NỐI (DATA LINE)
    if (points.isNotEmpty) {
      final Path path = Path();
      path.moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 5. VẼ DOTS
    for (var point in points) {
      canvas.drawCircle(point, 4, dotPaint);
      canvas.drawCircle(point, 4, dotBorderPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Paint paint, Offset p1, Offset p2) {
    double dashWidth = 6, dashSpace = 4, startX = p1.dx;
    final path = Path();
    while (startX < p2.dx) {
      path.moveTo(startX, p1.dy);
      path.lineTo(startX + dashWidth, p1.dy);
      startX += dashWidth + dashSpace;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- LEGEND PAINTER ---
class LegendDashedPainter extends CustomPainter {
  final Color color;
  LegendDashedPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(4, size.height / 2), paint);
    canvas.drawLine(
        Offset(8, size.height / 2), Offset(12, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

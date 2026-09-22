// lib/widgets/trend_chart_card.dart
// BUG FIX: hardcoded white background (line 46 gốc) → theme-aware
// BUG FIX: shadow implementation inconsistent → chuẩn hóa
// UI: giữ nguyên 100% — chart card, shadow depth, layout
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/report_model.dart';

class TrendChartCard extends StatefulWidget {
  final String title;
  final List<DailyReportItem> data;
  final double targetValue;
  final Color baseColor;
  final String unit;

  const TrendChartCard({
    super.key,
    required this.title,
    required this.data,
    required this.targetValue,
    required this.baseColor,
    required this.unit,
  });

  @override
  State<TrendChartCard> createState() => _TrendChartCardState();
}

class _TrendChartCardState extends State<TrendChartCard> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<AppThemeExtension>()!;

    // Tìm max Y để scale biểu đồ không bị tràn
    double maxY = widget.data.fold(0, (max, e) {
      double val =
          widget.title.contains("Protein") ? e.protein : e.calories.toDouble();
      return val > max ? val : max;
    });

    // Keep an empty or all-zero report renderable: fl_chart requires a
    // positive range and an empty series cannot have a negative max X.
    if (widget.targetValue > maxY) maxY = widget.targetValue;
    maxY = maxY > 0 ? maxY * 1.2 : 1;
    final maxX =
        widget.data.length > 1 ? (widget.data.length - 1).toDouble() : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header của Card
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Target: ${widget.targetValue.toInt()} ${widget.unit}",
                    style: TextStyle(fontSize: 12, color: colors.secondary),
                  ),
                ],
              ),
              _buildLegend(),
            ],
          ),
          const SizedBox(height: 30),

          // Chart Area
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4, // Chia làm 4 dòng kẻ ngang
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: tokens.hairline,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false)), // Ẩn trục Y cho clean
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < widget.data.length) {
                          DateTime date =
                              DateTime.tryParse(widget.data[index].date) ??
                                  DateTime.now();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('E').format(
                                  date)[0], // Lấy chữ cái đầu (M, T, W...)
                              style: TextStyle(
                                  color: colors.secondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                // Đường Goal (Nét đứt màu xám/đỏ nhạt)
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: widget.targetValue,
                      color: widget.baseColor.withOpacity(0.3),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 5, bottom: 5),
                        style: TextStyle(
                            color: widget.baseColor.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        labelResolver: (line) => "GOAL",
                      ),
                    ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: widget.data.asMap().entries.map((e) {
                      double val = widget.title.contains("Protein")
                          ? e.value.protein
                          : e.value.calories.toDouble();
                      return FlSpot(e.key.toDouble(), val);
                    }).toList(),
                    isCurved: true, // ĐƯỜNG CONG (SPLINE)
                    color: widget.baseColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(
                        show: false), // Ẩn dot mặc định, chỉ hiện khi chạm
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          widget.baseColor.withOpacity(0.3),
                          widget.baseColor.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                // Hiệu ứng khi chạm (Tooltip)
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: colors.onSurface,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                      return touchedBarSpots.map((barSpot) {
                        return LineTooltipItem(
                          "${barSpot.y.toInt()} ${widget.unit}",
                          TextStyle(
                              color: colors.surface,
                              fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final tokens = Theme.of(context).extension<AppThemeExtension>()!;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: widget.baseColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text("Actual", style: TextStyle(fontSize: 12, color: tokens.inkMuted)),
      ],
    );
  }
}

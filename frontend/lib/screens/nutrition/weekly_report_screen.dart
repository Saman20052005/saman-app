import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // thêm vào pubspec.yaml
import '../../../models/nutrition_model.dart';
import '../../../services/nutrition_service.dart';

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  WeeklyReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    // Lấy ngày đầu tuần hiện tại (Monday)
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startDate =
        '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

    try {
      final service = NutritionService();
      final response = await service.getWeeklyReport(startDate);
      setState(() {
        _report = WeeklyReport.fromJson(response);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo tuần')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Lỗi: $_error'))
              : _buildReport(),
    );
  }

  Widget _buildReport() {
    final r = _report!;
    return RefreshIndicator(
      onRefresh: _loadReport,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          _WeekRangeHeader(
            startDate: r.startDate,
            endDate: r.endDate,
            daysLogged: r.daysLogged,
          ),
          const SizedBox(height: 20),

          // Calories bar chart
          _SectionTitle('Calories theo ngày'),
          const SizedBox(height: 8),
          _CaloriesBarChart(
            daily: r.daily,
            targetCalories: r.macroTargets.calories.toDouble(),
          ),
          const SizedBox(height: 24),

          // Macro tổng tuần
          _SectionTitle('Macro tổng tuần'),
          const SizedBox(height: 8),
          _MacroSummaryRow(
            totals: r.weeklyTotals,
            targets: r.macroTargets,
          ),
          const SizedBox(height: 24),

          // Average calories
          _AverageCaloriesCard(
            avg: r.avgCalories,
            target: r.macroTargets.calories.toDouble(),
          ),
          const SizedBox(height: 24),

          // Daily breakdown list
          _SectionTitle('Chi tiết từng ngày'),
          const SizedBox(height: 8),
          ...r.daily.map((d) => _DailyRow(day: d, target: r.macroTargets)),
        ],
      ),
    );
  }
}

// ── SECTION COMPONENTS ────────────────────────────────────────────────────────

class _WeekRangeHeader extends StatelessWidget {
  final String startDate, endDate;
  final int daysLogged;

  const _WeekRangeHeader({
    required this.startDate,
    required this.endDate,
    required this.daysLogged,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$startDate → $endDate',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Chip(label: Text('$daysLogged/7 ngày')),
        ],
      );
}

class _CaloriesBarChart extends StatelessWidget {
  final List<DailyNutrition> daily;
  final double targetCalories;

  const _CaloriesBarChart({required this.daily, required this.targetCalories});

  @override
  Widget build(BuildContext context) {
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: (targetCalories * 1.3).ceilToDouble(),
          barGroups: daily.asMap().entries.map((e) {
            final idx = e.key;
            final d = e.value;
            return BarChartGroupData(
              x: idx,
              barRods: [
                BarChartRodData(
                  toY: d.calories,
                  color: d.calories > targetCalories
                      ? Colors.red.shade400
                      : Colors.blue.shade400,
                  width: 18,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),

          // Target line
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: targetCalories,
              color: Colors.orange,
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                labelResolver: (_) => '${targetCalories.toInt()} target',
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
            ),
          ]),

          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Text(
                  days[v.toInt() % 7],
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

class _MacroSummaryRow extends StatelessWidget {
  final MacroTargets totals, targets;
  const _MacroSummaryRow({required this.totals, required this.targets});

  @override
  Widget build(BuildContext context) => Row(children: [
        _MacroProgressCard(
          label: 'Protein',
          actual: totals.protein,
          target: targets.protein * 7, // target tuần = target ngày × 7
          color: Colors.blue,
          unit: 'g',
        ),
        const SizedBox(width: 8),
        _MacroProgressCard(
          label: 'Carbs',
          actual: totals.carbs,
          target: targets.carbs * 7,
          color: Colors.orange,
          unit: 'g',
        ),
        const SizedBox(width: 8),
        _MacroProgressCard(
          label: 'Fat',
          actual: totals.fat,
          target: targets.fat * 7,
          color: Colors.red,
          unit: 'g',
        ),
      ]);
}

class _MacroProgressCard extends StatelessWidget {
  final String label, unit;
  final double actual, target;
  final Color color;
  const _MacroProgressCard({
    required this.label,
    required this.unit,
    required this.actual,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text(
            '${actual.toStringAsFixed(0)}$unit',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toInt()}% of ${target.toStringAsFixed(0)}$unit',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ]),
      ),
    );
  }
}

class _AverageCaloriesCard extends StatelessWidget {
  final double avg, target;
  const _AverageCaloriesCard({required this.avg, required this.target});

  @override
  Widget build(BuildContext context) {
    final diff = avg - target;
    final isOver = diff > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Trung bình / ngày', style: TextStyle(fontSize: 13)),
            Text(
              '${avg.toStringAsFixed(0)} kcal',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('So với target', style: TextStyle(fontSize: 13)),
            Text(
              '${isOver ? "+" : ""}${diff.toStringAsFixed(0)} kcal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isOver ? Colors.red : Colors.green,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final DailyNutrition day;
  final MacroTargets target;
  const _DailyRow({required this.day, required this.target});

  @override
  Widget build(BuildContext context) {
    final pct = target.calories > 0
        ? (day.calories / target.calories).clamp(0.0, 1.5)
        : 0.0;
    final over = day.calories > target.calories;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: day.hasData ? null : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        // Ngày
        SizedBox(
          width: 36,
          child: Text(
            day.date.substring(8), // lấy DD
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        // Progress bar
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(
              value: pct.toDouble(),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                over ? Colors.red.shade400 : Colors.blue.shade400,
              ),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              day.hasData
                  ? 'P${day.protein.toStringAsFixed(0)}g  C${day.carbs.toStringAsFixed(0)}g  F${day.fat.toStringAsFixed(0)}g'
                  : 'Chưa có dữ liệu',
              style: TextStyle(
                fontSize: 11,
                color:
                    day.hasData ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        // Calories
        Text(
          day.hasData ? '${day.calories.toStringAsFixed(0)}\nkcal' : '—',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: over ? Colors.red : null,
          ),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      );
}

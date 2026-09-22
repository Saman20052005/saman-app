import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // thêm vào pubspec.yaml
import '../../../config/app_theme.dart';
import '../../../models/nutrition_model.dart';
import '../../../services/nutrition_service.dart';
import '../../../widgets/nutrition_primitives.dart';

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
      if (!mounted) return;
      setState(() {
        _report = WeeklyReport.fromJson(response);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Báo cáo tuần'),
        backgroundColor: context.bgColor,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Không thể tải báo cáo tuần.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: tokens.inkMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _loadReport();
                          },
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildReport(),
    );
  }

  Widget _buildReport() {
    final r = _report!;
    return RefreshIndicator(
      onRefresh: _loadReport,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const NutritionSectionHeader(label: 'Week'),
          const SizedBox(height: AppSpacing.md),
          _WeekRangeHeader(
            startDate: r.startDate,
            endDate: r.endDate,
            daysLogged: r.daysLogged,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Calories bar chart
          const NutritionSectionHeader(label: 'Calories theo ngày'),
          const SizedBox(height: AppSpacing.sm),
          _CaloriesBarChart(
            daily: r.daily,
            targetCalories: r.macroTargets.calories.toDouble(),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Macro tổng tuần
          const NutritionSectionHeader(label: 'Macro tổng tuần'),
          const SizedBox(height: AppSpacing.sm),
          _MacroSummaryRow(
            totals: r.weeklyTotals,
            targets: r.macroTargets,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Average calories
          _AverageCaloriesCard(
            avg: r.avgCalories,
            target: r.macroTargets.calories.toDouble(),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Daily breakdown list
          const NutritionSectionHeader(label: 'Chi tiết từng ngày'),
          const SizedBox(height: AppSpacing.sm),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              '$startDate → $endDate',
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: tokens.hairline),
            ),
            child: Text('$daysLogged/7 ngày', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _CaloriesBarChart extends StatelessWidget {
  final List<DailyNutrition> daily;
  final double targetCalories;

  const _CaloriesBarChart({required this.daily, required this.targetCalories});

  @override
  Widget build(BuildContext context) {
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;
    final maxDailyCalories = daily.fold<double>(
      1,
      (maximum, day) => day.calories > maximum ? day.calories : maximum,
    );
    final chartMax = (targetCalories > maxDailyCalories
            ? targetCalories
            : maxDailyCalories) *
        1.2;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.hairline),
      ),
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: chartMax.ceilToDouble(),
            barGroups: daily.asMap().entries.map((e) {
              final idx = e.key;
              final d = e.value;
              return BarChartGroupData(
                x: idx,
                barRods: [
                  BarChartRodData(
                    toY: d.calories,
                    color: d.calories > targetCalories
                        ? colors.error
                        : colors.primary,
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.sm),
                    ),
                  ),
                ],
              );
            }).toList(),

            // Target line
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(
                y: targetCalories,
                color: tokens.warning,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  labelResolver: (_) => '${targetCalories.toInt()} target',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.warning,
                  ),
                ),
              ),
            ]),

            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Text(
                    days[v.toInt() % 7],
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

class _MacroSummaryRow extends StatelessWidget {
  final MacroTargets totals, targets;
  const _MacroSummaryRow({required this.totals, required this.targets});

  @override
  Widget build(BuildContext context) {
    final proteinTarget = targets.protein * 7;
    final carbsTarget = targets.carbs * 7;
    final fatTarget = targets.fat * 7;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Theme.of(context).extension<AppThemeExtension>()!.hairline,
        ),
      ),
      child: Column(
        children: [
          NutritionMacroProgress(
            label: 'Protein',
            consumed: '${totals.protein.toStringAsFixed(0)}g',
            target: '${proteinTarget.toStringAsFixed(0)}g',
            progress: proteinTarget > 0
                ? (totals.protein / proteinTarget).clamp(0.0, 1.0)
                : 0.0,
            remaining:
                '${((proteinTarget - totals.protein).clamp(0, proteinTarget)).toStringAsFixed(0)}g remaining',
          ),
          const SizedBox(height: AppSpacing.lg),
          NutritionMacroProgress(
            label: 'Carbs',
            consumed: '${totals.carbs.toStringAsFixed(0)}g',
            target: '${carbsTarget.toStringAsFixed(0)}g',
            progress: carbsTarget > 0
                ? (totals.carbs / carbsTarget).clamp(0.0, 1.0)
                : 0.0,
            remaining:
                '${((carbsTarget - totals.carbs).clamp(0, carbsTarget)).toStringAsFixed(0)}g remaining',
          ),
          const SizedBox(height: AppSpacing.lg),
          NutritionMacroProgress(
            label: 'Fat',
            consumed: '${totals.fat.toStringAsFixed(0)}g',
            target: '${fatTarget.toStringAsFixed(0)}g',
            progress:
                fatTarget > 0 ? (totals.fat / fatTarget).clamp(0.0, 1.0) : 0.0,
            remaining:
                '${((fatTarget - totals.fat).clamp(0, fatTarget)).toStringAsFixed(0)}g remaining',
          ),
        ],
      ),
    );
  }
}

class _AverageCaloriesCard extends StatelessWidget {
  final double avg, target;
  const _AverageCaloriesCard({required this.avg, required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;
    final diff = avg - target;
    final isOver = diff > 0;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Trung bình / ngày', style: tokens.labelCaps),
            Text(
              '${avg.toStringAsFixed(0)} kcal',
              style: tokens.statValue,
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('So với target', style: tokens.labelCaps),
            Text(
              '${isOver ? "+" : ""}${diff.toStringAsFixed(0)} kcal',
              style: theme.textTheme.titleMedium?.copyWith(
                color: isOver ? colors.error : colors.primary,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;
    final pct = target.calories > 0
        ? (day.calories / target.calories).clamp(0.0, 1.5)
        : 0.0;
    final over = day.calories > target.calories;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: day.hasData ? colors.surface : tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(children: [
        // Ngày
        SizedBox(
          width: 36,
          child: Text(
            day.date.substring(8), // lấy DD
            style: theme.textTheme.titleMedium,
          ),
        ),
        // Progress bar
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(
              value: pct.toDouble(),
              backgroundColor: tokens.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                over ? colors.error : colors.primary,
              ),
              minHeight: AppSpacing.sm,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              day.hasData
                  ? 'P${day.protein.toStringAsFixed(0)}g  C${day.carbs.toStringAsFixed(0)}g  F${day.fat.toStringAsFixed(0)}g'
                  : 'Chưa có dữ liệu',
              style: theme.textTheme.bodySmall?.copyWith(
                color: day.hasData ? tokens.inkMuted : tokens.inkSubtle,
              ),
            ),
          ]),
        ),
        const SizedBox(width: AppSpacing.md),
        // Calories
        Text(
          day.hasData ? '${day.calories.toStringAsFixed(0)}\nkcal' : '—',
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: over ? colors.error : colors.onSurface,
          ),
        ),
      ]),
    );
  }
}

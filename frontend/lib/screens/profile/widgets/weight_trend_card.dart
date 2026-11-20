import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_theme.dart';
import '../../../features/profile/presentation/providers/weight_history_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/saman_feedback_snackbar.dart';

/// Screen 06 Telemetry: Weight Trend Card under Calm Athleticism.
class WeightTrendCard extends ConsumerWidget {
  const WeightTrendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final selectedDays = ref.watch(weightHistoryDaysProvider);
    final historyAsync = ref.watch(weightHistoryProvider);
    final profileState = ref.watch(profileProvider);

    final weightData = historyAsync.valueOrNull;
    final currentWeight = profileState.profile.weight;
    final latestWeight = weightData?.latestWeightKg ?? currentWeight;
    final delta = weightData?.deltaKg;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: WEIGHT TREND + Pill Filter (7D | 30D | 90D) + + Log
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WEIGHT TREND',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPillFilter(context, ref, selectedDays),
                      const SizedBox(width: 6),
                      _buildLogButton(context, ref, currentWeight),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Latest weight + Delta badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                latestWeight != null && latestWeight > 0
                    ? latestWeight.toStringAsFixed(1)
                    : '—',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'kg',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (delta <= 0 ? palette.accent : palette.amber)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${delta > 0 ? "+" : ""}${delta.toStringAsFixed(1)} kg',
                    style: TextStyle(
                      color: delta <= 0 ? palette.accent : palette.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Chart Area (~152px height)
          SizedBox(
            height: 152,
            child: _buildChartArea(context, historyAsync, weightData),
          ),
        ],
      ),
    );
  }

  Widget _buildPillFilter(
      BuildContext context, WidgetRef ref, int selectedDays) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.isDark
            ? const Color(0xFF202227)
            : palette.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [7, 30, 90].map((days) {
          final isSelected = selectedDays == days;
          return GestureDetector(
            onTap: () {
              ref.read(weightHistoryDaysProvider.notifier).state = days;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? (palette.isDark
                        ? const Color(0xFF26282F)
                        : palette.surface)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: isSelected
                    ? Border.all(
                        color: palette.accent.withOpacity(0.4),
                        width: 1,
                      )
                    : null,
              ),
              child: Text(
                '${days}D',
                style: TextStyle(
                  color: isSelected ? textPrimary : palette.textSecondary,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogButton(
      BuildContext context, WidgetRef ref, double? currentWeight) {
    final palette = context.samanColors;
    return GestureDetector(
      key: const Key('weight_trend_log_button'),
      onTap: () => _showLogWeightBottomSheet(context, ref, currentWeight),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: palette.accent.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 12, color: palette.accent),
            const SizedBox(width: 2),
            Text(
              'Log',
              style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatShortDate(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return rawDate;
    final dd = parsed.day.toString().padLeft(2, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  Widget _buildChartArea(
    BuildContext context,
    AsyncValue<WeightHistoryData> historyAsync,
    WeightHistoryData? data,
  ) {
    final palette = context.samanColors;
    final tooltipBg =
        palette.isDark ? const Color(0xFF26282F) : const Color(0xFF0F172A);
    final entries = data?.entries ?? const [];
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Chưa có lịch sử cân nặng • Bấm + Log để bắt đầu',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (entries.length == 1) {
      final w = entries.first.weightKg;
      final minY = w - 2.0;
      final maxY = w + 2.0;

      return LineChart(
        LineChartData(
          minX: 0,
          maxX: 1,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1.0,
            getDrawingHorizontalLine: (_) => FlLine(
              color: palette.border,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: 1.0,
                getTitlesWidget: (value, meta) {
                  if ((value - meta.min).abs() < 0.01 ||
                      (value - meta.max).abs() < 0.01) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      value.toStringAsFixed(1),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() != 0 || value != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _formatShortDate(entries.first.date),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: tooltipBg,
              tooltipRoundedRadius: 8,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)} kg\n${entries.first.date}',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
            handleBuiltInTouches: true,
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [FlSpot(0, w)],
              isCurved: true,
              color: palette.accent,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 4,
                  color: palette.accent,
                  strokeWidth: 2,
                  strokeColor: palette.isDark ? Colors.white : palette.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    palette.accent.withOpacity(0.15),
                    palette.accent.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // entries.length > 1
    final weights = entries.map((e) => e.weightKg).toList();
    double minY = weights.reduce((a, b) => a < b ? a : b);
    double maxY = weights.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      minY -= 2.0;
      maxY += 2.0;
    } else {
      final padding = (maxY - minY) * 0.15;
      minY -= padding;
      maxY += padding;
    }

    final spots = entries
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.weightKg))
        .toList();
    final maxX = (entries.length - 1).toDouble();
    final yInterval = (maxY - minY) > 0 ? (maxY - minY) / 3 : 1.0;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: palette.border,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                if ((value - meta.min).abs() < 0.01 ||
                    (value - meta.max).abs() < 0.01) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value != value.roundToDouble()) {
                  return const SizedBox.shrink();
                }
                final idx = value.toInt();
                final lastIdx = entries.length - 1;
                final midIdx = entries.length >= 3 ? entries.length ~/ 2 : -1;
                if (idx != 0 && idx != midIdx && idx != lastIdx) {
                  return const SizedBox.shrink();
                }
                if (idx < 0 || idx >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _formatShortDate(entries[idx].date),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: tooltipBg,
            tooltipRoundedRadius: 8,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.spotIndex;
                final dateStr =
                    (idx >= 0 && idx < entries.length) ? entries[idx].date : '';
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} kg${dateStr.isNotEmpty ? '\n$dateStr' : ''}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: palette.accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  palette.accent.withOpacity(0.15),
                  palette.accent.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogWeightBottomSheet(
    BuildContext context,
    WidgetRef ref,
    double? currentWeight,
  ) {
    final palette = context.samanColors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LogWeightBottomSheet(
        parentContext: context,
        currentWeight: currentWeight,
        ref: ref,
      ),
    );
  }
}

class _LogWeightBottomSheet extends StatefulWidget {
  final BuildContext parentContext;
  final double? currentWeight;
  final WidgetRef ref;

  const _LogWeightBottomSheet({
    required this.parentContext,
    required this.currentWeight,
    required this.ref,
  });

  @override
  State<_LogWeightBottomSheet> createState() => _LogWeightBottomSheetState();
}

class _LogWeightBottomSheetState extends State<_LogWeightBottomSheet> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.currentWeight != null && widget.currentWeight! > 0
        ? widget.currentWeight!.toStringAsFixed(1)
        : '';
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final text = _controller.text.trim().replaceAll(',', '.');
    final weight = double.tryParse(text);

    if (weight == null || weight <= 0 || weight > 500) {
      setState(() {
        _errorMessage = 'Cân nặng phải lớn hơn 0 và nhỏ hơn hoặc bằng 500 kg';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await logManualWeight(widget.ref, weightKg: weight);
      if (mounted) {
        Navigator.of(context).pop();
        if (widget.parentContext.mounted) {
          SamanFeedbackSnackBar.show(
            widget.parentContext,
            message: 'Đã cập nhật cân nặng thành công',
            type: FeedbackType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Không thể lưu cân nặng: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final handleColor =
        palette.isDark ? const Color(0xFF374151) : palette.border;
    final fieldFill =
        palette.isDark ? const Color(0xFF26282F) : palette.surfaceElevated;
    final fieldBorder =
        palette.isDark ? const Color(0xFF374151) : palette.border;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomInset > 0 ? bottomInset + 16 : 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Log weight',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: palette.textSecondary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('weight_input_field'),
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: TextStyle(
              color: textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: fieldFill,
              hintText: 'VD: 70.5',
              hintStyle: TextStyle(color: palette.textMuted, fontSize: 16),
              suffixText: 'kg',
              suffixStyle: TextStyle(
                color: palette.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accent),
              ),
              errorText: _errorMessage,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              key: const Key('save_weight_button'),
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                disabledBackgroundColor: palette.accent.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.onAccent,
                      ),
                    )
                  : Text(
                      'Save weight',
                      style: TextStyle(
                        color: palette.onAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

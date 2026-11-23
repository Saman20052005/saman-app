import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import '../../../../config/app_theme.dart';
import 'calories_consumed_chart_card.dart';

class ReportNutritionTab extends StatelessWidget {
  final WeeklyReportEntity report;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;

  const ReportNutritionTab({
    super.key,
    required this.report,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    // Macro progress percentages
    final double proteinRatio = report.targetProtein > 0
        ? (report.avgProtein / report.targetProtein).clamp(0.0, 1.0)
        : 0.0;
    final double carbsRatio = report.targetCarbs > 0
        ? (report.avgCarbs / report.targetCarbs).clamp(0.0, 1.0)
        : 0.0;
    final double fatRatio = report.targetFat > 0
        ? (report.avgFat / report.targetFat).clamp(0.0, 1.0)
        : 0.0;

    // Peak protein observation
    DailyStats? peakDay;
    for (final d in report.days) {
      if (d.isRecorded) {
        if (peakDay == null || d.protein > peakDay.protein) {
          peakDay = d;
        }
      }
    }

    String proteinObservation;
    if (peakDay != null && peakDay.protein > 0) {
      final dayName = DateFormat('EEEE').format(peakDay.date);
      proteinObservation =
          'Highest protein intake observed on $dayName: ${peakDay.protein.round()}g recorded.';
    } else {
      proteinObservation =
          'Log your daily meals to monitor protein distribution and lean mass recovery.';
    }

    // Water snapshot
    final double waterLiters = report.avgWaterMl / 1000.0;
    final double targetWaterLiters = report.targetWaterMl / 1000.0;
    final double waterRatio = targetWaterLiters > 0
        ? (waterLiters / targetWaterLiters).clamp(0.0, 1.0)
        : 0.0;

    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final cardBg = isDark ? const Color(0xFF16171A) : p.surface;
    final borderCol = isDark ? const Color(0xFF26282F) : p.border;
    final headingCol = isDark ? const Color(0xFFD1D5DB) : p.textPrimary;
    final valueCol = isDark ? Colors.white : p.textPrimary;
    final subCol = isDark ? const Color(0xFFA1A1AA) : p.textSecondary;
    final emerald = isDark ? const Color(0xFF10B981) : p.accent;
    final amber = isDark ? const Color(0xFFF59E0B) : p.amber;
    final violet = isDark ? const Color(0xFFA855F7) : const Color(0xFF9333EA);
    final waterTrack = isDark ? const Color(0xFF26282F) : p.border;
    final waterFill = isDark ? const Color(0xFFE5E7EB) : p.cyan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Macro Split & Adherence Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NUTRITION BREAKDOWN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: headingCol,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Macro split & calorie adherence',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: subCol,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: emerald.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: emerald.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      '${report.daysLogged} of 7 logged',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: emerald,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3 Macro Cards (Protein, Carbs, Fats)
              Row(
                children: [
                  // Protein
                  Expanded(
                    child: _MacroProgressTile(
                      label: 'PROTEIN',
                      current: report.avgProtein.round(),
                      target: report.targetProtein,
                      ratio: proteinRatio,
                      color: emerald,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Carbs
                  Expanded(
                    child: _MacroProgressTile(
                      label: 'CARBS',
                      current: report.avgCarbs.round(),
                      target: report.targetCarbs,
                      ratio: carbsRatio,
                      color: amber,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Fats
                  Expanded(
                    child: _MacroProgressTile(
                      label: 'FATS',
                      current: report.avgFat.round(),
                      target: report.targetFat,
                      ratio: fatRatio,
                      color: violet,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Calories Consumed Chart
        CaloriesConsumedChartCard(
          days: report.days,
          avgCalories: report.avgCaloriesIn,
          targetCalories: report.targetCalories,
          selectedIndex: selectedIndex,
          onSelectIndex: onSelectIndex,
        ),
        const SizedBox(height: 16),

        // 3. Protein Deep-Dive Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PROTEIN INTAKE DISTRIBUTION',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: emerald,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${report.avgProtein.round()}g',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: valueCol,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'daily avg',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subCol,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: emerald.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: emerald.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      'Target ${report.targetProtein}g',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: emerald,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                proteinObservation,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: subCol,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Micronutrient & Water Snapshot
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVERAGE WATER HYDRATION',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: subCol,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          waterLiters > 0
                              ? '${waterLiters.toStringAsFixed(1)} L'
                              : '—',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: valueCol,
                          ),
                        ),
                        if (waterLiters > 0 && targetWaterLiters > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '/ ${targetWaterLiters.toStringAsFixed(1)} L',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: subCol,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (waterLiters > 0)
                Container(
                  width: 90,
                  height: 6,
                  decoration: BoxDecoration(
                    color: waterTrack,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: waterRatio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: waterFill,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacroProgressTile extends StatelessWidget {
  final String label;
  final int current;
  final int target;
  final double ratio;
  final Color color;

  const _MacroProgressTile({
    required this.label,
    required this.current,
    required this.target,
    required this.ratio,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final tileBg = isDark ? const Color(0xFF101114) : p.surfaceElevated;
    final tileBorder = isDark ? const Color(0xFF23252A) : p.border;
    final valueCol = isDark ? Colors.white : p.textPrimary;
    final mutedCol = isDark ? const Color(0xFF71717A) : p.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tileBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              Text(
                '${current}g',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: valueCol,
                ),
              ),
              if (target > 0)
                Text(
                  '/ ${target}g',
                  style: TextStyle(
                    fontSize: 10,
                    color: mutedCol,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: tileBorder,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

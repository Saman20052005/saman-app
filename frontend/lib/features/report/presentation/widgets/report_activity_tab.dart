import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';
import '../../../../config/app_theme.dart';
import 'calories_burned_chart_card.dart';

class ReportActivityTab extends StatelessWidget {
  final WeeklyReportEntity report;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;

  const ReportActivityTab({
    super.key,
    required this.report,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    const int plannedDays = 4;
    final int adherencePct = plannedDays > 0
        ? ((report.activeDays / plannedDays) * 100).round()
        : 0;

    // Peak workout session
    WorkoutSessionItem? peakSession;
    for (final s in report.workoutSessions) {
      if (peakSession == null || s.caloriesBurned > peakSession.caloriesBurned) {
        peakSession = s;
      }
    }

    String peakSessionText;
    if (peakSession != null && peakSession.caloriesBurned > 0) {
      peakSessionText =
          'Peak session: ${peakSession.dayName} (${peakSession.title}) · ${peakSession.caloriesBurned} kcal';
    } else {
      peakSessionText = 'No peak session recorded this week';
    }

    // Weekly target burn calculation
    final totalTargetBurn = report.targetBurned * plannedDays;
    String burnDeltaLabel = '';
    if (totalTargetBurn > 0 && report.totalCaloriesBurned > 0) {
      final diff = report.totalCaloriesBurned.round() - totalTargetBurn;
      if (diff > 0) {
        burnDeltaLabel = '+$diff kcal over goal';
      } else if (diff < 0) {
        burnDeltaLabel = '$diff kcal under goal';
      } else {
        burnDeltaLabel = 'Met target goal';
      }
    }

    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final cardBg = isDark ? const Color(0xFF16171A) : p.surface;
    final borderCol = isDark ? const Color(0xFF26282F) : p.border;
    final tileBg = isDark ? const Color(0xFF101114) : p.surfaceElevated;
    final tileBorder = isDark ? const Color(0xFF23252A) : p.border;
    final headingCol = isDark ? const Color(0xFFD1D5DB) : p.textPrimary;
    final valueCol = isDark ? Colors.white : p.textPrimary;
    final subCol = isDark ? const Color(0xFFA1A1AA) : p.textSecondary;
    final mutedCol = isDark ? const Color(0xFF9CA3AF) : p.textSecondary;
    final subtleCol = isDark ? const Color(0xFF71717A) : p.textMuted;
    final emerald = isDark ? const Color(0xFF10B981) : p.accent;
    final amber = isDark ? const Color(0xFFF59E0B) : p.amber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Weekly Exertion Summary Header
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
                          'WEEKLY EXERTION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: headingCol,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total recorded burn & completed volume',
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
                      color: amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: amber.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      '${report.activeDays} active days',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: amber,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2 Compact Tiles: Total Burned & Training Sessions
              Row(
                children: [
                  // Tile 1: Total Burned
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tileBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL BURNED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: subCol,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                NumberFormat('#,###')
                                    .format(report.totalCaloriesBurned.round()),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: valueCol,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'kcal',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: subCol,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            burnDeltaLabel.isNotEmpty
                                ? burnDeltaLabel
                                : 'Target: ${NumberFormat('#,###').format(totalTargetBurn)} kcal',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Tile 2: Training Sessions
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tileBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRAINING SESSIONS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: subCol,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${report.workoutSessions.length}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: valueCol,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'sessions',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: subCol,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report.workoutSessions.isNotEmpty
                                ? '$adherencePct% plan adherence'
                                : '0 of $plannedDays planned',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: adherencePct >= 100
                                  ? emerald
                                  : mutedCol,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Calories Burned Chart Card
        CaloriesBurnedChartCard(
          days: report.days,
          avgCaloriesBurned: report.avgCaloriesBurned,
          targetBurned: report.targetBurned,
          selectedIndex: selectedIndex,
          onSelectIndex: onSelectIndex,
        ),
        const SizedBox(height: 10),

        // Peak Session Tagline
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            peakSessionText,
            style: TextStyle(
              fontSize: 11.5,
              color: subCol,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Logged Sessions This Week Card
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
              Text(
                'LOGGED SESSIONS THIS WEEK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: headingCol,
                ),
              ),
              const SizedBox(height: 12),
              if (report.workoutSessions.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  child: Text(
                    'No completed workout sessions recorded this week.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: subtleCol,
                    ),
                  ),
                )
              else
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: report.workoutSessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final session = report.workoutSessions[idx];
                    final String rpePart = session.rpe != null
                        ? ' · RPE ${session.rpe!.toStringAsFixed(1)}'
                        : '';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tileBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.title,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: valueCol,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${session.dayName} · ${session.durationMinutes} min$rpePart',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: subCol,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${session.caloriesBurned} kcal',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: amber,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

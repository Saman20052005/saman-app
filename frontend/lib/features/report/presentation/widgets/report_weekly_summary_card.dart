import 'package:flutter/material.dart';
import '../../../../config/app_theme.dart';

class ReportWeeklySummaryCard extends StatelessWidget {
  final int daysLogged;
  final double avgProtein;
  final int targetProtein;
  final int activeDays;
  final int targetActiveDays;
  final double? avgRpe;

  const ReportWeeklySummaryCard({
    super.key,
    required this.daysLogged,
    required this.avgProtein,
    required this.targetProtein,
    required this.activeDays,
    this.targetActiveDays = 4,
    this.avgRpe,
  });

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final cardBg = isDark ? const Color(0xFF16171A) : p.surface;
    final borderCol = isDark ? const Color(0xFF26282F) : p.border;
    final tileBg = isDark ? const Color(0xFF101114) : p.surfaceElevated;
    final tileBorder = isDark ? const Color(0xFF23252A) : p.border;
    final pillBg = isDark ? const Color(0xFF1F2228) : p.surfaceElevated;
    final pillBorder = isDark ? Colors.white.withOpacity(0.06) : p.border;
    final headingCol = isDark ? const Color(0xFFD1D5DB) : p.textPrimary;
    final titleValueCol = isDark ? Colors.white : p.textPrimary;
    final subCol = isDark ? const Color(0xFFA1A1AA) : p.textSecondary;
    final mutedCol = isDark ? const Color(0xFF9CA3AF) : p.textSecondary;
    final emerald = isDark ? const Color(0xFF10B981) : p.accent;
    final planPillBg =
        isDark ? Colors.white.withOpacity(0.05) : p.surface;
    final planPillBorder =
        isDark ? Colors.white.withOpacity(0.1) : p.border;

    final proteinPct = targetProtein > 0
        ? (avgProtein / targetProtein * 100).round()
        : 0;

    String activeSubtitle;
    if (activeDays >= targetActiveDays) {
      activeSubtitle = avgRpe != null
          ? 'Goal achieved · RPE ${avgRpe!.toStringAsFixed(1)}'
          : 'Goal achieved';
    } else {
      activeSubtitle = '$activeDays of $targetActiveDays planned';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR WEEK, AT A GLANCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: headingCol,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'High consistency with nutrition & training',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: subCol,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: pillBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: emerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$daysLogged / 7 days recorded',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: headingCol,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Two Compact Summary Tiles
          Row(
            children: [
              // Tile 1: Avg Protein
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          Text(
                            'AVG PROTEIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: subCol,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: emerald.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: emerald.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              'Target ${targetProtein}g',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: emerald,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${avgProtein.round()}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: titleValueCol,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'g / day',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: subCol,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        targetProtein > 0
                            ? '$proteinPct% of target met'
                            : 'No target set',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: mutedCol,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Tile 2: Active Days
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          Text(
                            'ACTIVE DAYS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: subCol,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: planPillBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: planPillBorder,
                              ),
                            ),
                            child: Text(
                              'Plan: $targetActiveDays days',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: headingCol,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$activeDays',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: titleValueCol,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '/ 7 days',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: subCol,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: activeDays >= targetActiveDays
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
    );
  }
}

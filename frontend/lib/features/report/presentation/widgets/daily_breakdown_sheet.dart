import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_ai_app/features/report/domain/entities/weekly_report_entity.dart';

class DailyBreakdownSheet extends StatelessWidget {
  final List<DailyStats> days;
  final int targetCalories;
  final int targetProtein;

  const DailyBreakdownSheet({
    super.key,
    required this.days,
    required this.targetCalories,
    required this.targetProtein,
  });

  static Future<void> show(
    BuildContext context, {
    required List<DailyStats> days,
    required int targetCalories,
    required int targetProtein,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DailyBreakdownSheet(
        days: days,
        targetCalories: targetCalories,
        targetProtein: targetProtein,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0D0E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0xFF26282F)),
          left: BorderSide(color: Color(0xFF26282F)),
          right: BorderSide(color: Color(0xFF26282F)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF353842),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Breakdown',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Day-by-day telemetry and recorded sessions',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFA1A1AA),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFFA1A1AA), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF23252A), height: 1),

          // Content List
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = days[i];
                final dateStr = DateFormat('EEEE, MMM dd').format(d.date);

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16171A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: d.isToday
                          ? const Color(0xFF3B82F6).withOpacity(0.4)
                          : const Color(0xFF26282F),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    dateStr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: d.isToday
                                          ? const Color(0xFF60A5FA)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                                if (d.isToday) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Today',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF60A5FA),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (d.isRecorded)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${d.logCount} logged',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            )
                          else if (d.isFuture)
                            const Text(
                              'Upcoming',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF52525B),
                              ),
                            )
                          else
                            const Text(
                              'Unlogged',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF71717A),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Metrics Row
                      Row(
                        children: [
                          Expanded(
                            child: _MetricTile(
                              label: 'Calories In',
                              value: d.isRecorded
                                  ? '${d.caloriesIn.round()} kcal'
                                  : '—',
                              color: const Color(0xFFE5E7EB),
                            ),
                          ),
                          Expanded(
                            child: _MetricTile(
                              label: 'Protein',
                              value: d.isRecorded ? '${d.protein.round()}g' : '—',
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          Expanded(
                            child: _MetricTile(
                              label: 'Burned',
                              value: (d.hasWorkout && d.caloriesBurned > 0)
                                  ? '${d.caloriesBurned.round()} kcal'
                                  : (d.isRestDay ? '0 kcal (Rest)' : '—'),
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),

                      if (d.workoutTitle != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101114),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF23252A)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.fitness_center_rounded,
                                size: 12,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${d.workoutTitle} · ${d.workoutDurationMinutes} min',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            color: Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

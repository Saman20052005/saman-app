import 'package:flutter/material.dart';
import '../../../presentation/screens/workout_history_screen.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Long-term athletic progress snapshot card.
///
/// Features:
/// - Section header: "YOUR PROGRESS"
/// - 3 long-term consistency metrics separated by subtle vertical dividers:
///   - Workouts count (e.g. 24)
///   - Current streak (e.g. 7d in Saman Green)
///   - Plan adherence (e.g. 82%)
/// - Understated link: "Xem tiến trình →"
class ProgressSnapshotCard extends StatelessWidget {
  const ProgressSnapshotCard({
    super.key,
    this.workoutsCount,
    this.streakDays,
    this.adherencePercent,
    this.workoutsValue,
    this.streakValue,
    this.adherenceValue,
    this.onViewProgressTap,
  });

  final int? workoutsCount;
  final int? streakDays;
  final int? adherencePercent;
  final String? workoutsValue;
  final String? streakValue;
  final String? adherenceValue;
  final VoidCallback? onViewProgressTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final resolvedWorkouts = workoutsValue ?? (workoutsCount != null ? '$workoutsCount' : '—');
    final resolvedStreak = streakValue ?? (streakDays != null ? '${streakDays}d' : '—');
    final resolvedAdherence = adherenceValue ?? (adherencePercent != null ? '$adherencePercent%' : '—');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR PROGRESS',
            style: tokens.sectionHeader,
          ),
          const SizedBox(height: SamanHomeTokens.spacingSm),
          Container(
            padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(
                color: tokens.border,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Workouts Metric
                    Expanded(
                      child: _MetricItem(
                        value: resolvedWorkouts,
                        label: 'Workouts',
                        valueColor: tokens.textWhite,
                      ),
                    ),
                    const _VerticalDivider(),
                    // Current Streak Metric (Saman Green if present)
                    Expanded(
                      child: _MetricItem(
                        value: resolvedStreak,
                        label: 'Current streak',
                        valueColor: resolvedStreak != '—'
                            ? tokens.greenAccent
                            : tokens.textWhite,
                      ),
                    ),
                    const _VerticalDivider(),
                    // Plan Adherence Metric
                    Expanded(
                      child: _MetricItem(
                        value: resolvedAdherence,
                        label: 'Plan adherence',
                        valueColor: tokens.textWhite,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SamanHomeTokens.spacingMd),
                Divider(
                  color: tokens.borderSubtle,
                  height: 1,
                ),
                const SizedBox(height: SamanHomeTokens.spacingSm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onViewProgressTap ??
                          () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const WorkoutHistoryScreen(),
                              ),
                            );
                          },
                      borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXs),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Xem tiến trình',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: tokens.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: valueColor,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: tokens.textMuted,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Container(
      width: 1,
      height: 36,
      color: tokens.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

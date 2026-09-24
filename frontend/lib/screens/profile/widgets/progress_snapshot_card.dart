import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Long-term athletic progress snapshot card.
///
/// Features:
/// - Section header: customizable, default "YOUR PROGRESS"
/// - 3 long-term consistency metrics separated by subtle vertical dividers:
///   - Workouts count
///   - Current streak (in Saman Green if non-null)
///   - Plan adherence
/// - Optional understated link: "View progress →" (rendered only when actionable)
///
/// Hardened behavior:
/// - No fabricated metrics; parameters are explicitly nullable.
/// - Zero is valid data (displays as 0, 0d, 0%).
/// - Null indicates unavailable data and displays [unavailableLabel].
/// - Interactive target meets 48x48 minimum when callback is provided.
class ProgressSnapshotCard extends StatelessWidget {
  const ProgressSnapshotCard({
    super.key,
    this.workoutsCount,
    this.streakDays,
    this.adherencePercent,
    this.onViewProgressTap,
    this.title = 'YOUR PROGRESS',
    this.workoutsLabel = 'Workouts',
    this.streakLabel = 'Current streak',
    this.adherenceLabel = 'Plan adherence',
    this.viewProgressLabel = 'View progress',
    this.unavailableLabel = '—',
  });

  final int? workoutsCount;
  final int? streakDays;
  final int? adherencePercent;
  final VoidCallback? onViewProgressTap;

  final String title;
  final String workoutsLabel;
  final String streakLabel;
  final String adherenceLabel;
  final String viewProgressLabel;
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final workoutsText = workoutsCount != null ? '$workoutsCount' : unavailableLabel;
    final streakText = streakDays != null ? '${streakDays}d' : unavailableLabel;
    final adherenceText = adherencePercent != null ? '$adherencePercent%' : unavailableLabel;

    final isActionable = onViewProgressTap != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SamanHomeTokens.sectionHeader,
            ),
            const SizedBox(height: SamanHomeTokens.spacingSm),
          ],
          Container(
            padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
            decoration: BoxDecoration(
              color: SamanHomeTokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(
                color: SamanHomeTokens.border,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Workouts Metric
                    Expanded(
                      child: _MetricItem(
                        value: workoutsText,
                        label: workoutsLabel,
                        valueColor: SamanHomeTokens.textWhite,
                      ),
                    ),
                    const _VerticalDivider(),
                    // Current Streak Metric (Saman Green)
                    Expanded(
                      child: _MetricItem(
                        value: streakText,
                        label: streakLabel,
                        valueColor: streakDays != null
                            ? SamanHomeTokens.greenAccent
                            : SamanHomeTokens.textSecondary,
                      ),
                    ),
                    const _VerticalDivider(),
                    // Plan Adherence Metric
                    Expanded(
                      child: _MetricItem(
                        value: adherenceText,
                        label: adherenceLabel,
                        valueColor: SamanHomeTokens.textWhite,
                      ),
                    ),
                  ],
                ),
                if (isActionable) ...[
                  const SizedBox(height: SamanHomeTokens.spacingMd),
                  const Divider(
                    color: SamanHomeTokens.borderSubtle,
                    height: 1,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      button: true,
                      enabled: true,
                      label: viewProgressLabel,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onViewProgressTap,
                          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXs),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                              minWidth: 48,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      viewProgressLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: SamanHomeTokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: SamanHomeTokens.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: valueColor,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: SamanHomeTokens.textMuted,
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
    return Container(
      width: 1,
      height: 36,
      color: SamanHomeTokens.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

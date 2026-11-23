import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Presentation data model for the approved Empty State context card.
class SamanChatContextData {
  final String overline;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String prompt;

  const SamanChatContextData({
    this.overline = 'Today',
    this.title = 'Legs & Chain · 45 min',
    this.subtitle = 'RPE 8.5 · 35g protein left',
    this.actionLabel = 'Review workout',
    this.prompt = "Review today's workout briefing: cues and volume.",
  });

  static int _toInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return num.tryParse(value)?.round() ?? fallback;
    return fallback;
  }

  factory SamanChatContextData.fromDailyBrief({
    String? brief,
    Map<String, dynamic>? metrics,
  }) {
    final trimmedBrief = brief?.trim() ?? '';
    final hasMetrics = metrics != null &&
        metrics.isNotEmpty &&
        (metrics.containsKey('calories') ||
            metrics.containsKey('calories_target') ||
            metrics.containsKey('water_ml') ||
            metrics.containsKey('water_target_ml') ||
            metrics.containsKey('protein') ||
            metrics.containsKey('protein_target'));

    if (hasMetrics) {
      final cal = _toInt(metrics['calories'], 0);
      final calTarget = _toInt(metrics['calories_target'], 2000);
      final water = _toInt(metrics['water_ml'], 0);
      final protein = _toInt(metrics['protein'], 0);
      final proteinTarget = _toInt(metrics['protein_target'], 120);

      return SamanChatContextData(
        overline: 'TODAY · COACH BRIEF',
        title: '$cal / $calTarget kcal · $water ml nước',
        subtitle: trimmedBrief.isNotEmpty
            ? trimmedBrief
            : 'Đạm: $protein/${proteinTarget}g',
        actionLabel: 'Hỏi nhanh',
        prompt:
            'Đánh giá nhanh dinh dưỡng, lượng nước và kế hoạch tập hôm nay của tôi.',
      );
    }

    if (trimmedBrief.isNotEmpty) {
      return SamanChatContextData(
        overline: 'TODAY · COACH BRIEF',
        title: 'Daily Coach Brief',
        subtitle: trimmedBrief,
        actionLabel: 'Hỏi nhanh',
        prompt:
            'Đánh giá nhanh dinh dưỡng, lượng nước và kế hoạch tập hôm nay của tôi.',
      );
    }

    return const SamanChatContextData();
  }
}

/// The approved single contextual card for the Saman Chat Empty State.
///
/// Visual rules:
/// - Translucent dark charcoal surface (#16171B with subtle alpha)
/// - Translucent hairline border
/// - Off-white primary text, muted secondary text
/// - Restrained green accent (#10B981) reserved strictly for the contextual action
class SamanChatContextCard extends StatelessWidget {
  final SamanChatContextData data;
  final ValueChanged<String>? onActionSelected;

  const SamanChatContextCard({
    super.key,
    this.data = const SamanChatContextData(),
    this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: t.contextCardBg,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: t.contextCardBorder,
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Contextual details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.overline,
                  style: t.contextCardOverline,
                ),
                const SizedBox(height: 2.0),
                Text(
                  data.title,
                  style: t.contextCardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2.0),
                Text(
                  data.subtitle,
                  style: t.contextCardSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8.0),

          // Right: Restrained green action CTA
          InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () {
              if (onActionSelected != null) {
                onActionSelected!(data.prompt);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.actionLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: t.greenAccent,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: t.greenAccent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

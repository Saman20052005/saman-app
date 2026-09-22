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
}

/// The approved single contextual card for the Saman Chat Empty State.
///
/// Visual rules:
/// - Dark charcoal surface (#16171B)
/// - Hairline graphite border (#23252A)
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: SamanChatTokens.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: SamanChatTokens.borderSubtle,
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
                  style: SamanChatTokens.contextCardOverline,
                ),
                const SizedBox(height: 2.0),
                Text(
                  data.title,
                  style: SamanChatTokens.contextCardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2.0),
                Text(
                  data.subtitle,
                  style: SamanChatTokens.contextCardSubtitle,
                  maxLines: 1,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: SamanChatTokens.greenAccent,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: SamanChatTokens.greenAccent,
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

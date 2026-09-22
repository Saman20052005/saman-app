import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Represents one of the 3 approved suggested actions for the Empty State.
class SamanChatActionItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String prompt;

  const SamanChatActionItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.prompt,
  });

  /// The 3 approved Empty State actions
  static const List<SamanChatActionItem> approvedActions = [
    SamanChatActionItem(
      icon: Icons.fitness_center_rounded,
      iconColor: SamanChatTokens.greenAccent, // #10B981
      title: "Review today's workout",
      prompt: "Review today's workout briefing: cues and volume.",
    ),
    SamanChatActionItem(
      icon: Icons.restaurant_rounded,
      iconColor: SamanChatTokens.amberAccent, // #F59E0B
      title: "Plan next meal",
      prompt: "Plan my next meal based on today's remaining nutrition targets.",
    ),
    SamanChatActionItem(
      icon: Icons.favorite_rounded,
      iconColor: SamanChatTokens.violetAccent, // #A855F7
      title: "Check recovery",
      prompt: "Check my recovery today and suggest how hard I should train.",
    ),
  ];
}

/// A lightweight sleek card row for empty-state suggested actions.
class SamanChatActionRow extends StatelessWidget {
  final SamanChatActionItem item;
  final ValueChanged<String> onTap;

  const SamanChatActionRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: () => onTap(item.prompt),
        splashColor: Colors.white.withOpacity(0.04),
        highlightColor: Colors.white.withOpacity(0.02),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 13.0),
          decoration: BoxDecoration(
            color: SamanChatTokens.surface,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: SamanChatTokens.borderSubtle,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 18,
                color: item.iconColor,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  item.title,
                  style: SamanChatTokens.actionRowLabel,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SamanChatTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

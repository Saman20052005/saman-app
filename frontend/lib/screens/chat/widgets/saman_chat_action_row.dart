import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Represents one of the 3 approved suggested actions for the Empty State.
class SamanChatActionItem {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String prompt;

  const SamanChatActionItem({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.prompt,
  });

  /// The 3 approved Empty State actions with consistent outline iconography
  static const List<SamanChatActionItem> approvedActions = [
    SamanChatActionItem(
      icon: Icons.fitness_center_outlined,
      title: "Review today's workout",
      prompt: "Review today's workout briefing: cues and volume.",
    ),
    SamanChatActionItem(
      icon: Icons.restaurant_outlined,
      title: "Plan next meal",
      prompt: "Plan my next meal based on today's remaining nutrition targets.",
    ),
    SamanChatActionItem(
      icon: Icons.favorite_border_rounded,
      title: "Check recovery",
      prompt: "Check my recovery today and suggest how hard I should train.",
    ),
  ];
}

/// A lightweight, translucent action row for empty-state suggested actions.
///
/// Visual rules:
/// - Thin, airy height (46 logical px)
/// - 12px rounded corners
/// - 15px horizontal padding
/// - Translucent white background (alpha 0.025–0.035) letting aurora show through
/// - Translucent hairline white border (alpha ~0.06, 1px)
/// - Unified #A8ADB7 outline icon (18px)
/// - Muted chevron (#737985, 16px)
/// - Crisp, un-dimmed text (#D5D8E0)
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
        hoverColor: SamanChatTokens.actionRowHoverBg,
        focusColor: SamanChatTokens.actionRowFocusBg,
        splashColor: SamanChatTokens.actionRowPressedBg,
        highlightColor: SamanChatTokens.actionRowPressedBg,
        child: Ink(
          height: 46.0,
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          decoration: BoxDecoration(
            color: SamanChatTokens.actionRowBg,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: SamanChatTokens.actionRowBorder,
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 18,
                color: item.iconColor ?? SamanChatTokens.actionRowIconColor,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  item.title,
                  style: SamanChatTokens.actionRowLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: SamanChatTokens.actionRowChevronColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

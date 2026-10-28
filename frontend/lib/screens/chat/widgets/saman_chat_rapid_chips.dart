import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Rapid query chip item with a label, prompt, and optional outline icon.
class SamanRapidChipItem {
  final String label;
  final String prompt;
  final IconData? icon;

  const SamanRapidChipItem({
    required this.label,
    required this.prompt,
    this.icon,
  });

  static const List<SamanRapidChipItem> defaultChips = [
    SamanRapidChipItem(
      label: 'Post-workout meal',
      prompt: 'Post-workout meal recommendation',
      icon: Icons.restaurant_outlined,
    ),
    SamanRapidChipItem(
      label: 'Protein check',
      prompt: 'Quick protein check for today',
      icon: Icons.bolt_outlined,
    ),
    SamanRapidChipItem(
      label: 'Squat warm-up',
      prompt: 'Squat mobility warmup protocol',
      icon: Icons.fitness_center_outlined,
    ),
    SamanRapidChipItem(
      label: 'Adjust workout',
      prompt: "Adjust today's workout volume",
      icon: Icons.tune_outlined,
    ),
  ];
}

/// Horizontal scrollable rapid query chips row.
///
/// Features:
/// - Compact pill visual height (34px)
/// - Meets touch target minimum (44px)
/// - Translucent white background (alpha ~0.025)
/// - Translucent hairline border (alpha ~0.06, 1px)
/// - Crisp outline icon (15px, #A8ADB7)
/// - Muted off-white text (12.5px, #C0C5CF)
class SamanChatRapidChips extends StatelessWidget {
  final List<SamanRapidChipItem> chips;
  final ValueChanged<String> onChipSelected;

  const SamanChatRapidChips({
    super.key,
    this.chips = SamanRapidChipItem.defaultChips,
    required this.onChipSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44.0, // Minimum touch target height
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8.0),
        itemBuilder: (context, index) {
          final chip = chips[index];
          return Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18.0),
                onTap: () => onChipSelected(chip.prompt),
                hoverColor: SamanChatTokens.actionRowHoverBg,
                focusColor: SamanChatTokens.actionRowFocusBg,
                splashColor: SamanChatTokens.actionRowPressedBg,
                highlightColor: SamanChatTokens.actionRowPressedBg,
                child: Ink(
                  height: 34.0,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: SamanChatTokens.rapidChipBg,
                    borderRadius: BorderRadius.circular(18.0),
                    border: Border.all(
                      color: SamanChatTokens.rapidChipBorder,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (chip.icon != null) ...[
                        Icon(
                          chip.icon,
                          size: 15.0,
                          color: SamanChatTokens.rapidChipIconColor,
                        ),
                        const SizedBox(width: 6.0),
                      ],
                      Text(
                        chip.label,
                        style: SamanChatTokens.chipLabel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

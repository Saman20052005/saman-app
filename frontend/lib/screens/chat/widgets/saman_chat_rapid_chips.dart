import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Rapid query chip item with a label and associated prompt.
class SamanRapidChipItem {
  final String label;
  final String prompt;

  const SamanRapidChipItem({
    required this.label,
    required this.prompt,
  });

  static const List<SamanRapidChipItem> defaultChips = [
    SamanRapidChipItem(
      label: 'Post-workout meal',
      prompt: 'Post-workout meal recommendation',
    ),
    SamanRapidChipItem(
      label: 'Protein check',
      prompt: 'Quick protein check for today',
    ),
    SamanRapidChipItem(
      label: 'Squat warm-up',
      prompt: 'Squat mobility warmup protocol',
    ),
    SamanRapidChipItem(
      label: 'Adjust workout',
      prompt: "Adjust today's workout volume",
    ),
  ];
}

/// Horizontal scrollable rapid query chips row.
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
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8.0),
        itemBuilder: (context, index) {
          final chip = chips[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20.0),
              onTap: () => onChipSelected(chip.prompt),
              splashColor: Colors.white.withOpacity(0.06),
              highlightColor: Colors.white.withOpacity(0.03),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13.0,
                  vertical: 7.0,
                ),
                decoration: BoxDecoration(
                  color: SamanChatTokens.chipBackground,
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: SamanChatTokens.borderSubtle,
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  chip.label,
                  style: SamanChatTokens.chipLabel,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

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

  static IconData _resolveIcon(String? iconName) {
    switch (iconName?.trim()) {
      case 'water_drop':
        return Icons.water_drop_outlined;
      case 'restaurant':
        return Icons.restaurant_outlined;
      case 'bolt':
        return Icons.bolt_outlined;
      case 'fitness_center':
        return Icons.fitness_center_outlined;
      case 'tune':
        return Icons.tune_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  static List<SamanRapidChipItem> fromDynamicChips(
    List<Map<String, String>> rawChips,
  ) {
    if (rawChips.isEmpty) {
      return defaultChips;
    }
    final mapped = rawChips
        .map((item) {
          final label = (item['label'] ?? '').trim();
          final prompt = (item['prompt'] ?? label).trim();
          if (label.isEmpty || prompt.isEmpty) {
            return null;
          }
          return SamanRapidChipItem(
            label: label,
            prompt: prompt,
            icon: _resolveIcon(item['icon']),
          );
        })
        .whereType<SamanRapidChipItem>()
        .toList(growable: false);

    return mapped.isEmpty ? defaultChips : mapped;
  }
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

  static List<SamanRapidChipItem> fromDynamicChips(
    List<Map<String, String>> rawChips,
  ) =>
      SamanRapidChipItem.fromDynamicChips(rawChips);

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
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
                hoverColor: t.actionRowHoverBg,
                focusColor: t.actionRowFocusBg,
                splashColor: t.actionRowPressedBg,
                highlightColor: t.actionRowPressedBg,
                child: Ink(
                  height: 34.0,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: t.rapidChipBg,
                    borderRadius: BorderRadius.circular(18.0),
                    border: Border.all(
                      color: t.rapidChipBorder,
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
                          color: t.rapidChipIconColor,
                        ),
                        const SizedBox(width: 6.0),
                      ],
                      Text(
                        chip.label,
                        style: t.chipLabel,
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

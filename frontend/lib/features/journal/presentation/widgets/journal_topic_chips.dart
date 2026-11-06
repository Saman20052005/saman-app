import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_article.dart';

/// Horizontal scrollable chips for filtering Journal topics (R01).
class JournalTopicChips extends StatelessWidget {
  const JournalTopicChips({
    super.key,
    required this.selectedTopic,
    required this.onTopicSelected,
  });

  final JournalTopic selectedTopic;
  final ValueChanged<JournalTopic> onTopicSelected;

  @override
  Widget build(BuildContext context) {
    const topics = [
      JournalTopic.workout,
      JournalTopic.nutrition,
      JournalTopic.recovery,
      JournalTopic.habits,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: topics.map((topic) {
          final isSelected = topic == selectedTopic;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTopicSelected(topic),
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1F2021)
                        : SamanHomeTokens.cardSurface,
                    borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                    border: Border.all(
                      color: isSelected
                          ? SamanHomeTokens.greenAccent.withOpacity(0.5)
                          : SamanHomeTokens.borderSubtle,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    context.tr(topic.translationKey),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? SamanHomeTokens.greenAccent
                          : SamanHomeTokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

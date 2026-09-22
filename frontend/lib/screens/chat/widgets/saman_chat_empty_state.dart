import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_chat_action_row.dart';
import 'saman_chat_context_card.dart';
import 'saman_monogram.dart';

/// The approved Saman Chat Empty State (State 01).
///
/// Visual hierarchy:
/// 1. Centered S monogram hero (44x44)
/// 2. "Your coach is ready"
/// 3. "Ask about training, meals, recovery, or what to do next."
/// 4. ONE contextual card ("Today", "Legs & Chain · 45 min", "RPE 8.5 · 35g protein left", "Review workout →")
/// 5. Exactly three lightweight suggested actions:
///    - Review today's workout
///    - Plan next meal
///    - Check recovery
///
/// Designed to fit comfortably within max-width 480px, responsive down to 360px width.
class SamanChatEmptyState extends StatelessWidget {
  final ValueChanged<String> onPromptSelected;
  final SamanChatContextData contextData;

  const SamanChatEmptyState({
    super.key,
    required this.onPromptSelected,
    this.contextData = const SamanChatContextData(),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8.0),

                  // ─── 1. Hero & Conversational Guidance ───────────────
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SamanMonogram.hero(),
                        const SizedBox(height: 12.0),
                        const Text(
                          'Your coach is ready',
                          style: SamanChatTokens.heroTitle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4.0),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320.0),
                          child: const Text(
                            'Ask about training, meals, recovery, or what to do next.',
                            style: SamanChatTokens.heroSubtitle,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20.0),

                  // ─── 2. Single Context Card ──────────────────────────
                  SamanChatContextCard(
                    data: contextData,
                    onActionSelected: onPromptSelected,
                  ),

                  const SizedBox(height: 16.0),

                  // ─── 3. Exactly Three Lightweight Suggested Actions ─
                  ...SamanChatActionItem.approvedActions.map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: SamanChatActionRow(
                        item: action,
                        onTap: onPromptSelected,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8.0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

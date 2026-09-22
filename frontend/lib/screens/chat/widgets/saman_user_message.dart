import 'package:flutter/material.dart';
import '../../../controllers/chat_controller.dart';
import '../tokens/saman_chat_tokens.dart';

/// The approved user message component for Saman Chat (State 02).
///
/// Visual rules:
/// - Right-aligned
/// - Max width ~78%
/// - Dark charcoal surface (#1E2024) with hairline graphite border (#23252A)
/// - Off-white text (#E3E2E6)
/// - Medium corner radius (16px with compact 4px top-right shoulder)
/// - Compact padding, no avatar, no green fill
class SamanUserMessage extends StatelessWidget {
  final ChatMessage message;

  const SamanUserMessage({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = (screenWidth > 480 ? 480 : screenWidth) * 0.78;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: SamanChatTokens.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(4.0),
              bottomLeft: Radius.circular(16.0),
              bottomRight: Radius.circular(16.0),
            ),
            border: Border.all(
              color: SamanChatTokens.userBubbleBorder,
              width: 1.0,
            ),
          ),
          child: Text(
            message.content,
            style: SamanChatTokens.userMessage,
          ),
        ),
      ),
    );
  }
}

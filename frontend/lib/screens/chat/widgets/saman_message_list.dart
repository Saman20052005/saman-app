import 'package:flutter/material.dart';
import '../../../controllers/chat_controller.dart';
import 'saman_assistant_response.dart';
import 'saman_user_message.dart';

/// Scrollable message feed for Saman Chat active conversations (State 02).
class SamanMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;

  const SamanMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480.0),
        child: ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          itemCount: messages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 20.0),
          itemBuilder: (context, index) {
            final msg = messages[index];
            if (msg.role == 'user') {
              return SamanUserMessage(message: msg);
            }
            return SamanAssistantResponse(message: msg);
          },
        ),
      ),
    );
  }
}

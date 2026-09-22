import 'package:flutter/material.dart';
import '../../../controllers/chat_controller.dart';
import 'saman_assistant_response.dart';
import 'saman_error_response.dart';
import 'saman_generating_indicator.dart';
import 'saman_user_message.dart';

/// Scrollable message feed for Saman Chat active conversations (State 02, 05, 07).
class SamanMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onEditQuestion;

  const SamanMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onEditQuestion,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null;
    final showGenerating =
        !hasError && isLoading && messages.isNotEmpty && messages.last.role == 'user';
    final extraCount = (hasError || showGenerating) ? 1 : 0;
    final totalCount = messages.length + extraCount;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480.0),
        child: ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          itemCount: totalCount,
          separatorBuilder: (_, __) => const SizedBox(height: 20.0),
          itemBuilder: (context, index) {
            if (index < messages.length) {
              final msg = messages[index];
              if (msg.role == 'user') {
                return SamanUserMessage(message: msg);
              }
              return SamanAssistantResponse(message: msg);
            }
            if (hasError) {
              return SamanErrorResponse(
                errorMessage: errorMessage!,
                onRetry: onRetry,
                onEditQuestion: onEditQuestion,
              );
            }
            return const SamanGeneratingIndicator();
          },
        ),
      ),
    );
  }
}

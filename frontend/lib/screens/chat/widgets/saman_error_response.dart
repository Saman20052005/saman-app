import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// Approved Recoverable Error presentation component for Saman Chat (State 07).
///
/// Visual structure:
/// - Saman identity row: [S monogram] + "Saman"
/// - Human, non-alarmist failure text: "I couldn't complete that response."
/// - Action row: "Retry →" and "Edit question"
///
/// Rules:
/// - Never renders raw exception or HTTP status code
/// - No red warning banner or alarmist iconography
/// - Retry triggers re-request without duplicating user message
/// - Edit question restores text to composer for modification
class SamanErrorResponse extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onEditQuestion;

  const SamanErrorResponse({
    super.key,
    this.errorMessage = "I couldn't complete that response.",
    this.onRetry,
    this.onEditQuestion,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saman could not complete response. Options: Retry or Edit question.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Identity row: Small S monogram + "Saman"
          const Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SamanMonogram(
                size: 20,
                borderRadius: 4,
                fontSize: 11,
                backgroundColor: SamanChatTokens.iconContainerBg,
                borderColor: SamanChatTokens.borderSubtle,
              ),
              SizedBox(width: 8.0),
              Text(
                'Saman',
                style: SamanChatTokens.assistantName,
              ),
            ],
          ),

          const SizedBox(height: 8.0),

          // 2. Human, non-alarmist error copy directly on canvas
          Text(
            errorMessage,
            style: SamanChatTokens.assistantBody.copyWith(
              color: SamanChatTokens.textSecondary,
            ),
          ),

          const SizedBox(height: 12.0),

          // 3. Action row: Retry → and Edit question
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Retry action
              Semantics(
                button: true,
                label: 'Retry response',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4.0),
                    onTap: onRetry,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Retry',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: SamanChatTokens.greenAccent,
                            ),
                          ),
                          SizedBox(width: 4.0),
                          Text(
                            '→',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: SamanChatTokens.greenAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 20.0),

              // Edit question action
              Semantics(
                button: true,
                label: 'Edit question',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4.0),
                    onTap: onEditQuestion,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                      child: Text(
                        'Edit question',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: SamanChatTokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

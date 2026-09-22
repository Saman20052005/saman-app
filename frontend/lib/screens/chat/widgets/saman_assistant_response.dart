import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../controllers/chat_controller.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// The approved assistant response component for Saman Chat (State 02).
///
/// Visual rules:
/// - Identity row: [S monogram] + "Saman" (Title case)
/// - Response text renders DIRECTLY on obsidian canvas (no bubble container around it)
/// - Clean restrained Markdown styling (off-white body, white bold, no green flood)
/// - Controlled line-height and modest vertical rhythm
class SamanAssistantResponse extends StatelessWidget {
  final ChatMessage message;

  const SamanAssistantResponse({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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

        // 2. Editorial response rendered directly on obsidian canvas
        MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: SamanChatTokens.assistantBody,
            strong: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
              height: 1.55,
            ),
            em: const TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: SamanChatTokens.textWhite,
              height: 1.55,
            ),
            h1: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.35,
              letterSpacing: -0.2,
            ),
            h2: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.35,
              letterSpacing: -0.2,
            ),
            h3: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.35,
            ),
            listBullet: const TextStyle(
              fontSize: 14,
              color: SamanChatTokens.textSecondary,
              height: 1.55,
            ),
            a: const TextStyle(
              fontSize: 14,
              color: SamanChatTokens.greenAccent,
              decoration: TextDecoration.underline,
            ),
            code: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: SamanChatTokens.textWhite,
              backgroundColor: Color(0xFF1E2024),
            ),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF16171B),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: SamanChatTokens.borderSubtle),
            ),
            codeblockPadding: const EdgeInsets.all(12.0),
            tableBorder: TableBorder.all(
              color: SamanChatTokens.borderSubtle,
              width: 1.0,
            ),
            tableHead: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
            ),
            tableBody: const TextStyle(
              fontSize: 13,
              color: SamanChatTokens.textSecondary,
            ),
            tableHeadAlign: TextAlign.left,
            tableCellsPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),

        // 3. Subtle typing indicator if active
        if (message.isTyping)
          const Padding(
            padding: EdgeInsets.only(top: 10.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SamanChatTokens.greenAccent,
                  ),
                ),
                SizedBox(width: 8.0),
                Text(
                  'Saman is thinking...',
                  style: TextStyle(
                    fontSize: 12,
                    color: SamanChatTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

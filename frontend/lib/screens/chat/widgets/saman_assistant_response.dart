import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../controllers/chat_controller.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// Approved action model for assistant responses in Saman Chat.
///
/// Used for contextual follow-up recommendations (e.g., "Adjust tomorrow's workout", "Plan breakfast").
class SamanAssistantAction {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  const SamanAssistantAction({
    required this.label,
    this.icon,
    this.onTap,
    this.isPrimary = false,
  });
}

/// The approved assistant response component for Saman Chat (State 02 & State 09).
///
/// Visual rules:
/// - Identity row: [S monogram] + "Saman" (Title case, strictly no "Saman COACH" or telemetry tags)
/// - Response text renders DIRECTLY on obsidian canvas (no card or bubble container around it)
/// - Clean restrained Markdown styling (off-white body, white bold, compact tables, no green flood)
/// - Restrained table borders and paddings optimized for 360px mobile viewports
/// - Optional contextual actions rendered at the bottom when explicitly supplied
class SamanAssistantResponse extends StatelessWidget {
  final ChatMessage message;
  final List<SamanAssistantAction>? actions;

  const SamanAssistantResponse({
    super.key,
    required this.message,
    this.actions,
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
            SamanMonogram.chat(),
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
            p: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              color: SamanChatTokens.textWhite,
              height: 1.55,
              letterSpacing: -0.1,
            ),
            pPadding: const EdgeInsets.only(bottom: 10.0),
            strong: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
              height: 1.55,
            ),
            em: const TextStyle(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              color: SamanChatTokens.textWhite,
              height: 1.55,
            ),
            h1: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.4,
              letterSpacing: -0.2,
            ),
            h1Padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
            h2: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.4,
              letterSpacing: -0.2,
            ),
            h2Padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
            h3: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.4,
            ),
            h3Padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
            h4: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
              height: 1.4,
            ),
            h4Padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
            listBullet: const TextStyle(
              fontSize: 14,
              color: SamanChatTokens.textSecondary,
              height: 1.55,
            ),
            listIndent: 22.0,
            listBulletPadding: const EdgeInsets.only(right: 6.0),
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
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SamanChatTokens.textWhite,
            ),
            tableBody: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: SamanChatTokens.textSecondary,
            ),
            tableHeadAlign: TextAlign.left,
            tableCellsPadding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 7.0),
            tableCellsDecoration: const BoxDecoration(
              color: Color(0xFF16171B),
            ),
            blockquotePadding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            blockquoteDecoration: BoxDecoration(
              color: SamanChatTokens.surface,
              borderRadius: BorderRadius.circular(6.0),
              border: const Border(
                left: BorderSide(
                  color: SamanChatTokens.greenAccent,
                  width: 3.0,
                ),
              ),
            ),
          ),
        ),

        // 3. Optional contextual action buttons
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: 12.0),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actions!.map((action) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _ActionPill(action: action),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  final SamanAssistantAction action;

  const _ActionPill({required this.action});

  @override
  Widget build(BuildContext context) {
    final isPrimary = action.isPrimary;
    final accentColor =
        isPrimary ? SamanChatTokens.greenAccent : SamanChatTokens.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 11.0),
          decoration: BoxDecoration(
            color: isPrimary
                ? SamanChatTokens.surface
                : SamanChatTokens.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: isPrimary
                  ? SamanChatTokens.greenAccent.withOpacity(0.35)
                  : SamanChatTokens.borderSubtle,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              if (action.icon != null) ...[
                Icon(
                  action.icon,
                  size: 17,
                  color: accentColor,
                ),
                const SizedBox(width: 8.0),
              ],
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isPrimary
                        ? SamanChatTokens.textWhite
                        : SamanChatTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

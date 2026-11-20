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
    final t = SamanChatTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Identity row: Small S monogram + "Saman"
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SamanMonogram.chat(),
            const SizedBox(width: 8.0),
            Text(
              'Saman',
              style: t.assistantName,
            ),
          ],
        ),

        const SizedBox(height: 8.0),

        // 2. Editorial response rendered directly on canvas
        MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              color: t.textWhite,
              height: 1.55,
              letterSpacing: -0.1,
            ),
            pPadding: const EdgeInsets.only(bottom: 10.0),
            strong: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: t.isDark ? const Color(0xFFFFFFFF) : t.textPrimary,
              height: 1.55,
            ),
            em: TextStyle(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              color: t.textWhite,
              height: 1.55,
            ),
            h1: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.textWhite,
              height: 1.4,
              letterSpacing: -0.2,
            ),
            h1Padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
            h2: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.textWhite,
              height: 1.4,
              letterSpacing: -0.2,
            ),
            h2Padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
            h3: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.textWhite,
              height: 1.4,
            ),
            h3Padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
            h4: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.textWhite,
              height: 1.4,
            ),
            h4Padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
            listBullet: TextStyle(
              fontSize: 14,
              color: t.textSecondary,
              height: 1.55,
            ),
            listIndent: 22.0,
            listBulletPadding: const EdgeInsets.only(right: 6.0),
            a: TextStyle(
              fontSize: 14,
              color: t.greenAccent,
              decoration: TextDecoration.underline,
            ),
            code: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: t.textWhite,
              backgroundColor: t.isDark ? const Color(0xFF1E2024) : t.surfaceElevated,
            ),
            codeblockDecoration: BoxDecoration(
              color: t.isDark ? const Color(0xFF16171B) : t.surfaceElevated,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: t.borderSubtle),
            ),
            codeblockPadding: const EdgeInsets.all(12.0),
            tableBorder: TableBorder.all(
              color: t.borderSubtle,
              width: 1.0,
            ),
            tableHead: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.textWhite,
            ),
            tableBody: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: t.textSecondary,
            ),
            tableHeadAlign: TextAlign.left,
            tableCellsPadding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 7.0),
            tableCellsDecoration: BoxDecoration(
              color: t.isDark ? const Color(0xFF16171B) : t.surface,
            ),
            blockquotePadding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            blockquoteDecoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(6.0),
              border: Border(
                left: BorderSide(
                  color: t.greenAccent,
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
    final t = SamanChatTokens.of(context);
    final isPrimary = action.isPrimary;
    final accentColor = isPrimary ? t.greenAccent : t.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 11.0),
          decoration: BoxDecoration(
            color: isPrimary
                ? t.surface
                : t.surface.withOpacity(t.isDark ? 0.5 : 0.85),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: isPrimary
                  ? t.greenAccent.withOpacity(0.35)
                  : t.borderSubtle,
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
                    color: isPrimary ? t.textWhite : t.textSecondary,
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

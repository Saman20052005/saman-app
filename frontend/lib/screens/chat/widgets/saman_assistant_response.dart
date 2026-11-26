import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../controllers/chat_controller.dart';
import '../../../models/video_citation.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';
import 'video_citation_player_sheet.dart';

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
  final void Function(VideoCitation citation)? onCitationTap;

  const SamanAssistantResponse({
    super.key,
    required this.message,
    this.actions,
    this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final isTypingPlaceholder = message.isTyping && message.content.isEmpty;
    final activeStatusLabel =
        (message.statusLabel != null && message.statusLabel!.trim().isNotEmpty)
            ? message.statusLabel!.trim()
            : 'Analyzing your request...';

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

        // 2. Live animated "..." + English status indicator before first delta,
        //    otherwise editorial Markdown response rendered directly on canvas.
        if (isTypingPlaceholder)
          _SamanTypingIndicator(statusLabel: activeStatusLabel)
        else
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

        // 2b. Optional video citation chips
        if (message.videoCitations.isNotEmpty) ...[
          const SizedBox(height: 12.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: message.videoCitations.map((citation) {
              return _VideoCitationChip(
                citation: citation,
                onTap: () {
                  if (onCitationTap != null) {
                    onCitationTap!(citation);
                  } else {
                    showVideoCitationPlayerSheet(context, citation);
                  }
                },
              );
            }).toList(),
          ),
        ],

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

class _VideoCitationChip extends StatelessWidget {
  final VideoCitation citation;
  final VoidCallback onTap;

  const _VideoCitationChip({
    required this.citation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final displayLabel = citation.label.isNotEmpty
        ? citation.label
        : 'Xem video (${citation.formattedTimestamp})';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40.0),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(999.0),
              border: Border.all(
                color: t.borderSubtle,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 17.0,
                  color: t.greenAccent,
                ),
                const SizedBox(width: 6.0),
                Flexible(
                  child: Text(
                    displayLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: t.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SamanTypingIndicator extends StatefulWidget {
  final String statusLabel;

  const _SamanTypingIndicator({
    required this.statusLabel,
  });

  @override
  State<_SamanTypingIndicator> createState() => _SamanTypingIndicatorState();
}

class _SamanTypingIndicatorState extends State<_SamanTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      key: const ValueKey('saman_typing_indicator'),
      liveRegion: true,
      label: widget.statusLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 9.0,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: t.borderSubtle,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedTypingDot(
                  controller: _controller,
                  phaseOffset: 0.0,
                  disableAnimations: disableAnimations,
                ),
                const SizedBox(width: 5.0),
                _AnimatedTypingDot(
                  controller: _controller,
                  phaseOffset: 0.22,
                  disableAnimations: disableAnimations,
                ),
                const SizedBox(width: 5.0),
                _AnimatedTypingDot(
                  controller: _controller,
                  phaseOffset: 0.44,
                  disableAnimations: disableAnimations,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10.0),
          Flexible(
            child: AnimatedSwitcher(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Text(
                widget.statusLabel,
                key: ValueKey<String>(widget.statusLabel),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13.0,
                  fontWeight: FontWeight.w500,
                  color: t.textSecondary,
                  height: 1.35,
                  letterSpacing: -0.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTypingDot extends StatelessWidget {
  final AnimationController controller;
  final double phaseOffset;
  final bool disableAnimations;

  const _AnimatedTypingDot({
    required this.controller,
    required this.phaseOffset,
    required this.disableAnimations,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final dot = Container(
      width: 6.0,
      height: 6.0,
      decoration: BoxDecoration(
        color: t.textSecondary,
        shape: BoxShape.circle,
      ),
    );

    if (disableAnimations) {
      return dot;
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = (controller.value - phaseOffset) % 1.0;
        final wave =
            0.5 * (1.0 + math.sin((progress * 2.0 * math.pi) - (math.pi / 2.0)));
        final opacity = (0.28 + 0.72 * wave).clamp(0.28, 1.0);
        final offsetY = -2.5 * wave;
        final scale = 0.88 + 0.18 * wave;
        return Transform.translate(
          offset: Offset(0.0, offsetY),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: child,
            ),
          ),
        );
      },
      child: dot,
    );
  }
}

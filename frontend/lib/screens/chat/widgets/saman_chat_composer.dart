import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// The approved global composer visual system for Saman Chat.
///
/// Visual structure:
///   [ + ] [ Ask Saman about training, meals, recovery... ] [ mic ] [ send ]
///
/// CRITICAL RULE:
/// - Default send button is strictly NEUTRAL / MONOCHROME (#E3E2E6 surface + #121316 icon).
/// - Never use Saman green for the default send button.
/// - The '+' and 'mic' controls are visually authentic but functionally honest placeholders.
class SamanChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isLoading;
  final String? loadingHintText;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onVoiceTap;

  const SamanChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.isLoading = false,
    this.loadingHintText,
    this.onAttachmentTap,
    this.onVoiceTap,
  });

  @override
  State<SamanChatComposer> createState() => _SamanChatComposerState();
}

class _SamanChatComposerState extends State<SamanChatComposer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant SamanChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      widget.controller.addListener(_handleTextChange);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleTextChange() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _defaultAttachmentAction(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo analysis & workout attachment will arrive in the next phase.',
          style: TextStyle(color: SamanChatTokens.textWhite, fontSize: 13),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _defaultVoiceAction(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Voice capture is not available yet.',
          style: TextStyle(color: SamanChatTokens.textWhite, fontSize: 13),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.isLoading && _hasText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: SamanChatTokens.composerBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: SamanChatTokens.composerBorder,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, 4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Attachment '+' button
          Semantics(
            button: true,
            label: 'Add attachment',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () {
                  if (widget.onAttachmentTap != null) {
                    widget.onAttachmentTap!();
                  } else {
                    _defaultAttachmentAction(context);
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SamanChatTokens.iconContainerBg,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.add_rounded,
                    color: SamanChatTokens.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8.0),

          // Center: Text input
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: !widget.isLoading,
              style: SamanChatTokens.composerInput,
              cursorColor: SamanChatTokens.textWhite,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.text,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: widget.isLoading
                    ? (widget.loadingHintText ?? 'Saman is responding...')
                    : 'Ask Saman about training, meals, recovery...',
                hintStyle: SamanChatTokens.composerHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 8.0,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
              onSubmitted: canSend ? (_) => widget.onSend() : null,
            ),
          ),

          const SizedBox(width: 6.0),

          // Right: Voice dictation mic button
          Semantics(
            button: true,
            label: 'Voice dictation',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () {
                  if (widget.onVoiceTap != null) {
                    widget.onVoiceTap!();
                  } else {
                    _defaultVoiceAction(context);
                  }
                },
                child: const SizedBox(
                  width: 32,
                  height: 36,
                  child: Icon(
                    Icons.mic_none_rounded,
                    color: SamanChatTokens.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 4.0),

          // Right: Monochrome Send / Neutral Stop button
          if (widget.isLoading)
            Semantics(
              label: widget.loadingHintText ?? 'Saman is responding',
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SamanChatTokens.composerStopBg,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: SamanChatTokens.borderSubtle,
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.stop_rounded,
                  color: SamanChatTokens.composerStopIcon,
                  size: 18,
                ),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Send message',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18.0),
                  onTap: canSend ? widget.onSend : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: canSend
                          ? SamanChatTokens.composerSendBg
                          : SamanChatTokens.composerSendDisabledBg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: canSend
                          ? SamanChatTokens.composerSendIcon
                          : SamanChatTokens.composerSendDisabledIcon,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

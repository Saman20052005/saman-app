import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../providers/community_providers.dart';
import '../tokens/saman_ig_tokens.dart';

class CommunityCommentComposer extends StatelessWidget {
  const CommunityCommentComposer({super.key, required this.state,
    required this.controller, required this.focusNode, required this.onChanged,
    required this.onSubmit, required this.onRetry, required this.onCancelReply});

  final CommunityPostDetailState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;
  final VoidCallback onCancelReply;

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        border: Border(
          top: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (state.replyToAuthorName != null)
            Row(children: [
              Icon(Icons.reply_rounded, color: ig.primaryAction),
              Expanded(child: Text('${context.tr('community_replying_to')} ${state.replyToAuthorName}',
                  style: ig.caption(color: ig.primaryAction),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: state.hasPendingSubmission ? null : onCancelReply,
                  tooltip: context.tr('community_cancel_reply'),
                  icon: Icon(Icons.close, color: ig.textSecondary)),
            ]),
          if (state.commentErrorKey != null)
            Row(children: [
              Icon(Icons.info_outline, color: ig.textSecondary),
              Expanded(child: Text(context.tr(state.commentErrorKey!),
                  style: ig.caption(color: ig.textPrimary))),
              if (!state.isSubmitting && state.post != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    context.tr('community_comment_retry'),
                    style: ig.buttonLabel(color: ig.primaryAction),
                  ),
                ),
            ]),
          Row(key: const ValueKey('community-comment-input-row'), children: [
            CircleAvatar(
              backgroundColor: ig.primaryAction,
              foregroundColor: ig.onPrimaryAction,
              child: const Icon(Icons.person_outline),
            ),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              key: const ValueKey('community-comment-input'),
              controller: controller, focusNode: focusNode,
              enabled: state.post != null,
              readOnly: state.hasPendingSubmission,
              maxLength: 2000, minLines: 1, maxLines: 3,
              style: ig.body(),
              onChanged: onChanged,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) { if (!state.isSubmitting) onSubmit(); },
              decoration: InputDecoration(hintText: context.tr('community_write_comment'), counterText: '',
                  filled: true, fillColor: ig.surfaceElevated,
                  hintStyle: ig.body(color: ig.textMuted),
                  border: OutlineInputBorder(borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(24))),
            )),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('community-comment-send'),
              tooltip: context.tr('community_comment_send'),
              style: IconButton.styleFrom(
                backgroundColor: ig.primaryAction,
                foregroundColor: ig.onPrimaryAction,
              ),
              onPressed: state.isSubmitting || state.post == null ? null : onSubmit,
              icon: state.isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ig.onPrimaryAction,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ]),
      )),
    );
  }
}

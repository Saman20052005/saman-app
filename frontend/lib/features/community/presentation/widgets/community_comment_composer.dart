import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../providers/community_providers.dart';

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
    final theme = Theme.of(context);
    return Material(
      color: SamanHomeTokens.companionSurface,
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (state.replyToAuthorName != null)
            Row(children: [
              const Icon(Icons.reply_rounded, color: SamanHomeTokens.greenAccent),
              Expanded(child: Text('${context.tr('community_replying_to')} ${state.replyToAuthorName}',
                  style: theme.textTheme.bodySmall?.copyWith(color: SamanHomeTokens.greenAccent),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: state.hasPendingSubmission ? null : onCancelReply,
                  tooltip: context.tr('community_cancel_reply'), icon: const Icon(Icons.close)),
            ]),
          if (state.commentErrorKey != null)
            Row(children: [
              const Icon(Icons.info_outline, color: SamanHomeTokens.textSecondary),
              Expanded(child: Text(context.tr(state.commentErrorKey!),
                  style: theme.textTheme.bodySmall?.copyWith(color: SamanHomeTokens.textPrimary))),
              if (!state.isSubmitting && state.post != null)
                TextButton(onPressed: onRetry, child: Text(context.tr('community_comment_retry'))),
            ]),
          Row(key: const ValueKey('community-comment-input-row'), children: [
            const CircleAvatar(backgroundColor: SamanHomeTokens.greenAccent,
                foregroundColor: SamanHomeTokens.canvas, child: Icon(Icons.person_outline)),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              key: const ValueKey('community-comment-input'),
              controller: controller, focusNode: focusNode,
              enabled: state.post != null,
              readOnly: state.hasPendingSubmission,
              maxLength: 2000, minLines: 1, maxLines: 3,
              style: theme.textTheme.bodyMedium?.copyWith(color: SamanHomeTokens.textWhite),
              onChanged: onChanged,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) { if (!state.isSubmitting) onSubmit(); },
              decoration: InputDecoration(hintText: context.tr('community_write_comment'), counterText: '',
                  filled: true, fillColor: SamanHomeTokens.cardSurfaceElevated,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(color: SamanHomeTokens.textSecondary),
                  border: OutlineInputBorder(borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill))),
            )),
            IconButton(
              key: const ValueKey('community-comment-send'),
              tooltip: context.tr('community_comment_send'),
              style: IconButton.styleFrom(backgroundColor: SamanHomeTokens.greenAccent,
                  foregroundColor: SamanHomeTokens.canvas),
              onPressed: state.isSubmitting || state.post == null ? null : onSubmit,
              icon: state.isSubmitting ? const CircularProgressIndicator() : const Icon(Icons.send_rounded),
            ),
          ]),
        ]),
      )),
    );
  }
}

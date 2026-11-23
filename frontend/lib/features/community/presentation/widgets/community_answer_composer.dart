import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../providers/community_providers.dart';
import '../tokens/saman_ig_tokens.dart';

class CommunityAnswerComposer extends StatelessWidget {
  const CommunityAnswerComposer({super.key, required this.state, required this.controller,
      required this.focusNode, required this.onChanged, required this.onSend, required this.onRetry});
  final CommunityQuestionDetailState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onRetry;
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
          if (state.errorMessage != null)
            Row(children: [
              Expanded(child: Text(context.tr(state.errorMessage!),
                  style: ig.caption(color: ig.textPrimary))),
              if (state.accessible && !state.isSubmitting)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    context.tr('community_comment_retry'),
                    style: ig.buttonLabel(color: ig.primaryAction),
                  ),
                ),
            ]),
          Row(key: const ValueKey('community-answer-input-row'), children: [
            Expanded(child: TextField(key: const ValueKey('community-answer-input'),
              controller: controller, focusNode: focusNode, maxLength: 2000, minLines: 1, maxLines: 3,
              enabled: state.accessible && !state.isLoading, readOnly: state.hasPendingAnswer,
              onChanged: onChanged, textInputAction: TextInputAction.send,
              onSubmitted: (_) { if (!state.isSubmitting) onSend(); },
              style: ig.body(),
              decoration: InputDecoration(hintText: context.tr('community_answer_hint'), counterText: '',
                  filled: true, fillColor: ig.surfaceElevated,
                  hintStyle: ig.body(color: ig.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
            )),
            const SizedBox(width: 8),
            IconButton(tooltip: context.tr('community_answer_send'),
              onPressed: state.isSubmitting || !state.accessible || state.isLoading ? null : onSend,
              icon: state.isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ig.primaryAction,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              color: ig.primaryAction),
          ]),
        ]),
      )),
    );
  }
}

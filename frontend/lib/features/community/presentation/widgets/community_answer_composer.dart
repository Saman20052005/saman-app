import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../providers/community_providers.dart';

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
  Widget build(BuildContext context) => Material(
    color: SamanHomeTokens.companionSurface,
    child: SafeArea(top: false, child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (state.errorMessage != null)
          Row(children: [
            Expanded(child: Text(context.tr(state.errorMessage!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SamanHomeTokens.textPrimary))),
            if (state.accessible && !state.isSubmitting)
              TextButton(onPressed: onRetry, child: Text(context.tr('community_comment_retry'))),
          ]),
        Row(key: const ValueKey('community-answer-input-row'), children: [
          Expanded(child: TextField(key: const ValueKey('community-answer-input'),
            controller: controller, focusNode: focusNode, maxLength: 2000, minLines: 1, maxLines: 3,
            enabled: state.accessible && !state.isLoading, readOnly: state.hasPendingAnswer,
            onChanged: onChanged, textInputAction: TextInputAction.send,
            onSubmitted: (_) { if (!state.isSubmitting) onSend(); },
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: SamanHomeTokens.textWhite),
            decoration: InputDecoration(hintText: context.tr('community_answer_hint'), counterText: '',
                filled: true, fillColor: SamanHomeTokens.canvas,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill), borderSide: BorderSide.none)),
          )),
          const SizedBox(width: 8),
          IconButton(tooltip: context.tr('community_answer_send'),
            onPressed: state.isSubmitting || !state.accessible || state.isLoading ? null : onSend,
            icon: state.isSubmitting ? const CircularProgressIndicator() : const Icon(Icons.send_rounded),
            color: SamanHomeTokens.greenAccent),
        ]),
      ]),
    )),
  );
}

import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import '../../widgets/community_answer_composer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/community_post.dart';
import '../../../domain/models/question_answer.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';

class CommunityQuestionDetailScreen extends ConsumerStatefulWidget {
  final String questionId;
  final CommunityPost? initialPost;

  const CommunityQuestionDetailScreen({
    super.key,
    required this.questionId,
    this.initialPost,
  });

  @override
  ConsumerState<CommunityQuestionDetailScreen> createState() =>
      _CommunityQuestionDetailScreenState();
}

class _CommunityQuestionDetailScreenState
    extends ConsumerState<CommunityQuestionDetailScreen> {
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _answerFocusNode = FocusNode();

  @override
  void dispose() {
    _answerController.dispose();
    _answerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendAnswer() async {
    await ref.read(communityQuestionDetailProvider(widget.questionId).notifier)
        .submitAnswer(_answerController.text);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CommunityQuestionDetailState>(communityQuestionDetailProvider(widget.questionId), (previous, next) {
      if (_answerController.text != next.draft) {
        _answerController.value = TextEditingValue(text: next.draft,
            selection: TextSelection.collapsed(offset: next.draft.length));
      }
    });
    final state =
        ref.watch(communityQuestionDetailProvider(widget.questionId));
    final notifier =
        ref.read(communityQuestionDetailProvider(widget.questionId).notifier);

    final post = state.accessible
        ? (ref.watch(useRemoteCommunityProvider) ? state.question : widget.initialPost ?? state.question)
        : null;

    final ig = SamanIgTokens.of(context);
    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, ig),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post != null) _buildQuestionCard(post, ig),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Câu trả lời từ cộng đồng',
                            overflow: TextOverflow.ellipsis,
                            style: ig.displayTitle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${state.answerCount} câu trả lời',
                          style: ig.caption(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.isLoading)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: ig.primaryAction,
                          ),
                        ),
                      )
                    else if (state.errorMessage != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr(state.errorMessage!),
                                style: ig.body(
                                  color: ig.danger,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => notifier.refresh(),
                                style: ig.primaryButtonStyle(borderRadius: 8),
                                child: Text(
                                  'Thử lại',
                                  style: ig.buttonLabel(color: ig.onPrimaryAction),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (state.answers.isEmpty)
                      _buildNoAnswersCard(ig)
                    else
                      ...state.answers.map((ans) => _buildAnswerCard(ans, notifier, ig)),
                    if (state.cursor != null && state.accessible)
                      TextButton(
                        onPressed: state.isLoading ? null : () => notifier.loadAnswers(more: true),
                        child: Text(
                          context.tr('community_answers_more'),
                          style: ig.buttonLabel(color: ig.primaryAction),
                        ),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            CommunityAnswerComposer(state: state, controller: _answerController,
              focusNode: _answerFocusNode, onChanged: notifier.updateDraft, onSend: _handleSendAnswer,
              onRetry: () { if (state.hasPendingAnswer) { _handleSendAnswer(); } else { notifier.refresh(); } }),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanIgTokens ig) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(bottom: BorderSide(color: ig.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          Text(
            'Chi tiết câu hỏi',
            style: ig.displayTitle(fontSize: 16),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.share_outlined,
              color: ig.textPrimary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(CommunityPost post, SamanIgTokens ig) {
    final qa = post.qaInfo;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.surfaceElevated,
                ),
                child: Center(
                  child: Text(
                    post.author.name.isNotEmpty ? post.author.name[0] : 'S',
                    style: ig.displayTitle(
                      fontSize: 15,
                      color: ig.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.name,
                      style: ig.username(fontSize: 13),
                    ),
                    Text(
                      post.timeAgo,
                      style: ig.caption(fontSize: 11, color: ig.textMuted),
                    ),
                  ],
                ),
              ),
              if (qa?.categoryTag != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ig.primaryAction.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: ig.primaryAction.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    qa!.categoryTag,
                    style: ig.caption(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ig.primaryAction,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            qa?.question ?? post.caption,
            style: ig.displayTitle(fontSize: 16).copyWith(height: 1.35),
          ),
          if (qa?.details != null && qa!.details!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              qa.details!,
              style: ig.body(
                fontSize: 13,
                color: ig.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoAnswersCard(SamanIgTokens ig) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 36, color: ig.textSecondary),
          const SizedBox(height: 10),
          Text(
            'Chưa có câu trả lời nào',
            style: ig.username(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Hãy là người đầu tiên chia sẻ kinh nghiệm của bạn!',
            style: ig.caption(fontSize: 12, color: ig.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(
    QuestionAnswer ans,
    CommunityQuestionDetailNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ans.isPinnedBest
              ? ig.primaryAction.withOpacity(0.45)
              : ig.border,
          width: ans.isPinnedBest ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ans.isPinnedBest) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ig.primaryAction.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: ig.primaryAction,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Câu trả lời hữu ích nhất',
                    style: ig.caption(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ig.primaryAction,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.surfaceElevated,
                ),
                child: Center(
                  child: Text(
                    ans.author.name.isNotEmpty ? ans.author.name[0] : 'S',
                    style: ig.displayTitle(
                      fontSize: 13,
                      color: ig.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ans.author.name,
                      style: ig.username(fontSize: 13),
                    ),
                    Text(
                      ans.timeAgo,
                      style: ig.caption(fontSize: 11, color: ig.textMuted),
                    ),
                  ],
                ),
              ),
              // Desired-state helpful action; pending work cannot toggle twice.
              Tooltip(message: context.tr(ans.isUpvoted ? 'community_helpful_remove' : 'community_helpful_add'), child: TextButton(
                onPressed: stateVoteEnabled(ans, notifier) ? () => notifier.toggleUpvote(ans.id) : null,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ans.isUpvoted
                        ? ig.primaryAction.withOpacity(0.14)
                        : ig.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ans.isUpvoted
                          ? ig.primaryAction
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.thumb_up_alt_rounded,
                        size: 13,
                        color: ans.isUpvoted
                            ? ig.primaryAction
                            : ig.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ans.upvoteCount}',
                        style: ig.caption(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ans.isUpvoted
                              ? ig.primaryAction
                              : ig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ans.content,
            style: ig.body(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  bool stateVoteEnabled(QuestionAnswer answer, CommunityQuestionDetailNotifier notifier) {
    final state = ref.watch(communityQuestionDetailProvider(widget.questionId));
    return state.accessible && notifier.canVote(answer) && !state.voting.contains(answer.id);
  }
}

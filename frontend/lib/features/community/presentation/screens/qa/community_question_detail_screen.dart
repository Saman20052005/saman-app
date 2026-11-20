import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import '../../widgets/community_answer_composer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/community_post.dart';
import '../../../domain/models/question_answer.dart';
import '../../providers/community_providers.dart';

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

    final tokens = SamanHomeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, tokens),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post != null) _buildQuestionCard(post, tokens),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Câu trả lời từ cộng đồng',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${state.answerCount} câu trả lời',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.isLoading)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: tokens.greenAccent,
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
                                style: TextStyle(
                                  color: tokens.isDark
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFDC2626),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => notifier.refresh(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: tokens.greenAccent,
                                  foregroundColor: tokens.isDark
                                      ? const Color(0xFF003824)
                                      : const Color(0xFFFFFFFF),
                                ),
                                child: const Text('Thử lại'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (state.answers.isEmpty)
                      _buildNoAnswersCard(tokens)
                    else
                      ...state.answers.map((ans) => _buildAnswerCard(ans, notifier, tokens)),
                    if (state.cursor != null && state.accessible)
                      TextButton(onPressed: state.isLoading ? null : () => notifier.loadAnswers(more: true),
                          child: Text(context.tr('community_answers_more'))),
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

  Widget _buildAppBar(BuildContext context, SamanHomePalette tokens) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Text(
            'Chi tiết câu hỏi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.share_outlined,
              color: tokens.textPrimary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(CommunityPost post, SamanHomePalette tokens) {
    final qa = post.qaInfo;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
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
                  color: tokens.secondarySurface,
                ),
                child: Center(
                  child: Text(
                    post.author.name.isNotEmpty ? post.author.name[0] : 'S',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      post.timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (qa?.categoryTag != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.greenAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: tokens.greenAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    qa!.categoryTag,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            qa?.question ?? post.caption,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
              height: 1.35,
            ),
          ),
          if (qa?.details != null && qa!.details!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              qa.details!,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoAnswersCard(SamanHomePalette tokens) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 36, color: tokens.textSecondary),
          const SizedBox(height: 10),
          Text(
            'Chưa có câu trả lời nào',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Hãy là người đầu tiên chia sẻ kinh nghiệm của bạn!',
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(
    QuestionAnswer ans,
    CommunityQuestionDetailNotifier notifier,
    SamanHomePalette tokens,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ans.isPinnedBest
              ? tokens.greenAccent.withOpacity(0.4)
              : tokens.border,
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
                color: tokens.greenAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: tokens.greenAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Câu trả lời hữu ích nhất',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
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
                  color: tokens.secondarySurface,
                ),
                child: Center(
                  child: Text(
                    ans.author.name.isNotEmpty ? ans.author.name[0] : 'S',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      ans.timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textMuted,
                      ),
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
                        ? tokens.greenAccent.withOpacity(0.15)
                        : tokens.secondarySurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ans.isUpvoted
                          ? tokens.greenAccent
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.thumb_up_alt_rounded,
                        size: 13,
                        color: ans.isUpvoted
                            ? tokens.greenAccent
                            : tokens.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ans.upvoteCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ans.isUpvoted
                              ? tokens.greenAccent
                              : tokens.textSecondary,
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
            style: TextStyle(
              fontSize: 13,
              color: tokens.textPrimary,
              height: 1.4,
            ),
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

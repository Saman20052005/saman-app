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

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post != null) _buildQuestionCard(post),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Câu trả lời từ cộng đồng',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SamanHomeTokens.textWhite,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${state.answerCount} câu trả lời',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFBBCAAF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: SamanHomeTokens.greenAccent,
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
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => notifier.refresh(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SamanHomeTokens.greenAccent,
                                  foregroundColor: const Color(0xFF003824),
                                ),
                                child: const Text('Thử lại'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (state.answers.isEmpty)
                      _buildNoAnswersCard()
                    else
                      ...state.answers.map((ans) => _buildAnswerCard(ans, notifier)),
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

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2021), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: SamanHomeTokens.textWhite,
              size: 22,
            ),
          ),
          const Text(
            'Chi tiết câu hỏi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.share_outlined,
              color: SamanHomeTokens.textWhite,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(CommunityPost post) {
    final qa = post.qaInfo;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F21),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF292A2B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF292A2B),
                ),
                child: Center(
                  child: Text(
                    post.author.name.isNotEmpty ? post.author.name[0] : 'S',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SamanHomeTokens.textWhite,
                      ),
                    ),
                    Text(
                      post.timeAgo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF71767B),
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
                    color: SamanHomeTokens.greenAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: SamanHomeTokens.greenAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    qa!.categoryTag,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            qa?.question ?? post.caption,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
              height: 1.35,
            ),
          ),
          if (qa?.details != null && qa!.details!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              qa.details!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFBBCAAF),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoAnswersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F21),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(Icons.forum_outlined, size: 36, color: Color(0xFFBBCAAF)),
          SizedBox(height: 10),
          Text(
            'Chưa có câu trả lời nào',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SamanHomeTokens.textWhite,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Hãy là người đầu tiên chia sẻ kinh nghiệm của bạn!',
            style: TextStyle(fontSize: 12, color: Color(0xFF71767B)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(
    QuestionAnswer ans,
    CommunityQuestionDetailNotifier notifier,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F21),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ans.isPinnedBest
              ? SamanHomeTokens.greenAccent.withOpacity(0.4)
              : const Color(0xFF292A2B),
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
                color: SamanHomeTokens.greenAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: SamanHomeTokens.greenAccent,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Câu trả lời hữu ích nhất',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF292A2B),
                ),
                child: Center(
                  child: Text(
                    ans.author.name.isNotEmpty ? ans.author.name[0] : 'S',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SamanHomeTokens.textWhite,
                      ),
                    ),
                    Text(
                      ans.timeAgo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF71767B),
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
                        ? SamanHomeTokens.greenAccent.withOpacity(0.15)
                        : const Color(0xFF292A2B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ans.isUpvoted
                          ? SamanHomeTokens.greenAccent
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.thumb_up_alt_rounded,
                        size: 13,
                        color: ans.isUpvoted
                            ? SamanHomeTokens.greenAccent
                            : const Color(0xFFBBCAAF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ans.upvoteCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ans.isUpvoted
                              ? SamanHomeTokens.greenAccent
                              : const Color(0xFFBBCAAF),
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
            style: const TextStyle(
              fontSize: 13,
              color: SamanHomeTokens.textWhite,
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

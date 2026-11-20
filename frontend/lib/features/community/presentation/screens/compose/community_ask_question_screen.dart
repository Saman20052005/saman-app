import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/draft_post.dart';
import '../../providers/community_providers.dart';
import '../../providers/community_composer_provider.dart';
import '../../widgets/draft_discard_dialog.dart';

class CommunityAskQuestionScreen extends ConsumerStatefulWidget {
  const CommunityAskQuestionScreen({super.key});

  @override
  ConsumerState<CommunityAskQuestionScreen> createState() =>
      _CommunityAskQuestionScreenState();
}

class _CommunityAskQuestionScreenState
    extends ConsumerState<CommunityAskQuestionScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  final List<String> _topics = [
    'Dinh dưỡng',
    'Tập luyện',
    'Phục hồi',
    'Thói quen',
    'Thực phẩm bổ sung',
  ];

  String get _selectedTopic => ref.read(communityQuestionComposerProvider).topic;
  bool get _isSubmitting => ref.read(communityQuestionComposerProvider).isSubmitting;
  bool get _pending => ref.read(communityQuestionComposerProvider).hasPendingSubmission;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(communityQuestionComposerProvider);
    _titleController.text = draft.caption;
    _detailsController.text = draft.questionDetails;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    if (ref.read(useRemoteCommunityProvider)) { Navigator.pop(context); return; }
    final title = _titleController.text.trim();
    if (title.isNotEmpty) {
      final action = await DraftDiscardDialog.show(context);
      if (!mounted) return;
      if (action == DraftDiscardAction.saveDraft) {
        final draft = DraftPost(
          id: 'draft_qa_${DateTime.now().millisecondsSinceEpoch}',
          questionTitle: title,
          questionDetails: _detailsController.text.trim(),
          topic: _selectedTopic,
          updatedAt: DateTime.now(),
        );
        await ref.read(communityRepositoryProvider).saveDraft(draft);
        if (!mounted) return;
        Navigator.pop(context);
      } else if (action == DraftDiscardAction.discard) {
        Navigator.pop(context);
      }
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _handleSubmit() async {
    final post = await ref.read(communityQuestionComposerProvider.notifier).publish();
    if (!mounted || post == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('community_publish_success'))));
    Navigator.popUntil(context,
      (route) => route.settings.name == '/community/feed' || route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(communityQuestionComposerProvider);
    ref.listen<CommunityComposerState>(communityQuestionComposerProvider, (previous, next) {
      if (_titleController.text != next.caption) _titleController.text = next.caption;
      if (_detailsController.text != next.questionDetails) _detailsController.text = next.questionDetails;
    });
    final tokens = SamanHomeTokens.of(context);
    final charCount = _titleController.text.length;

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildAppBar(context, tokens),
            if (draft.errorMessage != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(context.tr(draft.errorMessage!), style: tokens.headerSubtitle)),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author Identity
                    _buildAuthorRow(tokens),
                    _QuestionAudience(
                      value: draft.audience,
                      enabled: !draft.hasPendingSubmission,
                      onChanged: ref.read(communityQuestionComposerProvider.notifier).setAudience,
                    ),
                    const SizedBox(height: 16),

                    // Topic Selection
                    _buildTopicChips(tokens),
                    const SizedBox(height: 16),

                    // Question Title input
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.cardSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Câu hỏi của bạn *',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                              Text(
                                '$charCount/150 ký tự',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: charCount > 130
                                      ? tokens.carbsAmber
                                      : tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const ValueKey('question-title-input'),
                            controller: _titleController,
                            readOnly: draft.hasPendingSubmission,
                            maxLength: 150,
                            maxLines: 2,
                            onChanged: ref.read(communityQuestionComposerProvider.notifier).setCaption,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: tokens.textPrimary,
                              height: 1.3,
                            ),
                            decoration: InputDecoration(
                              filled: false,
                              counterStyle: tokens.headerSubtitle,
                              hintText: 'Đặt câu hỏi ngắn gọn, trọng tâm...',
                              hintStyle: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: tokens.textMuted,
                              ),
                              counterText: '',
                              border: InputBorder.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Question Details input
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.cardSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chi tiết thêm (không bắt buộc)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const ValueKey('question-details-input'),
                            controller: _detailsController,
                            readOnly: draft.hasPendingSubmission,
                            onChanged: ref.read(communityQuestionComposerProvider.notifier).setQuestionDetails,
                            maxLength: 2000,
                            maxLines: 4,
                            style: TextStyle(
                              fontSize: 14,
                              color: tokens.textPrimary,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              filled: false,
                              counterStyle: tokens.headerSubtitle,
                              hintText:
                                  'Chia sẻ bối cảnh, mục tiêu của bạn để nhận được câu trả lời chính xác hơn...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: tokens.textMuted,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanHomePalette tokens) {
    final hasTitle = _titleController.text.trim().isNotEmpty;

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
            onPressed: _handleClose,
            icon: Icon(
              Icons.close_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Text(
            'Đặt câu hỏi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          _isSubmitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.greenAccent,
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: hasTitle ? _handleSubmit : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  label: const Text('Đăng'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.greenAccent,
                    foregroundColor: tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAuthorRow(SamanHomePalette tokens) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.secondarySurface,
          ),
          child: Icon(
            Icons.person_rounded,
            color: tokens.greenAccent,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.watch(useRemoteCommunityProvider) ? context.tr('community_publish_current_user') : 'Linh Nguyễn',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Hỏi cộng đồng',
              style: TextStyle(fontSize: 11, color: tokens.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopicChips(SamanHomePalette tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Chủ đề thảo luận',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary,
                ),
              ),
            ),
            Text(
              'Bắt buộc chọn 1',
              style: TextStyle(
                fontSize: 11,
                color: tokens.greenAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _topics.map((t) {
              final isSelected = _selectedTopic == t;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t),
                  selected: isSelected,
                  selectedColor: tokens.greenAccent,
                  disabledColor: tokens.cardSurface,
                  backgroundColor: tokens.cardSurface,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (tokens.isDark
                            ? const Color(0xFF003824)
                            : const Color(0xFFFFFFFF))
                        : tokens.textSecondary,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? tokens.greenAccent
                        : tokens.border,
                  ),
                  onSelected: _pending ? null : (_) => ref.read(communityQuestionComposerProvider.notifier).setTopic(t),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _QuestionAudience extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _QuestionAudience({required this.value, required this.enabled, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return DropdownButtonFormField<String>(
      key: const ValueKey('question-audience'),
      value: value,
      decoration: InputDecoration(filled: false, labelStyle: tokens.headerSubtitle, labelText: context.tr('community_publish_audience')),
      dropdownColor: tokens.cardSurface,
      style: TextStyle(color: tokens.textPrimary),
      items: ['Công khai', 'Người theo dõi', 'Chỉ mình tôi'].map((audience) =>
        DropdownMenuItem(value: audience, child: Text(context.tr(
          audience == 'Công khai' ? 'community_audience_public' :
          audience == 'Người theo dõi' ? 'community_audience_followers' : 'community_audience_private'), style: TextStyle(color: tokens.textPrimary)))).toList(),
      onChanged: enabled ? (next) { if (next != null) onChanged(next); } : null,
    );
  }
}

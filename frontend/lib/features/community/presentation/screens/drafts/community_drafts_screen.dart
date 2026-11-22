import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/draft_post.dart';
import '../../../domain/models/post_attachment_snapshot.dart';
import '../../providers/community_composer_provider.dart';
import '../../providers/community_providers.dart';
import '../compose/community_ask_question_screen.dart';
import '../compose/post_compose_publish_screen.dart';

class CommunityDraftsScreen extends ConsumerWidget {
  const CommunityDraftsScreen({super.key});

  String _draftCategoryLabel(DraftPost draft) {
    if (draft.isQuestionDraft) {
      return draft.topic.isNotEmpty
          ? 'Câu hỏi • ${draft.topic}'
          : 'Câu hỏi';
    }
    if (draft.attachment != null) {
      return draft.attachment!.type == AttachmentType.workout
          ? 'Chia sẻ buổi tập'
          : 'Chia sẻ bữa ăn';
    }
    if (draft.mediaUrls.isNotEmpty) {
      return 'Bài viết • ${draft.mediaUrls.length} ảnh';
    }
    return 'Bài viết văn bản';
  }

  String _formatUpdatedAt(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays == 1) return 'Hôm qua';
    return '${diff.inDays} ngày trước';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DraftPost draft,
    CommunityDraftsNotifier notifier,
    SamanHomePalette tokens,
  ) async {
    final previewText = draft.isQuestionDraft
        ? (draft.questionTitle ?? '')
        : (draft.caption.isNotEmpty
            ? draft.caption
            : 'Bản nháp không có tiêu đề');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: tokens.cardSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tokens.border),
        ),
        title: Text(
          'Xóa bản nháp này?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (previewText.isNotEmpty) ...[
              Text(
                previewText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Hành động này không thể hoàn tác và nội dung chưa đăng sẽ bị mất vĩnh viễn.',
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Hủy',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Xóa bản nháp',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.fatRose,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await notifier.deleteDraft(draft.id);
    }
  }

  void _openDraft(BuildContext context, WidgetRef ref, DraftPost draft) {
    if (draft.isQuestionDraft) {
      final qNotifier = ref.read(communityQuestionComposerProvider.notifier);
      qNotifier.reset();
      qNotifier.setCaption(draft.questionTitle ?? draft.caption);
      if (draft.questionDetails != null) {
        qNotifier.setQuestionDetails(draft.questionDetails!);
      }
      if (draft.topic.isNotEmpty) {
        qNotifier.setTopic(draft.topic);
      }
      qNotifier.setAudience(draft.audience);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CommunityAskQuestionScreen(),
        ),
      );
      return;
    }

    ref.read(communityComposerProvider.notifier).restoreFromDraft(draft);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PostComposePublishScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final state = ref.watch(communityDraftsProvider);
    final notifier = ref.read(communityDraftsProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state.drafts.length, tokens),
            Expanded(
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: tokens.greenAccent,
                      ),
                    )
                  : RefreshIndicator(
                      color: tokens.greenAccent,
                      backgroundColor: tokens.cardSurface,
                      onRefresh: () => notifier.loadDrafts(),
                      child: state.drafts.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) =>
                                  SingleChildScrollView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 12, 16, 0),
                                        child: _buildPrivacyInfoPill(tokens),
                                      ),
                                      _buildEmptyState(tokens),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : _buildDraftsList(
                              context,
                              ref,
                              state.drafts,
                              notifier,
                              tokens,
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    int count,
    SamanHomePalette tokens,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Quay lại',
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Bản nháp bài viết',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.cardSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyInfoPill(SamanHomePalette tokens) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: tokens.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Chỉ bạn nhìn thấy các bản nháp này',
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SamanHomePalette tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.cardSurface,
                border: Border.all(color: tokens.border),
              ),
              child: Icon(
                Icons.edit_note_rounded,
                size: 34,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có bản nháp nào',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Khi bạn bắt đầu viết bài và lưu lại trước khi đăng, bài viết sẽ hiển thị tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftsList(
    BuildContext context,
    WidgetRef ref,
    List<DraftPost> drafts,
    CommunityDraftsNotifier notifier,
    SamanHomePalette tokens,
  ) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: drafts.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 14 : 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildPrivacyInfoPill(tokens);
        }
        final draft = drafts[index - 1];
        final displayText = draft.isQuestionDraft
            ? (draft.questionTitle ?? '')
            : (draft.caption.isNotEmpty
                ? draft.caption
                : 'Bản nháp không có tiêu đề');

        return InkWell(
          onTap: () => _openDraft(context, ref, draft),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumbnail(draft, tokens),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: tokens.secondarySurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _draftCategoryLabel(draft),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tokens.greenAccent,
                              ),
                            ),
                          ),
                          if (!draft.isQuestionDraft && draft.topic.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: tokens.secondarySurface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                draft.topic,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: tokens.textPrimary,
                          height: 1.35,
                        ),
                      ),
                      if (draft.attachment != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tokens.secondarySurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.attachment_rounded,
                                size: 14,
                                color: tokens.textMuted,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  draft.attachment!.durationFormatted != null
                                      ? '${draft.attachment!.title} (${draft.attachment!.durationFormatted})'
                                      : draft.attachment!.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatUpdatedAt(draft.updatedAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      _confirmDelete(context, draft, notifier, tokens),
                  tooltip: 'Xóa bản nháp',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: tokens.fatRose,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(DraftPost draft, SamanHomePalette tokens) {
    if (draft.mediaUrls.isNotEmpty) {
      final url = draft.mediaUrls.first;
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: tokens.secondarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            url.startsWith('http')
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.photo_library_outlined,
                      size: 22,
                      color: tokens.textSecondary,
                    ),
                  )
                : Image.asset(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.photo_library_outlined,
                      size: 22,
                      color: tokens.textSecondary,
                    ),
                  ),
            if (draft.mediaUrls.length > 1)
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: tokens.canvas.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.photo_library_rounded,
                    size: 11,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final IconData icon;
    if (draft.isQuestionDraft) {
      icon = Icons.help_center_rounded;
    } else if (draft.attachment != null) {
      icon = draft.attachment!.type == AttachmentType.workout
          ? Icons.fitness_center_rounded
          : Icons.restaurant_rounded;
    } else {
      icon = Icons.notes_rounded;
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: tokens.secondarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Icon(
        icon,
        size: 24,
        color: tokens.textSecondary,
      ),
    );
  }
}

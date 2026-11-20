import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/draft_post.dart';
import '../../providers/community_composer_provider.dart';
import '../../providers/community_providers.dart';
import '../compose/post_compose_publish_screen.dart';

class CommunityDraftsScreen extends ConsumerWidget {
  const CommunityDraftsScreen({super.key});

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
                  : state.drafts.isEmpty
                      ? _buildEmptyState(tokens)
                      : _buildDraftsList(context, ref, state.drafts, notifier, tokens),
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
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Bản nháp bài viết',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.cardSurface,
                    borderRadius: BorderRadius.circular(10),
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

  Widget _buildEmptyState(SamanHomePalette tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.cardSurface,
              ),
              child: Icon(
                Icons.edit_note_rounded,
                size: 32,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có bản nháp nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Khi bạn bắt đầu viết bài và lưu lại trước khi đăng, bài viết sẽ hiển thị tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textMuted,
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
      padding: const EdgeInsets.all(16),
      itemCount: drafts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final draft = drafts[index];

        return InkWell(
          onTap: () {
            // Restore full draft state into composer
            ref.read(communityComposerProvider.notifier).restoreFromDraft(draft);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PostComposePublishScreen(),
              ),
            );
          },
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (draft.topic.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: tokens.secondarySurface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            draft.topic,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: tokens.greenAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        draft.caption.isNotEmpty
                            ? draft.caption
                            : 'Bản nháp không có tiêu đề',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (draft.mediaUrls.isNotEmpty) ...[
                            Icon(
                              Icons.image_outlined,
                              size: 14,
                              color: tokens.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${draft.mediaUrls.length} ảnh  •  ',
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Đã lưu gần đây',
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
                  onPressed: () => notifier.deleteDraft(draft.id),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: tokens.isDark
                        ? const Color(0xFFFFB4AB)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

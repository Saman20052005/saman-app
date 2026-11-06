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
    final state = ref.watch(communityDraftsProvider);
    final notifier = ref.read(communityDraftsProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state.drafts.length),
            Expanded(
              child: state.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SamanHomeTokens.greenAccent,
                      ),
                    )
                  : state.drafts.isEmpty
                      ? _buildEmptyState()
                      : _buildDraftsList(context, ref, state.drafts, notifier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, int count) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2021), width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: SamanHomeTokens.textWhite,
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text(
                    'Bản nháp bài viết',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.textWhite,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1F21),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E3033)),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFBBCAAF),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1E1F21),
              ),
              child: const Icon(
                Icons.edit_note_rounded,
                size: 32,
                color: Color(0xFFBBCAAF),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có bản nháp nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Khi bạn bắt đầu viết bài và lưu lại trước khi đăng, bài viết sẽ hiển thị tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF71767B),
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
              color: const Color(0xFF1E1F21),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF292A2B)),
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
                            color: const Color(0xFF292A2B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            draft.topic,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: SamanHomeTokens.greenAccent,
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
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SamanHomeTokens.textWhite,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (draft.mediaUrls.isNotEmpty) ...[
                            const Icon(
                              Icons.image_outlined,
                              size: 14,
                              color: Color(0xFFBBCAAF),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${draft.mediaUrls.length} ảnh  •  ',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFBBCAAF),
                              ),
                            ),
                          ],
                          const Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: Color(0xFF71767B),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Đã lưu gần đây',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF71767B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => notifier.deleteDraft(draft.id),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Color(0xFFFFB4AB),
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

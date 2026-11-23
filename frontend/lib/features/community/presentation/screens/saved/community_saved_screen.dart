import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/routes.dart';
import '../../../domain/models/community_post.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';

class CommunitySavedScreen extends ConsumerWidget {
  const CommunitySavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final state = ref.watch(communitySavedProvider);
    final notifier = ref.read(communitySavedProvider.notifier);

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state.posts.length, ig),
            Expanded(
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ig.primaryAction,
                      ),
                    )
                  : state.posts.isEmpty
                      ? _buildEmptyState(ig)
                      : _buildSavedList(context, state.posts, notifier, ig),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    int count,
    SamanIgTokens ig,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(bottom: BorderSide(color: ig.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
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
                    'Bài viết đã lưu',
                    overflow: TextOverflow.ellipsis,
                    style: ig.displayTitle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ig.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ig.border, width: 0.5),
                  ),
                  child: Text(
                    '$count',
                    style: ig.caption(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

  Widget _buildEmptyState(SamanIgTokens ig) {
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
                color: ig.surface,
              ),
              child: Icon(
                Icons.bookmark_border_rounded,
                size: 32,
                color: ig.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có bài viết nào được lưu',
              style: ig.displayTitle(fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Nhấn vào biểu tượng dấu trang ở bất kỳ bài viết nào để lưu lại xem sau.',
              textAlign: TextAlign.center,
              style: ig.body(
                fontSize: 13,
                color: ig.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedList(
    BuildContext context,
    List<CommunityPost> posts,
    CommunitySavedNotifier notifier,
    SamanIgTokens ig,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: posts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final post = posts[index];
        final img = post.photoUrls.isNotEmpty
            ? post.photoUrls.first
            : 'assets/images/nutrition/meal_pho.jpg';

        return InkWell(
          onTap: () {
            Navigator.pushNamed(
              context,
              AppRoutes.communityPost,
              arguments: post.id,
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ig.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ig.border, width: 0.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: ig.surfaceElevated,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: ig.textMuted,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              post.author.name,
                              overflow: TextOverflow.ellipsis,
                              style: ig.username(fontSize: 13),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              try {
                                await notifier.unbookmark(post.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã bỏ lưu bài viết.',
                                        style: ig.body(),
                                      ),
                                      backgroundColor: ig.surface,
                                      duration: const Duration(seconds: 3),
                                      action: SnackBarAction(
                                        label: 'Hoàn tác',
                                        textColor: ig.primaryAction,
                                        onPressed: () => notifier.restore(post),
                                      ),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Không thể bỏ lưu bài viết. Vui lòng thử lại.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: Icon(
                              Icons.bookmark_rounded,
                              size: 20,
                              color: ig.primaryAction,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        post.caption.isNotEmpty
                            ? post.caption
                            : (post.workoutAttachment?.title ??
                                post.nutritionInfo?.defaultBadge ??
                                'Bài viết chia sẻ'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ig.body(
                          fontSize: 12,
                          color: ig.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${post.likeCount} thích • ${post.commentCount} bình luận',
                        style: ig.caption(fontSize: 11, color: ig.textMuted),
                      ),
                    ],
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

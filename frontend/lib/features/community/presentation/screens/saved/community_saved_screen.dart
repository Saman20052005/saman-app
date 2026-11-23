import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/routes.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/community_post.dart';
import '../../providers/community_providers.dart';

class CommunitySavedScreen extends ConsumerWidget {
  const CommunitySavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final state = ref.watch(communitySavedProvider);
    final notifier = ref.read(communitySavedProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state.posts.length, tokens),
            Expanded(
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: tokens.greenAccent,
                      ),
                    )
                  : state.posts.isEmpty
                      ? _buildEmptyState(tokens)
                      : _buildSavedList(context, state.posts, notifier, tokens),
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
                    'Bài viết đã lưu',
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
                Icons.bookmark_border_rounded,
                size: 32,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có bài viết nào được lưu',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Nhấn vào biểu tượng dấu trang ở bất kỳ bài viết nào để lưu lại xem sau.',
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

  Widget _buildSavedList(
    BuildContext context,
    List<CommunityPost> posts,
    CommunitySavedNotifier notifier,
    SamanHomePalette tokens,
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
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
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
                        color: tokens.secondarySurface,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: tokens.textMuted,
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
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
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
                                        style: TextStyle(color: tokens.textPrimary),
                                      ),
                                      backgroundColor: tokens.cardSurface,
                                      duration: const Duration(seconds: 3),
                                      action: SnackBarAction(
                                        label: 'Hoàn tác',
                                        textColor: tokens.greenAccent,
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
                              color: tokens.greenAccent,
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
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${post.likeCount} thích • ${post.commentCount} bình luận',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textMuted,
                        ),
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

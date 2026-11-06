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
    final state = ref.watch(communitySavedProvider);
    final notifier = ref.read(communitySavedProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state.posts.length),
            Expanded(
              child: state.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SamanHomeTokens.greenAccent,
                      ),
                    )
                  : state.posts.isEmpty
                      ? _buildEmptyState()
                      : _buildSavedList(context, state.posts, notifier),
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
                    'Bài viết đã lưu',
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
                Icons.bookmark_border_rounded,
                size: 32,
                color: Color(0xFFBBCAAF),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có bài viết nào được lưu',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Nhấn vào biểu tượng dấu trang ở bất kỳ bài viết nào để lưu lại xem sau.',
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

  Widget _buildSavedList(
    BuildContext context,
    List<CommunityPost> posts,
    CommunitySavedNotifier notifier,
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
              color: const Color(0xFF1E1F21),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF292A2B)),
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
                        color: const Color(0xFF292A2B),
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: Color(0xFF55585C),
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
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: SamanHomeTokens.textWhite,
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
                                      content: const Text('Đã bỏ lưu bài viết.'),
                                      backgroundColor: const Color(0xFF1F2021),
                                      duration: const Duration(seconds: 3),
                                      action: SnackBarAction(
                                        label: 'Hoàn tác',
                                        textColor: SamanHomeTokens.greenAccent,
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
                            icon: const Icon(
                              Icons.bookmark_rounded,
                              size: 20,
                              color: SamanHomeTokens.greenAccent,
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBBCAAF),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${post.likeCount} thích • ${post.commentCount} bình luận',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF71767B),
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

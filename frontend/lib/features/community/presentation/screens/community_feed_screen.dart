import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_post.dart';
import '../providers/community_providers.dart';
import '../widgets/community_bottom_navigation_bar.dart';
import '../widgets/post_card_view.dart';
import 'community_post_detail_screen.dart';
import 'qa/community_question_detail_screen.dart';

class CommunityFeedScreen extends ConsumerWidget {
  const CommunityFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final feedState = ref.watch(communityFeedProvider);
    final feedNotifier = ref.read(communityFeedProvider.notifier);
    final isRemote = ref.watch(useRemoteCommunityProvider);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildTopAppBar(context, tokens),

            // Honest Preview Notice Banner
            if (!isRemote) _buildPreviewNoticeBanner(context, isRemote, tokens),

            // Feed Category Tabs
            _buildCategoryTabs(context, feedState.activeFilter, (filter) {
              feedNotifier.setFilter(filter);
            }, tokens),

            // Feed Content
            Expanded(
              child: feedState.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: tokens.greenAccent,
                      ),
                    )
                  : feedState.errorMessage != null
                      ? _buildErrorView(feedState.errorMessage!, () {
                          feedNotifier.refresh();
                        }, tokens)
                      : RefreshIndicator(
                          color: tokens.greenAccent,
                          backgroundColor: tokens.cardSurface,
                          onRefresh: () => feedNotifier.refresh(),
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: feedState.posts.length + 1,
                            itemBuilder: (context, index) {
                              if (index < feedState.posts.length) {
                                final post = feedState.posts[index];
                                return PostCardView(
                                  post: post,
                                  onLikeToggle: () async {
                                    try {
                                      await feedNotifier.toggleLike(post.id);
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Không thể cập nhật lượt thích. Vui lòng thử lại.'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  onBookmarkToggle: () async {
                                    try {
                                      await feedNotifier.toggleBookmark(post.id);
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Không thể lưu bài viết. Vui lòng thử lại.'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  onOpenDetail: () {
                                    if (post.type == CommunityPostType.qa) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CommunityQuestionDetailScreen(
                                            questionId: post.id,
                                            initialPost: post,
                                          ),
                                        ),
                                      );
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CommunityPostDetailScreen(
                                            postId: post.id,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              }
                              // End of Feed delight card
                              return _buildEndOfFeedCard(context, tokens, isEmpty: feedState.posts.isEmpty);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CommunityBottomNavigationBar(
        currentTab: CommunityNavTab.feed,
      ),
    );
  }

  Widget _buildPreviewNoticeBanner(
    BuildContext context,
    bool isRemote,
    SamanHomePalette tokens,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: tokens.cardSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: tokens.greenAccent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isRemote
                  ? (Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                      ? 'Saman Community (Server mode) • Likes & Bookmarks enabled'
                      : 'Saman Community (Chế độ máy chủ) • Đã kích hoạt Thích & Lưu')
                  : (Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                      ? 'UI Preview • Sample testing data'
                      : 'Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: tokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(BuildContext context, SamanHomePalette tokens) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(
          bottom: BorderSide(
            color: tokens.border,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: tokens.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    context.tr('community_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.greenAccent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.send_rounded,
                  color: tokens.textSecondary,
                  size: 22,
                ),
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                        ? 'Community inbox will open in the next checkpoint.'
                        : 'Hộp thư cộng đồng sẽ mở ở checkpoint tiếp theo.',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(
    BuildContext context,
    CommunityFeedFilter activeFilter,
    ValueChanged<CommunityFeedFilter> onFilterSelected,
    SamanHomePalette tokens,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              context: context,
              label: context.tr('community_tab_all'),
              isActive: activeFilter == CommunityFeedFilter.forYou,
              onTap: () => onFilterSelected(CommunityFeedFilter.forYou),
              tokens: tokens,
              legacyVietnameseText: 'Dành cho bạn',
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              context: context,
              label: context.tr('community_tab_following'),
              isActive: activeFilter == CommunityFeedFilter.following,
              onTap: () => onFilterSelected(CommunityFeedFilter.following),
              tokens: tokens,
              legacyVietnameseText: 'Đang theo dõi',
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              context: context,
              label: context.tr('community_tab_qa'),
              isActive: activeFilter == CommunityFeedFilter.qa,
              onTap: () => onFilterSelected(CommunityFeedFilter.qa),
              tokens: tokens,
              legacyVietnameseText: 'Hỏi đáp',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required SamanHomePalette tokens,
    String? legacyVietnameseText,
  }) {
    return Stack(
      children: [
        if (legacyVietnameseText != null &&
            Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
          SizedBox(
            width: 0,
            height: 0,
            child: OverflowBox(
              minWidth: 0,
              minHeight: 0,
              maxWidth: 0,
              maxHeight: 0,
              child: Text(legacyVietnameseText),
            ),
          ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: isActive
                  ? tokens.greenAccent
                  : tokens.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? null
                  : Border.all(color: tokens.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? (tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF))
                    : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndOfFeedCard(
    BuildContext context,
    SamanHomePalette tokens, {
    bool isEmpty = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tokens.secondarySurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isEmpty ? Icons.inbox_rounded : Icons.task_alt_rounded,
              size: 26,
              color: tokens.greenAccent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isEmpty
                ? context.tr('community_empty_feed')
                : context.tr('community_all_caught_up'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                ? 'Share your energy or start a discussion with the community today.'
                : 'Hãy chia sẻ năng lượng của bạn hoặc khởi tạo thảo luận cùng cộng đồng hôm nay.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: tokens.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(
    String message,
    VoidCallback onRetry,
    SamanHomePalette tokens,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: tokens.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 15,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
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
    );
  }
}

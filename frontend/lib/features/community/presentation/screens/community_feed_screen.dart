import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../../../config/routes.dart';
import '../../domain/models/community_post.dart';
import '../providers/community_dm_provider.dart';
import '../providers/community_providers.dart';
import '../providers/community_social_providers.dart';
import '../tokens/saman_ig_tokens.dart';
import '../widgets/community_bottom_navigation_bar.dart';
import '../widgets/community_call_host_listener.dart';
import '../widgets/community_story_tray.dart';
import '../widgets/post_card_view.dart';
import 'community_post_detail_screen.dart';
import 'qa/community_question_detail_screen.dart';

class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() =>
      _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(communityStoriesProvider.notifier).loadStories();
      ref.read(communityDmUnreadProvider.notifier).loadUnreadCount();
      ref.read(communityDmWsServiceProvider).connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final feedState = ref.watch(communityFeedProvider);
    final feedNotifier = ref.read(communityFeedProvider.notifier);
    final isRemote = ref.watch(useRemoteCommunityProvider);
    final dmUnreadCount = ref.watch(communityDmUnreadProvider);
    final showStoryTray = feedState.activeFilter != CommunityFeedFilter.qa;

    return CommunityCallHostListener(
      child: Scaffold(
        backgroundColor: ig.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top App Bar
              _buildTopAppBar(context, ig, dmUnreadCount),

              // Honest Preview Notice Banner
              if (!isRemote) _buildPreviewNoticeBanner(context, isRemote, ig),

              // Feed Category Tabs
              _buildCategoryTabs(context, feedState.activeFilter, (filter) {
                feedNotifier.setFilter(filter);
              }, ig),

              // Feed Content
              Expanded(
                child: feedState.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: ig.primaryAction,
                        ),
                      )
                    : feedState.errorMessage != null
                        ? _buildErrorView(feedState.errorMessage!, () {
                            feedNotifier.refresh();
                          }, ig)
                        : RefreshIndicator(
                            color: ig.primaryAction,
                            backgroundColor: ig.surface,
                            onRefresh: () async {
                              await Future.wait([
                                feedNotifier.refresh(),
                                ref
                                    .read(communityStoriesProvider.notifier)
                                    .loadStories(),
                                ref
                                    .read(communityDmUnreadProvider.notifier)
                                    .loadUnreadCount(),
                              ]);
                            },
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: (showStoryTray ? 1 : 0) +
                                  feedState.posts.length +
                                  1,
                              itemBuilder: (context, index) {
                                if (showStoryTray && index == 0) {
                                  return const CommunityStoryTray();
                                }
                                final postIndex =
                                    showStoryTray ? index - 1 : index;
                                if (postIndex < feedState.posts.length) {
                                  final post = feedState.posts[postIndex];
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
                                return _buildEndOfFeedCard(context, ig, isEmpty: feedState.posts.isEmpty);
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
      ),
    );
  }

  Widget _buildPreviewNoticeBanner(
    BuildContext context,
    bool isRemote,
    SamanIgTokens ig,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: ig.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: ig.textSecondary,
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
              style: ig.caption(
                fontSize: 11,
                color: ig.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(
    BuildContext context,
    SamanIgTokens ig,
    int unreadCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: ig.canvas,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: SamanIgTokens.minTouchTarget,
                      minHeight: SamanIgTokens.minTouchTarget,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: ig.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr('community_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ig.displayTitle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: ig.textPrimary,
                    ).copyWith(letterSpacing: -0.4, height: 1.2),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('feed-inbox-button'),
            constraints: const BoxConstraints(
              minWidth: SamanIgTokens.minTouchTarget,
              minHeight: SamanIgTokens.minTouchTarget,
            ),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.send_outlined,
                  color: ig.textPrimary,
                  size: 22,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -5,
                    right: -6,
                    child: Container(
                      key: const ValueKey('feed-inbox-unread-badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: ig.likeHeart,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: ig.caption(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: ig.onPrimaryAction,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.communityInbox);
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
    SamanIgTokens ig,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(
          bottom: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterTab(
              context: context,
              label: context.tr('community_tab_all'),
              isActive: activeFilter == CommunityFeedFilter.forYou,
              onTap: () => onFilterSelected(CommunityFeedFilter.forYou),
              ig: ig,
              legacyVietnameseText: 'Dành cho bạn',
            ),
            const SizedBox(width: 20),
            _buildFilterTab(
              context: context,
              label: context.tr('community_tab_following'),
              isActive: activeFilter == CommunityFeedFilter.following,
              onTap: () => onFilterSelected(CommunityFeedFilter.following),
              ig: ig,
              legacyVietnameseText: 'Đang theo dõi',
            ),
            const SizedBox(width: 20),
            _buildFilterTab(
              context: context,
              label: context.tr('community_tab_qa'),
              isActive: activeFilter == CommunityFeedFilter.qa,
              onTap: () => onFilterSelected(CommunityFeedFilter.qa),
              ig: ig,
              legacyVietnameseText: 'Hỏi đáp',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab({
    required BuildContext context,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required SamanIgTokens ig,
    String? legacyVietnameseText,
  }) {
    return Stack(
      children: [
        if (legacyVietnameseText != null && legacyVietnameseText != label)
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
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isActive ? ig.textPrimary : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
            child: Text(
              label,
              style: ig.username(
                fontSize: 13.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? ig.textPrimary : ig.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndOfFeedCard(
    BuildContext context,
    SamanIgTokens ig, {
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
              color: ig.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isEmpty ? Icons.inbox_rounded : Icons.task_alt_rounded,
              size: 26,
              color: ig.primaryAction,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isEmpty
                ? context.tr('community_empty_feed')
                : context.tr('community_all_caught_up'),
            textAlign: TextAlign.center,
            style: ig.displayTitle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ig.textPrimary,
            ).copyWith(height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(
            Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                ? 'Share your energy or start a discussion with the community today.'
                : 'Hãy chia sẻ năng lượng của bạn hoặc khởi tạo thảo luận cùng cộng đồng hôm nay.',
            textAlign: TextAlign.center,
            style: ig.caption(
              fontSize: 13,
              color: ig.textSecondary,
            ).copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(
    String message,
    VoidCallback onRetry,
    SamanIgTokens ig,
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
              color: ig.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ig.body(
                color: ig.textPrimary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ig.primaryButtonStyle(),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

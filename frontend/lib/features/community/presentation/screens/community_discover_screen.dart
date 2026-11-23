import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/community_author.dart';
import '../../domain/models/community_discover_item.dart';
import '../providers/community_providers.dart';
import '../tokens/saman_ig_tokens.dart';
import '../widgets/community_bottom_navigation_bar.dart';
import 'community_post_detail_screen.dart';
import 'profile/community_profile_screen.dart';

class CommunityDiscoverScreen extends ConsumerStatefulWidget {
  const CommunityDiscoverScreen({super.key});

  @override
  ConsumerState<CommunityDiscoverScreen> createState() =>
      _CommunityDiscoverScreenState();
}

class _CommunityDiscoverScreenState
    extends ConsumerState<CommunityDiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final isRemote = ref.watch(useRemoteCommunityProvider);
    final discoverState = ref.watch(communityDiscoverProvider);
    final discoverNotifier = ref.read(communityDiscoverProvider.notifier);

    final hasNoResults = !discoverState.isLoading &&
        discoverState.searchQuery.trim().isNotEmpty &&
        discoverState.data.gridItems.isEmpty &&
        discoverState.data.trendingTopics.isEmpty &&
        discoverState.data.recommendedCreators.isEmpty;

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildHeader(context, ig),

            // Honest Preview Notice Banner (hidden in remote mode)
            if (!isRemote) _buildPreviewNoticeBanner(ig),

            // Search Bar
            _buildSearchBar(discoverNotifier, ig),

            // Content Scroll
            Expanded(
              child: discoverState.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ig.primaryAction,
                      ),
                    )
                  : RefreshIndicator(
                      color: ig.primaryAction,
                      backgroundColor: ig.surface,
                      onRefresh: () => discoverNotifier.refresh(),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Topic Chips
                            _buildTopicChips(
                              discoverState.data.topicChips,
                              discoverState.activeTopic,
                              (topic) => discoverNotifier.setTopic(topic),
                              ig,
                            ),
                            const SizedBox(height: 12),

                            if (hasNoResults)
                              _buildSearchEmptyState(discoverNotifier, ig)
                            else ...[
                              // Section 1: Visual Grid (3x3 edge-to-edge)
                              _buildVisualGridSection(
                                context,
                                discoverState.data.gridItems,
                                ig,
                              ),
                              const SizedBox(height: 24),

                              // Section 2: Trending Topics
                              if (discoverState.data.trendingTopics.isNotEmpty) ...[
                                _buildTrendingTopicsSection(
                                  discoverState.data.trendingTopics,
                                  discoverNotifier,
                                  ig,
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Section 3: Recommended Creators to follow
                              if (discoverState.data.recommendedCreators.isNotEmpty)
                                _buildRecommendedCreatorsSection(
                                  discoverState.data.recommendedCreators,
                                  (authorId) =>
                                      discoverNotifier.toggleFollow(authorId),
                                  ig,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CommunityBottomNavigationBar(
        currentTab: CommunityNavTab.discover,
      ),
    );
  }

  Widget _buildPreviewNoticeBanner(SamanIgTokens ig) {
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
              'Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm',
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

  Widget _buildHeader(BuildContext context, SamanIgTokens ig) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khám phá cộng đồng',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.displayTitle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: ig.textPrimary,
                        ).copyWith(letterSpacing: -0.3),
                      ),
                      Text(
                        'Không gian truyền cảm hứng',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.caption(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: ig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(
              minWidth: SamanIgTokens.minTouchTarget,
              minHeight: SamanIgTokens.minTouchTarget,
            ),
            icon: Icon(
              Icons.tune_rounded,
              color: ig.textPrimary,
              size: 20,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bộ lọc nâng cao sẽ mở ở checkpoint tiếp theo.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
    CommunityDiscoverNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: ig.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: ig.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => notifier.setSearchQuery(val),
                style: ig.body(
                  color: ig.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm bài viết, chủ đề, thành viên…',
                  hintStyle: ig.body(
                    color: ig.textSecondary,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return Icon(
                    Icons.mic_none_rounded,
                    color: ig.textSecondary,
                    size: 18,
                  );
                }
                return InkWell(
                  key: const ValueKey('discover-search-clear-button'),
                  onTap: () {
                    _searchController.clear();
                    notifier.setSearchQuery('');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      color: ig.textSecondary,
                      size: 18,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicChips(
    List<String> chips,
    String activeTopic,
    ValueChanged<String> onSelected,
    SamanIgTokens ig,
  ) {
    final Map<String, (String, IconData)> topicMeta = {
      'all': ('Tất cả', Icons.apps_rounded),
      'workout': ('Tập luyện', Icons.fitness_center_rounded),
      'meal': ('Bữa ăn', Icons.lunch_dining_rounded),
      'recipe': ('Công thức', Icons.menu_book_rounded),
      'qna': ('Hỏi đáp', Icons.help_center_rounded),
      'journey': ('Hành trình', Icons.route_rounded),
    };

    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = chips[index];
          final meta = topicMeta[key] ?? (key, Icons.tag_rounded);
          final isActive = activeTopic == key;

          return InkWell(
            onTap: () => onSelected(key),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? ig.textPrimary : ig.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    meta.$2,
                    size: 14,
                    color: isActive ? ig.canvas : ig.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    meta.$1,
                    style: ig.caption(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? ig.canvas : ig.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVisualGridSection(
    BuildContext context,
    List<CommunityVisualGridItem> items,
    SamanIgTokens ig,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      size: 18,
                      color: ig.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Khoảnh khắc tiêu biểu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.displayTitle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ig.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Mới nhất',
                style: ig.caption(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ig.primaryAction,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 32,
                    color: ig.textMuted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chưa có khoảnh khắc nào trong chủ đề này',
                    textAlign: TextAlign.center,
                    style: ig.caption(
                      fontSize: 13,
                      color: ig.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1.5,
              mainAxisSpacing: 1.5,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return InkWell(
                onTap: () {
                  if (item.postId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityPostDetailScreen(
                          postId: item.postId!,
                        ),
                      ),
                    );
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildGridMedia(item, ig),
                    // Top badge
                    if (item.hasMultiPhoto || item.hasVideo)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: ig.scrim,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(
                            item.hasMultiPhoto
                                ? Icons.photo_library_rounded
                                : Icons.play_arrow_rounded,
                            size: 12,
                            color: ig.onPrimaryAction,
                          ),
                        ),
                      ),
                    // Bottom gradient & likes
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.75),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.favorite_rounded,
                              size: 11,
                              color: ig.likeHeart,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.formattedLikes,
                              style: TextStyle(
                                fontFamily: SamanIgTokens.fontFamily,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: ig.onPrimaryAction,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildGridMedia(
    CommunityVisualGridItem item,
    SamanIgTokens ig,
  ) {
    final url = item.imageUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildGridPlaceholder(item, ig),
      );
    }
    return _buildGridPlaceholder(item, ig);
  }

  Widget _buildGridPlaceholder(
    CommunityVisualGridItem item,
    SamanIgTokens ig,
  ) {
    return Container(
      color: ig.surfaceElevated,
      child: Center(
        child: Icon(
          item.hasVideo
              ? Icons.play_circle_fill_rounded
              : Icons.image_rounded,
          size: 28,
          color: ig.textMuted,
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(
    CommunityDiscoverNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: ig.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              'Không tìm thấy kết quả phù hợp',
              textAlign: TextAlign.center,
              style: ig.username(
                fontSize: 15,
                color: ig.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hãy thử từ khóa khác hoặc xóa bộ lọc tìm kiếm.',
              textAlign: TextAlign.center,
              style: ig.caption(
                fontSize: 13,
                color: ig.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                _searchController.clear();
                notifier.loadDiscover(topic: 'all', searchQuery: '');
              },
              child: Text(
                'Xóa tìm kiếm',
                style: ig.buttonLabel(
                  fontSize: 13,
                  color: ig.primaryAction,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingTopicsSection(
    List<CommunityTrendingTopic> topics,
    CommunityDiscoverNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      size: 19,
                      color: ig.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Chủ đề đang được quan tâm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.displayTitle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ig.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Thịnh hành',
                style: ig.caption(
                  fontSize: 11,
                  color: ig.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topics.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final topic = topics[index];
              return InkWell(
                onTap: () {
                  _searchController.text = topic.hashtag;
                  notifier.loadDiscover(topic: 'all', searchQuery: topic.hashtag);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ig.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ig.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: ig.surfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.tag_rounded,
                                color: ig.textPrimary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    topic.hashtag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ig.username(
                                      fontSize: 14,
                                      color: ig.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: ig.primaryAction,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          topic.postCountFormatted,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: ig.caption(
                                            fontSize: 11,
                                            color: ig.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: ig.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              topic.growthPercent,
                              style: ig.caption(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: topic.isStable
                                    ? ig.textSecondary
                                    : ig.primaryAction,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: ig.textMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedCreatorsSection(
    List<CommunityAuthor> creators,
    ValueChanged<String> onFollowToggle,
    SamanIgTokens ig,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 19,
                      color: ig.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Có thể bạn muốn theo dõi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.displayTitle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ig.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Xem tất cả',
                style: ig.caption(
                  fontSize: 12,
                  color: ig.primaryAction,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: creators.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final creator = creators[index];
              final isFollowing = creator.isFollowing;

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityProfileScreen(
                        authorId: creator.id,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ig.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ig.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ig.surfaceElevated,
                                border: Border.all(
                                  color: ig.border,
                                  width: 1,
                                ),
                              ),
                              child: ClipOval(
                                child: (creator.avatarUrl != null &&
                                        (creator.avatarUrl!.startsWith('http://') ||
                                            creator.avatarUrl!.startsWith('https://')))
                                    ? Image.network(
                                        creator.avatarUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(
                                            creator.name.isNotEmpty
                                                ? creator.name[0]
                                                : 'S',
                                            style: ig.displayTitle(
                                              fontSize: 18,
                                              color: ig.textPrimary,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          creator.name.isNotEmpty
                                              ? creator.name[0]
                                              : 'S',
                                          style: ig.displayTitle(
                                            fontSize: 18,
                                            color: ig.textPrimary,
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
                                    children: [
                                      Flexible(
                                        child: Text(
                                          creator.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: ig.username(
                                            fontSize: 14,
                                            color: ig.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (creator.isVerified) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.verified_rounded,
                                          size: 14,
                                          color: ig.primaryAction,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    creator.title ?? 'Thành viên Saman',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ig.caption(
                                      fontSize: 12,
                                      color: ig.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    creator.followerCount >= 1000
                                        ? '${(creator.followerCount / 1000).toStringAsFixed(1)}k người theo dõi'
                                        : '${creator.followerCount} người theo dõi',
                                    style: ig.caption(
                                      fontSize: 10,
                                      color: ig.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => onFollowToggle(creator.id),
                        style: (isFollowing
                                ? ig.secondaryButtonStyle(
                                    minHeight: 34,
                                    borderRadius: 8,
                                  )
                                : ig.primaryButtonStyle(
                                    minHeight: 34,
                                    borderRadius: 8,
                                  ))
                            .copyWith(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                        ),
                        child: Text(
                          isFollowing ? 'Đang theo dõi' : 'Theo dõi',
                          style: ig.buttonLabel(
                            fontSize: 12,
                            color: isFollowing
                                ? ig.secondaryButtonText
                                : ig.onPrimaryAction,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

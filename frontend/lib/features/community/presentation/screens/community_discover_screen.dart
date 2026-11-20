import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_author.dart';
import '../../domain/models/community_discover_item.dart';
import '../providers/community_providers.dart';
import '../widgets/community_bottom_navigation_bar.dart';
import 'community_post_detail_screen.dart';

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
    final tokens = SamanHomeTokens.of(context);
    final discoverState = ref.watch(communityDiscoverProvider);
    final discoverNotifier = ref.read(communityDiscoverProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildHeader(context, tokens),

            // Honest Preview Notice Banner
            _buildPreviewNoticeBanner(tokens),

            // Search Bar
            _buildSearchBar(discoverNotifier, tokens),

            // Content Scroll
            Expanded(
              child: discoverState.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: tokens.greenAccent,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Topic Chips
                          _buildTopicChips(
                            discoverState.data.topicChips,
                            discoverState.activeTopic,
                            (topic) => discoverNotifier.setTopic(topic),
                            tokens,
                          ),
                          const SizedBox(height: 16),

                          // Section 1: Visual Grid (3x3)
                          _buildVisualGridSection(
                            context,
                            discoverState.data.gridItems,
                            tokens,
                          ),
                          const SizedBox(height: 24),

                          // Section 2: Trending Topics
                          _buildTrendingTopicsSection(
                            discoverState.data.trendingTopics,
                            tokens,
                          ),
                          const SizedBox(height: 24),

                          // Section 3: Recommended Creators to follow
                          _buildRecommendedCreatorsSection(
                            discoverState.data.recommendedCreators,
                            (authorId) =>
                                discoverNotifier.toggleFollow(authorId),
                            tokens,
                          ),
                        ],
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

  Widget _buildPreviewNoticeBanner(SamanHomePalette tokens) {
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
              'Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm',
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

  Widget _buildHeader(BuildContext context, SamanHomePalette tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: tokens.textPrimary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khám phá cộng đồng',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Không gian truyền cảm hứng',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.tune_rounded,
              color: tokens.textSecondary,
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
    SamanHomePalette tokens,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tokens.border,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: tokens.textMuted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => notifier.setSearchQuery(val),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm bài viết, chủ đề, thành viên…',
                  hintStyle: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            Icon(
              Icons.mic_none_rounded,
              color: tokens.textMuted,
              size: 20,
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
    SamanHomePalette tokens,
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
      height: 40,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? tokens.secondarySurface
                    : tokens.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive
                      ? tokens.greenAccent.withOpacity(0.5)
                      : tokens.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    meta.$2,
                    size: 15,
                    color: isActive
                        ? tokens.greenAccent
                        : tokens.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    meta.$1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? tokens.greenAccent
                          : tokens.textSecondary,
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
    SamanHomePalette tokens,
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
                      Icons.grid_view_rounded,
                      size: 18,
                      color: tokens.greenAccent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Khoảnh khắc tiêu biểu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Mới nhất',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tokens.greenAccent.withOpacity(0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: tokens.isDark
                  ? const Color(0xFF0D0E0F)
                  : tokens.border,
              borderRadius: BorderRadius.circular(16),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
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
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: tokens.cardSurface,
                          child: Center(
                            child: Icon(
                              item.hasVideo
                                  ? Icons.play_circle_fill_rounded
                                  : Icons.image_rounded,
                              size: 28,
                              color: tokens.secondarySurface,
                            ),
                          ),
                        ),
                        // Top badge (dark translucent overlay kept for media contrast)
                        if (item.hasMultiPhoto || item.hasVideo)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF121314).withOpacity(0.8),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Icon(
                                item.hasMultiPhoto
                                    ? Icons.photo_library_rounded
                                    : Icons.play_arrow_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        // Bottom gradient & likes (dark scrim kept for media contrast)
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
                                  Colors.black.withOpacity(0.85),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 11,
                                  color: Color(0xFF5BBFA0),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  item.formattedLikes,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingTopicsSection(
    List<CommunityTrendingTopic> topics,
    SamanHomePalette tokens,
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
                      color: tokens.greenAccent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Chủ đề đang được quan tâm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Thịnh hành',
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.textSecondary,
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
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: tokens.border,
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
                              color: tokens.secondarySurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.tag_rounded,
                              color: tokens.greenAccent,
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary,
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
                                        color: tokens.greenAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        topic.postCountFormatted,
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
                            color: tokens.secondarySurface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            topic.growthPercent,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: topic.isStable
                                  ? tokens.textSecondary
                                  : tokens.greenAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: tokens.textMuted,
                        ),
                      ],
                    ),
                  ],
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
    SamanHomePalette tokens,
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
                      color: tokens.greenAccent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Có thể bạn muốn theo dõi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Xem tất cả',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textSecondary,
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

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: tokens.border,
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
                              color: tokens.secondarySurface,
                              border: Border.all(
                                color: tokens.greenAccent.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                creator.name.isNotEmpty ? creator.name[0] : 'S',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: tokens.greenAccent,
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
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (creator.isVerified) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.verified_rounded,
                                        size: 14,
                                        color: tokens.greenAccent,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  creator.title ?? 'Thành viên Saman',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${(creator.followerCount / 1000).toStringAsFixed(1)}k người theo dõi',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: tokens.textMuted,
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFollowing
                            ? tokens.secondarySurface
                            : tokens.greenAccent,
                        foregroundColor: isFollowing
                            ? tokens.textSecondary
                            : (tokens.isDark
                                ? const Color(0xFF003824)
                                : const Color(0xFFFFFFFF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFollowing
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            size: 15,
                            color: isFollowing
                                ? tokens.greenAccent
                                : (tokens.isDark
                                    ? const Color(0xFF003824)
                                    : const Color(0xFFFFFFFF)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isFollowing ? 'Đang theo dõi' : 'Theo dõi',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

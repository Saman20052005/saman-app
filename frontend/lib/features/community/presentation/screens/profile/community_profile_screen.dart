import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/routes.dart';
import '../../../../../providers/profile_provider.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/community_author.dart';
import '../../../domain/models/community_post.dart';
import '../../providers/community_providers.dart';
import '../../widgets/community_bottom_navigation_bar.dart';
import '../../widgets/create_content_bottom_sheet.dart';
import 'community_edit_profile_screen.dart';
import 'community_follow_list_screen.dart';
import '../saved/community_saved_screen.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';

class CommunityProfileScreen extends ConsumerStatefulWidget {
  final String authorId;
  const CommunityProfileScreen({
    super.key,
    this.authorId = 'me',
  });

  @override
  ConsumerState<CommunityProfileScreen> createState() =>
      _CommunityProfileScreenState();
}

class _CommunityProfileScreenState
    extends ConsumerState<CommunityProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CommunityAuthor? _author;
  String _bio =
      'Yêu thích rèn luyện thể chất và dinh dưỡng cân bằng. Chia sẻ hành trình tập luyện thực tế mỗi ngày cùng Saman.';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAuthor());
  }

  Future<void> _loadAuthor() async {
    final a = await ref
        .read(communityRepositoryProvider)
        .getAuthorProfile(widget.authorId);
    if (mounted) setState(() => _author = a);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isMe {
    if (widget.authorId == 'me') return true;
    final confirmedId = ref.read(profileProvider).confirmedUserId;
    if (confirmedId != null && confirmedId.isNotEmpty && confirmedId == widget.authorId) {
      return true;
    }
    final snapId = ref.read(profileProvider).snapshot?.userId;
    if (snapId != null && snapId.isNotEmpty && snapId == widget.authorId) {
      return true;
    }
    return widget.authorId == 'author_linh';
  }

  bool _isTogglingFollow = false;

  Future<void> _handleToggleFollow(CommunityAuthor author) async {
    if (_isTogglingFollow) return;
    _isTogglingFollow = true;

    final prevFollowing = author.isFollowing;
    final nextFollowing = !prevFollowing;
    final nextFollowerCount = nextFollowing
        ? author.followerCount + 1
        : (author.followerCount > 0 ? author.followerCount - 1 : 0);

    setState(() {
      _author = author.copyWith(
        isFollowing: nextFollowing,
        followerCount: nextFollowerCount,
      );
    });

    ref.read(communityFeedProvider.notifier).updateAuthorFollow(
      authorId: author.id,
      isFollowing: nextFollowing,
      followerCount: nextFollowerCount,
    );

    try {
      final actualState = await ref
          .read(communityRepositoryProvider)
          .toggleFollow(author.id);
      if (mounted && actualState != nextFollowing) {
        setState(() {
          _author = _author?.copyWith(isFollowing: actualState);
        });
        ref.read(communityFeedProvider.notifier).updateAuthorFollow(
          authorId: author.id,
          isFollowing: actualState,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _author = author;
        });
        ref.read(communityFeedProvider.notifier).updateAuthorFollow(
          authorId: author.id,
          isFollowing: prevFollowing,
          followerCount: author.followerCount,
        );
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể cập nhật theo dõi: ${e.toString()}',
          type: FeedbackType.error,
        );
      }
    } finally {
      _isTogglingFollow = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final author = _author ??
        const CommunityAuthor(
          id: 'me',
          name: 'Linh Nguyễn',
          isVerified: true,
          title: 'Thành viên chia sẻ (Mẫu)',
        );
    final feedState = ref.watch(communityFeedProvider);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(context, author, tokens),
            _buildPreviewNoticeBanner(tokens),
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileHeader(context, author, tokens),
                          const SizedBox(height: 12),
                          _buildActionStrip(context, author, tokens),
                          const SizedBox(height: 16),
                          _buildStatsStrip(tokens),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabBarDelegate(
                        TabBar(
                          controller: _tabController,
                          indicatorColor: tokens.greenAccent,
                          labelColor: tokens.greenAccent,
                          unselectedLabelColor: tokens.textSecondary,
                          tabs: const [
                            Tab(text: 'Bài viết'),
                            Tab(text: 'Buổi tập'),
                            Tab(text: 'Bữa ăn'),
                          ],
                        ),
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPostGrid(feedState.posts, tokens),
                    _buildPostGrid(
                      feedState.posts
                          .where((p) => p.type == CommunityPostType.workout)
                          .toList(),
                      tokens,
                    ),
                    _buildPostGrid(
                      feedState.posts
                          .where((p) => p.nutritionInfo != null)
                          .toList(),
                      tokens,
                    ),
                  ],
                ),
              ),
            ),
            CommunityBottomNavigationBar(
              currentTab: CommunityNavTab.profile,
              onTabSelected: (tab) {
                if (tab == CommunityNavTab.feed) {
                  Navigator.pushReplacementNamed(context, AppRoutes.communityFeed);
                } else if (tab == CommunityNavTab.discover) {
                  Navigator.pushReplacementNamed(
                      context, AppRoutes.communityDiscover);
                } else if (tab == CommunityNavTab.create) {
                  CreateContentBottomSheet.show(context);
                } else if (tab == CommunityNavTab.notifications) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tính năng đang hoàn thiện, sẽ sớm ra mắt!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        ),
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

  Widget _buildAppBar(
    BuildContext context,
    CommunityAuthor author,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              '@${author.name.toLowerCase().replaceAll(' ', '.')}',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.share_outlined,
              color: tokens.textPrimary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    CommunityAuthor author,
    SamanHomePalette tokens,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tokens.greenAccent,
                    width: 2,
                  ),
                  color: tokens.secondarySurface,
                ),
                child: Center(
                  child: Text(
                    author.name.isNotEmpty ? author.name[0] : 'S',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            author.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (author.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: tokens.greenAccent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author.title ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CommunityFollowListScreen(
                                  authorId: author.id,
                                  authorName: author.name,
                                  initialTabIndex: 1,
                                ),
                              ),
                            );
                            if (mounted) _loadAuthor();
                          },
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${author.followingCount} ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Đang theo dõi  •  ',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CommunityFollowListScreen(
                                  authorId: author.id,
                                  authorName: author.name,
                                  initialTabIndex: 0,
                                ),
                              ),
                            );
                            if (mounted) _loadAuthor();
                          },
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${author.followerCount} ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Người theo dõi',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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
          const SizedBox(height: 12),
          Text(
            _bio,
            style: TextStyle(
              fontSize: 13,
              color: tokens.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStrip(
    BuildContext context,
    CommunityAuthor author,
    SamanHomePalette tokens,
  ) {
    if (!_isMe) {
      final isFollowing = author.isFollowing;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          height: 38,
          child: isFollowing
              ? OutlinedButton(
                  onPressed: () => _handleToggleFollow(author),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Đang theo dõi',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                )
              : ElevatedButton(
                  onPressed: () => _handleToggleFollow(author),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.greenAccent,
                    foregroundColor: tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Theo dõi',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityEditProfileScreen(
                        initialName: author.name,
                        initialTitle: author.title,
                        initialBio: _bio,
                      ),
                    ),
                  );
                  if (result is Map<String, dynamic> && mounted) {
                    setState(() {
                      if (result['bio'] != null &&
                          (result['bio'] as String).isNotEmpty) {
                        _bio = result['bio'] as String;
                      }
                      if (result['name'] != null &&
                          (result['name'] as String).isNotEmpty) {
                        _author = (_author ?? author)
                            .copyWith(name: result['name'] as String);
                      }
                      if (result['title'] != null &&
                          (result['title'] as String).isNotEmpty) {
                        _author = (_author ?? author)
                            .copyWith(title: result['title'] as String);
                      }
                    });
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  side: BorderSide(color: tokens.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Chỉnh sửa hồ sơ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CommunitySavedScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.bookmark_border_rounded, size: 16),
              label: const Text('Đã lưu', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textSecondary,
                side: BorderSide(color: tokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tính năng đang hoàn thiện, sẽ sớm ra mắt!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: const Text('Bản nháp', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textSecondary,
                side: BorderSide(color: tokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(SamanHomePalette tokens) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('42', 'Buổi tập chia sẻ', tokens),
          Container(width: 1, height: 24, color: tokens.border),
          _buildStatItem('18', 'Bữa ăn dinh dưỡng', tokens),
          Container(width: 1, height: 24, color: tokens.border),
          _buildStatItem('1.2k', 'Lượt thích nhận', tokens),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    SamanHomePalette tokens,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.greenAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostGrid(
    List<CommunityPost> posts,
    SamanHomePalette tokens,
  ) {
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'Chưa có bài viết nào trong mục này.',
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: posts.length,
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
          child: Container(
            color: tokens.cardSurface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: tokens.secondarySurface,
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: tokens.textMuted,
                      size: 24,
                    ),
                  ),
                ),
                if (post.type == CommunityPostType.workout)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.bolt_rounded,
                      color: tokens.greenAccent,
                      size: 16,
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

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final tokens = SamanHomeTokens.of(context);
    return Container(
      color: tokens.canvas,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}

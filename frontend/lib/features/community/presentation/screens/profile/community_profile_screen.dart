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
import '../drafts/community_drafts_screen.dart';
import '../saved/community_saved_screen.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể cập nhật theo dõi: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _isTogglingFollow = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = _author ??
        const CommunityAuthor(
          id: 'me',
          name: 'Linh Nguyễn',
          isVerified: true,
          title: 'Thành viên chia sẻ (Mẫu)',
        );
    final feedState = ref.watch(communityFeedProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(context, author),
            _buildPreviewNoticeBanner(),
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileHeader(context, author),
                          const SizedBox(height: 12),
                          _buildActionStrip(context, author),
                          const SizedBox(height: 16),
                          _buildStatsStrip(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabBarDelegate(
                        TabBar(
                          controller: _tabController,
                          indicatorColor: SamanHomeTokens.greenAccent,
                          labelColor: SamanHomeTokens.greenAccent,
                          unselectedLabelColor: const Color(0xFFBBCAAF),
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
                    _buildPostGrid(feedState.posts),
                    _buildPostGrid(
                      feedState.posts
                          .where((p) => p.type == CommunityPostType.workout)
                          .toList(),
                    ),
                    _buildPostGrid(
                      feedState.posts
                          .where((p) => p.nutritionInfo != null)
                          .toList(),
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
                  Navigator.pushNamed(context, '/community/notifications');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewNoticeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF1B1C1D),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: SamanHomeTokens.greenAccent,
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFBBCAAF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, CommunityAuthor author) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2021), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: SamanHomeTokens.textWhite,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              '@${author.name.toLowerCase().replaceAll(' ', '.')}',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.share_outlined,
              color: SamanHomeTokens.textWhite,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, CommunityAuthor author) {
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
                    color: SamanHomeTokens.greenAccent,
                    width: 2,
                  ),
                  color: const Color(0xFF292A2B),
                ),
                child: Center(
                  child: Text(
                    author.name.isNotEmpty ? author.name[0] : 'S',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: SamanHomeTokens.textWhite,
                            ),
                          ),
                        ),
                        if (author.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: SamanHomeTokens.greenAccent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author.title ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFBBCAAF),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: SamanHomeTokens.textWhite,
                                    fontSize: 13,
                                  ),
                                ),
                                const TextSpan(
                                  text: 'Đang theo dõi  •  ',
                                  style: TextStyle(
                                    color: Color(0xFFBBCAAF),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: SamanHomeTokens.textWhite,
                                    fontSize: 13,
                                  ),
                                ),
                                const TextSpan(
                                  text: 'Người theo dõi',
                                  style: TextStyle(
                                    color: Color(0xFFBBCAAF),
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
            style: const TextStyle(
              fontSize: 13,
              color: SamanHomeTokens.textWhite,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStrip(BuildContext context, CommunityAuthor author) {
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
                    foregroundColor: const Color(0xFFBBCAAF),
                    side: const BorderSide(color: Color(0xFF343536)),
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
                    backgroundColor: SamanHomeTokens.greenAccent,
                    foregroundColor: const Color(0xFF003824),
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
                  foregroundColor: SamanHomeTokens.textWhite,
                  side: const BorderSide(color: Color(0xFF343536)),
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
                foregroundColor: const Color(0xFFBBCAAF),
                side: const BorderSide(color: Color(0xFF343536)),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CommunityDraftsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: const Text('Bản nháp', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFBBCAAF),
                side: const BorderSide(color: Color(0xFF343536)),
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

  Widget _buildStatsStrip() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F21),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF292A2B)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('42', 'Buổi tập chia sẻ'),
          Container(width: 1, height: 24, color: const Color(0xFF2E3033)),
          _buildStatItem('18', 'Bữa ăn dinh dưỡng'),
          Container(width: 1, height: 24, color: const Color(0xFF2E3033)),
          _buildStatItem('1.2k', 'Lượt thích nhận'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.greenAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFBBCAAF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostGrid(List<CommunityPost> posts) {
    if (posts.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có bài viết nào trong mục này.',
          style: TextStyle(color: Color(0xFF71767B), fontSize: 13),
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
            color: const Color(0xFF1F2021),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF292A2B),
                    child: const Icon(
                      Icons.fitness_center_rounded,
                      color: Color(0xFF55585C),
                      size: 24,
                    ),
                  ),
                ),
                if (post.type == CommunityPostType.workout)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.bolt_rounded,
                      color: SamanHomeTokens.greenAccent,
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
    return Container(
      color: const Color(0xFF121314),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}

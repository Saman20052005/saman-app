import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/community_author.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';
import 'community_profile_screen.dart';

class CommunityFollowListScreen extends ConsumerStatefulWidget {
  final String authorId;
  final String authorName;
  final int initialTabIndex;

  const CommunityFollowListScreen({
    super.key,
    this.authorId = 'me',
    this.authorName = 'Linh Nguyễn',
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<CommunityFollowListScreen> createState() =>
      _CommunityFollowListScreenState();
}

class _CommunityFollowListScreenState
    extends ConsumerState<CommunityFollowListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<CommunityAuthor> _followers = const [
    CommunityAuthor(
      id: 'author_khang',
      name: 'Minh Khang',
      title: 'Thành viên Saman',
    ),
    CommunityAuthor(
      id: 'creator_mai',
      name: 'Thanh Mai',
      title: 'HLV Yoga & Pilates',
      isVerified: true,
    ),
  ];
  List<CommunityAuthor> _following = const [
    CommunityAuthor(
      id: 'author_ha',
      name: 'Thu Hà',
      title: 'Người tập luyện (Mẫu)',
    ),
    CommunityAuthor(
      id: 'creator_long',
      name: 'Hoàng Long',
      title: 'HLV Thể hình & Dinh dưỡng',
      isVerified: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final repo = ref.read(communityRepositoryProvider);
    final f1 = await repo.getFollowers(widget.authorId);
    final f2 = await repo.getFollowing(widget.authorId);
    if (mounted) {
      setState(() {
        _followers = f1;
        _following = f2;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final followers = _followers;
    final following = _following;

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, ig),
            _buildSearchBar(ig),
            TabBar(
              controller: _tabController,
              indicatorColor: ig.textPrimary,
              indicatorWeight: 1.5,
              dividerColor: ig.border,
              dividerHeight: 0.5,
              labelColor: ig.textPrimary,
              unselectedLabelColor: ig.textSecondary,
              labelStyle: ig.username(fontSize: 13),
              unselectedLabelStyle: ig.body(
                fontSize: 13,
                color: ig.textSecondary,
              ),
              tabs: [
                Tab(text: '${followers.length} Người theo dõi'),
                Tab(text: '${following.length} Đang theo dõi'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUserList(followers, ig),
                  _buildUserList(following, ig),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanIgTokens ig) {
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
          Expanded(
            child: Text(
              widget.authorName,
              overflow: TextOverflow.ellipsis,
              style: ig.displayTitle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(SamanIgTokens ig) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: ig.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ig.borderSubtle, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: ig.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: ig.body(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm theo tên thành viên...',
                  hintStyle: ig.body(fontSize: 13, color: ig.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: Icon(Icons.clear_rounded, size: 16, color: ig.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(
    List<CommunityAuthor> authors,
    SamanIgTokens ig,
  ) {
    final filtered = _searchQuery.isEmpty
        ? authors
        : authors
            .where((a) =>
                a.name.toLowerCase().contains(_searchQuery) ||
                (a.title != null && a.title!.toLowerCase().contains(_searchQuery)))
            .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? 'Danh sách trống.'
              : 'Không tìm thấy kết quả phù hợp.',
          style: ig.body(color: ig.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => Divider(color: ig.border, height: 16, thickness: 0.5),
      itemBuilder: (context, index) {
        final author = filtered[index];
        return _buildUserTile(author, ig);
      },
    );
  }

  Widget _buildUserTile(CommunityAuthor author, SamanIgTokens ig) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityProfileScreen(authorId: author.id),
              ),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ig.surfaceElevated,
            ),
            child: Center(
              child: Text(
                author.name.isNotEmpty ? author.name[0] : 'S',
                style: ig.displayTitle(
                  fontSize: 16,
                  color: ig.textPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityProfileScreen(authorId: author.id),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author.name,
                        overflow: TextOverflow.ellipsis,
                        style: ig.username(fontSize: 14),
                      ),
                    ),
                    if (author.isVerified) ...[
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
                  author.title ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: ig.caption(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 34,
          child: author.isFollowing
              ? OutlinedButton(
                  onPressed: () async {
                    final newState = await ref
                        .read(communityRepositoryProvider)
                        .toggleFollow(author.id);
                    ref.read(communityFeedProvider.notifier).updateAuthorFollow(
                          authorId: author.id,
                          isFollowing: newState,
                        );
                    if (mounted) {
                      setState(() {
                        _followers = _followers
                            .map((a) => a.id == author.id
                                ? a.copyWith(isFollowing: newState)
                                : a)
                            .toList();
                        _following = _following
                            .map((a) => a.id == author.id
                                ? a.copyWith(isFollowing: newState)
                                : a)
                            .toList();
                      });
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: ig.secondaryButtonBg,
                    foregroundColor: ig.secondaryButtonText,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Đang theo dõi',
                    style: ig.buttonLabel(
                      fontSize: 12,
                      color: ig.secondaryButtonText,
                    ),
                  ),
                )
              : ElevatedButton(
                  onPressed: () async {
                    final newState = await ref
                        .read(communityRepositoryProvider)
                        .toggleFollow(author.id);
                    ref.read(communityFeedProvider.notifier).updateAuthorFollow(
                          authorId: author.id,
                          isFollowing: newState,
                        );
                    if (mounted) {
                      setState(() {
                        _followers = _followers
                            .map((a) => a.id == author.id
                                ? a.copyWith(isFollowing: newState)
                                : a)
                            .toList();
                        _following = _following
                            .map((a) => a.id == author.id
                                ? a.copyWith(isFollowing: newState)
                                : a)
                            .toList();
                      });
                    }
                  },
                  style: ig.primaryButtonStyle(
                    minHeight: 34,
                    borderRadius: 8,
                  ).copyWith(
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                  child: Text(
                    'Theo dõi',
                    style: ig.buttonLabel(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ig.onPrimaryAction,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/community_author.dart';
import '../../providers/community_providers.dart';
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
    final tokens = SamanHomeTokens.of(context);
    final followers = _followers;
    final following = _following;

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, tokens),
            _buildSearchBar(tokens),
            TabBar(
              controller: _tabController,
              indicatorColor: tokens.greenAccent,
              labelColor: tokens.greenAccent,
              unselectedLabelColor: tokens.textSecondary,
              tabs: [
                Tab(text: '${followers.length} Người theo dõi'),
                Tab(text: '${following.length} Đang theo dõi'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUserList(followers, tokens),
                  _buildUserList(following, tokens),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanHomePalette tokens) {
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
          Expanded(
            child: Text(
              widget.authorName,
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
    );
  }

  Widget _buildSearchBar(SamanHomePalette tokens) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: tokens.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: TextStyle(fontSize: 13, color: tokens.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm theo tên thành viên...',
                  hintStyle: TextStyle(fontSize: 13, color: tokens.textMuted),
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
                icon: Icon(Icons.clear_rounded, size: 16, color: tokens.textSecondary),
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
    SamanHomePalette tokens,
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
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => Divider(color: tokens.border, height: 16),
      itemBuilder: (context, index) {
        final author = filtered[index];
        return _buildUserTile(author, tokens);
      },
    );
  }

  Widget _buildUserTile(CommunityAuthor author, SamanHomePalette tokens) {
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
              color: tokens.secondarySurface,
            ),
            child: Center(
              child: Text(
                author.name.isNotEmpty ? author.name[0] : 'S',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.greenAccent,
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (author.isVerified) ...[
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
                  author.title ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 32,
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
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Đang theo dõi', style: TextStyle(fontSize: 12)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.greenAccent,
                    foregroundColor: tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Theo dõi',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
        ),
      ],
    );
  }
}

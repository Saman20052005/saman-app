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
    final followers = _followers;
    final following = _following;

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            _buildSearchBar(),
            TabBar(
              controller: _tabController,
              indicatorColor: SamanHomeTokens.greenAccent,
              labelColor: SamanHomeTokens.greenAccent,
              unselectedLabelColor: const Color(0xFFBBCAAF),
              tabs: [
                Tab(text: '${followers.length} Người theo dõi'),
                Tab(text: '${following.length} Đang theo dõi'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUserList(followers),
                  _buildUserList(following),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
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
          Expanded(
            child: Text(
              widget.authorName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1F21),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E3033)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: Color(0xFFBBCAAF),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: const TextStyle(fontSize: 13, color: SamanHomeTokens.textWhite),
                decoration: const InputDecoration(
                  hintText: 'Tìm kiếm theo tên thành viên...',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF71767B)),
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
                icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFFBBCAAF)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(List<CommunityAuthor> authors) {
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
          style: const TextStyle(color: Color(0xFF71767B), fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1F2021), height: 16),
      itemBuilder: (context, index) {
        final author = filtered[index];
        return _buildUserTile(author);
      },
    );
  }

  Widget _buildUserTile(CommunityAuthor author) {
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF292A2B),
            ),
            child: Center(
              child: Text(
                author.name.isNotEmpty ? author.name[0] : 'S',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.greenAccent,
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SamanHomeTokens.textWhite,
                        ),
                      ),
                    ),
                    if (author.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: SamanHomeTokens.greenAccent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  author.title ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFBBCAAF),
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
                    foregroundColor: const Color(0xFFBBCAAF),
                    side: const BorderSide(color: Color(0xFF343536)),
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
                    backgroundColor: SamanHomeTokens.greenAccent,
                    foregroundColor: const Color(0xFF003824),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/app_translations.dart';
import '../../../../../config/routes.dart';
import '../../../../../providers/profile_provider.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_author.dart';
import '../../../domain/models/community_post.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_providers.dart';
import '../../providers/community_social_providers.dart';
import '../../widgets/community_bottom_navigation_bar.dart';
import '../../widgets/create_content_bottom_sheet.dart';
import '../../widgets/post_card_view.dart';
import '../saved/community_saved_screen.dart';
import 'community_edit_profile_screen.dart';
import 'community_follow_list_screen.dart';

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
  List<CommunityPost> _posts = const [];
  bool _isLoading = true;
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfileData());
  }

  Future<void> _loadProfileData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final repo = ref.read(communityRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.getAuthorProfile(widget.authorId),
        repo.getAuthorPosts(widget.authorId),
      ]);
      if (!mounted) return;
      setState(() {
        _author = results[0] as CommunityAuthor;
        _posts = results[1] as List<CommunityPost>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isMe {
    if (widget.authorId == 'me') return true;
    final confirmedId = ref.read(profileProvider).confirmedUserId;
    if (confirmedId != null &&
        confirmedId.isNotEmpty &&
        confirmedId == widget.authorId) {
      return true;
    }
    final snapId = ref.read(profileProvider).snapshot?.userId;
    if (snapId != null && snapId.isNotEmpty && snapId == widget.authorId) {
      return true;
    }
    return widget.authorId == 'author_linh';
  }

  bool _isTogglingFollow = false;
  bool _isStartingChat = false;

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

  String _formatCount(int count) {
    if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      final clean = formatted.endsWith('.0')
          ? formatted.substring(0, formatted.length - 2)
          : formatted;
      return '${clean}k';
    }
    return '$count';
  }

  void _openPost(CommunityPost post) {
    if (post.type == CommunityPostType.qa) {
      Navigator.pushNamed(
        context,
        AppRoutes.communityQuestionDetail,
        arguments: post.id,
      );
    } else {
      Navigator.pushNamed(
        context,
        AppRoutes.communityPost,
        arguments: post.id,
      );
    }
  }

  Future<void> _handleStartChat(CommunityAuthor author) async {
    if (_isStartingChat) return;
    setState(() => _isStartingChat = true);
    try {
      final conv = await ref
          .read(communityInboxProvider.notifier)
          .createOrGetConversation(author.id);
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        AppRoutes.communityChat,
        arguments: conv,
      );
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể bắt đầu cuộc trò chuyện với ${author.name}.',
          type: FeedbackType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingChat = false);
      }
    }
  }

  void _showUserOptionsSheet(BuildContext context, CommunityAuthor author) {
    final sheetBg = SamanHomeTokens.of(context).cardSurface;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final tokens = SamanHomeTokens.of(ctx);
        final dangerColor = Theme.of(ctx).colorScheme.error;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('profile-options-mute-tile'),
                leading: Icon(
                  Icons.volume_off_outlined,
                  color: tokens.textPrimary,
                ),
                title: Text(
                  context.tr('profile_action_mute_user'),
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _handleMuteUser(author);
                },
              ),
              ListTile(
                key: const ValueKey('profile-options-block-tile'),
                leading: Icon(Icons.block_rounded, color: dangerColor),
                title: Text(
                  context.tr('profile_action_block_user'),
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: dangerColor,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBlockUserConfirmation(author);
                },
              ),
              ListTile(
                key: const ValueKey('profile-options-report-tile'),
                leading: Icon(Icons.flag_outlined, color: dangerColor),
                title: Text(
                  context.tr('profile_action_report_user'),
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: dangerColor,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportUserReasonSheet(author);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleMuteUser(CommunityAuthor author) async {
    try {
      await ref.read(communitySettingsProvider.notifier).muteUser(author.id);
      await ref.read(communityFeedProvider.notifier).refresh();
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: context.tr('post_mute_success'),
          type: FeedbackType.info,
        );
      }
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: context.tr('post_report_error'),
          type: FeedbackType.error,
        );
      }
    }
  }

  Future<void> _showBlockUserConfirmation(CommunityAuthor author) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final tokens = SamanHomeTokens.of(dialogCtx);
        final dangerColor = Theme.of(dialogCtx).colorScheme.error;
        return AlertDialog(
          backgroundColor: tokens.cardSurface,
          title: Text(
            context.tr('post_block_confirm_title'),
            style: Theme.of(dialogCtx).textTheme.titleMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            context.tr('post_block_confirm_msg'),
            style: Theme.of(dialogCtx).textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                context.tr('compose_discard'),
                style: Theme.of(dialogCtx).textTheme.labelLarge?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('profile-confirm-block-button'),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                context.tr('post_block_confirm_btn'),
                style: Theme.of(dialogCtx).textTheme.labelLarge?.copyWith(
                  color: dangerColor,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(communitySettingsProvider.notifier).blockUser(author.id);
        await ref.read(communityFeedProvider.notifier).refresh();
        if (mounted) {
          SamanFeedbackSnackBar.show(
            context,
            message: context.tr('post_block_success'),
            type: FeedbackType.info,
          );
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }
      } catch (_) {
        if (mounted) {
          SamanFeedbackSnackBar.show(
            context,
            message: context.tr('post_report_error'),
            type: FeedbackType.error,
          );
        }
      }
    }
  }

  void _showReportUserReasonSheet(CommunityAuthor author) {
    final tokens = SamanHomeTokens.of(context);
    final reasons = <({String key, String labelKey})>[
      (key: 'spam', labelKey: 'post_report_reason_spam'),
      (key: 'harassment', labelKey: 'post_report_reason_harassment'),
      (key: 'misinformation', labelKey: 'post_report_reason_misinformation'),
      (key: 'inappropriate', labelKey: 'post_report_reason_inappropriate'),
      (key: 'other', labelKey: 'post_report_reason_other'),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final sheetTokens = SamanHomeTokens.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('profile_action_report_user'),
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: sheetTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...reasons.map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.tr(r.labelKey),
                      style: Theme.of(sheetCtx).textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: sheetTokens.textPrimary,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: sheetTokens.textSecondary,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await ref
                            .read(communitySettingsProvider.notifier)
                            .reportContent(
                              targetType: 'user',
                              targetId: author.id,
                              reason: r.key,
                            );
                        if (mounted) {
                          SamanFeedbackSnackBar.show(
                            context,
                            message: context.tr('post_report_success'),
                            type: FeedbackType.success,
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          SamanFeedbackSnackBar.show(
                            context,
                            message: context.tr('post_report_error'),
                            type: FeedbackType.error,
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final author = _author ??
        const CommunityAuthor(
          id: 'me',
          name: 'Linh Nguyễn',
          isVerified: true,
          title: 'Thành viên chia sẻ',
        );

    final workoutPosts = _posts
        .where(
          (p) =>
              p.type == CommunityPostType.workout ||
              p.workoutAttachment != null,
        )
        .toList();
    final mealPosts = _posts
        .where(
          (p) =>
              p.type == CommunityPostType.meal || p.nutritionInfo != null,
        )
        .toList();

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(context, author, tokens),
            Expanded(
              child: _isLoading && _author == null
                  ? Center(
                      child: CircularProgressIndicator(
                        color: tokens.greenAccent,
                      ),
                    )
                  : NestedScrollView(
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
                                _buildStatsStrip(author, tokens),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SliverTabBarDelegate(
                              Row(
                                children: [
                                  Expanded(
                                    child: TabBar(
                                      controller: _tabController,
                                      indicatorColor: tokens.greenAccent,
                                      dividerColor: tokens.borderSubtle,
                                      labelColor: tokens.greenAccent,
                                      unselectedLabelColor:
                                          tokens.textSecondary,
                                      tabs: const [
                                        Tab(text: 'Bài viết'),
                                        Tab(text: 'Buổi tập'),
                                        Tab(text: 'Bữa ăn'),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey('profile-view-toggle'),
                                    constraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _isGridView = !_isGridView,
                                      );
                                    },
                                    tooltip: _isGridView
                                        ? 'Xem dạng danh sách'
                                        : 'Xem dạng lưới',
                                    icon: Icon(
                                      _isGridView
                                          ? Icons.view_agenda_outlined
                                          : Icons.grid_view_rounded,
                                      color: tokens.textSecondary,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ];
                      },
                      body: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPostsBody(_posts, tokens),
                          _buildPostsBody(workoutPosts, tokens),
                          _buildPostsBody(mealPosts, tokens),
                        ],
                      ),
                    ),
            ),
            CommunityBottomNavigationBar(
              currentTab: CommunityNavTab.profile,
              onTabSelected: (tab) {
                if (tab == CommunityNavTab.feed) {
                  Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.communityFeed,
                  );
                } else if (tab == CommunityNavTab.discover) {
                  Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.communityDiscover,
                  );
                } else if (tab == CommunityNavTab.create) {
                  CreateContentBottomSheet.show(context);
                } else if (tab == CommunityNavTab.notifications) {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.communityNotifications,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    CommunityAuthor author,
    SamanHomePalette tokens,
  ) {
    final handleText =
        (author.handle != null && author.handle!.trim().isNotEmpty)
            ? '@${author.handle!.trim()}'
            : '@${author.name.toLowerCase().replaceAll(' ', '.')}';

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
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              handleText,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isMe)
                IconButton(
                  key: const ValueKey('profile-settings-btn'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.communitySettings);
                  },
                  icon: Icon(
                    Icons.settings_outlined,
                    color: tokens.textPrimary,
                    size: 22,
                  ),
                )
              else
                IconButton(
                  key: const ValueKey('profile-more-btn'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => _showUserOptionsSheet(context, author),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: tokens.textPrimary,
                    size: 22,
                  ),
                ),
            ],
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
    final initial = author.name.isNotEmpty ? author.name[0].toUpperCase() : 'S';
    final bioText = (author.bio != null && author.bio!.trim().isNotEmpty)
        ? author.bio!.trim()
        : 'Thành viên cộng đồng Saman';

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
                clipBehavior: Clip.antiAlias,
                child: author.avatarUrl != null && author.avatarUrl!.isNotEmpty
                    ? Image.network(
                        author.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            initial,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.greenAccent,
                                ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initial,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
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
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                  height: 1.25,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                            if (mounted) _loadProfileData();
                          },
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${author.followingCount} ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: tokens.textPrimary,
                                        fontSize: 13,
                                      ),
                                ),
                                TextSpan(
                                  text: 'Đang theo dõi  •  ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
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
                            if (mounted) _loadProfileData();
                          },
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${author.followerCount} ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: tokens.textPrimary,
                                        fontSize: 13,
                                      ),
                                ),
                                TextSpan(
                                  text: 'Người theo dõi',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
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
            bioText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: tokens.textPrimary,
              height: 1.5,
            ),
          ),
          if (author.interestTopics.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: author.interestTopics
                  .map(
                    (topic) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.secondarySurface,
                        borderRadius: BorderRadius.circular(
                          SamanHomeTokens.radiusSm,
                        ),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Text(
                        topic,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.greenAccent,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
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
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: isFollowing
                    ? OutlinedButton(
                        onPressed: () => _handleToggleFollow(author),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.textSecondary,
                          side: BorderSide(color: tokens.border),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              SamanHomeTokens.radiusMd,
                            ),
                          ),
                        ),
                        child: Text(
                          'Đang theo dõi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tokens.textSecondary,
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () => _handleToggleFollow(author),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.greenAccent,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              SamanHomeTokens.radiusMd,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Theo dõi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  key: const ValueKey('profile-message-btn'),
                  onPressed: _isStartingChat
                      ? null
                      : () => _handleStartChat(author),
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: tokens.textPrimary,
                  ),
                  label: Text(
                    context.tr('profile_action_message'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textPrimary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        SamanHomeTokens.radiusMd,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityEditProfileScreen(
                        initialName: author.name,
                        initialHandle: author.handle,
                        initialTitle: author.title,
                        initialBio: author.bio ?? '',
                        initialAvatarUrl: author.avatarUrl,
                        initialInterestTopics: author.interestTopics,
                        onSaveProfile: (payload) async {
                          try {
                            await ref
                                .read(communityRepositoryProvider)
                                .updateProfile(
                                  name: payload['name'] as String?,
                                  handle: payload['handle'] as String?,
                                  title: payload['title'] as String?,
                                  bio: payload['bio'] as String?,
                                  interestTopics:
                                      (payload['interestTopics'] as List<dynamic>?)
                                          ?.map((e) => e.toString())
                                          .toList(),
                                  avatarUrl: payload['avatarUrl'] as String?,
                                  localAvatarPath:
                                      payload['avatarPath'] as String?,
                                  removeAvatar:
                                      payload['avatarRemoved'] == true,
                                );
                            if (mounted) {
                              await _loadProfileData();
                              ref
                                  .read(communityFeedProvider.notifier)
                                  .refresh();
                            }
                            return true;
                          } catch (_) {
                            return false;
                          }
                        },
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  side: BorderSide(color: tokens.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      SamanHomeTokens.radiusMd,
                    ),
                  ),
                ),
                child: Text(
                  'Chỉnh sửa hồ sơ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: SizedBox(
              height: 44,
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
                label: Text(
                  'Đã lưu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  side: BorderSide(color: tokens.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      SamanHomeTokens.radiusMd,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.communityDrafts);
                },
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: Text(
                  'Bản nháp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  side: BorderSide(color: tokens.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      SamanHomeTokens.radiusMd,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(CommunityAuthor author, SamanHomePalette tokens) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            '${author.workoutPostCount}',
            'Buổi tập chia sẻ',
            tokens,
          ),
          Container(width: 1, height: 24, color: tokens.borderSubtle),
          _buildStatItem(
            '${author.mealPostCount}',
            'Bữa ăn dinh dưỡng',
            tokens,
          ),
          Container(width: 1, height: 24, color: tokens.borderSubtle),
          _buildStatItem(
            _formatCount(author.totalLikesReceived),
            'Lượt thích nhận',
            tokens,
          ),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsBody(
    List<CommunityPost> posts,
    SamanHomePalette tokens,
  ) {
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'Chưa có bài viết nào trong mục này.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: tokens.textMuted,
          ),
        ),
      );
    }

    if (!_isGridView) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          return PostCardView(
            post: post,
            onOpenDetail: () => _openPost(post),
            onLikeToggle: () =>
                ref.read(communityFeedProvider.notifier).toggleLike(post.id),
            onBookmarkToggle: () => ref
                .read(communityFeedProvider.notifier)
                .toggleBookmark(post.id),
          );
        },
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
          onTap: () => _openPost(post),
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
                      post.type == CommunityPostType.qa
                          ? Icons.question_answer_rounded
                          : Icons.fitness_center_rounded,
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
                if (post.type == CommunityPostType.qa)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.help_outline_rounded,
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
  final Widget _child;
  _SliverTabBarDelegate(this._child);

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final tokens = SamanHomeTokens.of(context);
    return Container(
      color: tokens.canvas,
      child: _child,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}

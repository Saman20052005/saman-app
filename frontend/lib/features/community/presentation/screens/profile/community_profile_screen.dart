import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/app_translations.dart';
import '../../../../../config/routes.dart';
import '../../../../../providers/profile_provider.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_author.dart';
import '../../../domain/models/community_post.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_providers.dart';
import '../../providers/community_social_providers.dart';
import '../../tokens/saman_ig_tokens.dart';
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
    final ig = SamanIgTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetIg = SamanIgTokens.of(ctx);
        final dangerColor = sheetIg.danger;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('profile-options-mute-tile'),
                leading: Icon(
                  Icons.volume_off_outlined,
                  color: sheetIg.textPrimary,
                ),
                title: Text(
                  context.tr('profile_action_mute_user'),
                  style: sheetIg.body(),
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
                  style: sheetIg.body(color: dangerColor),
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
                  style: sheetIg.body(color: dangerColor),
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
        final ig = SamanIgTokens.of(dialogCtx);
        final dangerColor = ig.danger;
        return AlertDialog(
          backgroundColor: ig.surface,
          title: Text(
            context.tr('post_block_confirm_title'),
            style: ig.displayTitle(fontSize: 16),
          ),
          content: Text(
            context.tr('post_block_confirm_msg'),
            style: ig.body(color: ig.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                context.tr('compose_discard'),
                style: ig.buttonLabel(color: ig.textMuted),
              ),
            ),
            TextButton(
              key: const ValueKey('profile-confirm-block-button'),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                context.tr('post_block_confirm_btn'),
                style: ig.buttonLabel(color: dangerColor),
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
    final ig = SamanIgTokens.of(context);
    final reasons = <({String key, String labelKey})>[
      (key: 'spam', labelKey: 'post_report_reason_spam'),
      (key: 'harassment', labelKey: 'post_report_reason_harassment'),
      (key: 'misinformation', labelKey: 'post_report_reason_misinformation'),
      (key: 'inappropriate', labelKey: 'post_report_reason_inappropriate'),
      (key: 'other', labelKey: 'post_report_reason_other'),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final sheetIg = SamanIgTokens.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('profile_action_report_user'),
                  style: sheetIg.displayTitle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...reasons.map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.tr(r.labelKey),
                      style: sheetIg.body(fontSize: 14),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: sheetIg.textSecondary,
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
    final ig = SamanIgTokens.of(context);
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
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(context, author, ig),
            Expanded(
              child: _isLoading && _author == null
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ig.primaryAction,
                      ),
                    )
                  : NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) {
                        return [
                          SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProfileHeader(context, author, ig),
                                const SizedBox(height: 12),
                                _buildActionStrip(context, author, ig),
                                const SizedBox(height: 16),
                                _buildStatsStrip(author, ig),
                                const SizedBox(height: 12),
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
                                      color: ig.textPrimary,
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
                          _buildPostsBody(_posts, ig),
                          _buildPostsBody(workoutPosts, ig),
                          _buildPostsBody(mealPosts, ig),
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
    SamanIgTokens ig,
  ) {
    final handleText =
        (author.handle != null && author.handle!.trim().isNotEmpty)
            ? '@${author.handle!.trim()}'
            : '@${author.name.toLowerCase().replaceAll(' ', '.')}';

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(bottom: BorderSide(color: ig.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              handleText,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: ig.displayTitle(fontSize: 16),
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
                    color: ig.textPrimary,
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
                    color: ig.textPrimary,
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
    SamanIgTokens ig,
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
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ig.border,
                    width: 1,
                  ),
                  color: ig.surfaceElevated,
                ),
                clipBehavior: Clip.antiAlias,
                child: author.avatarUrl != null && author.avatarUrl!.isNotEmpty
                    ? Image.network(
                        author.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            initial,
                            style: ig.displayTitle(
                              fontSize: 28,
                              color: ig.textPrimary,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initial,
                          style: ig.displayTitle(
                            fontSize: 28,
                            color: ig.textPrimary,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: _buildHeaderMetricColumn(
                        value: '${_posts.length}',
                        label: 'Bài viết',
                        ig: ig,
                      ),
                    ),
                    Expanded(
                      child: _buildHeaderMetricColumn(
                        value: '${author.followerCount}',
                        label: 'Người theo dõi',
                        ig: ig,
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
                      ),
                    ),
                    Expanded(
                      child: _buildHeaderMetricColumn(
                        value: '${author.followingCount}',
                        label: 'Đang theo dõi',
                        ig: ig,
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
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  author.name,
                  overflow: TextOverflow.ellipsis,
                  style: ig.username(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (author.isVerified) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: ig.primaryAction,
                ),
              ],
            ],
          ),
          if (author.title != null && author.title!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              author.title!,
              style: ig.caption(fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            bioText,
            style: ig.body(fontSize: 13, height: 1.45),
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
                        color: ig.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ig.border, width: 0.5),
                      ),
                      child: Text(
                        topic,
                        style: ig.caption(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ig.primaryAction,
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

  Widget _buildHeaderMetricColumn({
    required String value,
    required String label,
    required SamanIgTokens ig,
    VoidCallback? onTap,
  }) {
    final column = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ig.displayTitle(fontSize: 17),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ig.caption(fontSize: 11, color: ig.textPrimary),
          ),
        ],
      ),
    );
    if (onTap == null) return column;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: column,
    );
  }

  Widget _buildActionStrip(
    BuildContext context,
    CommunityAuthor author,
    SamanIgTokens ig,
  ) {
    if (!_isMe) {
      final isFollowing = author.isFollowing;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: isFollowing
                    ? OutlinedButton(
                        onPressed: () => _handleToggleFollow(author),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: ig.secondaryButtonBg,
                          foregroundColor: ig.secondaryButtonText,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Đang theo dõi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ig.buttonLabel(
                            color: ig.secondaryButtonText,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () => _handleToggleFollow(author),
                        style: ig.primaryButtonStyle(
                          minHeight: 38,
                          borderRadius: 8,
                        ),
                        child: Text(
                          'Theo dõi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ig.buttonLabel(
                            color: ig.onPrimaryAction,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  key: const ValueKey('profile-message-btn'),
                  onPressed: _isStartingChat
                      ? null
                      : () => _handleStartChat(author),
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: ig.secondaryButtonText,
                  ),
                  label: Text(
                    context.tr('profile_action_message'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ig.buttonLabel(
                      color: ig.secondaryButtonText,
                      fontSize: 13,
                    ),
                  ),
                  style: ig.secondaryButtonStyle(
                    minHeight: 38,
                    borderRadius: 8,
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
              height: 38,
              child: ElevatedButton(
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
                style: ig.secondaryButtonStyle(
                  minHeight: 38,
                  borderRadius: 8,
                ).copyWith(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                child: Text(
                  'Chỉnh sửa hồ sơ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ig.buttonLabel(
                    color: ig.secondaryButtonText,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CommunitySavedScreen(),
                    ),
                  );
                },
                icon: Icon(
                  Icons.bookmark_border_rounded,
                  size: 16,
                  color: ig.secondaryButtonText,
                ),
                label: Text(
                  'Đã lưu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ig.buttonLabel(
                    color: ig.secondaryButtonText,
                    fontSize: 12,
                  ),
                ),
                style: ig.secondaryButtonStyle(
                  minHeight: 38,
                  borderRadius: 8,
                ).copyWith(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.communityDrafts);
                },
                icon: Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: ig.secondaryButtonText,
                ),
                label: Text(
                  'Bản nháp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ig.buttonLabel(
                    color: ig.secondaryButtonText,
                    fontSize: 12,
                  ),
                ),
                style: ig.secondaryButtonStyle(
                  minHeight: 38,
                  borderRadius: 8,
                ).copyWith(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(CommunityAuthor author, SamanIgTokens ig) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            '${author.workoutPostCount}',
            'Buổi tập chia sẻ',
            ig,
          ),
          Container(width: 0.5, height: 24, color: ig.border),
          _buildStatItem(
            '${author.mealPostCount}',
            'Bữa ăn dinh dưỡng',
            ig,
          ),
          Container(width: 0.5, height: 24, color: ig.border),
          _buildStatItem(
            _formatCount(author.totalLikesReceived),
            'Lượt thích nhận',
            ig,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    SamanIgTokens ig,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: ig.displayTitle(fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ig.caption(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsBody(
    List<CommunityPost> posts,
    SamanIgTokens ig,
  ) {
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'Chưa có bài viết nào trong mục này.',
          style: ig.body(fontSize: 13, color: ig.textMuted),
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
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1.5,
        mainAxisSpacing: 1.5,
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
            color: ig.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: ig.surfaceElevated,
                    child: Icon(
                      post.type == CommunityPostType.qa
                          ? Icons.question_answer_rounded
                          : Icons.fitness_center_rounded,
                      color: ig.textMuted,
                      size: 24,
                    ),
                  ),
                ),
                if (post.type == CommunityPostType.workout)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      Icons.bolt_rounded,
                      color: ig.primaryAction,
                      size: 16,
                    ),
                  ),
                if (post.type == CommunityPostType.qa)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      Icons.help_outline_rounded,
                      color: ig.primaryAction,
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
    final ig = SamanIgTokens.of(context);
    return Container(
      color: ig.canvas,
      child: _child,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}

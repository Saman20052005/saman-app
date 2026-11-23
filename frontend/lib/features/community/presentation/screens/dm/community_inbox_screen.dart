import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_author.dart';
import '../../../domain/models/community_dm.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';
import '../../widgets/community_call_host_listener.dart';
import 'community_chat_thread_screen.dart';

/// R16 Messenger-Lite Inbox screen.
/// Displays DM conversation threads with realtime search, unread badges,
/// activity indicators, pagination, pull-to-refresh, and new conversation modal.
class CommunityInboxScreen extends ConsumerStatefulWidget {
  const CommunityInboxScreen({super.key});

  @override
  ConsumerState<CommunityInboxScreen> createState() =>
      _CommunityInboxScreenState();
}

class _CommunityInboxScreenState extends ConsumerState<CommunityInboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  bool _isCreatingConversation = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(communityDmWsServiceProvider).connect();
      ref.read(communityInboxProvider.notifier).loadConversations();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      final state = ref.read(communityInboxProvider);
      if (state.nextCursor != null && !state.isLoadingMore && !state.isLoading) {
        ref.read(communityInboxProvider.notifier).loadMore();
      }
    }
  }

  Future<void> _openThread(DmConversation conversation) async {
    final hadUnread = conversation.unreadCount > 0;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CommunityChatThreadScreen(
          conversationId: conversation.id,
          peer: conversation.peer,
          initialConversation: conversation,
        ),
      ),
    );
    if (!mounted) return;
    if (hadUnread) {
      ref.read(communityInboxProvider.notifier).loadConversations();
    }
  }

  Future<void> _startConversationWithAuthor(CommunityAuthor author) async {
    if (_isCreatingConversation) return;
    setState(() {
      _isCreatingConversation = true;
    });
    try {
      final conv = await ref
          .read(communityInboxProvider.notifier)
          .createOrGetConversation(author.id);
      if (!mounted) return;
      await _openThread(conv);
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
        setState(() {
          _isCreatingConversation = false;
        });
      }
    }
  }

  Future<void> _showNewChatBottomSheet() async {
    final ig = SamanIgTokens.of(context);
    final selectedAuthor = await showModalBottomSheet<CommunityAuthor>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _NewChatMemberSheet(),
    );

    if (selectedAuthor != null && mounted) {
      await _startConversationWithAuthor(selectedAuthor);
    }
  }

  List<DmConversation> _filterConversations(List<DmConversation> all) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((conv) {
      return conv.peer.name.toLowerCase().contains(q) ||
          conv.lastMessagePreview.toLowerCase().contains(q);
    }).toList();
  }

  String _formatRelativeTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút';
    if (diff.inHours < 24 && local.day == now.day) {
      return '${diff.inHours} giờ';
    }
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final msgDay = DateTime(local.year, local.month, local.day);
    if (msgDay == yesterday) return 'Hôm qua';
    if (diff.inDays < 7) return '${diff.inDays} ngày';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo';
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(communityInboxProvider);
    final notifier = ref.read(communityInboxProvider.notifier);
    final visibleConversations = _filterConversations(state.conversations);

    return CommunityCallHostListener(
      child: Scaffold(
        backgroundColor: ig.canvas,
        body: SafeArea(
          child: Column(
            children: [
              _InboxAppBar(
                totalUnreadCount: state.totalUnreadCount,
                ig: ig,
                onBack: () => Navigator.pop(context),
                onNewChat: _showNewChatBottomSheet,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: ig.surfaceElevated,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 14,
                      color: ig.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm cuộc trò chuyện...',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 14,
                        color: ig.textMuted,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: ig.textMuted,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              tooltip: 'Xóa tìm kiếm',
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: ig.textMuted,
                              ),
                            )
                          : null,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildBody(
                  context: context,
                  state: state,
                  visibleConversations: visibleConversations,
                  notifier: notifier,
                  ig: ig,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required CommunityInboxState state,
    required List<DmConversation> visibleConversations,
    required CommunityInboxNotifier notifier,
    required SamanIgTokens ig,
  }) {
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && state.conversations.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: ig.primaryAction),
      );
    }

    if (state.errorMessage != null && state.conversations.isEmpty) {
      return RefreshIndicator(
        color: ig.primaryAction,
        backgroundColor: ig.surface,
        onRefresh: notifier.loadConversations,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 40,
                        color: ig.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.errorMessage!,
                        textAlign: TextAlign.center,
                        style: textTheme.titleSmall?.copyWith(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ig.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: notifier.loadConversations,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ig.primaryAction,
                          side: BorderSide(color: ig.primaryAction),
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          'Thử lại',
                          style: textTheme.labelLarge?.copyWith(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ig.primaryAction,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (state.conversations.isEmpty) {
      return RefreshIndicator(
        color: ig.primaryAction,
        backgroundColor: ig.surface,
        onRefresh: notifier.loadConversations,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _InboxEmptyState(
                ig: ig,
                onStartChat: _showNewChatBottomSheet,
              ),
            ),
          ),
        ),
      );
    }

    if (visibleConversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 40,
                color: ig.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                'Không tìm thấy cuộc trò chuyện nào',
                style: textTheme.titleSmall?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ig.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Thử từ khóa khác hoặc bắt đầu cuộc trò chuyện mới.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 13,
                  color: ig.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final itemCount =
        visibleConversations.length + (state.isLoadingMore ? 1 : 0);

    return RefreshIndicator(
      color: ig.primaryAction,
      backgroundColor: ig.surface,
      onRefresh: notifier.loadConversations,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= visibleConversations.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ig.primaryAction,
                  ),
                ),
              ),
            );
          }

          final conv = visibleConversations[index];
          return _ConversationTile(
            conversation: conv,
            relativeTime:
                _formatRelativeTime(conv.lastMessageAt ?? conv.updatedAt),
            ig: ig,
            onTap: () => _openThread(conv),
          );
        },
      ),
    );
  }
}

class _InboxAppBar extends StatelessWidget {
  final int totalUnreadCount;
  final SamanIgTokens ig;
  final VoidCallback onBack;
  final VoidCallback onNewChat;

  const _InboxAppBar({
    required this.totalUnreadCount,
    required this.ig,
    required this.onBack,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: ig.canvas,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Quay lại',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Tin nhắn',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: ig.textPrimary,
                    ),
                  ),
                ),
                if (totalUnreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: ig.primaryAction.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ig.primaryAction.withOpacity(0.35),
                      ),
                    ),
                    child: Text(
                      totalUnreadCount > 99 ? '99+' : '$totalUnreadCount',
                      style: textTheme.labelSmall?.copyWith(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ig.primaryAction,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onNewChat,
            tooltip: 'Tin nhắn mới',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.add_comment_outlined,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final DmConversation conversation;
  final String relativeTime;
  final SamanIgTokens ig;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.relativeTime,
    required this.ig,
    required this.onTap,
  });

  ({IconData? icon, String text}) _buildPreviewData() {
    final type = (conversation.lastMessageType ?? '').toLowerCase();
    final raw = conversation.lastMessagePreview.trim();

    switch (type) {
      case 'voice':
        return (
          icon: Icons.mic_rounded,
          text: raw.isEmpty || raw == 'voice' ? 'Tin nhắn thoại' : raw,
        );
      case 'photo':
        return (
          icon: Icons.photo_outlined,
          text: raw.isEmpty || raw == 'photo' ? 'Hình ảnh' : raw,
        );
      case 'video':
        return (
          icon: Icons.videocam_outlined,
          text: raw.isEmpty || raw == 'video' ? 'Video' : raw,
        );
      case 'post_share':
        return (
          icon: Icons.article_outlined,
          text: raw.isEmpty || raw == 'post_share'
              ? 'Đã chia sẻ bài viết'
              : raw,
        );
      case 'story_reply':
        return (
          icon: Icons.auto_stories_rounded,
          text: raw.isEmpty || raw == 'story_reply'
              ? 'Đã trả lời tin'
              : raw,
        );
      case 'call_log':
        final isVideoCall = raw.toLowerCase().contains('video');
        return (
          icon: isVideoCall ? Icons.videocam_outlined : Icons.call_outlined,
          text: raw.isEmpty || raw == 'call_log' ? 'Cuộc gọi' : raw,
        );
      default:
        return (
          icon: null,
          text: raw.isNotEmpty ? raw : 'Bắt đầu cuộc trò chuyện',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasUnread = conversation.unreadCount > 0;
    final preview = _buildPreviewData();
    final peer = conversation.peer;
    final initial =
        peer.name.trim().isNotEmpty ? peer.name.trim()[0].toUpperCase() : 'S';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ig.surfaceElevated,
                    border: Border.all(color: ig.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: peer.avatarUrl != null && peer.avatarUrl!.isNotEmpty
                      ? Image.network(
                          peer.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              initial,
                              style: textTheme.titleMedium?.copyWith(
                                fontFamily: SamanIgTokens.fontFamily,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: ig.primaryAction,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: textTheme.titleMedium?.copyWith(
                              fontFamily: SamanIgTokens.fontFamily,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: ig.primaryAction,
                            ),
                          ),
                        ),
                ),
                if (peer.showActivityStatus)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: ig.primaryAction,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ig.canvas,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                peer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleSmall?.copyWith(
                                  fontFamily: SamanIgTokens.fontFamily,
                                  fontSize: 15,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: ig.textPrimary,
                                ),
                              ),
                            ),
                            if (peer.isVerified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified_rounded,
                                size: 15,
                                color: ig.primaryAction,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        relativeTime,
                        style: textTheme.labelSmall?.copyWith(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 12,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w400,
                          color: hasUnread ? ig.primaryAction : ig.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (preview.icon != null) ...[
                        Icon(
                          preview.icon,
                          size: 14,
                          color: hasUnread
                              ? ig.textPrimary
                              : ig.textSecondary,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          preview.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 13.5,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w400,
                            color: hasUnread
                                ? ig.textPrimary
                                : ig.textSecondary,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: ig.primaryAction,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxEmptyState extends StatelessWidget {
  final SamanIgTokens ig;
  final VoidCallback onStartChat;

  const _InboxEmptyState({
    required this.ig,
    required this.onStartChat,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: ig.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ig.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.surfaceElevated,
                ),
                child: Icon(
                  Icons.forum_outlined,
                  size: 30,
                  color: ig.primaryAction,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Chưa có cuộc trò chuyện nào',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ig.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Kết nối trực tiếp với huấn luyện viên và bạn bè trong cộng đồng Saman qua tin nhắn, ảnh và giọng nói.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 13,
                  color: ig.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: onStartChat,
                  style: ig.primaryButtonStyle(
                    minHeight: 46,
                    borderRadius: 12,
                  ),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: Text(
                    'Bắt đầu trò chuyện',
                    style: ig.buttonLabel(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewChatMemberSheet extends ConsumerStatefulWidget {
  const _NewChatMemberSheet();

  @override
  ConsumerState<_NewChatMemberSheet> createState() =>
      _NewChatMemberSheetState();
}

class _NewChatMemberSheetState extends ConsumerState<_NewChatMemberSheet> {
  final TextEditingController _filterController = TextEditingController();
  List<CommunityAuthor> _suggestions = const [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final repo = ref.read(communityRepositoryProvider);
    final activeUserId = repo.activeUserId;
    final byId = <String, CommunityAuthor>{};

    try {
      final following = await repo.getFollowing('me');
      for (final author in following) {
        if (author.id.isNotEmpty && author.id != activeUserId) {
          byId[author.id] = author;
        }
      }
    } catch (_) {}

    try {
      final discover = await repo.getDiscoverData();
      for (final creator in discover.recommendedCreators) {
        if (creator.id.isNotEmpty && creator.id != activeUserId) {
          byId.putIfAbsent(creator.id, () => creator);
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _suggestions = byId.values.toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final filtered = _query.trim().isEmpty
        ? _suggestions
        : _suggestions.where((author) {
            final q = _query.trim().toLowerCase();
            return author.name.toLowerCase().contains(q) ||
                (author.handle?.toLowerCase().contains(q) ?? false);
          }).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ig.textMuted.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tin nhắn mới',
                      style: textTheme.titleMedium?.copyWith(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: ig.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Đóng',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      color: ig.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: ig.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _filterController,
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 14,
                    color: ig.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tìm thành viên để nhắn tin...',
                    hintStyle: textTheme.bodyMedium?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 14,
                      color: ig.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: ig.textMuted,
                    ),
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _isLoading
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: ig.primaryAction,
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'Không có gợi ý thành viên phù hợp.',
                              style: textTheme.bodySmall?.copyWith(
                                fontFamily: SamanIgTokens.fontFamily,
                                fontSize: 13,
                                color: ig.textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final author = filtered[index];
                              final initial = author.name.trim().isNotEmpty
                                  ? author.name.trim()[0].toUpperCase()
                                  : 'S';
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                minTileHeight: 56,
                                onTap: () => Navigator.pop(context, author),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ig.surfaceElevated,
                                    border: Border.all(color: ig.border),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: author.avatarUrl != null &&
                                          author.avatarUrl!.isNotEmpty
                                      ? Image.network(
                                          author.avatarUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Center(
                                            child: Text(
                                              initial,
                                              style: textTheme.titleSmall
                                                  ?.copyWith(
                                                fontFamily:
                                                    SamanIgTokens.fontFamily,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: ig.primaryAction,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            initial,
                                            style:
                                                textTheme.titleSmall?.copyWith(
                                              fontFamily:
                                                  SamanIgTokens.fontFamily,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: ig.primaryAction,
                                            ),
                                          ),
                                        ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        author.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleSmall?.copyWith(
                                          fontFamily: SamanIgTokens.fontFamily,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: ig.textPrimary,
                                        ),
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
                                subtitle: (author.title?.isNotEmpty ?? false) ||
                                        (author.handle?.isNotEmpty ?? false)
                                    ? Text(
                                        author.title ?? '@${author.handle}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          fontFamily: SamanIgTokens.fontFamily,
                                          fontSize: 12,
                                          color: ig.textSecondary,
                                        ),
                                      )
                                    : null,
                                trailing: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: ig.primaryAction,
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

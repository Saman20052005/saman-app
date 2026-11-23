import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_author.dart';
import '../../../domain/models/community_dm.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_providers.dart';
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
    final tokens = SamanHomeTokens.of(context);
    final selectedAuthor = await showModalBottomSheet<CommunityAuthor>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.cardSurface,
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
    final tokens = SamanHomeTokens.of(context);
    final state = ref.watch(communityInboxProvider);
    final notifier = ref.read(communityInboxProvider.notifier);
    final visibleConversations = _filterConversations(state.conversations);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _InboxAppBar(
              totalUnreadCount: state.totalUnreadCount,
              tokens: tokens,
              onBack: () => Navigator.pop(context),
              onNewChat: _showNewChatBottomSheet,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: TextStyle(
                  fontSize: 14,
                  color: tokens.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm cuộc trò chuyện...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: tokens.textMuted,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: tokens.textSecondary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: tokens.textMuted,
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: tokens.cardSurface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: tokens.greenAccent),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _buildBody(
                state: state,
                visibleConversations: visibleConversations,
                notifier: notifier,
                tokens: tokens,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required CommunityInboxState state,
    required List<DmConversation> visibleConversations,
    required CommunityInboxNotifier notifier,
    required SamanHomePalette tokens,
  }) {
    if (state.isLoading && state.conversations.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: tokens.greenAccent),
      );
    }

    if (state.errorMessage != null && state.conversations.isEmpty) {
      return RefreshIndicator(
        color: tokens.greenAccent,
        backgroundColor: tokens.cardSurface,
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
                        color: tokens.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: notifier.loadConversations,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.greenAccent,
                          side: BorderSide(color: tokens.greenAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Thử lại'),
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
        color: tokens.greenAccent,
        backgroundColor: tokens.cardSurface,
        onRefresh: notifier.loadConversations,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _InboxEmptyState(
                tokens: tokens,
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
                color: tokens.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                'Không tìm thấy cuộc trò chuyện nào',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Thử từ khóa khác hoặc bắt đầu cuộc trò chuyện mới.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
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
      color: tokens.greenAccent,
      backgroundColor: tokens.cardSurface,
      onRefresh: notifier.loadConversations,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: itemCount,
        separatorBuilder: (_, __) => Divider(
          color: tokens.border,
          height: 1,
          indent: 70,
        ),
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
                    color: tokens.greenAccent,
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
            tokens: tokens,
            onTap: () => _openThread(conv),
          );
        },
      ),
    );
  }
}

class _InboxAppBar extends StatelessWidget {
  final int totalUnreadCount;
  final SamanHomePalette tokens;
  final VoidCallback onBack;
  final VoidCallback onNewChat;

  const _InboxAppBar({
    required this.totalUnreadCount,
    required this.tokens,
    required this.onBack,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Quay lại',
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
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
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                if (totalUnreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.greenBadgeBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.greenBadgeBorder),
                    ),
                    child: Text(
                      totalUnreadCount > 99 ? '99+' : '$totalUnreadCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tokens.greenAccent,
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
            icon: Icon(
              Icons.add_comment_outlined,
              color: tokens.textPrimary,
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
  final SamanHomePalette tokens;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.relativeTime,
    required this.tokens,
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
      default:
        return (
          icon: null,
          text: raw.isNotEmpty ? raw : 'Bắt đầu cuộc trò chuyện',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    final preview = _buildPreviewData();
    final peer = conversation.peer;
    final initial =
        peer.name.trim().isNotEmpty ? peer.name.trim()[0].toUpperCase() : 'S';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: hasUnread
              ? tokens.greenAccent.withOpacity(0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.secondarySurface,
                    border: Border.all(color: tokens.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: peer.avatarUrl != null && peer.avatarUrl!.isNotEmpty
                      ? Image.network(
                          peer.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              initial,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: tokens.greenAccent,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: tokens.greenAccent,
                            ),
                          ),
                        ),
                ),
                if (peer.showActivityStatus)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: tokens.greenAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tokens.canvas,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            if (peer.isVerified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified_rounded,
                                size: 15,
                                color: tokens.greenAccent,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        relativeTime,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w500,
                          color: hasUnread
                              ? tokens.greenAccent
                              : tokens.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (preview.icon != null) ...[
                        Icon(
                          preview.icon,
                          size: 14,
                          color: hasUnread
                              ? tokens.greenAccent
                              : tokens.textSecondary,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          preview.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                            color: hasUnread
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.greenAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : '${conversation.unreadCount}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: tokens.primaryCtaText,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
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
  final SamanHomePalette tokens;
  final VoidCallback onStartChat;

  const _InboxEmptyState({
    required this.tokens,
    required this.onStartChat,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.secondarySurface,
                ),
                child: Icon(
                  Icons.forum_outlined,
                  size: 30,
                  color: tokens.greenAccent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Chưa có cuộc trò chuyện nào',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Kết nối trực tiếp với huấn luyện viên và bạn bè trong cộng đồng Saman qua tin nhắn, ảnh và giọng nói.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onStartChat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.greenAccent,
                    foregroundColor: tokens.primaryCtaText,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text(
                    'Bắt đầu trò chuyện',
                    style: TextStyle(
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
    final tokens = SamanHomeTokens.of(context);
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
                  color: tokens.borderHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tin nhắn mới',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: tokens.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _filterController,
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
                style: TextStyle(fontSize: 14, color: tokens.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Tìm thành viên để nhắn tin...',
                  hintStyle: TextStyle(fontSize: 14, color: tokens.textMuted),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: tokens.textSecondary,
                  ),
                  filled: true,
                  fillColor: tokens.secondarySurface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: tokens.greenAccent),
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
                            color: tokens.greenAccent,
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'Không có gợi ý thành viên phù hợp.',
                              style: TextStyle(
                                fontSize: 13,
                                color: tokens.textSecondary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              color: tokens.border,
                              height: 1,
                            ),
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
                                onTap: () => Navigator.pop(context, author),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.secondarySurface,
                                    border: Border.all(color: tokens.border),
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
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: tokens.greenAccent,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            initial,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: tokens.greenAccent,
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
                                subtitle: (author.title?.isNotEmpty ?? false) ||
                                        (author.handle?.isNotEmpty ?? false)
                                    ? Text(
                                        author.title ?? '@${author.handle}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: tokens.textSecondary,
                                        ),
                                      )
                                    : null,
                                trailing: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: tokens.greenAccent,
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

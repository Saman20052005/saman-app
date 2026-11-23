import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/routes.dart';
import '../../../domain/models/community_notification.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';

class CommunityNotificationsScreen extends ConsumerWidget {
  const CommunityNotificationsScreen({super.key});

  bool _isToday(String timeAgo) {
    final lower = timeAgo.toLowerCase();
    return lower.contains('phút') ||
        lower.contains('giờ') ||
        lower.contains('vừa xong');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final state = ref.watch(communityNotificationsProvider);
    final notifier = ref.read(communityNotificationsProvider.notifier);

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state, notifier, ig),
            _buildFilterChips(state, notifier, ig),
            Expanded(
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ig.primaryAction,
                      ),
                    )
                  : _buildNotificationList(context, state, notifier, ig),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    CommunityNotificationsState state,
    CommunityNotificationsNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(bottom: BorderSide(color: ig.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Quay lại',
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
                    'Thông báo',
                    overflow: TextOverflow.ellipsis,
                    style: ig.displayTitle(fontSize: 20).copyWith(
                          letterSpacing: -0.3,
                        ),
                  ),
                ),
                if (state.unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ig.primaryAction,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            onPressed:
                state.unreadCount > 0 ? () => notifier.markAllAsRead() : null,
            icon: Icon(
              Icons.done_all_rounded,
              size: 18,
              color: state.unreadCount > 0
                  ? ig.primaryAction
                  : ig.textMuted,
            ),
            label: Text(
              'Đã đọc',
              style: ig.buttonLabel(
                fontSize: 13,
                color: state.unreadCount > 0
                    ? ig.textSecondary
                    : ig.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    CommunityNotificationsState state,
    CommunityNotificationsNotifier notifier,
    SamanIgTokens ig,
  ) {
    final filters = [
      {'key': 'all', 'label': 'Tất cả'},
      {'key': 'interactions', 'label': 'Tương tác'},
      {'key': 'system', 'label': 'Hệ thống'},
    ];

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: filters.map((f) {
            final isSelected = state.activeFilter == f['key'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => notifier.setFilter(f['key']!),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ig.primaryAction.withOpacity(0.12)
                        : ig.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? ig.primaryAction : ig.border,
                      width: isSelected ? 1 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ig.primaryAction,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        f['label']!,
                        style: ig.caption(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? ig.primaryAction
                              : ig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNotificationList(
    BuildContext context,
    CommunityNotificationsState state,
    CommunityNotificationsNotifier notifier,
    SamanIgTokens ig,
  ) {
    final list = state.filteredNotifications;

    if (list.isEmpty) {
      return RefreshIndicator(
        color: ig.primaryAction,
        backgroundColor: ig.surface,
        onRefresh: () => notifier.loadNotifications(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildEmptyState(ig),
            ),
          ),
        ),
      );
    }

    final todayList = list.where((n) => _isToday(n.timeAgo)).toList();
    final earlierList = list.where((n) => !_isToday(n.timeAgo)).toList();

    return RefreshIndicator(
      color: ig.primaryAction,
      backgroundColor: ig.surface,
      onRefresh: () => notifier.loadNotifications(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (todayList.isNotEmpty) ...[
            _buildSectionHeader(
              title: 'Hôm nay',
              badgeText: state.unreadCount > 0 ? '${state.unreadCount} mới' : null,
              ig: ig,
            ),
            ..._buildSectionItems(
              context: context,
              items: todayList,
              notifier: notifier,
              ig: ig,
            ),
          ],
          if (earlierList.isNotEmpty) ...[
            SizedBox(height: todayList.isNotEmpty ? 16 : 0),
            _buildSectionHeader(
              title: 'Trước đó',
              ig: ig,
            ),
            ..._buildSectionItems(
              context: context,
              items: earlierList,
              notifier: notifier,
              ig: ig,
              dimmed: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? badgeText,
    required SamanIgTokens ig,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: ig.caption(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ).copyWith(letterSpacing: 0.8),
          ),
          if (badgeText != null)
            Text(
              badgeText,
              style: ig.caption(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ig.primaryAction,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSectionItems({
    required BuildContext context,
    required List<CommunityNotification> items,
    required CommunityNotificationsNotifier notifier,
    required SamanIgTokens ig,
    bool dimmed = false,
  }) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final notif = items[i];
      widgets.add(_buildNotificationRow(
        context: context,
        notif: notif,
        notifier: notifier,
        ig: ig,
        dimmed: dimmed && !notif.isUnread,
      ));
      if (i < items.length - 1) {
        widgets.add(Divider(color: ig.border, height: 1, thickness: 0.5));
      }
    }
    return widgets;
  }

  Widget _buildNotificationRow({
    required BuildContext context,
    required CommunityNotification notif,
    required CommunityNotificationsNotifier notifier,
    required SamanIgTokens ig,
    bool dimmed = false,
  }) {
    return Opacity(
      opacity: dimmed ? 0.88 : 1.0,
      child: InkWell(
        onTap: () {
          notifier.markAsRead(notif.id);
          if (notif.targetPostId != null) {
            Navigator.pushNamed(
              context,
              AppRoutes.communityPost,
              arguments: notif.targetPostId,
            );
          } else if (notif.type == CommunityNotificationType.follow) {
            // Keep safe navigation for follow notifications without an actor profile route
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: notif.isUnread
                ? ig.primaryAction.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActorAvatar(notif, ig),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: ig.body(fontSize: 14, height: 1.38),
                        children: [
                          TextSpan(
                            text: notif.actorName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: ' ${notif.actionText}',
                            style: TextStyle(color: ig.textSecondary),
                          ),
                          if (notif.targetSnippet != null)
                            TextSpan(
                              text: ' "${notif.targetSnippet}"',
                              style: TextStyle(
                                color: ig.textPrimary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          notif.timeAgo,
                          style: ig.caption(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: ig.textMuted,
                          ),
                        ),
                        if (notif.isUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ig.primaryAction,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (notif.targetPostId != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ig.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ig.border, width: 0.5),
                  ),
                  child: Icon(
                    notif.type == CommunityNotificationType.comment
                        ? Icons.forum_outlined
                        : Icons.article_outlined,
                    size: 18,
                    color: ig.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(SamanIgTokens ig) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            color: ig.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ig.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.surfaceElevated,
                ),
                child: Icon(
                  Icons.notifications_paused_rounded,
                  size: 28,
                  color: ig.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Chưa có thông báo nào',
                style: ig.displayTitle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Các tương tác cộng đồng trong nhóm lọc này sẽ xuất hiện tại đây ngay khi có cập nhật.',
                textAlign: TextAlign.center,
                style: ig.body(
                  fontSize: 13,
                  color: ig.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActorAvatar(
    CommunityNotification notif,
    SamanIgTokens ig,
  ) {
    IconData icon;
    Color iconColor;

    switch (notif.type) {
      case CommunityNotificationType.like:
        icon = Icons.favorite_rounded;
        iconColor = ig.likeHeart;
        break;
      case CommunityNotificationType.comment:
        icon = Icons.chat_bubble_rounded;
        iconColor = ig.primaryAction;
        break;
      case CommunityNotificationType.follow:
        icon = Icons.person_add_rounded;
        iconColor = ig.primaryAction;
        break;
      case CommunityNotificationType.answer:
        icon = Icons.question_answer_rounded;
        iconColor = ig.primaryAction;
        break;
      case CommunityNotificationType.system:
        icon = Icons.notifications_active_rounded;
        iconColor = ig.textSecondary;
        break;
    }

    final initial = notif.actorName.isNotEmpty
        ? notif.actorName[0].toUpperCase()
        : 'S';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ig.surfaceElevated,
          ),
          clipBehavior: Clip.antiAlias,
          child: notif.actorAvatarUrl != null &&
                  notif.actorAvatarUrl!.isNotEmpty
              ? Image.network(
                  notif.actorAvatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      initial,
                      style: ig.displayTitle(
                        fontSize: 16,
                        color: ig.textPrimary,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    initial,
                    style: ig.displayTitle(
                      fontSize: 16,
                      color: ig.textPrimary,
                    ),
                  ),
                ),
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ig.surface,
              border: Border.all(color: ig.canvas, width: 1.5),
            ),
            child: Icon(icon, size: 11, color: iconColor),
          ),
        ),
      ],
    );
  }
}

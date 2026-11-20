import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/routes.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/community_notification.dart';
import '../../providers/community_providers.dart';

class CommunityNotificationsScreen extends ConsumerWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final state = ref.watch(communityNotificationsProvider);
    final notifier = ref.read(communityNotificationsProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state, notifier, tokens),
            _buildFilterChips(state, notifier, tokens),
            Expanded(
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: tokens.greenAccent,
                      ),
                    )
                  : _buildNotificationList(context, state, notifier, tokens),
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
          Row(
            children: [
              Text(
                'Thông báo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              if (state.unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.greenAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${state.unreadCount}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tokens.isDark
                          ? const Color(0xFF003824)
                          : const Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ],
          ),
          TextButton(
            onPressed: state.unreadCount > 0 ? () => notifier.markAllAsRead() : null,
            child: Text(
              'Đọc hết',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: state.unreadCount > 0
                    ? tokens.greenAccent
                    : tokens.textMuted,
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
    SamanHomePalette tokens,
  ) {
    final filters = [
      {'key': 'all', 'label': 'Tất cả'},
      {'key': 'interactions', 'label': 'Tương tác'},
      {'key': 'system', 'label': 'Hệ thống'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = state.activeFilter == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: isSelected,
              onSelected: (_) => notifier.setFilter(f['key']!),
              selectedColor: tokens.greenAccent,
              backgroundColor: tokens.cardSurface,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF))
                    : tokens.textSecondary,
              ),
              side: BorderSide(
                color: isSelected
                    ? tokens.greenAccent
                    : tokens.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNotificationList(
    BuildContext context,
    CommunityNotificationsState state,
    CommunityNotificationsNotifier notifier,
    SamanHomePalette tokens,
  ) {
    final list = state.filteredNotifications;

    if (list.isEmpty) {
      return Center(
        child: Text(
          'Không có thông báo nào.',
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          Divider(color: tokens.border, height: 1),
      itemBuilder: (context, index) {
        final notif = list[index];
        return InkWell(
          onTap: () {
            notifier.markAsRead(notif.id);
            if (notif.targetPostId != null) {
              Navigator.pushNamed(
                context,
                AppRoutes.communityPost,
                arguments: notif.targetPostId,
              );
            }
          },
          child: Container(
            color: notif.isUnread
                ? tokens.greenAccent.withOpacity(0.04)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActorAvatar(notif, tokens),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.textPrimary,
                            height: 1.35,
                          ),
                          children: [
                            TextSpan(
                              text: notif.actorName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: ' ${notif.actionText}'),
                          ],
                        ),
                      ),
                      if (notif.targetSnippet != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '"${notif.targetSnippet}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        notif.timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (notif.isUnread) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.greenAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActorAvatar(
    CommunityNotification notif,
    SamanHomePalette tokens,
  ) {
    IconData icon;
    Color iconColor;

    switch (notif.type) {
      case CommunityNotificationType.like:
        icon = Icons.favorite_rounded;
        iconColor = tokens.isDark
            ? const Color(0xFFFF5252)
            : const Color(0xFFDC2626);
        break;
      case CommunityNotificationType.comment:
        icon = Icons.chat_bubble_rounded;
        iconColor = tokens.greenAccent;
        break;
      case CommunityNotificationType.follow:
        icon = Icons.person_add_rounded;
        iconColor = tokens.isDark
            ? const Color(0xFF64B5F6)
            : const Color(0xFF0284C7);
        break;
      case CommunityNotificationType.system:
        icon = Icons.notifications_active_rounded;
        iconColor = tokens.isDark
            ? const Color(0xFFFFB74D)
            : tokens.carbsAmber;
        break;
    }

    return Stack(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.secondarySurface,
          ),
          child: Center(
            child: Text(
              notif.actorName.isNotEmpty ? notif.actorName[0] : 'S',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.greenAccent,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.canvas,
            ),
            child: Icon(icon, size: 12, color: iconColor),
          ),
        ),
      ],
    );
  }
}

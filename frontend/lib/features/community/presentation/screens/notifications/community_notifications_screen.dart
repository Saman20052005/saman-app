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
    final state = ref.watch(communityNotificationsProvider);
    final notifier = ref.read(communityNotificationsProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, state, notifier),
            _buildFilterChips(state, notifier),
            Expanded(
              child: state.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SamanHomeTokens.greenAccent,
                      ),
                    )
                  : _buildNotificationList(context, state, notifier),
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
  ) {
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
          Row(
            children: [
              const Text(
                'Thông báo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
                ),
              ),
              if (state.unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: SamanHomeTokens.greenAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${state.unreadCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF003824),
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
                    ? SamanHomeTokens.greenAccent
                    : const Color(0xFF55585C),
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
              selectedColor: SamanHomeTokens.greenAccent,
              backgroundColor: const Color(0xFF1E1F21),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF003824)
                    : const Color(0xFFBBCAAF),
              ),
              side: BorderSide(
                color: isSelected
                    ? SamanHomeTokens.greenAccent
                    : const Color(0xFF2E3033),
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
  ) {
    final list = state.filteredNotifications;

    if (list.isEmpty) {
      return const Center(
        child: Text(
          'Không có thông báo nào.',
          style: TextStyle(color: Color(0xFF71767B), fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Color(0xFF1F2021), height: 1),
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
                ? SamanHomeTokens.greenAccent.withOpacity(0.04)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActorAvatar(notif),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 13,
                            color: SamanHomeTokens.textWhite,
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
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFBBCAAF),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        notif.timeAgo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF71767B),
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
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: SamanHomeTokens.greenAccent,
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

  Widget _buildActorAvatar(CommunityNotification notif) {
    IconData icon;
    Color iconColor;

    switch (notif.type) {
      case CommunityNotificationType.like:
        icon = Icons.favorite_rounded;
        iconColor = const Color(0xFFFF5252);
        break;
      case CommunityNotificationType.comment:
        icon = Icons.chat_bubble_rounded;
        iconColor = SamanHomeTokens.greenAccent;
        break;
      case CommunityNotificationType.follow:
        icon = Icons.person_add_rounded;
        iconColor = const Color(0xFF64B5F6);
        break;
      case CommunityNotificationType.system:
        icon = Icons.notifications_active_rounded;
        iconColor = const Color(0xFFFFB74D);
        break;
    }

    return Stack(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF292A2B),
          ),
          child: Center(
            child: Text(
              notif.actorName.isNotEmpty ? notif.actorName[0] : 'S',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.greenAccent,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF121314),
            ),
            child: Icon(icon, size: 12, color: iconColor),
          ),
        ),
      ],
    );
  }
}

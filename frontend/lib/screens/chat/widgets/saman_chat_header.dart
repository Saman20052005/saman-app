import 'package:flutter/material.dart';
import '../../../config/routes.dart';
import '../../../features/community/presentation/screens/notifications/community_notifications_screen.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// The approved Saman Chat header:
/// - Left: Minimal menu/drawer icon (visible on mobile, hidden on desktop when sidebar/rail is shown)
/// - Center: Small 20x20 S monogram + "Saman Coach" title
/// - Right: New conversation action + default inactive bell icon
///
/// Built on Flutter's robust AppBar foundation to guarantee perfect centering,
/// responsive layout down to narrow viewports, and clean touch targets.
/// Strips all legacy AI branding ("AI Coach", robot icon, trash icon as primary visible action).
class SamanChatHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onNewChat;
  final VoidCallback? onNotificationsTap;
  final bool hasActiveReminders;
  final bool showLeadingMenu;

  const SamanChatHeader({
    super.key,
    required this.onMenuTap,
    required this.onNewChat,
    this.onNotificationsTap,
    this.hasActiveReminders = false,
    this.showLeadingMenu = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56.0);

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return AppBar(
      backgroundColor: t.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleSpacing: 0,
      leadingWidth: 48,
      automaticallyImplyLeading: showLeadingMenu,
      shape: Border(
        bottom: BorderSide(
          color: t.borderSubtle,
          width: 1.0,
        ),
      ),
      leading: showLeadingMenu
          ? Semantics(
              button: true,
              label: 'Open Coach Menu',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.notes_rounded,
                  color: t.textSecondary,
                  size: 22,
                ),
                tooltip: 'Coach Menu',
                onPressed: onMenuTap,
              ),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SamanMonogram.header(),
          const SizedBox(width: 8.0),
          Flexible(
            child: Text(
              'Saman Coach',
              style: t.headerTitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        Semantics(
          button: true,
          label: 'New Conversation',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.edit_square,
              color: t.textSecondary,
              size: 20,
            ),
            tooltip: 'New conversation',
            onPressed: onNewChat,
          ),
        ),
        Semantics(
          button: true,
          label: 'Reminders',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: t.textSecondary,
                  size: 22,
                ),
                tooltip: 'Reminders',
                onPressed: () {
                  if (onNotificationsTap != null) {
                    onNotificationsTap!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CommunityNotificationsScreen(),
                        settings: const RouteSettings(
                          name: AppRoutes.communityNotifications,
                        ),
                      ),
                    );
                  }
                },
              ),
              if (hasActiveReminders)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: t.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4.0),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// The approved Saman Chat header:
/// - Left: Minimal menu/drawer icon
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

  const SamanChatHeader({
    super.key,
    required this.onMenuTap,
    required this.onNewChat,
    this.onNotificationsTap,
    this.hasActiveReminders = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56.0);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: SamanChatTokens.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleSpacing: 0,
      leadingWidth: 48,
      shape: const Border(
        bottom: BorderSide(
          color: SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
      ),
      leading: Semantics(
        button: true,
        label: 'Open Coach Menu',
        child: IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.notes_rounded,
            color: SamanChatTokens.textSecondary,
            size: 22,
          ),
          tooltip: 'Coach Menu',
          onPressed: onMenuTap,
        ),
      ),
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SamanMonogram.header(),
          SizedBox(width: 8.0),
          Flexible(
            child: Text(
              'Saman Coach',
              style: SamanChatTokens.headerTitle,
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
            icon: const Icon(
              Icons.edit_square,
              color: SamanChatTokens.textSecondary,
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
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: SamanChatTokens.textSecondary,
                  size: 22,
                ),
                tooltip: 'Reminders',
                onPressed: () {
                  if (onNotificationsTap != null) {
                    onNotificationsTap!();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No active coach reminders right now.',
                          style: TextStyle(color: SamanChatTokens.textWhite),
                        ),
                        backgroundColor: SamanChatTokens.surfaceElevated,
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
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
                    decoration: const BoxDecoration(
                      color: SamanChatTokens.greenAccent,
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

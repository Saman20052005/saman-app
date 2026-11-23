import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Top header bar for Saman Home screen.
///
/// Displays:
/// - User greeting ("Hello, Saman")
/// - Dynamic date & session theme ("Tuesday, Oct 24 • Recovery & Power")
/// - Notification button with active status badge
/// - Settings action button
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.userName,
    this.dateSubtitle = 'Tuesday, Oct 24 • Recovery & Power',
    this.hasUnreadNotifications = true,
    this.onNotificationTap,
    this.onSettingsTap,
  });

  final String userName;
  final String dateSubtitle;
  final bool hasUnreadNotifications;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
        vertical: SamanHomeTokens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hello, $userName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.screenTitle,
                ),
                const SizedBox(height: 2),
                Text(
                  dateSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.headerSubtitle,
                ),
              ],
            ),
          ),
          const SizedBox(width: SamanHomeTokens.spacingSm),
          _HeaderSquareButton(
            icon: Icons.notifications_outlined,
            hasBadge: hasUnreadNotifications,
            badgeColor: tokens.greenAccent,
            tooltip: 'Notifications',
            onTap: onNotificationTap,
          ),
          const SizedBox(width: SamanHomeTokens.spacingSm),
          _HeaderSquareButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _HeaderSquareButton extends StatelessWidget {
  const _HeaderSquareButton({
    required this.icon,
    this.hasBadge = false,
    this.badgeColor,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final bool hasBadge;
  final Color? badgeColor;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tokens.secondarySurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            border: Border.all(
              color: tokens.border,
              width: 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: tokens.textSecondary,
              ),
              if (hasBadge)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: badgeColor ?? tokens.mintAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tokens.secondarySurface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

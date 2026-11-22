import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../providers/community_providers.dart';
import 'create_content_bottom_sheet.dart';

enum CommunityNavTab {
  feed,
  discover,
  create,
  notifications,
  profile,
}

class CommunityBottomNavigationBar extends ConsumerWidget {
  final CommunityNavTab currentTab;
  final ValueChanged<CommunityNavTab>? onTabSelected;
  final bool? hasUnreadBadge;

  const CommunityBottomNavigationBar({
    super.key,
    required this.currentTab,
    this.onTabSelected,
    this.hasUnreadBadge,
  });

  void _handleTabTap(BuildContext context, CommunityNavTab tab) {
    if (tab == currentTab) return;
    if (onTabSelected != null) {
      onTabSelected!(tab);
      return;
    }
    switch (tab) {
      case CommunityNavTab.feed:
        Navigator.pushReplacementNamed(context, AppRoutes.communityFeed);
        break;
      case CommunityNavTab.discover:
        Navigator.pushReplacementNamed(context, AppRoutes.communityDiscover);
        break;
      case CommunityNavTab.create:
        CreateContentBottomSheet.show(context);
        break;
      case CommunityNavTab.notifications:
        Navigator.pushNamed(context, AppRoutes.communityNotifications);
        break;
      case CommunityNavTab.profile:
        Navigator.pushNamed(context, AppRoutes.communityProfile);
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasScope =
        context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() !=
            null;
    final bool showNotificationsBadge = hasUnreadBadge ??
        (hasScope
            ? ref.watch(
                communityNotificationsProvider.select((s) => s.unreadCount > 0),
              )
            : false);

    return Container(
      decoration: BoxDecoration(
        color: tokens.canvas.withOpacity(0.95),
        border: Border(
          top: BorderSide(
            color: tokens.border,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.isDark ? Colors.black45 : const Color(0x140F172A),
            offset: const Offset(0, -2),
            blurRadius: 12,
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 4,
        right: 4,
        top: 2,
        bottom: bottomInset > 0 ? bottomInset : 4,
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.feed,
                icon: Icons.dynamic_feed_rounded,
                label: 'Bảng tin',
                isActive: currentTab == CommunityNavTab.feed,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.discover,
                icon: Icons.explore_rounded,
                label: 'Khám phá',
                isActive: currentTab == CommunityNavTab.discover,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: Center(
                child: _buildFabButton(context, tokens),
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.notifications,
                icon: Icons.notifications_rounded,
                label: 'Thông báo',
                isActive: currentTab == CommunityNavTab.notifications,
                hasBadge: showNotificationsBadge,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.profile,
                icon: Icons.person_rounded,
                label: 'Cá nhân',
                isActive: currentTab == CommunityNavTab.profile,
                isAvatar: true,
                tokens: tokens,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required CommunityNavTab tab,
    required IconData icon,
    required String label,
    required bool isActive,
    required SamanHomePalette tokens,
    bool hasBadge = false,
    bool isAvatar = false,
  }) {
    final activeColor = tokens.greenAccent;
    final inactiveColor =
        tokens.textSecondary.withOpacity(tokens.isDark ? 0.7 : 0.85);

    return InkWell(
      onTap: () => _handleTabTap(context, tab),
      borderRadius: BorderRadius.circular(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (isAvatar)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? activeColor.withOpacity(0.2)
                          : tokens.secondarySurface,
                      border: Border.all(
                        color: isActive ? activeColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 15,
                      color: isActive ? activeColor : inactiveColor,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 22,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                if (hasBadge)
                  Positioned(
                    top: -1,
                    right: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tokens.greenAccent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? activeColor : inactiveColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFabButton(BuildContext context, SamanHomePalette tokens) {
    return InkWell(
      onTap: () => _handleTabTap(context, CommunityNavTab.create),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.greenAccent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: tokens.greenAccent.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          Icons.add_rounded,
          color: tokens.isDark
              ? const Color(0xFF003824)
              : const Color(0xFFFFFFFF),
          size: 26,
        ),
      ),
    );
  }
}

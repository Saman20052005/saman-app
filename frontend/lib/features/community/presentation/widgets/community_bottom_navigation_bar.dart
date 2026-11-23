import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../providers/community_providers.dart';
import '../tokens/saman_ig_tokens.dart';
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
    final ig = SamanIgTokens.of(context);
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
        color: ig.canvas,
        border: Border(
          top: BorderSide(
            color: ig.border,
            width: 0.5,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 4,
        right: 4,
        top: 2,
        bottom: bottomInset > 0 ? bottomInset : 4,
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.feed,
                activeIcon: Icons.home_rounded,
                inactiveIcon: Icons.home_outlined,
                label: 'Bảng tin',
                isActive: currentTab == CommunityNavTab.feed,
                ig: ig,
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.discover,
                activeIcon: Icons.search_rounded,
                inactiveIcon: Icons.search_rounded,
                label: 'Khám phá',
                isActive: currentTab == CommunityNavTab.discover,
                ig: ig,
              ),
            ),
            Expanded(
              child: Center(
                child: _buildCreateButton(context, ig),
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.notifications,
                activeIcon: Icons.favorite_rounded,
                inactiveIcon: Icons.favorite_border_rounded,
                label: 'Thông báo',
                isActive: currentTab == CommunityNavTab.notifications,
                hasBadge: showNotificationsBadge,
                ig: ig,
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.profile,
                activeIcon: Icons.person_rounded,
                inactiveIcon: Icons.person_outline_rounded,
                label: 'Cá nhân',
                isActive: currentTab == CommunityNavTab.profile,
                isAvatar: true,
                ig: ig,
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
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String label,
    required bool isActive,
    required SamanIgTokens ig,
    bool hasBadge = false,
    bool isAvatar = false,
  }) {
    final activeColor = ig.textPrimary;
    final inactiveColor = ig.textSecondary;

    return InkWell(
      onTap: () => _handleTabTap(context, tab),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: SamanIgTokens.minTouchTarget,
          minHeight: SamanIgTokens.minTouchTarget,
        ),
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
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ig.surfaceElevated,
                        border: Border.all(
                          color: isActive ? activeColor : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        isActive ? activeIcon : inactiveIcon,
                        size: 16,
                        color: isActive ? activeColor : inactiveColor,
                      ),
                    )
                  else
                    Icon(
                      isActive ? activeIcon : inactiveIcon,
                      size: 24,
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
                          color: ig.likeHeart,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: ig.caption(
                      fontSize: 10.5,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive ? activeColor : inactiveColor,
                    ).copyWith(letterSpacing: -0.2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context, SamanIgTokens ig) {
    return InkWell(
      onTap: () => _handleTabTap(context, CommunityNavTab.create),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: SamanIgTokens.minTouchTarget,
        height: SamanIgTokens.minTouchTarget,
        child: Center(
          child: Icon(
            Icons.add_box_outlined,
            color: ig.textPrimary,
            size: 26,
          ),
        ),
      ),
    );
  }
}

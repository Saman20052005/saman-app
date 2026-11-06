import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import 'create_content_bottom_sheet.dart';

enum CommunityNavTab {
  feed,
  discover,
  create,
  notifications,
  profile,
}

class CommunityBottomNavigationBar extends StatelessWidget {
  final CommunityNavTab currentTab;
  final ValueChanged<CommunityNavTab>? onTabSelected;

  const CommunityBottomNavigationBar({
    super.key,
    required this.currentTab,
    this.onTabSelected,
  });

  void _handleTabTap(BuildContext context, CommunityNavTab tab) {
    if (tab == currentTab) return;
    if (onTabSelected != null) {
      onTabSelected!(tab);
      return;
    }
    switch (tab) {
      case CommunityNavTab.feed:
        Navigator.pushReplacementNamed(context, '/community/feed');
        break;
      case CommunityNavTab.discover:
        Navigator.pushReplacementNamed(context, '/community/discover');
        break;
      case CommunityNavTab.create:
        CreateContentBottomSheet.show(context);
        break;
      case CommunityNavTab.notifications:
        Navigator.pushNamed(context, '/community/notifications');
        break;
      case CommunityNavTab.profile:
        Navigator.pushNamed(context, '/community/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121314).withOpacity(0.95),
        border: const Border(
          top: BorderSide(
            color: Color(0xFF292A2B),
            width: 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            offset: Offset(0, -2),
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
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.discover,
                icon: Icons.explore_rounded,
                label: 'Khám phá',
                isActive: currentTab == CommunityNavTab.discover,
              ),
            ),
            Expanded(
              child: Center(
                child: _buildFabButton(context),
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                tab: CommunityNavTab.notifications,
                icon: Icons.notifications_rounded,
                label: 'Thông báo',
                isActive: currentTab == CommunityNavTab.notifications,
                hasBadge: true,
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
    bool hasBadge = false,
    bool isAvatar = false,
  }) {
    const activeColor = SamanHomeTokens.greenAccent;
    final inactiveColor = const Color(0xFFBBCAAF).withOpacity(0.7);

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
                          : const Color(0xFF343536),
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
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: SamanHomeTokens.greenAccent,
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

  Widget _buildFabButton(BuildContext context) {
    return InkWell(
      onTap: () => _handleTabTap(context, CommunityNavTab.create),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SamanHomeTokens.greenAccent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: SamanHomeTokens.greenAccent.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(
          Icons.add_rounded,
          color: Color(0xFF003824),
          size: 26,
        ),
      ),
    );
  }
}

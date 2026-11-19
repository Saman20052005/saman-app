import 'package:flutter/material.dart';
import '../../../config/app_translations.dart';
import '../../../../features/membership/presentation/screens/manage_membership_screen.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_plans_comparison_screen.dart';

/// Gemini-style floating account menu component for Saman AI Chat (Frame 1).
class SamanAccountPopupMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onOpenPreferences;
  final VoidCallback? onOpenReminders;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenPlans;
  final bool isDesktop;

  const SamanAccountPopupMenu({
    super.key,
    required this.onClose,
    required this.onOpenPreferences,
    this.onOpenReminders,
    this.onOpenHistory,
    this.onOpenPlans,
    this.isDesktop = false,
  });

  @override
  State<SamanAccountPopupMenu> createState() => _SamanAccountPopupMenuState();
}

class _SamanAccountPopupMenuState extends State<SamanAccountPopupMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 165),
      reverseDuration: const Duration(milliseconds: 115),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnimation = Tween<double>(begin: 6.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleCloseWithAnimation() async {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      widget.onClose();
      return;
    }
    await _animController.reverse();
    if (mounted) {
      widget.onClose();
    }
  }

  void _showUnavailableFeatureNotice(String title) {
    _handleCloseWithAnimation();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title: Tính năng chưa khả dụng trong phiên bản thử nghiệm.',
          style: const TextStyle(
            color: SamanChatTokens.textWhite,
            fontSize: 13,
          ),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleManagePlans() {
    _handleCloseWithAnimation();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ManageMembershipScreen(),
      ),
    );
  }

  void _handleUpgradePlans() {
    _handleCloseWithAnimation();
    if (widget.onOpenPlans != null) {
      widget.onOpenPlans!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SamanPlansComparisonScreen(),
        ),
      );
    }
  }

  void _handleOpenPreferences() {
    _handleCloseWithAnimation();
    widget.onOpenPreferences();
  }

  void _handleThemeSubmenu() {
    _handleCloseWithAnimation();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SamanChatTokens.menuSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: const BorderSide(color: SamanChatTokens.menuBorder),
        ),
        title: Text(
          context.tr('theme_dialog_title'),
          style: const TextStyle(color: SamanChatTokens.textWhite, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined,
                  color: SamanChatTokens.textPrimary),
              title: Text(context.tr('theme_dark_default'),
                  style: const TextStyle(
                      color: SamanChatTokens.textWhite, fontSize: 14)),
              trailing:
                  const Icon(Icons.check_rounded, color: Color(0xFF10B981)),
              onTap: () => Navigator.of(ctx).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.light_mode_outlined,
                  color: SamanChatTokens.textMuted),
              title: Text(context.tr('theme_light_coming_soon'),
                  style: const TextStyle(
                      color: SamanChatTokens.textMuted, fontSize: 14)),
              onTap: () => Navigator.of(ctx).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.settings_system_daydream_outlined,
                  color: SamanChatTokens.textMuted),
              title: Text(context.tr('theme_system_coming_soon'),
                  style: const TextStyle(
                      color: SamanChatTokens.textMuted, fontSize: 14)),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final rowHeight = widget.isDesktop ? 40.0 : 44.0;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxMenuHeight = (screenHeight * 0.72).clamp(320.0, 520.0);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final double opacity = _fadeAnimation.value.clamp(0.0, 1.0);
        final double offsetY = reduceMotion ? 0.0 : _slideAnimation.value;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: child,
          ),
        );
      },
      child: Container(
        width: 280.0,
        constraints: BoxConstraints(maxHeight: maxMenuHeight),
        decoration: BoxDecoration(
          color: SamanChatTokens.menuSurface,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: SamanChatTokens.menuBorder,
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xA6000000),
              blurRadius: 36.0,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15.0),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── NHÓM 1: TÀI KHOẢN ───
                _buildGroupHeader('Tài khoản'),
                _buildRow(
                  icon: Icons.timelapse_outlined,
                  title: 'Giới hạn sử dụng',
                  rowHeight: rowHeight,
                  onTap: () =>
                      _showUnavailableFeatureNotice('Giới hạn sử dụng'),
                ),
                _buildRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Quản lý gói',
                  rowHeight: rowHeight,
                  onTap: _handleManagePlans,
                ),
                _buildRow(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Nâng cấp gói',
                  rowHeight: rowHeight,
                  isSparkle: true,
                  onTap: _handleUpgradePlans,
                ),

                _buildDivider(),

                // ─── NHÓM 2: TÙY CHỌN ───
                _buildGroupHeader('Tùy chọn'),
                _buildRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Cá nhân hóa Coach',
                  rowHeight: rowHeight,
                  onTap: _handleOpenPreferences,
                ),
                _buildRow(
                  icon: Icons.brightness_medium_outlined,
                  title: 'Giao diện',
                  rowHeight: rowHeight,
                  hasChevron: true,
                  onTap: _handleThemeSubmenu,
                ),
                _buildRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Cài đặt nhắc nhở',
                  rowHeight: rowHeight,
                  onTap: () {
                    _handleCloseWithAnimation();
                    if (widget.onOpenReminders != null) {
                      widget.onOpenReminders!();
                    } else {
                      _showUnavailableFeatureNotice('Cài đặt nhắc nhở');
                    }
                  },
                ),

                _buildDivider(),

                // ─── NHÓM 3: DỮ LIỆU VÀ QUYỀN RIÊNG TƯ ───
                _buildGroupHeader('Dữ liệu và quyền riêng tư'),
                _buildRow(
                  icon: Icons.upload_file_outlined,
                  title: 'Dữ liệu dùng để cá nhân hóa',
                  rowHeight: rowHeight,
                  onTap: () => _showUnavailableFeatureNotice(
                      'Dữ liệu dùng để cá nhân hóa'),
                ),
                _buildRow(
                  icon: Icons.history_rounded,
                  title: 'Lịch sử trò chuyện',
                  rowHeight: rowHeight,
                  onTap: () {
                    _handleCloseWithAnimation();
                    if (widget.onOpenHistory != null) {
                      widget.onOpenHistory!();
                    } else {
                      _showUnavailableFeatureNotice('Lịch sử trò chuyện');
                    }
                  },
                ),
                _buildRow(
                  icon: Icons.feedback_outlined,
                  title: 'Gửi phản hồi',
                  rowHeight: rowHeight,
                  onTap: () => _showUnavailableFeatureNotice('Gửi phản hồi'),
                ),
                _buildRow(
                  icon: Icons.help_outline_rounded,
                  title: 'Trợ giúp',
                  rowHeight: rowHeight,
                  onTap: () => _showUnavailableFeatureNotice('Trợ giúp'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 2.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          color: SamanChatTokens.menuGroupHeader,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      child: Divider(
        height: 1.0,
        thickness: 1.0,
        color: SamanChatTokens.menuDivider,
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    required double rowHeight,
    required VoidCallback onTap,
    bool hasChevron = false,
    bool isSparkle = false,
  }) {
    final textColor =
        isSparkle ? SamanChatTokens.textWhite : SamanChatTokens.menuItemText;
    final iconColor =
        isSparkle ? SamanChatTokens.sparkleWhite : SamanChatTokens.menuItemIcon;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        hoverColor: SamanChatTokens.menuItemHover,
        splashColor: SamanChatTokens.menuItemHover,
        onTap: onTap,
        child: SizedBox(
          height: rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18.0,
                  color: iconColor,
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: isSparkle ? FontWeight.w600 : FontWeight.w400,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasChevron)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16.0,
                    color: SamanChatTokens.menuChevron,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

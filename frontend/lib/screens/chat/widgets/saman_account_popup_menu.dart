import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_translations.dart';
import '../../../config/routes.dart';
import '../../../config/theme_provider.dart';
import '../../../controllers/chat_controller.dart';
import '../../../core/widgets/coach_marks/coach_tour_service.dart';
import '../../../../features/membership/presentation/screens/manage_membership_screen.dart';
import '../../settings/app_settings_screen.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_plans_comparison_screen.dart';

/// Gemini-style floating account menu component for Saman AI Chat (Frame 1).
class SamanAccountPopupMenu extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onOpenPreferences;
  final VoidCallback? onOpenReminders;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenPlans;
  final VoidCallback? onResetCoachTour;
  final bool isDesktop;

  const SamanAccountPopupMenu({
    super.key,
    required this.onClose,
    required this.onOpenPreferences,
    this.onOpenReminders,
    this.onOpenHistory,
    this.onOpenPlans,
    this.onResetCoachTour,
    this.isDesktop = false,
  });

  @override
  ConsumerState<SamanAccountPopupMenu> createState() =>
      _SamanAccountPopupMenuState();
}

class _SamanAccountPopupMenuState extends ConsumerState<SamanAccountPopupMenu>
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

  void _handleManagePlans() {
    final navigator = Navigator.of(context);
    _handleCloseWithAnimation();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const ManageMembershipScreen(),
        settings: const RouteSettings(name: '/membership/manage'),
      ),
    );
  }

  void _handleOpenReminders() {
    final navigator = Navigator.of(context);
    _handleCloseWithAnimation();
    if (widget.onOpenReminders != null) {
      widget.onOpenReminders!();
    } else {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const AppSettingsScreen(),
          settings: const RouteSettings(name: AppRoutes.appSettings),
        ),
      );
    }
  }

  void _handleOpenHistory() {
    final scaffoldState = Scaffold.maybeOf(context);
    final conversations = ref.read(chatControllerProvider).recentConversations;
    final activeId = ref.read(chatControllerProvider).activeConversationId;
    final chatNotifier = ref.read(chatControllerProvider.notifier);
    final hostContext = Navigator.of(context).context;
    _handleCloseWithAnimation();
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!();
    } else if (scaffoldState != null &&
        scaffoldState.hasDrawer &&
        !scaffoldState.isDrawerOpen) {
      scaffoldState.openDrawer();
    } else {
      _showConversationHistorySheet(
        hostContext,
        conversations: conversations,
        activeConversationId: activeId,
        onSelectConversation: (id) => chatNotifier.loadConversation(id),
      );
    }
  }

  void _showConversationHistorySheet(
    BuildContext hostContext, {
    required List<ChatConversationSummary> conversations,
    required String? activeConversationId,
    required ValueChanged<String> onSelectConversation,
  }) {
    final t = SamanChatTokens.of(hostContext);
    showModalBottomSheet<void>(
      context: hostContext,
      backgroundColor: t.menuSurface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
        side: BorderSide(color: t.menuBorder),
      ),
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.65;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Lịch sử trò chuyện',
                          style: TextStyle(
                            color: t.textWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: t.textSecondary,
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  if (conversations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          sheetContext.tr('no_recent_conversations'),
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: conversations.length,
                        itemBuilder: (_, index) {
                          final conv = conversations[index];
                          final isSelected = conv.id == activeConversationId;
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            selected: isSelected,
                            selectedTileColor: t.surface,
                            leading: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                              color: isSelected ? t.greenAccent : t.textMuted,
                            ),
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected ? t.textWhite : t.textSecondary,
                                fontSize: 13.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              onSelectConversation(conv.id);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleHelpDialog() {
    final coachTourService = ref.read(coachTourServiceProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    _handleCloseWithAnimation();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = SamanChatTokens.of(ctx);
        Widget buildGuideItem({
          required IconData icon,
          required String title,
          required String description,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: t.greenAccent),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: t.textWhite,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        description,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          backgroundColor: t.menuSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(color: t.menuBorder),
          ),
          title: Text(
            'Hướng dẫn nhanh Saman V1.0',
            style: TextStyle(
              color: t.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildGuideItem(
                  icon: Icons.smart_toy_outlined,
                  title: 'AI Coach & Dẫn chứng Video',
                  description:
                      'Hỏi đáp lịch tập, kỹ thuật và dinh dưỡng; chạm chip dẫn chứng để mở video hướng dẫn.',
                ),
                buildGuideItem(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Workout Form Check AI',
                  description:
                      'Quay hoặc tải video bài tập để AI phân tích tư thế, đếm rep và cảnh báo lỗi kỹ thuật.',
                ),
                buildGuideItem(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Quét & Theo dõi Dinh dưỡng',
                  description:
                      'Chụp ảnh bữa ăn hoặc quét thực phẩm để ước lượng calo và macro mỗi ngày.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (widget.onResetCoachTour != null) {
                  widget.onResetCoachTour!.call();
                  return;
                }
                await coachTourService.resetAll();
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Đã đặt lại hướng dẫn tương tác. Mở lại Home, Dinh dưỡng hoặc Tập luyện để xem!',
                    ),
                    duration: Duration(seconds: 3),
                  ),
                );
              },
              child: Text(
                'Xem lại hướng dẫn tương tác',
                style: TextStyle(color: t.greenAccent, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Đóng',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
              ),
            ),
          ],
        );
      },
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
      builder: (ctx) {
        final t = SamanChatTokens.of(ctx);
        return Consumer(
          builder: (dialogContext, dialogRef, _) {
            final currentMode = dialogRef.watch(themeProvider);
            Widget buildThemeOption({
              required ThemeMode mode,
              required IconData icon,
              required String titleKey,
            }) {
              final isSelected = currentMode == mode;
              return ListTile(
                leading: Icon(
                  icon,
                  color: isSelected ? t.textPrimary : t.textMuted,
                ),
                title: Text(
                  dialogContext.tr(titleKey),
                  style: TextStyle(
                    color: isSelected ? t.textWhite : t.textMuted,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_rounded, color: t.greenAccent)
                    : null,
                onTap: () {
                  dialogRef.read(themeProvider.notifier).setThemeMode(mode);
                  Navigator.of(ctx).pop();
                },
              );
            }

            return AlertDialog(
              backgroundColor: t.menuSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: BorderSide(color: t.menuBorder),
              ),
              title: Text(
                dialogContext.tr('theme_dialog_title'),
                style: TextStyle(color: t.textWhite, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildThemeOption(
                    mode: ThemeMode.dark,
                    icon: Icons.dark_mode_outlined,
                    titleKey: 'theme_dark',
                  ),
                  buildThemeOption(
                    mode: ThemeMode.light,
                    icon: Icons.light_mode_outlined,
                    titleKey: 'theme_light',
                  ),
                  buildThemeOption(
                    mode: ThemeMode.system,
                    icon: Icons.settings_system_daydream_outlined,
                    titleKey: 'theme_system',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
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
          color: t.menuSurface,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: t.menuBorder,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: t.isDark
                  ? const Color(0xA6000000)
                  : const Color(0x1F0F172A),
              blurRadius: 36.0,
              offset: const Offset(0, 16),
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
                _buildGroupHeader(t, 'Tài khoản'),
                _buildRow(
                  t: t,
                  icon: Icons.timelapse_outlined,
                  title: 'Giới hạn sử dụng',
                  rowHeight: rowHeight,
                  onTap: _handleManagePlans,
                ),
                _buildRow(
                  t: t,
                  icon: Icons.info_outline_rounded,
                  title: 'Quản lý gói',
                  rowHeight: rowHeight,
                  onTap: _handleManagePlans,
                ),
                _buildRow(
                  t: t,
                  icon: Icons.auto_awesome_rounded,
                  title: 'Nâng cấp gói',
                  rowHeight: rowHeight,
                  isSparkle: true,
                  onTap: _handleUpgradePlans,
                ),

                _buildDivider(t),

                // ─── NHÓM 2: TÙY CHỌN ───
                _buildGroupHeader(t, 'Tùy chọn'),
                _buildRow(
                  t: t,
                  icon: Icons.person_outline_rounded,
                  title: 'Cá nhân hóa Coach',
                  rowHeight: rowHeight,
                  onTap: _handleOpenPreferences,
                ),
                _buildRow(
                  t: t,
                  icon: Icons.brightness_medium_outlined,
                  title: 'Giao diện',
                  rowHeight: rowHeight,
                  hasChevron: true,
                  onTap: _handleThemeSubmenu,
                ),
                _buildRow(
                  t: t,
                  icon: Icons.notifications_none_rounded,
                  title: 'Cài đặt nhắc nhở',
                  rowHeight: rowHeight,
                  onTap: _handleOpenReminders,
                ),

                _buildDivider(t),

                // ─── NHÓM 3: DỮ LIỆU VÀ QUYỀN RIÊNG TƯ ───
                _buildGroupHeader(t, 'Dữ liệu và quyền riêng tư'),
                _buildRow(
                  t: t,
                  icon: Icons.history_rounded,
                  title: 'Lịch sử trò chuyện',
                  rowHeight: rowHeight,
                  onTap: _handleOpenHistory,
                ),
                _buildRow(
                  t: t,
                  icon: Icons.help_outline_rounded,
                  title: 'Trợ giúp',
                  rowHeight: rowHeight,
                  onTap: _handleHelpDialog,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(SamanChatPalette t, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 2.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          color: t.menuGroupHeader,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildDivider(SamanChatPalette t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      child: Divider(
        height: 1.0,
        thickness: 1.0,
        color: t.menuDivider,
      ),
    );
  }

  Widget _buildRow({
    required SamanChatPalette t,
    required IconData icon,
    required String title,
    required double rowHeight,
    required VoidCallback onTap,
    bool hasChevron = false,
    bool isSparkle = false,
  }) {
    final textColor = isSparkle ? t.textWhite : t.menuItemText;
    final iconColor = isSparkle ? t.sparkleWhite : t.menuItemIcon;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        hoverColor: t.menuItemHover,
        splashColor: t.menuItemHover,
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
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16.0,
                    color: t.menuChevron,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

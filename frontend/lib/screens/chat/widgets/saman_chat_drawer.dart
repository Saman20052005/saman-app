import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../controllers/chat_controller.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/saman_avatar.dart';
import '../../profile_screen.dart';
import '../tokens/saman_chat_tokens.dart';

/// Approved Unified Sidebar & Drawer component for Saman Chat.
///
/// Supports three display modes:
/// 1. Mobile Drawer: Slide-out overlay modal with scrim (width: 280-340px)
/// 2. Desktop Expanded: Pinned left sidebar (width: 260px)
/// 3. Desktop Rail: Collapsed icon rail (width: 64px)
class SamanChatDrawer extends ConsumerWidget {
  final VoidCallback onNewChat;
  final ValueChanged<String> onPromptSelected;
  final VoidCallback onOpenPreferences;
  final VoidCallback? onOpenAnalytics;
  final VoidCallback? onAttachFoodPhoto;
  final VoidCallback? onOpenProfile;
  final bool hasActiveReminders;
  final List<ChatConversationSummary> recentConversations;
  final String? activeConversationId;
  final ValueChanged<String>? onSelectConversation;
  final bool isDesktop;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  const SamanChatDrawer({
    super.key,
    required this.onNewChat,
    required this.onPromptSelected,
    required this.onOpenPreferences,
    this.onOpenAnalytics,
    this.onAttachFoodPhoto,
    this.onOpenProfile,
    this.hasActiveReminders = false,
    this.recentConversations = const [],
    this.activeConversationId,
    this.onSelectConversation,
    this.isDesktop = false,
    this.isExpanded = true,
    this.onToggleExpand,
  });

  static String maskEmail(String email) {
    if (email.isEmpty) return '';
    final atIndex = email.indexOf('@');
    if (atIndex <= 1) return '***@***';
    final namePart = email.substring(0, atIndex);
    final domainPart = email.substring(atIndex + 1);
    final maskedName = namePart.length > 2
        ? '${namePart.substring(0, 2)}***'
        : '${namePart[0]}***';
    return '$maskedName@$domainPart';
  }

  void _closeDrawerIfNeeded(BuildContext context) {
    if (!isDesktop) {
      Navigator.of(context).pop();
    }
  }

  void _handleRecentPlaceholder(BuildContext context) {
    _closeDrawerIfNeeded(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Previous conversation history will be available in a future update.',
          style: TextStyle(color: SamanChatTokens.textWhite, fontSize: 13),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleRemindersPlaceholder(BuildContext context) {
    _closeDrawerIfNeeded(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reminders and proactive notifications will arrive in the next phase.',
          style: TextStyle(color: SamanChatTokens.textWhite, fontSize: 13),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleProfileNavigation(BuildContext context) {
    _closeDrawerIfNeeded(context);
    if (onOpenProfile != null) {
      onOpenProfile!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (!isDesktop) {
      final drawerWidth = (screenWidth * 0.82).clamp(280.0, 340.0);
      return Drawer(
        width: drawerWidth,
        backgroundColor: SamanChatTokens.drawerBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: SamanChatTokens.drawerBg,
            border: Border(
              right: BorderSide(
                color: SamanChatTokens.borderSubtle,
                width: 1.0,
              ),
            ),
          ),
          child: SafeArea(
            child: _buildExpandedContent(context, ref),
          ),
        ),
      );
    }

    // Desktop mode: AnimatedContainer switching between Expanded (260px) and Rail (64px)
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetWidth = isExpanded ? 260.0 : 64.0;
    return AnimatedContainer(
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      width: targetWidth,
      decoration: const BoxDecoration(
        color: SamanChatTokens.drawerBg,
        border: Border(
          right: BorderSide(
            color: SamanChatTokens.borderSubtle,
            width: 1.0,
          ),
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: targetWidth,
          maxWidth: targetWidth,
          child: SizedBox(
            width: targetWidth,
            child: SafeArea(
              child: isExpanded
                  ? _buildExpandedContent(context, ref)
                  : _buildRailContent(context, ref),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileProvider);
    final rawName = profileState.snapshot?.fullName?.trim();
    final athleteName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Saman Athlete';
    final email = profileState.snapshot?.email ?? 'saman@member.app';
    final avatarUrl = profileState.avatar;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Saman Coach',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SamanChatTokens.textWhite,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Saman · Your personal coach',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: SamanChatTokens.textMuted,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDesktop)
                Semantics(
                  button: true,
                  label: 'Thu gọn thanh bên',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.view_sidebar_outlined,
                      size: 20,
                      color: SamanChatTokens.textSecondary,
                    ),
                    tooltip: 'Thu gọn thanh bên',
                    onPressed: onToggleExpand,
                  ),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: SamanChatTokens.textSecondary,
                  ),
                  tooltip: 'Đóng menu',
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),

          const SizedBox(height: 12.0),

          // 2. New conversation pill button
          Semantics(
            button: true,
            label: 'New conversation',
            child: InkWell(
              borderRadius: BorderRadius.circular(24.0),
              onTap: () {
                _closeDrawerIfNeeded(context);
                onNewChat();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: SamanChatTokens.surface,
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(
                    color: SamanChatTokens.borderSubtle,
                    width: 1.0,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: SamanChatTokens.textWhite,
                    ),
                    SizedBox(width: 8.0),
                    Flexible(
                      child: Text(
                        'New conversation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SamanChatTokens.textWhite,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12.0),

          // 3. Scrollable middle area (Recent & Coach tools)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
              children: [
                // --- Coach tools Section ---
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                  child: Text(
                    'Coach tools',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SamanChatTokens.textMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 4.0),
                if (onOpenAnalytics != null)
                  _CoachToolRow(
                    icon: Icons.insights_rounded,
                    title: 'Phân tích lịch sử',
                    subtitle: '7, 14, 30 ngày',
                    onTap: () {
                      _closeDrawerIfNeeded(context);
                      onOpenAnalytics!();
                    },
                  ),
                if (onAttachFoodPhoto != null)
                  _CoachToolRow(
                    icon: Icons.add_a_photo_rounded,
                    title: 'Phân tích ảnh món ăn',
                    subtitle: 'Standard & Advanced AI',
                    onTap: () {
                      _closeDrawerIfNeeded(context);
                      onAttachFoodPhoto!();
                    },
                  ),

                const SizedBox(height: 16.0),

                // --- Recent Section ---
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                  child: Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SamanChatTokens.textMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 4.0),
                if (recentConversations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    child: Text(
                      'No recent conversations',
                      style: TextStyle(
                        fontSize: 13,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                  )
                else
                  ...recentConversations.map(
                    (c) => _RecentConversationRow(
                      title: c.title,
                      timestamp: _formatTimestamp(c.updatedAt),
                      isSelected: c.id == activeConversationId,
                      onTap: () {
                        _closeDrawerIfNeeded(context);
                        onSelectConversation?.call(c.id);
                      },
                    ),
                  ),
                const SizedBox(height: 4.0),
                InkWell(
                  borderRadius: BorderRadius.circular(8.0),
                  onTap: () => _handleRecentPlaceholder(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'View all conversations',
                            style: TextStyle(
                              fontSize: 12,
                              color: SamanChatTokens.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 4.0),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: SamanChatTokens.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14.0),

                // Utilities
                const Divider(
                  color: SamanChatTokens.borderSubtle,
                  height: 1.0,
                ),
                const SizedBox(height: 8.0),

                _DrawerUtilityRow(
                  icon: Icons.access_time_rounded,
                  title: 'Reminders',
                  hasActiveDot: hasActiveReminders,
                  onTap: () => _handleRemindersPlaceholder(context),
                ),
                const SizedBox(height: 2.0),
                _DrawerUtilityRow(
                  icon: Icons.tune_rounded,
                  title: 'Saman preferences',
                  subtitle: 'Coaching tone, response style, reminders',
                  onTap: () {
                    _closeDrawerIfNeeded(context);
                    onOpenPreferences();
                  },
                ),
              ],
            ),
          ),

          // 4. Sticky Footer: Pinned Account Row
          const Divider(
            color: SamanChatTokens.borderSubtle,
            height: 1.0,
          ),
          const SizedBox(height: 8.0),
          Semantics(
            button: true,
            label: 'Tài khoản người dùng: $athleteName',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () => _handleProfileNavigation(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
                  child: Row(
                    children: [
                      SamanAvatar(
                        name: athleteName,
                        avatarUrl: avatarUrl,
                        size: 34.0,
                      ),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              athleteName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: SamanChatTokens.textWhite,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1.0),
                            Text(
                              maskEmail(email),
                              style: const TextStyle(
                                fontSize: 11,
                                color: SamanChatTokens.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: SamanChatTokens.textSecondary,
                        ),
                        tooltip: 'Tùy chọn Saman',
                        onPressed: () {
                          _closeDrawerIfNeeded(context);
                          onOpenPreferences();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRailContent(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileProvider);
    final rawName = profileState.snapshot?.fullName?.trim();
    final athleteName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Saman Athlete';
    final avatarUrl = profileState.avatar;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        children: [
          // 1. Expand sidebar button
          Semantics(
            button: true,
            label: 'Mở rộng thanh bên',
            child: IconButton(
              icon: const Icon(
                Icons.view_sidebar_outlined,
                color: SamanChatTokens.textSecondary,
                size: 20,
              ),
              tooltip: 'Mở rộng thanh bên',
              onPressed: onToggleExpand,
            ),
          ),

          const SizedBox(height: 8.0),

          // 2. New conversation button (rail icon)
          Semantics(
            button: true,
            label: 'New conversation',
            child: IconButton(
              icon: const Icon(
                Icons.add_rounded,
                color: SamanChatTokens.textWhite,
                size: 22,
              ),
              tooltip: 'New conversation',
              onPressed: onNewChat,
            ),
          ),

          const SizedBox(height: 12.0),
          const Divider(
            color: SamanChatTokens.borderSubtle,
            height: 1.0,
            indent: 14,
            endIndent: 14,
          ),
          const SizedBox(height: 8.0),

          // 3. Scrollable Rail Tools
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (onOpenAnalytics != null)
                    IconButton(
                      icon: const Icon(
                        Icons.insights_rounded,
                        color: SamanChatTokens.textSecondary,
                        size: 20,
                      ),
                      tooltip: 'Phân tích lịch sử',
                      onPressed: onOpenAnalytics,
                    ),
                  if (onAttachFoodPhoto != null)
                    IconButton(
                      icon: const Icon(
                        Icons.add_a_photo_rounded,
                        color: SamanChatTokens.textSecondary,
                        size: 20,
                      ),
                      tooltip: 'Phân tích ảnh món ăn',
                      onPressed: onAttachFoodPhoto,
                    ),
                  const SizedBox(height: 8.0),
                  // History expand affordance in rail
                  IconButton(
                    icon: const Icon(
                      Icons.history_rounded,
                      color: SamanChatTokens.textMuted,
                      size: 20,
                    ),
                    tooltip: 'Lịch sử (${recentConversations.length}) - Bấm để mở rộng',
                    onPressed: onToggleExpand,
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Pinned Icons in Rail
          const Divider(
            color: SamanChatTokens.borderSubtle,
            height: 1.0,
            indent: 14,
            endIndent: 14,
          ),
          const SizedBox(height: 8.0),
          IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              color: SamanChatTokens.textSecondary,
              size: 20,
            ),
            tooltip: 'Saman preferences',
            onPressed: onOpenPreferences,
          ),
          const SizedBox(height: 8.0),
          Semantics(
            button: true,
            label: 'Hồ sơ cá nhân: $athleteName',
            child: InkWell(
              borderRadius: BorderRadius.circular(16.0),
              onTap: () => _handleProfileNavigation(context),
              child: SamanAvatar(
                name: athleteName,
                avatarUrl: avatarUrl,
                size: 32.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentConversationRow extends StatelessWidget {
  final String title;
  final String timestamp;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecentConversationRow({
    required this.title,
    required this.timestamp,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      decoration: BoxDecoration(
        color: isSelected ? SamanChatTokens.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10.0),
        border: isSelected
            ? Border.all(color: SamanChatTokens.borderSubtle, width: 1.0)
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected
                        ? SamanChatTokens.textWhite
                        : SamanChatTokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timestamp.isNotEmpty) ...[
                const SizedBox(width: 8.0),
                Text(
                  timestamp,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SamanChatTokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _CoachToolRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: SamanChatTokens.textSecondary,
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: SamanChatTokens.textWhite,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1.0),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: SamanChatTokens.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: SamanChatTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerUtilityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool hasActiveDot;

  const _DrawerUtilityRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.hasActiveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 7.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: SamanChatTokens.textSecondary,
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: SamanChatTokens.textWhite,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1.0),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: SamanChatTokens.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (hasActiveDot)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8.0),
                  decoration: const BoxDecoration(
                    color: SamanChatTokens.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: SamanChatTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatTimestamp(String? val) {
  if (val == null || val.isEmpty) return '';
  try {
    final dt = DateTime.parse(val).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 2 && dt.day == now.day - 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  } catch (_) {
    return val;
  }
}

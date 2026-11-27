import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_translations.dart';
import '../../../config/routes.dart';
import '../../../controllers/chat_controller.dart';
import '../../../features/membership/presentation/providers/membership_providers.dart';
import '../../../providers/profile_provider.dart';
import '../../../core/widgets/saman_tier_avatar.dart';
import '../../../widgets/saman_feedback_snackbar.dart';
import '../../profile_screen.dart';
import '../../settings/app_settings_screen.dart';
import '../tokens/saman_chat_tokens.dart';
import '../../../providers/coach_persona_provider.dart';
import 'saman_account_popup_menu.dart';
import 'saman_persona_menu.dart';
import 'saman_plans_comparison_screen.dart';

/// Approved Unified Sidebar & Drawer component for Saman Chat.
///
/// Supports three display modes:
/// 1. Mobile Drawer: Slide-out overlay modal with scrim (width: 280-340px)
/// 2. Desktop Expanded: Pinned left sidebar (width: 260px)
/// 3. Desktop Rail: Collapsed icon rail (width: 64px)
class SamanChatDrawer extends ConsumerStatefulWidget {
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
  final VoidCallback? onResetCoachTour;

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
    this.onResetCoachTour,
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

  @override
  ConsumerState<SamanChatDrawer> createState() => _SamanChatDrawerState();
}

class _SamanChatDrawerState extends ConsumerState<SamanChatDrawer> {
  bool _isAccountMenuOpen = false;
  final FocusNode _triggerFocusNode = FocusNode();
  final GlobalKey _personaRowKey = GlobalKey();
  final GlobalKey _railPersonaKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mState = ref.read(accountMembershipProvider);
      if (!mState.isKnown && !mState.isLoading) {
        final userId = ref.read(profileProvider).confirmedUserId;
        ref
            .read(accountMembershipProvider.notifier)
            .loadMembership(accountId: userId);
      }
    });
  }

  Rect _calculateAnchorRect(GlobalKey key) {
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero);
      return offset & renderBox.size;
    }
    return Rect.zero;
  }

  Future<void> _handleSelectPersona(
      BuildContext context, CoachPersona persona) async {
    final personaNotifier = ref.read(coachPersonaProvider.notifier);
    final success = await personaNotifier.selectPersona(
      persona,
      onSendPrompt: (prompt) async {
        ref.read(chatControllerProvider.notifier).sendMessage(prompt);
      },
    );

    if (!mounted) return;
    if (success) {
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('switched_coach_persona_format').replaceAll('{name}', persona.displayName),
        type: FeedbackType.success,
        duration: const Duration(seconds: 2),
      );
    } else {
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('coach_persona_update_error'),
        type: FeedbackType.error,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void _openPersonaSelector(BuildContext context, {GlobalKey? fromKey}) {
    _closeAccountMenu();
    onOpenPreferences();
    final key = fromKey ?? _personaRowKey;
    final anchor = _calculateAnchorRect(key);
    final personaState = ref.read(coachPersonaProvider);

    showCoachPersonaMenu(
      context: context,
      anchorRect: anchor,
      currentPersona: personaState.persona,
      onSelectPersona: (p) => _handleSelectPersona(context, p),
      isDesktop: isDesktop,
      isSaving: personaState.isSaving,
    );
  }

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

  bool get isDesktop => widget.isDesktop;
  bool get isExpanded => widget.isExpanded;
  VoidCallback get onNewChat => widget.onNewChat;
  ValueChanged<String> get onPromptSelected => widget.onPromptSelected;
  VoidCallback get onOpenPreferences => widget.onOpenPreferences;
  VoidCallback? get onOpenAnalytics => widget.onOpenAnalytics;
  VoidCallback? get onAttachFoodPhoto => widget.onAttachFoodPhoto;
  VoidCallback? get onOpenProfile => widget.onOpenProfile;
  bool get hasActiveReminders => widget.hasActiveReminders;
  List<ChatConversationSummary> get recentConversations =>
      widget.recentConversations;
  String? get activeConversationId => widget.activeConversationId;
  ValueChanged<String>? get onSelectConversation => widget.onSelectConversation;
  VoidCallback? get onToggleExpand => widget.onToggleExpand;

  void _toggleAccountMenu() {
    setState(() {
      _isAccountMenuOpen = !_isAccountMenuOpen;
    });
  }

  void _closeAccountMenu() {
    if (_isAccountMenuOpen) {
      setState(() {
        _isAccountMenuOpen = false;
      });
      _triggerFocusNode.requestFocus();
    }
  }

  void _closeDrawerIfNeeded(BuildContext context) {
    if (!isDesktop) {
      Navigator.of(context).pop();
    }
  }

  void _showAllConversationsSheet(BuildContext context) {
    final t = SamanChatTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
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
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.borderSubtle,
                        borderRadius: BorderRadius.circular(2.0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sheetContext.tr('view_all_conversations'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: t.textWhite,
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
                  if (recentConversations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          sheetContext.tr('no_recent_conversations'),
                          style: TextStyle(
                            fontSize: 14,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: recentConversations.length,
                        itemBuilder: (itemContext, index) {
                          final conv = recentConversations[index];
                          return _RecentConversationRow(
                            title: conv.title,
                            timestamp:
                                _formatTimestamp(sheetContext, conv.updatedAt),
                            isSelected: conv.id == activeConversationId,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              if (context.mounted) {
                                _closeDrawerIfNeeded(context);
                              }
                              onSelectConversation?.call(conv.id);
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

  void _openRemindersSettings(BuildContext context) {
    final navigator = Navigator.of(context);
    _closeDrawerIfNeeded(context);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const AppSettingsScreen(),
        settings: const RouteSettings(name: AppRoutes.appSettings),
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
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    final Widget rootContent;
    if (!isDesktop) {
      final drawerWidth = (screenWidth * 0.82).clamp(280.0, 340.0);
      rootContent = Drawer(
        width: drawerWidth,
        backgroundColor: t.drawerBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: t.drawerBg,
            border: Border(
              right: BorderSide(
                color: t.borderSubtle,
                width: 1.0,
              ),
            ),
          ),
          child: SafeArea(
            child: _buildExpandedContent(context, ref),
          ),
        ),
      );
    } else {
      // Desktop mode: AnimatedContainer switching between Expanded (260px) and Rail (64px)
      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final targetWidth = isExpanded ? 260.0 : 64.0;
      rootContent = AnimatedContainer(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeInOutCubic,
        width: targetWidth,
        decoration: BoxDecoration(
          color: t.drawerBg,
          border: Border(
            right: BorderSide(
              color: t.borderSubtle,
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

    return PopScope(
      canPop: !_isAccountMenuOpen,
      onPopInvoked: (didPop) {
        if (!didPop && _isAccountMenuOpen) {
          _closeAccountMenu();
        }
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (_isAccountMenuOpen &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _closeAccountMenu();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: rootContent,
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, WidgetRef ref) {
    final t = SamanChatTokens.of(context);
    final profileState = ref.watch(profileProvider);
    final personaState = ref.watch(coachPersonaProvider);
    final currentPersona = personaState.persona;
    final personaName = currentPersona.displayName;
    final rawName = profileState.snapshot?.fullName?.trim();
    final athleteName =
        (rawName != null && rawName.isNotEmpty) ? rawName : 'Saman Athlete';
    final email = profileState.snapshot?.email ?? 'saman@member.app';
    final avatarUrl = profileState.avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.tr('saman_coach_title'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.textWhite,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('saman_coach_subtitle'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: t.textMuted,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDesktop)
                    Semantics(
                      button: true,
                      label: context.tr('collapse_sidebar'),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.view_sidebar_outlined,
                          size: 20,
                          color: t.textSecondary,
                        ),
                        tooltip: context.tr('collapse_sidebar'),
                        onPressed: onToggleExpand,
                      ),
                    )
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: t.textSecondary,
                      ),
                      tooltip: context.tr('close_menu'),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),

              const SizedBox(height: 12.0),

              // 2. New conversation pill button
              Semantics(
                button: true,
                label: context.tr('new_conversation'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24.0),
                  onTap: () {
                    _closeDrawerIfNeeded(context);
                    onNewChat();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(
                        color: t.borderSubtle,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: t.textWhite,
                        ),
                        const SizedBox(width: 8.0),
                        Flexible(
                          child: Text(
                            context.tr('new_conversation'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.textWhite,
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
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      child: Text(
                        context.tr('coach_tools_header'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    if (onOpenAnalytics != null)
                      _CoachToolRow(
                        icon: Icons.insights_rounded,
                        title: context.tr('tool_history_analytics'),
                        subtitle: context.tr('tool_history_analytics_subtitle'),
                        onTap: () {
                          _closeDrawerIfNeeded(context);
                          onOpenAnalytics!();
                        },
                      ),
                    if (onAttachFoodPhoto != null)
                      _CoachToolRow(
                        icon: Icons.add_a_photo_rounded,
                        title: context.tr('tool_food_photo_analysis'),
                        subtitle: context.tr('tool_food_photo_analysis_subtitle'),
                        onTap: () {
                          _closeDrawerIfNeeded(context);
                          onAttachFoodPhoto!();
                        },
                      ),

                    const SizedBox(height: 16.0),

                    // --- Recent Section ---
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      child: Text(
                        context.tr('recent_header'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    if (recentConversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 8.0),
                        child: Text(
                          context.tr('no_recent_conversations'),
                          style: TextStyle(
                            fontSize: 13,
                            color: t.textMuted,
                          ),
                        ),
                      )
                    else
                      ...recentConversations.map(
                        (c) => _RecentConversationRow(
                          title: c.title,
                          timestamp: _formatTimestamp(context, c.updatedAt),
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
                      onTap: () => _showAllConversationsSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 6.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                context.tr('view_all_conversations'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: t.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4.0),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: t.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14.0),

                    // Utilities
                    Divider(
                      color: t.borderSubtle,
                      height: 1.0,
                    ),
                    const SizedBox(height: 8.0),

                    _DrawerUtilityRow(
                      icon: Icons.access_time_rounded,
                      title: context.tr('reminders_label'),
                      hasActiveDot: hasActiveReminders,
                      onTap: () => _openRemindersSettings(context),
                    ),
                    const SizedBox(height: 2.0),
                    _DrawerUtilityRow(
                      key: _personaRowKey,
                      icon: Icons.tune_rounded,
                      title: context.tr('coach_persona_label'),
                      subtitle: personaName,
                      onTap: () => _openPersonaSelector(context, fromKey: _personaRowKey),
                    ),
                  ],
                ),
              ),

              // 4. Sticky Footer: Pinned Account Row
              Divider(
                color: t.borderSubtle,
                height: 1.0,
              ),
              const SizedBox(height: 8.0),
              Semantics(
                button: true,
                label: context.tr('user_account_semantic').replaceAll('{name}', athleteName),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10.0),
                    focusNode: _triggerFocusNode,
                    onTap: _toggleAccountMenu,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6.0, vertical: 6.0),
                      child: Row(
                        children: [
                          SamanTierAvatar(
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
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: t.textWhite,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1.0),
                                Text(
                                  SamanChatDrawer.maskEmail(email),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: t.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.settings_outlined,
                              size: 18,
                              color: t.textSecondary,
                            ),
                            tooltip: context.tr('saman_options_tooltip'),
                            onPressed: _toggleAccountMenu,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isAccountMenuOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeAccountMenu,
            ),
          ),
          Positioned(
            bottom: 58.0,
            right: 6.0,
            left: isDesktop ? null : 6.0,
            child: SamanAccountPopupMenu(
              isDesktop: isDesktop,
              onClose: _closeAccountMenu,
              onOpenPreferences: () {
                _closeAccountMenu();
                _openPersonaSelector(
                  context,
                  fromKey: isDesktop ? _personaRowKey : null,
                );
              },
              onOpenReminders: () {
                _closeAccountMenu();
                _openRemindersSettings(context);
              },
              onOpenHistory: () {
                _closeAccountMenu();
                _showAllConversationsSheet(context);
              },
              onResetCoachTour: widget.onResetCoachTour,
              onOpenPlans: () {
                _closeAccountMenu();
                _closeDrawerIfNeeded(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SamanPlansComparisonScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRailContent(BuildContext context, WidgetRef ref) {
    final t = SamanChatTokens.of(context);
    final profileState = ref.watch(profileProvider);
    final personaState = ref.watch(coachPersonaProvider);
    final personaName = personaState.persona.displayName;
    final rawName = profileState.snapshot?.fullName?.trim();
    final athleteName =
        (rawName != null && rawName.isNotEmpty) ? rawName : 'Saman Athlete';
    final avatarUrl = profileState.avatar;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        children: [
          // 1. Expand sidebar button
          Semantics(
            button: true,
            label: context.tr('expand_sidebar'),
            child: IconButton(
              icon: Icon(
                Icons.view_sidebar_outlined,
                color: t.textSecondary,
                size: 20,
              ),
              tooltip: context.tr('expand_sidebar'),
              onPressed: onToggleExpand,
            ),
          ),

          const SizedBox(height: 8.0),

          // 2. New conversation button (rail icon)
          Semantics(
            button: true,
            label: context.tr('new_conversation'),
            child: IconButton(
              icon: Icon(
                Icons.add_rounded,
                color: t.textWhite,
                size: 22,
              ),
              tooltip: context.tr('new_conversation'),
              onPressed: onNewChat,
            ),
          ),

          const SizedBox(height: 12.0),
          Divider(
            color: t.borderSubtle,
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
                      icon: Icon(
                        Icons.insights_rounded,
                        color: t.textSecondary,
                        size: 20,
                      ),
                      tooltip: context.tr('tool_history_analytics'),
                      onPressed: onOpenAnalytics,
                    ),
                  if (onAttachFoodPhoto != null)
                    IconButton(
                      icon: Icon(
                        Icons.add_a_photo_rounded,
                        color: t.textSecondary,
                        size: 20,
                      ),
                      tooltip: context.tr('tool_food_photo_analysis'),
                      onPressed: onAttachFoodPhoto,
                    ),
                  const SizedBox(height: 8.0),
                  // History expand affordance in rail
                  IconButton(
                    icon: Icon(
                      Icons.history_rounded,
                      color: t.textMuted,
                      size: 20,
                    ),
                    tooltip: context.tr('history_rail_tooltip').replaceAll('{count}', '${recentConversations.length}'),
                    onPressed: onToggleExpand,
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Pinned Icons in Rail
          Divider(
            color: t.borderSubtle,
            height: 1.0,
            indent: 14,
            endIndent: 14,
          ),
          const SizedBox(height: 8.0),
          IconButton(
            key: _railPersonaKey,
            icon: Icon(
              Icons.tune_rounded,
              color: t.textSecondary,
              size: 20,
            ),
            tooltip: context.tr('coach_persona_tooltip').replaceAll('{name}', personaName),
            onPressed: () => _openPersonaSelector(context, fromKey: _railPersonaKey),
          ),
          const SizedBox(height: 8.0),
          Semantics(
            button: true,
            label: context.tr('profile_semantic').replaceAll('{name}', athleteName),
            child: InkWell(
              borderRadius: BorderRadius.circular(16.0),
              onTap: () => _handleProfileNavigation(context),
              child: SamanTierAvatar(
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
    final t = SamanChatTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      decoration: BoxDecoration(
        color: isSelected ? t.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10.0),
        border: isSelected
            ? Border.all(color: t.borderSubtle, width: 1.0)
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
                    color: isSelected ? t.textWhite : t.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timestamp.isNotEmpty) ...[
                const SizedBox(width: 8.0),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 11,
                    color: t.textMuted,
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
    final t = SamanChatTokens.of(context);
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
                color: t.textSecondary,
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: t.textWhite,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1.0),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: t.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: t.textMuted,
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
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.hasActiveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
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
                color: t.textSecondary,
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: t.textWhite,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1.0),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: t.textMuted,
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
                  decoration: BoxDecoration(
                    color: t.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: t.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatTimestamp(BuildContext context, String? val) {
  if (val == null || val.isEmpty) return '';
  try {
    final dt = DateTime.parse(val).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 2 && dt.day == now.day - 1) {
      return context.tr('yesterday');
    } else if (diff.inDays < 7) {
      final days = [
        context.tr('day_mon_short'),
        context.tr('day_tue_short'),
        context.tr('day_wed_short'),
        context.tr('day_thu_short'),
        context.tr('day_fri_short'),
        context.tr('day_sat_short'),
        context.tr('day_sun_short'),
      ];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  } catch (_) {
    return val;
  }
}

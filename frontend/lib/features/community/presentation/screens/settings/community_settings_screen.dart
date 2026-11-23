import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../config/app_translations.dart';
import '../../../../../config/routes.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_settings.dart';
import '../../providers/community_social_providers.dart';
import '../../tokens/saman_ig_tokens.dart';
import '../../widgets/community_blocked_muted_sheet.dart';

class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key});

  @override
  ConsumerState<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState
    extends ConsumerState<CommunitySettingsScreen> {
  static const int _maxMutedKeywords = 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(communitySettingsProvider.notifier);
      notifier.loadSettings();
      notifier.loadBlockedUsers();
      notifier.loadMutedUsers();
    });
  }

  Future<void> _applyUpdate(
    Future<CommunitySettings?> Function() updateCall,
  ) async {
    final result = await updateCall();
    if (!mounted) return;
    if (result == null) {
      final errorMsg = ref.read(communitySettingsProvider).errorMessage ??
          context.tr('community_settings_update_error');
      SamanFeedbackSnackBar.show(
        context,
        message: errorMsg,
        type: FeedbackType.error,
      );
    }
  }

  Future<void> _pickAudience({
    required String title,
    required String currentValue,
    required Future<CommunitySettings?> Function(String value) onSelected,
  }) async {
    final selected = await _AudiencePickerSheet.show(
      context,
      title: title,
      currentValue: currentValue,
    );
    if (!mounted || selected == null || selected == currentValue) return;
    await _applyUpdate(() => onSelected(selected));
  }

  Future<void> _showAddKeywordDialog(List<String> currentKeywords) async {
    if (currentKeywords.length >= _maxMutedKeywords) {
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('community_settings_keyword_limit_reached'),
        type: FeedbackType.warning,
      );
      return;
    }

    final keyword = await _AddKeywordDialog.show(context);
    if (!mounted || keyword == null) return;

    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final exists = currentKeywords.any(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('community_settings_keyword_exists'),
        type: FeedbackType.info,
      );
      return;
    }

    final nextKeywords = [...currentKeywords, trimmed];
    final notifier = ref.read(communitySettingsProvider.notifier);
    await _applyUpdate(() => notifier.updateSettings(mutedKeywords: nextKeywords));
  }

  Future<void> _removeKeyword(
    List<String> currentKeywords,
    String keyword,
  ) async {
    final nextKeywords = currentKeywords.where((k) => k != keyword).toList();
    final notifier = ref.read(communitySettingsProvider.notifier);
    await _applyUpdate(() => notifier.updateSettings(mutedKeywords: nextKeywords));
  }

  String _audienceLabel(BuildContext context, String value) {
    switch (value) {
      case 'followers':
        return context.tr('community_settings_audience_followers');
      case 'nobody':
        return context.tr('community_settings_audience_nobody');
      case 'everyone':
      default:
        return context.tr('community_settings_audience_everyone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final state = ref.watch(communitySettingsProvider);
    final settings = state.settings;
    final notifier = ref.read(communitySettingsProvider.notifier);

    return Scaffold(
      backgroundColor: ig.canvas,
      appBar: AppBar(
        backgroundColor: ig.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          constraints: const BoxConstraints(
            minWidth: SamanIgTokens.minTouchTarget,
            minHeight: SamanIgTokens.minTouchTarget,
          ),
          icon: Icon(Icons.arrow_back_rounded, color: ig.textPrimary),
          tooltip: context.tr('community_settings_back'),
        ),
        titleSpacing: 4,
        title: Text(
          context.tr('community_settings_title'),
          style: ig.displayTitle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (state.isSaving)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ig.primaryAction,
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: ig.border),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (state.isLoading)
              LinearProgressIndicator(
                minHeight: 2,
                color: ig.primaryAction,
                backgroundColor: ig.surfaceElevated,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  // 1. How others can interact with you
                  _SectionHeader(
                    title: context.tr('community_settings_section_interactions'),
                  ),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsSwitchTile(
                        switchKey: const ValueKey('settings-private-switch'),
                        icon: Icons.lock_outline_rounded,
                        title: context.tr('community_settings_private_account'),
                        subtitle: context.tr(
                          'community_settings_private_account_desc',
                        ),
                        value: settings.isPrivateAccount,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    isPrivateAccount: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: context.tr('community_settings_who_can_dm'),
                        trailingText: _audienceLabel(context, settings.whoCanDm),
                        onTap: state.isSaving
                            ? null
                            : () => _pickAudience(
                                  title: context.tr(
                                    'community_settings_who_can_dm',
                                  ),
                                  currentValue: settings.whoCanDm,
                                  onSelected: (val) =>
                                      notifier.updateSettings(whoCanDm: val),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.mode_comment_outlined,
                        title: context.tr('community_settings_who_can_comment'),
                        trailingText: _audienceLabel(
                          context,
                          settings.whoCanComment,
                        ),
                        onTap: state.isSaving
                            ? null
                            : () => _pickAudience(
                                  title: context.tr(
                                    'community_settings_who_can_comment',
                                  ),
                                  currentValue: settings.whoCanComment,
                                  onSelected: (val) => notifier.updateSettings(
                                    whoCanComment: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.reply_outlined,
                        title: context.tr(
                          'community_settings_who_can_reply_story',
                        ),
                        trailingText: _audienceLabel(
                          context,
                          settings.whoCanReplyStory,
                        ),
                        onTap: state.isSaving
                            ? null
                            : () => _pickAudience(
                                  title: context.tr(
                                    'community_settings_who_can_reply_story',
                                  ),
                                  currentValue: settings.whoCanReplyStory,
                                  onSelected: (val) => notifier.updateSettings(
                                    whoCanReplyStory: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.alternate_email_rounded,
                        title: context.tr('community_settings_allow_mentions'),
                        trailingText: _audienceLabel(
                          context,
                          settings.allowMentions,
                        ),
                        onTap: state.isSaving
                            ? null
                            : () => _pickAudience(
                                  title: context.tr(
                                    'community_settings_allow_mentions',
                                  ),
                                  currentValue: settings.allowMentions,
                                  onSelected: (val) => notifier.updateSettings(
                                    allowMentions: val,
                                  ),
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 2. What you see
                  _SectionHeader(
                    title: context.tr('community_settings_section_what_you_see'),
                  ),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsSwitchTile(
                        switchKey: const ValueKey('settings-hide-likes-switch'),
                        icon: Icons.favorite_border_rounded,
                        title: context.tr('community_settings_hide_likes'),
                        subtitle: context.tr(
                          'community_settings_hide_likes_desc',
                        ),
                        value: settings.hideLikeCounts,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    hideLikeCounts: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsSwitchTile(
                        switchKey:
                            const ValueKey('settings-activity-status-switch'),
                        icon: Icons.circle_outlined,
                        title: context.tr('community_settings_activity_status'),
                        subtitle: context.tr(
                          'community_settings_activity_status_desc',
                        ),
                        value: settings.showActivityStatus,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    showActivityStatus: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _MutedKeywordsSection(
                        keywords: settings.mutedKeywords,
                        maxKeywords: _maxMutedKeywords,
                        isDisabled: state.isSaving,
                        onAddPressed: () =>
                            _showAddKeywordDialog(settings.mutedKeywords),
                        onRemoveKeyword: (keyword) =>
                            _removeKeyword(settings.mutedKeywords, keyword),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.volume_off_rounded,
                        title: context.tr('community_settings_muted_accounts'),
                        badgeCount: state.mutedUsers.length,
                        onTap: () => CommunityBlockedMutedSheet.show(
                          context,
                          mode: BlockedMutedMode.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 3. Your archive & activity
                  _SectionHeader(
                    title: context.tr(
                      'community_settings_section_archive_activity',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsNavTile(
                        icon: Icons.bookmark_border_rounded,
                        title: context.tr('community_settings_saved_posts'),
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.communitySaved),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.history_rounded,
                        title: context.tr('community_settings_story_archive'),
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.communityStoryArchive),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsNavTile(
                        icon: Icons.edit_note_rounded,
                        title: context.tr('community_settings_drafts'),
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.communityDrafts),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 4. Saman Ecosystem Sync
                  _SectionHeader(
                    title: context.tr('community_settings_section_saman_sync'),
                  ),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsSwitchTile(
                        switchKey:
                            const ValueKey('settings-auto-workout-switch'),
                        icon: Icons.fitness_center_rounded,
                        title: context.tr(
                          'community_settings_auto_prompt_workout',
                        ),
                        subtitle: context.tr(
                          'community_settings_auto_prompt_workout_desc',
                        ),
                        value: settings.autoPromptShareWorkout,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    autoPromptShareWorkout: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      _SettingsSwitchTile(
                        switchKey: const ValueKey('settings-auto-meal-switch'),
                        icon: Icons.restaurant_outlined,
                        title: context.tr(
                          'community_settings_auto_prompt_meal',
                        ),
                        subtitle: context.tr(
                          'community_settings_auto_prompt_meal_desc',
                        ),
                        value: settings.autoPromptShareMeal,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    autoPromptShareMeal: val,
                                  ),
                                ),
                      ),
                      _HairlineDivider(ig: ig),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: ig.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ig.border, width: 0.5),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                                color: ig.primaryAction,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  context.tr(
                                    'community_settings_privacy_by_design',
                                  ),
                                  style: ig.caption(
                                    color: ig.textSecondary,
                                    fontSize: 12,
                                  ).copyWith(height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 5. Safety
                  _SectionHeader(
                    title: context.tr('community_settings_section_safety'),
                  ),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsNavTile(
                        icon: Icons.block_rounded,
                        iconColor: ig.danger,
                        title: context.tr('community_settings_blocked_accounts'),
                        badgeCount: state.blockedUsers.length,
                        onTap: () => CommunityBlockedMutedSheet.show(
                          context,
                          mode: BlockedMutedMode.blocked,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  final SamanIgTokens ig;

  const _HairlineDivider({required this.ig});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 0.5, thickness: 0.5, color: ig.border);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: ig.caption(
          color: ig.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final Key? switchKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitchTile({
    this.switchKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: ig.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ig.username(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: ig.caption(
                    color: ig.textSecondary,
                    fontSize: 12.5,
                  ).copyWith(height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeColor: ig.primaryAction,
            activeTrackColor: ig.primaryAction.withOpacity(0.42),
            inactiveThumbColor: ig.textMuted,
            inactiveTrackColor: ig.surfaceElevated,
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? trailingText;
  final int? badgeCount;
  final VoidCallback? onTap;

  const _SettingsNavTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.trailingText,
    this.badgeCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SamanIgTokens.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor ?? ig.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: ig.username(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailingText != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailingText!,
                  style: ig.caption(
                    color: ig.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (badgeCount != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ig.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ig.border, width: 0.5),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: ig.caption(
                      color: ig.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: ig.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutedKeywordsSection extends StatelessWidget {
  final List<String> keywords;
  final int maxKeywords;
  final bool isDisabled;
  final VoidCallback onAddPressed;
  final ValueChanged<String> onRemoveKeyword;

  const _MutedKeywordsSection({
    required this.keywords,
    required this.maxKeywords,
    required this.isDisabled,
    required this.onAddPressed,
    required this.onRemoveKeyword,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_off_outlined,
                size: 20,
                color: ig.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('community_settings_muted_keywords'),
                  style: ig.username(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${keywords.length}/$maxKeywords',
                style: ig.caption(
                  color: ig.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              context.tr('community_settings_muted_keywords_desc'),
              style: ig.caption(
                color: ig.textSecondary,
                fontSize: 12.5,
              ).copyWith(height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in keywords)
                Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: ig.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ig.border, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        keyword,
                        style: ig.caption(
                          color: ig.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        key: ValueKey('remove-keyword-$keyword'),
                        onTap:
                            isDisabled ? null : () => onRemoveKeyword(keyword),
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: ig.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              InkWell(
                key: const ValueKey('add-muted-keyword-btn'),
                onTap: isDisabled ? null : onAddPressed,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: SamanIgTokens.minTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: ig.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ig.border, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: ig.primaryAction,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('community_settings_add_keyword'),
                        style: ig.caption(
                          color: ig.primaryAction,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudiencePickerSheet extends StatelessWidget {
  final String title;
  final String currentValue;

  const _AudiencePickerSheet({
    required this.title,
    required this.currentValue,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String currentValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AudiencePickerSheet(
        title: title,
        currentValue: currentValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final options = <({String value, String label, String subtitle})>[
      (
        value: 'everyone',
        label: context.tr('community_settings_audience_everyone'),
        subtitle: context.tr('community_settings_audience_everyone_desc'),
      ),
      (
        value: 'followers',
        label: context.tr('community_settings_audience_followers'),
        subtitle: context.tr('community_settings_audience_followers_desc'),
      ),
      (
        value: 'nobody',
        label: context.tr('community_settings_audience_nobody'),
        subtitle: context.tr('community_settings_audience_nobody_desc'),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(
          top: BorderSide(color: ig.border, width: 0.5),
          left: BorderSide(color: ig.border, width: 0.5),
          right: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ig.textMuted.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: ig.displayTitle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: ig.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _AudienceOptionTile(
                      label: options[i].label,
                      subtitle: options[i].subtitle,
                      isSelected: options[i].value == currentValue,
                      onTap: () => Navigator.of(context).pop(options[i].value),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceOptionTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _AudienceOptionTile({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: SamanIgTokens.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ig.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? ig.primaryAction : ig.border,
            width: isSelected ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: ig.username(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: ig.caption(
                      color: ig.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: isSelected ? ig.primaryAction : ig.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddKeywordDialog extends StatefulWidget {
  const _AddKeywordDialog();

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const _AddKeywordDialog(),
    );
  }

  @override
  State<_AddKeywordDialog> createState() => _AddKeywordDialogState();
}

class _AddKeywordDialogState extends State<_AddKeywordDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return AlertDialog(
      backgroundColor: ig.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: ig.border, width: 0.5),
      ),
      title: Text(
        context.tr('community_settings_add_keyword_title'),
        style: ig.displayTitle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        style: ig.body(color: ig.textPrimary, fontSize: 14),
        decoration: ig
            .inputDecoration(
              hintText: context.tr('community_settings_add_keyword_hint'),
              borderRadius: 10,
            )
            .copyWith(
              counterStyle: ig.caption(
                color: ig.textMuted,
                fontSize: 11,
              ).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: ig.textSecondary,
            minimumSize: const Size(
              SamanIgTokens.minTouchTarget,
              SamanIgTokens.minTouchTarget,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            context.tr('community_settings_cancel'),
            style: ig.buttonLabel(
              color: ig.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ig.primaryButtonStyle(borderRadius: 8),
          child: Text(context.tr('community_settings_add')),
        ),
      ],
    );
  }
}

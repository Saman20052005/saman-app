import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_settings.dart';
import '../../providers/community_social_providers.dart';
import '../../widgets/community_blocked_muted_sheet.dart';

class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key});

  @override
  ConsumerState<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState
    extends ConsumerState<CommunitySettingsScreen> {
  static const int _maxMutedKeywords = 20;

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
          'Không thể cập nhật cài đặt. Vui lòng thử lại.';
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
        message: 'Đã đạt giới hạn tối đa $_maxMutedKeywords từ khóa đã ẩn',
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
        message: 'Từ khóa "$trimmed" đã có trong danh sách',
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

  String _audienceLabel(String value) {
    switch (value) {
      case 'followers':
        return 'Người theo dõi';
      case 'nobody':
        return 'Không ai';
      case 'everyone':
      default:
        return 'Mọi người';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(communitySettingsProvider);
    final settings = state.settings;
    final notifier = ref.read(communitySettingsProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary),
          tooltip: 'Quay lại',
        ),
        title: Text(
          'Cài đặt cộng đồng',
          style: textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
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
                    color: tokens.greenAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (state.isLoading)
              LinearProgressIndicator(
                minHeight: 2.5,
                color: tokens.greenAccent,
                backgroundColor: tokens.progressTrack,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  const _SectionHeader(title: 'QUYỀN RIÊNG TƯ'),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsSwitchTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Tài khoản riêng tư',
                        subtitle:
                            'Chỉ người theo dõi được chấp nhận mới xem được bài viết và hoạt động của bạn.',
                        value: settings.isPrivateAccount,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    isPrivateAccount: val,
                                  ),
                                ),
                      ),
                      Divider(height: 1, thickness: 1, color: tokens.border),
                      _SettingsSwitchTile(
                        icon: Icons.favorite_border_rounded,
                        title: 'Ẩn số lượt thích trên bài viết',
                        subtitle:
                            'Người khác sẽ không thấy tổng số lượt thích trên bài viết của bạn.',
                        value: settings.hideLikeCounts,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    hideLikeCounts: val,
                                  ),
                                ),
                      ),
                      Divider(height: 1, thickness: 1, color: tokens.border),
                      _SettingsSwitchTile(
                        icon: Icons.circle_outlined,
                        title: 'Hiển thị trạng thái hoạt động',
                        subtitle:
                            'Cho phép người theo dõi biết khi bạn đang hoạt động trong cộng đồng.',
                        value: settings.showActivityStatus,
                        onChanged: state.isSaving
                            ? null
                            : (val) => _applyUpdate(
                                  () => notifier.updateSettings(
                                    showActivityStatus: val,
                                  ),
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'TƯƠNG TÁC'),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsNavTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Ai có thể nhắn tin cho bạn',
                        trailingText: _audienceLabel(settings.whoCanDm),
                        onTap: state.isSaving
                            ? null
                            : () => _pickAudience(
                                  title: 'Ai có thể nhắn tin cho bạn',
                                  currentValue: settings.whoCanDm,
                                  onSelected: (val) =>
                                      notifier.updateSettings(whoCanDm: val),
                                ),
                      ),
                      Divider(height: 1, thickness: 1, color: tokens.border),
                      _SettingsNavTile(
                        icon: Icons.mode_comment_outlined,
                        title: 'Ai có thể bình luận',
                        trailingText: _audienceLabel(settings.whoCanComment),
                        onTap: state.isSaving
                            ? null
                            : () => _pickAudience(
                                  title: 'Ai có thể bình luận',
                                  currentValue: settings.whoCanComment,
                                  onSelected: (val) => notifier.updateSettings(
                                    whoCanComment: val,
                                  ),
                                ),
                      ),
                      Divider(height: 1, thickness: 1, color: tokens.border),
                      _MutedKeywordsSection(
                        keywords: settings.mutedKeywords,
                        maxKeywords: _maxMutedKeywords,
                        isDisabled: state.isSaving,
                        onAddPressed: () =>
                            _showAddKeywordDialog(settings.mutedKeywords),
                        onRemoveKeyword: (keyword) =>
                            _removeKeyword(settings.mutedKeywords, keyword),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'KIỂM SOÁT TÀI KHOẢN'),
                  const SizedBox(height: 8),
                  _SettingsGroupCard(
                    children: [
                      _SettingsNavTile(
                        icon: Icons.block_rounded,
                        title: 'Tài khoản đã chặn',
                        badgeCount: state.blockedUsers.length,
                        onTap: () => CommunityBlockedMutedSheet.show(
                          context,
                          mode: BlockedMutedMode.blocked,
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: tokens.border),
                      _SettingsNavTile(
                        icon: Icons.volume_off_rounded,
                        title: 'Tài khoản đã ẩn tiếng',
                        badgeCount: state.mutedUsers.length,
                        onTap: () => CommunityBlockedMutedSheet.show(
                          context,
                          mode: BlockedMutedMode.muted,
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

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: tokens.textSecondary,
        ),
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(color: tokens.border, width: 1),
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
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: tokens.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    color: tokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: tokens.greenAccent,
            inactiveThumbColor: tokens.textMuted,
            inactiveTrackColor: tokens.secondarySurface,
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final int? badgeCount;
  final VoidCallback? onTap;

  const _SettingsNavTile({
    required this.icon,
    required this.title,
    this.trailingText,
    this.badgeCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tokens.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (badgeCount != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.secondarySurface,
                  borderRadius:
                      BorderRadius.circular(SamanHomeTokens.radiusSm),
                  border: Border.all(color: tokens.border, width: 1),
                ),
                child: Text(
                  '$badgeCount',
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: tokens.textMuted,
            ),
          ],
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
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
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
                color: tokens.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Từ khóa đã ẩn',
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              Text(
                '${keywords.length}/$maxKeywords',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: tokens.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              'Bài viết hoặc bình luận chứa từ khóa này sẽ được ẩn khỏi bảng tin của bạn.',
              style: textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in keywords)
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: tokens.secondarySurface,
                    borderRadius:
                        BorderRadius.circular(SamanHomeTokens.radiusSm),
                    border: Border.all(color: tokens.border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        keyword,
                        style: textTheme.labelMedium?.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap:
                            isDisabled ? null : () => onRemoveKeyword(keyword),
                        borderRadius:
                            BorderRadius.circular(SamanHomeTokens.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              InkWell(
                onTap: isDisabled ? null : onAddPressed,
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.secondarySurface,
                    borderRadius:
                        BorderRadius.circular(SamanHomeTokens.radiusMd),
                    border: Border.all(color: tokens.border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: tokens.greenAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Thêm từ khóa',
                        style: textTheme.labelMedium?.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: tokens.greenAccent,
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

  static const List<({String value, String label, String subtitle})> _options =
      [
    (
      value: 'everyone',
      label: 'Mọi người',
      subtitle: 'Tất cả thành viên trong cộng đồng Saman',
    ),
    (
      value: 'followers',
      label: 'Người theo dõi',
      subtitle: 'Chỉ những người đang theo dõi bạn',
    ),
    (
      value: 'nobody',
      label: 'Không ai',
      subtitle: 'Tắt hoàn toàn tương tác này',
    ),
  ];

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
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SamanHomeTokens.radiusLg),
        ),
        border: Border(
          top: BorderSide(color: tokens.border, width: 1),
          left: BorderSide(color: tokens.border, width: 1),
          right: BorderSide(color: tokens.border, width: 1),
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
                  color: tokens.borderHigh,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _AudienceOptionTile(
                      label: _options[i].label,
                      subtitle: _options[i].subtitle,
                      isSelected: _options[i].value == currentValue,
                      onTap: () => Navigator.of(context).pop(_options[i].value),
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
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.secondarySurface,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
          border: Border.all(
            color: isSelected ? tokens.greenAccent : tokens.border,
            width: 1,
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
                    style: textTheme.titleSmall?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: tokens.textSecondary,
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
              color: isSelected ? tokens.greenAccent : tokens.textMuted,
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
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: tokens.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        side: BorderSide(color: tokens.border, width: 1),
      ),
      title: Text(
        'Thêm từ khóa ẩn',
        style: textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        style: textTheme.bodyMedium?.copyWith(
          color: tokens.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Ví dụ: quảng cáo, spam...',
          hintStyle: textTheme.bodySmall?.copyWith(
            color: tokens.textMuted,
            fontSize: 13.5,
          ),
          filled: true,
          fillColor: tokens.secondarySurface,
          counterStyle: textTheme.labelSmall?.copyWith(
            color: tokens.textMuted,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            borderSide: BorderSide(color: tokens.border, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            borderSide: BorderSide(color: tokens.border, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            borderSide: BorderSide(color: tokens.greenAccent, width: 1),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            ),
          ),
          child: Text(
            'Hủy',
            style: textTheme.labelLarge?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.greenAccent,
            foregroundColor: tokens.primaryCtaText,
            minimumSize: const Size(0, 44),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            ),
          ),
          child: Text(
            'Thêm',
            style: textTheme.labelLarge?.copyWith(
              color: tokens.primaryCtaText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

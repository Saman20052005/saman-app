import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import '../../widgets/community_activity_snapshot_card.dart';
import 'post_compose_publish_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/post_attachment_snapshot.dart';
import '../../providers/community_composer_provider.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';

class CommunitySelectAttachmentScreen extends ConsumerStatefulWidget {
  final AttachmentType initialTab;
  final bool continueToComposer;

  const CommunitySelectAttachmentScreen({
    super.key,
    this.initialTab = AttachmentType.workout,
    this.continueToComposer = false,
  });

  @override
  ConsumerState<CommunitySelectAttachmentScreen> createState() =>
      _CommunitySelectAttachmentScreenState();
}

class _CommunitySelectAttachmentScreenState
    extends ConsumerState<CommunitySelectAttachmentScreen> {
  late AttachmentType _currentTab;
  List<PostAttachmentSnapshot> _workouts = [];
  List<PostAttachmentSnapshot> _meals = [];
  PostAttachmentSnapshot? _selectedAttachment;
  bool _isLoading = true;
  bool _previewLoading = false;
  String? _error;
  int _requestGeneration = 0;

  // Privacy toggles
  bool _includeDuration = true;
  bool _includeExercises = true;
  bool _includeLoadOrMacros = false; // Strict privacy default: OFF

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _includeDuration = _currentTab == AttachmentType.workout;
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    final request = ++_requestGeneration;
    setState(() { _isLoading = true; _previewLoading = false; _error = null; _selectedAttachment = null; _workouts = []; _meals = []; });
    try {
      final repo = ref.read(communityRepositoryProvider);
      final workouts = await repo.getRecentWorkoutActivities();
      final meals = await repo.getRecentMealActivities();
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _workouts = workouts; _meals = meals; _isLoading = false;
        final list = _currentTab == AttachmentType.workout ? workouts : meals;
        _selectedAttachment = list.isEmpty ? null : list.first;
        _includeDuration = _currentTab == AttachmentType.workout;
        _includeExercises = true; _includeLoadOrMacros = false;
      });
    } catch (_) {
      if (!mounted || request != _requestGeneration) return;
      setState(() { _isLoading = false; _error = 'community_attachment_load_error'; });
    }
  }

  Future<void> _selectAttachment(PostAttachmentSnapshot item) async {
    final request = ++_requestGeneration;
    setState(() { _previewLoading = true; _error = null; });
    try {
      final preview = await ref.read(communityRepositoryProvider).previewActivity(item,
        duration: _includeDuration, items: _includeExercises, sensitive: _includeLoadOrMacros);
      if (!mounted || request != _requestGeneration) return;
      setState(() { _selectedAttachment = preview; _previewLoading = false; });
    } catch (_) {
      if (!mounted || request != _requestGeneration) return;
      setState(() { _previewLoading = false; _selectedAttachment = null; _error = 'community_attachment_load_error'; });
    }
  }

  void _onTabChanged(AttachmentType tab) {
    if (_previewLoading) return;
    setState(() {
      _currentTab = tab; _includeDuration = tab == AttachmentType.workout;
      _includeExercises = true; _includeLoadOrMacros = false;
      final list = tab == AttachmentType.workout ? _workouts : _meals;
      _selectedAttachment = list.isEmpty ? null : list.first;
    });
  }

  void _updatePrivacy({bool? duration, bool? items, bool? sensitive}) {
    final source = _selectedAttachment;
    setState(() { _includeDuration = duration ?? _includeDuration; _includeExercises = items ?? _includeExercises; _includeLoadOrMacros = sensitive ?? _includeLoadOrMacros; });
    if (source != null) _selectAttachment(source);
  }

  void _onAttach() {
    if (_selectedAttachment == null || _isLoading || _previewLoading || _error != null) return;

    final configuredSnapshot = _selectedAttachment!.copyWith(
      includeDuration: _includeDuration,
      includeExercisesOrFoods: _includeExercises,
      includeLoadOrMacros: _includeLoadOrMacros,
    ).sanitize();

    ref
        .read(communityComposerProvider.notifier)
        .setAttachment(configuredSnapshot);

    if (widget.continueToComposer) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PostComposePublishScreen()));
    } else { Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(communityIdentityRevisionProvider, (previous, next) {
      if (previous != null && previous != next) _loadActivities();
    });
    final ig = SamanIgTokens.of(context);
    final activeList = _currentTab == AttachmentType.workout ? _workouts : _meals;

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildAppBar(context, ig),

            if (_error != null) ...[
              Text(context.tr(_error!), style: ig.caption(color: ig.danger)),
              TextButton(
                onPressed: _loadActivities,
                child: Text(
                  context.tr('community_attachment_retry'),
                  style: ig.buttonLabel(color: ig.primaryAction),
                ),
              ),
            ],
            if (_previewLoading)
              LinearProgressIndicator(
                color: ig.primaryAction,
                backgroundColor: ig.surfaceElevated,
              ),
            // Main Content Scroll
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ig.primaryAction,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tab Switcher
                          _buildTabSwitcher(ig),
                          const SizedBox(height: 16),

                          // Activity Selection List
                          _buildActivityList(activeList, ig),
                          const SizedBox(height: 16),

                          // Selected Item Preview
                          if (_selectedAttachment != null) ...[
                            _buildAttachmentPreview(ig),
                            const SizedBox(height: 16),

                            // Privacy Settings Accordion
                            _buildPrivacySettingsAccordion(ig),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
            ),

            // Bottom CTA
            _buildBottomCta(context, ig),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanIgTokens ig) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(
          bottom: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Đính kèm hoạt động',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: ig.displayTitle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ig.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 48), // balance spacing
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(SamanIgTokens ig) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'Buổi tập',
              icon: Icons.fitness_center_rounded,
              isActive: _currentTab == AttachmentType.workout,
              onTap: () => _onTabChanged(AttachmentType.workout),
              ig: ig,
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Bữa ăn',
              icon: Icons.restaurant_rounded,
              isActive: _currentTab == AttachmentType.meal,
              onTap: () => _onTabChanged(AttachmentType.meal),
              ig: ig,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required SamanIgTokens ig,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? ig.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isActive
                ? ig.primaryAction.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? ig.primaryAction : ig.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: ig.username(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? ig.primaryAction : ig.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(
    List<PostAttachmentSnapshot> list,
    SamanIgTokens ig,
  ) {
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Chưa có dữ liệu hoạt động gần đây.',
            style: ig.caption(color: ig.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Gần đây',
            style: ig.caption(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ig.textSecondary,
            ).copyWith(letterSpacing: 0.5),
          ),
        ),
        ...list.map((item) {
          final isSelected = _selectedAttachment?.id == item.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected ? ig.surfaceElevated : ig.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? ig.primaryAction.withOpacity(0.6)
                    : ig.border,
              ),
            ),
            child: InkWell(
              onTap: () {
                if (!_previewLoading) _selectAttachment(item);
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (item.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          item.imageUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: ig.surfaceElevated,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: ig.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.type == AttachmentType.workout
                              ? Icons.fitness_center_rounded
                              : Icons.restaurant_rounded,
                          color: ig.primaryAction,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: ig.username(
                              fontSize: 14,
                              color: ig.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${item.dateFormatted} • ${item.durationFormatted ?? item.category}',
                            style: ig.caption(
                              fontSize: 12,
                              color: ig.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Radio<String>(
                      value: item.id,
                      groupValue: _selectedAttachment?.id,
                      activeColor: ig.primaryAction,
                      onChanged: (val) {
                        if (!_previewLoading) _selectAttachment(item);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAttachmentPreview(SamanIgTokens ig) {
    final item = _selectedAttachment!;
    if (item.sharedSnapshot != null) return CommunityActivitySnapshotCard(snapshot:item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Xem trước thẻ trong bài viết',
            style: ig.caption(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ig.textSecondary,
            ).copyWith(letterSpacing: 0.5),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ig.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ig.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    item.type == AttachmentType.workout
                        ? Icons.fitness_center_rounded
                        : Icons.restaurant_rounded,
                    size: 16,
                    color: ig.primaryAction,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.category,
                    style: ig.caption(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ig.primaryAction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: ig.displayTitle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ig.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_includeDuration && item.durationFormatted != null)
                    _buildPreviewChip(
                      Icons.schedule_rounded,
                      item.durationFormatted!,
                      ig,
                    ),
                  if (_includeExercises && item.exercises.isNotEmpty)
                    _buildPreviewChip(
                      Icons.format_list_bulleted_rounded,
                      '${item.exercises.length} động tác',
                      ig,
                    ),
                  if (_includeLoadOrMacros && item.loadSummaryFormatted != null)
                    _buildPreviewChip(
                      Icons.scale_rounded,
                      item.loadSummaryFormatted!,
                      ig,
                    ),
                  if (_includeLoadOrMacros &&
                      item.macrosSummaryFormatted != null)
                    _buildPreviewChip(
                      Icons.pie_chart_outline_rounded,
                      item.macrosSummaryFormatted!,
                      ig,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewChip(
    IconData icon,
    String label,
    SamanIgTokens ig,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ig.primaryAction),
          const SizedBox(width: 4),
          Text(
            label,
            style: ig.caption(
              fontSize: 11,
              color: ig.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySettingsAccordion(SamanIgTokens ig) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ig.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: ig.primaryAction,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Thông tin hiển thị & Quyền riêng tư',
                  overflow: TextOverflow.ellipsis,
                  style: ig.username(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ig.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Duration switch
          _buildSwitchRow(
            title: 'Thời lượng hoạt động',
            subtitle: _currentTab == AttachmentType.meal ? context.tr('community_attachment_no_meal_duration') : 'Bật hiển thị số phút trên bài viết',
            value: _includeDuration,
            onChanged: (v) => _updatePrivacy(duration:v),
            ig: ig,
          ),
          Divider(color: ig.border, height: 16),
          // Exercises / Items switch
          _buildSwitchRow(
            title: _currentTab == AttachmentType.workout
                ? 'Danh sách bài tập'
                : 'Thành phần món ăn',
            subtitle: 'Hiển thị các bài tập/món ăn đã thực hiện',
            value: _includeExercises,
            onChanged: (v) => _updatePrivacy(items:v),
            ig: ig,
          ),
          Divider(color: ig.border, height: 16),
          // Load & Sets / Macros switch (DEFAULT OFF)
          _buildSwitchRow(
            title: _currentTab == AttachmentType.workout
                ? 'Khối lượng tạ & Số hiệp'
                : 'Chi tiết Calo & Macros',
            subtitle: 'Bảo vệ riêng tư: TẮT mặc định',
            value: _includeLoadOrMacros,
            isSensitive: true,
            onChanged: (v) => _updatePrivacy(sensitive:v),
            ig: ig,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    bool isSensitive = false,
    required ValueChanged<bool> onChanged,
    required SamanIgTokens ig,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ig.username(
                  fontSize: 13,
                  color: ig.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: ig.caption(
                  fontSize: 11,
                  color: isSensitive ? ig.primaryAction : ig.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: ig.primaryAction,
          onChanged: _previewLoading || (_currentTab == AttachmentType.meal && title == 'Thời lượng hoạt động') ? null : onChanged,
        ),
      ],
    );
  }

  Widget _buildBottomCta(BuildContext context, SamanIgTokens ig) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      color: ig.canvas,
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _selectedAttachment != null && !_isLoading && !_previewLoading && _error == null ? _onAttach : null,
          style: ig.primaryButtonStyle(minHeight: 48, borderRadius: 12),
          child: const Text(
            'Đính kèm vào bài viết',
          ),
        ),
      ),
    );
  }
}

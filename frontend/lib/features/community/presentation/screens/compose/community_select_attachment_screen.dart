import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import '../../widgets/community_activity_snapshot_card.dart';
import 'post_compose_publish_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/post_attachment_snapshot.dart';
import '../../providers/community_composer_provider.dart';
import '../../providers/community_providers.dart';

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
    final activeList = _currentTab == AttachmentType.workout ? _workouts : _meals;

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildAppBar(context),

            if (_error != null) ...[
              Text(context.tr(_error!),style: SamanHomeTokens.headerSubtitle),
              TextButton(onPressed:_loadActivities,child:Text(context.tr('community_attachment_retry'),style:SamanHomeTokens.linkText)),
            ],
            if (_previewLoading) const LinearProgressIndicator(),
            // Main Content Scroll
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SamanHomeTokens.greenAccent,
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
                          _buildTabSwitcher(),
                          const SizedBox(height: 16),

                          // Activity Selection List
                          _buildActivityList(activeList),
                          const SizedBox(height: 16),

                          // Selected Item Preview
                          if (_selectedAttachment != null) ...[
                            _buildAttachmentPreview(),
                            const SizedBox(height: 16),

                            // Privacy Settings Accordion
                            _buildPrivacySettingsAccordion(),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
            ),

            // Bottom CTA
            _buildBottomCta(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1F2021), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: SamanHomeTokens.textWhite,
              size: 22,
            ),
          ),
          const Expanded(
            child: Text(
              'Đính kèm hoạt động',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
          ),
          const SizedBox(width: 48), // balance spacing
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2021),
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
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Bữa ăn',
              icon: Icons.restaurant_rounded,
              isActive: _currentTab == AttachmentType.meal,
              onTap: () => _onTabChanged(AttachmentType.meal),
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
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF292A2B) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isActive
                ? SamanHomeTokens.greenAccent.withOpacity(0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? SamanHomeTokens.greenAccent
                  : const Color(0xFFBBCAAF),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? SamanHomeTokens.greenAccent
                    : const Color(0xFFBBCAAF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(List<PostAttachmentSnapshot> list) {
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: Text(
            'Chưa có dữ liệu hoạt động gần đây.',
            style: TextStyle(color: Color(0xFFBBCAAF)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Gần đây',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFBBCAAF),
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...list.map((item) {
          final isSelected = _selectedAttachment?.id == item.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF292A2B)
                  : const Color(0xFF1E1F21),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? SamanHomeTokens.greenAccent.withOpacity(0.6)
                    : const Color(0xFF2E3033),
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
                            color: const Color(0xFF343536),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF343536),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.type == AttachmentType.workout
                              ? Icons.fitness_center_rounded
                              : Icons.restaurant_rounded,
                          color: SamanHomeTokens.greenAccent,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: SamanHomeTokens.textWhite,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${item.dateFormatted} • ${item.durationFormatted ?? item.category}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFBBCAAF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Radio<String>(
                      value: item.id,
                      groupValue: _selectedAttachment?.id,
                      activeColor: SamanHomeTokens.greenAccent,
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

  Widget _buildAttachmentPreview() {
    final item = _selectedAttachment!;
    if (item.sharedSnapshot != null) return CommunityActivitySnapshotCard(snapshot:item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Xem trước thẻ trong bài viết',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFBBCAAF),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F21),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2E3033)),
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
                    color: SamanHomeTokens.greenAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.category,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
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
                    ),
                  if (_includeExercises && item.exercises.isNotEmpty)
                    _buildPreviewChip(
                      Icons.format_list_bulleted_rounded,
                      '${item.exercises.length} động tác',
                    ),
                  if (_includeLoadOrMacros && item.loadSummaryFormatted != null)
                    _buildPreviewChip(
                      Icons.scale_rounded,
                      item.loadSummaryFormatted!,
                    ),
                  if (_includeLoadOrMacros &&
                      item.macrosSummaryFormatted != null)
                    _buildPreviewChip(
                      Icons.pie_chart_outline_rounded,
                      item.macrosSummaryFormatted!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF292A2B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: SamanHomeTokens.greenAccent),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: SamanHomeTokens.textWhite,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySettingsAccordion() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F21),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E3033)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: SamanHomeTokens.greenAccent,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Thông tin hiển thị & Quyền riêng tư',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.textWhite,
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
          ),
          const Divider(color: Color(0xFF2E3033), height: 16),
          // Exercises / Items switch
          _buildSwitchRow(
            title: _currentTab == AttachmentType.workout
                ? 'Danh sách bài tập'
                : 'Thành phần món ăn',
            subtitle: 'Hiển thị các bài tập/món ăn đã thực hiện',
            value: _includeExercises,
            onChanged: (v) => _updatePrivacy(items:v),
          ),
          const Divider(color: Color(0xFF2E3033), height: 16),
          // Load & Sets / Macros switch (DEFAULT OFF)
          _buildSwitchRow(
            title: _currentTab == AttachmentType.workout
                ? 'Khối lượng tạ & Số hiệp'
                : 'Chi tiết Calo & Macros',
            subtitle: 'Bảo vệ riêng tư: TẮT mặc định',
            value: _includeLoadOrMacros,
            isSensitive: true,
            onChanged: (v) => _updatePrivacy(sensitive:v),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SamanHomeTokens.textWhite,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isSensitive
                      ? const Color(0xFF10B981)
                      : const Color(0xFFBBCAAF),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: SamanHomeTokens.greenAccent,
          onChanged: _previewLoading || (_currentTab == AttachmentType.meal && title == 'Thời lượng hoạt động') ? null : onChanged,
        ),
      ],
    );
  }

  Widget _buildBottomCta(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      color: const Color(0xFF121314),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _selectedAttachment != null && !_isLoading && !_previewLoading && _error == null ? _onAttach : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: SamanHomeTokens.greenAccent,
            foregroundColor: const Color(0xFF003824),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Đính kèm vào bài viết',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';

class CommunityEditProfileScreen extends StatefulWidget {
  final String? initialName;
  final String? initialHandle;
  final String? initialTitle;
  final String? initialBio;
  final String? initialAvatarUrl;
  final List<String>? initialInterestTopics;
  final Future<bool> Function(Map<String, dynamic> payload)? onSaveProfile;

  const CommunityEditProfileScreen({
    super.key,
    this.initialName,
    this.initialHandle,
    this.initialTitle,
    this.initialBio,
    this.initialAvatarUrl,
    this.initialInterestTopics,
    this.onSaveProfile,
  });

  @override
  State<CommunityEditProfileScreen> createState() =>
      _CommunityEditProfileScreenState();
}

class _CommunityEditProfileScreenState
    extends State<CommunityEditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  late final TextEditingController _titleController;
  late final TextEditingController _bioController;

  static const List<String> _interestTopics = [
    'Tập luyện',
    'Dinh dưỡng',
    'Nấu ăn',
    'Phục hồi',
    'Thói quen',
  ];

  static const int _maxTopics = 3;

  late final Set<String> _selectedTopics;
  final ImagePicker _imagePicker = ImagePicker();
  String? _avatarUrl;
  String? _localAvatarPath;
  bool _avatarRemoved = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialName ?? 'Linh Nguyễn');
    _handleController =
        TextEditingController(text: widget.initialHandle ?? 'linh.kinetic');
    _titleController = TextEditingController(
        text: widget.initialTitle ?? 'Thành viên chia sẻ (Mẫu)');
    _bioController = TextEditingController(
      text: widget.initialBio ??
          'Yêu thích rèn luyện thể chất và dinh dưỡng cân bằng. Chia sẻ hành trình tập luyện thực tế mỗi ngày cùng Saman.',
    );
    _avatarUrl = widget.initialAvatarUrl;
    if (widget.initialInterestTopics != null &&
        widget.initialInterestTopics!.isNotEmpty) {
      _selectedTopics = widget.initialInterestTopics!.take(_maxTopics).toSet();
    } else {
      _selectedTopics = {_interestTopics[0], _interestTopics[1]};
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _titleController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked != null && mounted) {
        setState(() {
          _localAvatarPath = picked.path;
          _avatarRemoved = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      SamanFeedbackSnackBar.show(
        context,
        message: 'Không thể truy cập ảnh. Vui lòng thử lại.',
        type: FeedbackType.error,
      );
    }
  }

  void _showAvatarOptionsSheet(SamanHomePalette tokens) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.borderHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Cập nhật ảnh đại diện',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Đồng bộ tự động cùng hồ sơ tài khoản Saman',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSheetAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Chọn từ thư viện ảnh',
                  iconColor: tokens.greenAccent,
                  textColor: tokens.textPrimary,
                  tokens: tokens,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAvatar(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),
                _buildSheetAction(
                  icon: Icons.photo_camera_rounded,
                  label: 'Chụp ảnh mới',
                  iconColor: tokens.greenAccent,
                  textColor: tokens.textPrimary,
                  tokens: tokens,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAvatar(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
                _buildSheetAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Xóa ảnh hiện tại',
                  iconColor: tokens.fatRose,
                  textColor: tokens.fatRose,
                  tokens: tokens,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _localAvatarPath = null;
                      _avatarUrl = null;
                      _avatarRemoved = true;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: TextButton.styleFrom(
                      backgroundColor: tokens.secondarySurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Hủy',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetAction({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color textColor,
    required SamanHomePalette tokens,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: tokens.secondarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      SamanFeedbackSnackBar.show(
        context,
        message: 'Vui lòng nhập tên hiển thị',
        type: FeedbackType.error,
      );
      return;
    }

    final payload = <String, dynamic>{
      'name': _nameController.text.trim(),
      'handle': _handleController.text.trim(),
      'title': _titleController.text.trim(),
      'bio': _bioController.text.trim(),
      'goals': _selectedTopics.toList(),
      'interestTopics': _selectedTopics.toList(),
      if (_localAvatarPath != null) 'avatarPath': _localAvatarPath,
      if (_avatarRemoved) 'avatarRemoved': true,
      if (!_avatarRemoved && _avatarUrl != null) 'avatarUrl': _avatarUrl,
    };

    setState(() => _isSaving = true);

    if (widget.onSaveProfile != null) {
      bool ok = false;
      try {
        ok = await widget.onSaveProfile!(payload);
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (ok) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Đã cập nhật hồ sơ thành công!',
          type: FeedbackType.success,
          duration: const Duration(seconds: 2),
        );
        Navigator.pop(context, payload);
      } else {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể cập nhật hồ sơ. Vui lòng thử lại.',
          type: FeedbackType.error,
        );
      }
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _isSaving = false);
    SamanFeedbackSnackBar.show(
      context,
      message: 'Đã cập nhật hồ sơ thành công!',
      type: FeedbackType.success,
      duration: const Duration(seconds: 2),
    );
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, tokens),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarEdit(tokens),
                    const SizedBox(height: 24),
                    _buildInputCard(
                      label: 'TÊN HIỂN THỊ *',
                      controller: _nameController,
                      hint: 'Nhập họ và tên...',
                      tokens: tokens,
                    ),
                    const SizedBox(height: 14),
                    _buildInputCard(
                      label: 'TÊN NGƯỜI DÙNG (HANDLE)',
                      trailingLabel: 'duy nhất',
                      controller: _handleController,
                      prefixText: '@',
                      hint: 'username',
                      tokens: tokens,
                    ),
                    const SizedBox(height: 14),
                    _buildInputCard(
                      label: 'CHỨC DANH / DANH HIỆU',
                      controller: _titleController,
                      hint: 'Ví dụ: HLV thể hình, Người tập luyện...',
                      tokens: tokens,
                    ),
                    const SizedBox(height: 14),
                    _buildBioField(tokens),
                    const SizedBox(height: 16),
                    _buildTopicsSelector(tokens),
                    const SizedBox(height: 16),
                    _buildPrivacyNoticeCard(tokens),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanHomePalette tokens) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Quay lại',
            icon: Icon(
              Icons.close_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Chỉnh sửa hồ sơ',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
          _isSaving
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.greenAccent,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _handleSave,
                  child: Text(
                    'Lưu',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAvatarEdit(SamanHomePalette tokens) {
    final nameText = _nameController.text.trim();
    final initial = nameText.isNotEmpty ? nameText[0].toUpperCase() : 'L';

    Widget avatarContent;
    if (_localAvatarPath != null) {
      avatarContent = Image.file(
        File(_localAvatarPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitialAvatar(initial, tokens),
      );
    } else if (!_avatarRemoved &&
        _avatarUrl != null &&
        _avatarUrl!.isNotEmpty) {
      avatarContent = Image.network(
        _avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitialAvatar(initial, tokens),
      );
    } else {
      avatarContent = _buildInitialAvatar(initial, tokens);
    }

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showAvatarOptionsSheet(tokens),
            child: Stack(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.secondarySurface,
                    border: Border.all(color: tokens.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: avatarContent,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.greenAccent,
                      border: Border.all(color: tokens.canvas, width: 2),
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: 16,
                      color: tokens.isDark
                          ? const Color(0xFF003824)
                          : const Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _showAvatarOptionsSheet(tokens),
            child: Text(
              'Đổi ảnh đại diện',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.greenAccent,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ảnh đại diện cũng được cập nhật trong Saman.',
            style: TextStyle(
              fontSize: 11,
              color: tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialAvatar(String initial, SamanHomePalette tokens) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: tokens.greenAccent,
        ),
      ),
    );
  }

  Widget _buildInputCard({
    required String label,
    required TextEditingController controller,
    required SamanHomePalette tokens,
    String? trailingLabel,
    String? hint,
    String? prefixText,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              if (trailingLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailingLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (prefixText != null) ...[
                Text(
                  prefixText,
                  style: TextStyle(
                    fontSize: 15,
                    color: tokens.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 15,
                    color: tokens.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: tokens.textMuted,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBioField(SamanHomePalette tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'GIỚI THIỆU',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              Text(
                '${_bioController.text.length}/150',
                style: TextStyle(fontSize: 11, color: tokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            buildCounter: (_,
                    {required currentLength,
                    required isFocused,
                    maxLength}) =>
                null,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 14,
              color: tokens.textPrimary,
              height: 1.4,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText:
                  'Viết đôi dòng chia sẻ nguồn cảm hứng hoặc hành trình của bạn...',
              hintStyle: TextStyle(fontSize: 13, color: tokens.textMuted),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicsSelector(SamanHomePalette tokens) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHỦ ĐỀ QUAN TÂM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chọn tối đa $_maxTopics chủ đề hiển thị trên hồ sơ cá nhân',
            style: TextStyle(
              fontSize: 12,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interestTopics.map((topic) {
              final isSelected = _selectedTopics.contains(topic);
              return InkWell(
                onTap: () {
                  if (!isSelected && _selectedTopics.length >= _maxTopics) {
                    SamanFeedbackSnackBar.show(
                      context,
                      message: 'Tối đa $_maxTopics chủ đề quan tâm',
                      type: FeedbackType.info,
                      duration: const Duration(seconds: 2),
                    );
                    return;
                  }
                  setState(() {
                    if (isSelected) {
                      _selectedTopics.remove(topic);
                    } else {
                      _selectedTopics.add(topic);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? tokens.secondarySurface
                        : tokens.canvas.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? tokens.greenAccent : tokens.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: tokens.greenAccent,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        topic,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? tokens.greenAccent
                              : tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNoticeCard(SamanHomePalette tokens) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.secondarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 20,
            color: tokens.greenAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Những thông tin này hiển thị trên hồ sơ cộng đồng của bạn.',
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

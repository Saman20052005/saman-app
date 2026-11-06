import 'package:flutter/material.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';

class CommunityEditProfileScreen extends StatefulWidget {
  final String? initialName;
  final String? initialHandle;
  final String? initialTitle;
  final String? initialBio;

  const CommunityEditProfileScreen({
    super.key,
    this.initialName,
    this.initialHandle,
    this.initialTitle,
    this.initialBio,
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

  final List<String> _goals = [
    'Tăng cơ giảm mỡ',
    'Sức mạnh Hypertrophy',
    'Ăn sạch Clean Eating',
    'Kỷ luật thói quen',
    'Phục hồi cơ bắp',
  ];

  late final Set<String> _selectedGoals;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? 'Linh Nguyễn');
    _handleController = TextEditingController(text: widget.initialHandle ?? 'linh.kinetic');
    _titleController = TextEditingController(text: widget.initialTitle ?? 'Thành viên chia sẻ (Mẫu)');
    _bioController = TextEditingController(
      text: widget.initialBio ??
          'Yêu thích rèn luyện thể chất và dinh dưỡng cân bằng. Chia sẻ hành trình tập luyện thực tế mỗi ngày cùng Saman.',
    );
    _selectedGoals = {_goals[0], _goals[2]};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _titleController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã cập nhật hồ sơ thành công!'),
        backgroundColor: Color(0xFF003824),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'handle': _handleController.text.trim(),
      'title': _titleController.text.trim(),
      'bio': _bioController.text.trim(),
      'goals': _selectedGoals.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarEdit(),
                    const SizedBox(height: 24),
                    _buildTextField(
                      label: 'Tên hiển thị *',
                      controller: _nameController,
                      hint: 'Nhập họ và tên...',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Tên người dùng (Handle)',
                      controller: _handleController,
                      prefixText: '@',
                      hint: 'username',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Chức danh / Danh hiệu',
                      controller: _titleController,
                      hint: 'Ví dụ: HLV thể hình, Người tập luyện...',
                    ),
                    const SizedBox(height: 16),
                    _buildBioField(),
                    const SizedBox(height: 20),
                    _buildGoalsSelector(),
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

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2021), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.close_rounded,
              color: SamanHomeTokens.textWhite,
              size: 22,
            ),
          ),
          const Expanded(
            child: Text(
              'Chỉnh sửa hồ sơ',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
          ),
          _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SamanHomeTokens.greenAccent,
                  ),
                )
              : TextButton(
                  onPressed: _handleSave,
                  child: const Text(
                    'Lưu',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAvatarEdit() {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF292A2B),
                ),
                child: const Center(
                  child: Text(
                    'L',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SamanHomeTokens.greenAccent,
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: Color(0xFF003824),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Đổi ảnh đại diện',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SamanHomeTokens.greenAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? prefixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFBBCAAF),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F21),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E3033)),
          ),
          child: Row(
            children: [
              if (prefixText != null) ...[
                Text(
                  prefixText,
                  style: const TextStyle(
                    fontSize: 14,
                    color: SamanHomeTokens.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(
                    fontSize: 14,
                    color: SamanHomeTokens.textWhite,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF71767B),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Tiểu sử cá nhân',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFBBCAAF),
                ),
              ),
            ),
            Text(
              '${_bioController.text.length}/150',
              style: const TextStyle(fontSize: 11, color: Color(0xFFBBCAAF)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F21),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E3033)),
          ),
          child: TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                null,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 14,
              color: SamanHomeTokens.textWhite,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText: 'Giới thiệu ngắn về mục tiêu, kinh nghiệm tập luyện...',
              hintStyle: TextStyle(fontSize: 13, color: Color(0xFF71767B)),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoalsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mục tiêu thể chất & dinh dưỡng',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFBBCAAF),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _goals.map((goal) {
            final isSelected = _selectedGoals.contains(goal);
            return ChoiceChip(
              label: Text(goal),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedGoals.add(goal);
                  } else {
                    _selectedGoals.remove(goal);
                  }
                });
              },
              selectedColor: SamanHomeTokens.greenAccent,
              backgroundColor: const Color(0xFF1E1F21),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF003824)
                    : SamanHomeTokens.textWhite,
              ),
              side: BorderSide(
                color: isSelected
                    ? SamanHomeTokens.greenAccent
                    : const Color(0xFF2E3033),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

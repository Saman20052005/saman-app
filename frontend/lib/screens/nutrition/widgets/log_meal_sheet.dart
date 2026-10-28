// lib/screens/nutrition/widgets/log_meal_sheet.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/meal_log.dart';
import '../../../providers/daily_story_provider.dart';
import '../../../services/nutrition_service.dart';
import 'meal_review_dialog.dart' hide MealType;

class LogMealSheet extends ConsumerStatefulWidget {
  final DateTime selectedDate;
  const LogMealSheet({super.key, required this.selectedDate});

  @override
  ConsumerState<LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends ConsumerState<LogMealSheet> {
  static const Color _bgCanvas = Color(0xFF0F0F0F);
  static const Color _bgSurface = Color(0xFF1C1C1C);
  static const Color _bgCard = Color(0xFF242424);
  static const Color _borderSubtle = Color(0xFF2A2A2A);
  static const Color _borderStrong = Color(0xFF3D3D3D);

  static const Color _brandPrimary = Color(0xFF0E8F5E);
  static const Color _aiAccent = Color(0xFFFF8A3D);

  static const Color _textPrimary = Color(0xFFF0F0F0);
  static const Color _textSecondary = Color(0xFFAAAAAA);
  static const Color _textMuted = Color(0xFF707070);
  static const Color _errorColor = Color(0xFFCF6679);

  final _noteController = TextEditingController();
  MealType _selectedType = MealType.snack;
  bool _isAnalyzing = false;
  String _mode = 'standard';
  NutritionRequestContext? _photoOwner;

  XFile? _pickedFile;
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final owner = await ref.read(nutritionSessionProvider).capture();
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 800,
        maxHeight: 800,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (picked != null) {
        await owner.validate();
        if (!mounted) return;
        setState(() {
          _pickedFile = picked;
          _photoOwner = owner;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is NutritionSessionChanged
                  ? e.toString()
                  : 'Không thể mở ảnh. Vui lòng thử lại.',
            ),
          ),
        );
      }
    }
  }

  void _clearImage() {
    setState(() => _pickedFile = null);
  }

  Future<void> _handleLogStory() async {
    if (_isAnalyzing || _pickedFile == null) return;
    setState(() => _isAnalyzing = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
    final controller = ref.read(dailyStoryControllerProvider(dateStr).notifier);
    try {
      final owner =
          _photoOwner ?? await ref.read(nutritionSessionProvider).capture();
      await owner.validate();
      final result = await controller.analyzeImage(
        _pickedFile!,
        mode: _mode,
        session: owner,
      );
      if (!mounted) return;
      await owner.validate();
      if (!mounted) return;
      final confirmed = await MealReviewDialog.show(
        context,
        result!,
        imageFile: _pickedFile,
        onConfirm: (data) async {
          await owner.validate();
          await controller.confirmLog(data,
              imageFile: _pickedFile, session: owner);
          await owner.validate();
        },
      );
      if (!mounted || confirmed == null) return;
      await owner.validate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã thêm bữa ăn thành công!')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      // The photo and note remain available for another analysis attempt.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _borderStrong),
          ),
          title: const Text(
            'Không thể phân tích ảnh',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                foodAnalysisErrorMessage(error),
                style: const TextStyle(
                  color: _errorColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Lưu chỉ ảnh hiện chưa khả dụng. Ảnh và nội dung của bạn được giữ lại để thử phân tích lại hoặc hủy.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              if (_mode == 'advanced') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: const Text(
                    '💡 Gợi ý: Bạn có thể chuyển sang chế độ Tiêu chuẩn và thử phân tích lại.',
                    style: TextStyle(
                      color: _brandPrimary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (_mode == 'advanced')
              TextButton(
                onPressed: () {
                  setState(() => _mode = 'standard');
                  Navigator.pop(context);
                },
                child: const Text(
                  'Đổi sang Tiêu chuẩn',
                  style: TextStyle(color: _brandPrimary, fontSize: 13),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Đóng',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
    final displayDateStr = DateFormat('EEE, MMM d').format(widget.selectedDate);
    final isToday = DateUtils.isSameDay(widget.selectedDate, DateTime.now());
    final isAdvanced = _mode == 'advanced';

    ref.listen<AsyncValue>(dailyStoryControllerProvider(dateStr), (_, state) {
      if (!state.isLoading && state.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(foodAnalysisErrorMessage(state.error!)),
            backgroundColor: _errorColor,
          ),
        );
      }
    });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: const BoxDecoration(
            color: _bgSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: _borderStrong, width: 1),
              left: BorderSide(color: _borderStrong, width: 1),
              right: BorderSide(color: _borderStrong, width: 1),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 18,
            right: 18,
            top: 12,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ghi Nhận Dinh Dưỡng',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Chụp ảnh hoặc chọn từ thư viện để phân tích',
                            style: TextStyle(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      icon: const Icon(Icons.close, color: _textSecondary, size: 22),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Date Anchor Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: _brandPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayDateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _textPrimary,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 4),
                        const Text(
                          '· Hôm nay',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Meal Type Segmented Selector
                _buildMealTypeSegmentedSelector(),
                const SizedBox(height: 14),

                // Mode Selector Pill (HTML Scenario 2 Spec)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _isAnalyzing
                              ? null
                              : () => setState(() => _mode = 'standard'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !isAdvanced ? _brandPrimary : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: !isAdvanced
                                  ? [
                                      BoxShadow(
                                        color: _brandPrimary.withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.balance_rounded,
                                  size: 13,
                                  color: !isAdvanced ? Colors.white : _textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Tiêu chuẩn',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !isAdvanced
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color:
                                        !isAdvanced ? Colors.white : _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _isAnalyzing
                              ? null
                              : () => setState(() => _mode = 'advanced'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isAdvanced ? _aiAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: isAdvanced
                                  ? [
                                      BoxShadow(
                                        color: _aiAccent.withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '✨ AI nâng cao',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isAdvanced
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color:
                                        isAdvanced ? Colors.white : _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 12, color: _textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isAdvanced
                              ? 'Nhận diện đa món • Hỗ trợ món ăn Việt'
                              : 'Tra cứu nhanh • Cơ sở dữ liệu tham chiếu',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // In-Flight Analyzing Banner (Scenario 3 Spec)
                if (_isAnalyzing) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _bgCanvas,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _borderStrong),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: isAdvanced ? _aiAccent : _brandPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Đang phân tích món ăn...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Vui lòng đợi giây lát trong khi hệ thống nhận diện thành phần dinh dưỡng.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: _textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _borderSubtle),
                          ),
                          child: const Text(
                            'Chống gửi đúp: Toàn bộ nút thao tác đã tạm khóa',
                            style: TextStyle(fontSize: 10, color: _textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Photo Picker & Preview Section
                _buildPhotoSection(),
                const SizedBox(height: 14),

                // Note TextField
                Container(
                  decoration: BoxDecoration(
                    color: _bgCanvas,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderSubtle),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: TextField(
                    controller: _noteController,
                    minLines: 2,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    cursorColor: _brandPrimary,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Ghi chú (Tên món, cảm nhận...)',
                      hintStyle: TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Contract Notice
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _bgCanvas.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: _textMuted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Phân tích ảnh và xác nhận trước khi lưu bữa ăn. Lưu chỉ ảnh hiện chưa khả dụng.',
                          style: TextStyle(
                            fontSize: 11,
                            color: _textMuted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Save Action Button
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _isAnalyzing
                        ? null
                        : () async {
                            if (_pickedFile == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Vui lòng chọn ảnh trước khi lưu')),
                              );
                              return;
                            }
                            await _handleLogStory();
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _brandPrimary.withOpacity(0.35),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Lưu Nhật Ký Ảnh',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8),

                // Cancel Link
                Center(
                  child: TextButton(
                    onPressed: _isAnalyzing
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Hủy',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMealTypeSegmentedSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: MealType.values.map((type) {
          final isSelected = _selectedType == type;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _bgSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: _brandPrimary.withOpacity(0.5))
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: _brandPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        type.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? _textPrimary : _textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPhotoSection() {
    if (_pickedFile != null) {
      return Container(
        decoration: BoxDecoration(
          color: _bgCanvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderSubtle),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: kIsWeb
                    ? Image.network(
                        _pickedFile!.path,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: _errorColor),
                        ),
                      )
                    : Image.file(
                        File(_pickedFile!.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: _textSecondary),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.refresh, size: 16, color: _brandPrimary),
                  label: const Text(
                    'Đổi ảnh',
                    style: TextStyle(fontSize: 12, color: _brandPrimary),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isAnalyzing ? null : _clearImage,
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: _errorColor),
                  label: const Text(
                    'Xóa ảnh',
                    style: TextStyle(fontSize: 12, color: _errorColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgCanvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderStrong),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtle),
            ),
            child: Icon(
              Icons.add_a_photo_outlined,
              size: 24,
              color: _mode == 'advanced' ? _aiAccent : _brandPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Thêm ảnh bữa ăn',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Chụp món ăn hoặc chọn từ thư viện ảnh',
            style: TextStyle(
              fontSize: 11,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('Chụp ảnh'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _bgCard,
                    foregroundColor: _textPrimary,
                    side: const BorderSide(color: _borderSubtle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text('Thư viện'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _bgCard,
                    foregroundColor: _textPrimary,
                    side: const BorderSide(color: _borderSubtle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
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

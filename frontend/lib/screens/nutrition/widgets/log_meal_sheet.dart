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
        setState(() { _pickedFile = picked; _photoOwner = owner; });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is NutritionSessionChanged ? e.toString() : 'Không thể mở ảnh. Vui lòng thử lại.')),
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
      final owner = _photoOwner ?? await ref.read(nutritionSessionProvider).capture();
      await owner.validate();
      final result = await controller.analyzeImage(_pickedFile!, mode: _mode, session: owner);
      if (!mounted) return;
      await owner.validate();
      if (!mounted) return;
      final confirmed = await MealReviewDialog.show(context, result!, onConfirm: (data) async {
        await owner.validate();
        await controller.confirmLog(data, imageFile: _pickedFile, session: owner);
        await owner.validate();
      });
      if (!mounted || confirmed == null) return;
      await owner.validate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã thêm bữa ăn thành công!')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      // The photo and note remain available for another analysis attempt.
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16171B),
        title: const Text('Không thể phân tích ảnh'),
        content: Text('${foodAnalysisErrorMessage(error)}\n\nLưu chỉ ảnh hiện chưa khả dụng. Ảnh và nội dung của bạn được giữ lại để thử phân tích lại hoặc hủy.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))],
      ));
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

    ref.listen<AsyncValue>(dailyStoryControllerProvider(dateStr), (_, state) {
      if (!state.isLoading && state.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(foodAnalysisErrorMessage(state.error!)),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF16171B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Color(0xFF26282F), width: 1),
              left: BorderSide(color: Color(0xFF26282F), width: 1),
              right: BorderSide(color: Color(0xFF26282F), width: 1),
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
                      color: const Color(0xFF383A42),
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
                            'Log Bữa Ăn Nhanh',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF9FAFB),
                              letterSpacing: -0.4,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Chụp ảnh hoặc chọn từ thư viện',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      icon: const Icon(Icons.close, color: Color(0xFF9CA3AF), size: 22),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Date Anchor Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2026),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF26282F)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayDateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFF3F4F6),
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 4),
                        const Text(
                          '· Today',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF),
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

                // Photo Picker & Preview Section
                _buildPhotoSection(),
                const SizedBox(height: 14),

                // Note TextField
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2026),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF26282F)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: TextField(
                    controller: _noteController,
                    minLines: 3,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    cursorColor: const Color(0xFF10B981),
                    style: const TextStyle(
                      color: Color(0xFFF3F4F6),
                      fontSize: 13,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Ghi chú (Tên món, cảm nhận...)',
                      hintStyle: TextStyle(
                        color: Color(0xFF6B7280),
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

                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('Standard'), selected: _mode == 'standard',
                    onSelected: _isAnalyzing ? null : (_) => setState(() => _mode = 'standard')),
                  ChoiceChip(label: const Text('Advanced'), selected: _mode == 'advanced',
                    onSelected: _isAnalyzing ? null : (_) => setState(() => _mode = 'advanced')),
                ]),
                const SizedBox(height: 12),
                // Contract Notice
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2026).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF26282F)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Color(0xFF9CA3AF)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Phân tích ảnh và xác nhận trước khi lưu bữa ăn. Lưu chỉ ảnh hiện chưa khả dụng.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Save Action Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isAnalyzing
                        ? null
                        : () async {
                            if (_pickedFile == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Vui lòng chọn ảnh trước khi lưu')),
                              );
                              return;
                            }
                            await _handleLogStory();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9FAFB),
                      foregroundColor: const Color(0xFF0C0D0E),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0C0D0E),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Lưu Nhật Ký Ảnh',
                                style: TextStyle(
                                  fontSize: 15,
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
                        color: Color(0xFF9CA3AF),
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
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
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
                  color: isSelected ? const Color(0xFF16171B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF10B981).withOpacity(0.4))
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
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
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        type.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? const Color(0xFFF9FAFB) : const Color(0xFF9CA3AF),
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
          color: const Color(0xFF1E2026),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF26282F)),
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
                          child: Icon(Icons.broken_image, color: Color(0xFFEF4444)),
                        ),
                      )
                    : Image.file(
                        File(_pickedFile!.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Color(0xFF9CA3AF)),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF10B981)),
                  label: const Text(
                    'Đổi ảnh',
                    style: TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isAnalyzing ? null : _clearImage,
                  icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                  label: const Text(
                    'Xóa ảnh',
                    style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
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
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF212328),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF26282F)),
            ),
            child: const Icon(
              Icons.add_a_photo_outlined,
              size: 24,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Thêm ảnh bữa ăn',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF9FAFB),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Chụp món ăn hoặc chọn từ thư viện ảnh',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('Chụp ảnh'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF212328),
                    foregroundColor: const Color(0xFFF3F4F6),
                    side: const BorderSide(color: Color(0xFF26282F)),
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
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text('Thư viện'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF212328),
                    foregroundColor: const Color(0xFFF3F4F6),
                    side: const BorderSide(color: Color(0xFF26282F)),
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

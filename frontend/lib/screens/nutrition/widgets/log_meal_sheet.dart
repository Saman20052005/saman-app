// lib/screens/nutrition/widgets/log_meal_sheet.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/meal_log.dart';
import '../../../providers/daily_story_provider.dart';
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
  bool _isConfirmed = false;

  XFile? _pickedFile;
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 800,
        maxHeight: 800,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (picked != null) {
        setState(() => _pickedFile = picked);
      }
    } catch (e) {
      debugPrint("Pick image error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Không thể mở ảnh: $e")),
        );
      }
    }
  }

  Future<void> _handleLogStory(File imageFile) async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final result = await ref
          .read(dailyStoryControllerProvider(dateStr).notifier)
          .analyzeImage(_pickedFile!);

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      // AI analysis succeeded
      final confirmed = await MealReviewDialog.show(context, result!);
      if (!mounted) return;
      if (confirmed != null && !_isConfirmed) {
        _isConfirmed = true;
        await ref
            .read(dailyStoryControllerProvider(dateStr).notifier)
            .confirmLog(confirmed, imageFile: _pickedFile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Đã thêm bữa ăn thành công!')),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      // AI analysis failed - show confirmation dialog for manual save
      final shouldSaveManual = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Không nhận diện được món ăn'),
          content: const Text(
              'Bạn có muốn lưu ảnh mà không có thông tin dinh dưỡng?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lưu thủ công'),
            ),
          ],
        ),
      );

      if (shouldSaveManual == true) {
        try {
          final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
          await ref
              .read(dailyStoryControllerProvider(dateStr).notifier)
              .saveStoryWithoutAI(
                imageFile: _pickedFile!,
                mealType: _selectedType.name,
                note: _noteController.text,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Đã lưu ảnh. Phân tích AI tạm thời không khả dụng.'),
              ),
            );
            Navigator.of(context).pop(true);
          }
        } catch (saveError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi lưu: $saveError')),
            );
          }
        }
      }
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
    ref.listen<AsyncValue>(dailyStoryControllerProvider(dateStr), (_, state) {
      if (!state.isLoading && state.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${state.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    final state = ref.watch(dailyStoryControllerProvider(dateStr));
    final isLoading = state.isLoading;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Log Bữa Ăn Nhanh',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<MealType>(
            value: _selectedType,
            decoration: const InputDecoration(labelText: 'Loại bữa'),
            items: MealType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type.displayName),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedType = val);
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _pickedFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.network(
                              _pickedFile!.path,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.error, color: Colors.red),
                            )
                          : Image.file(
                              File(_pickedFile!.path),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey),
                            ),
                    )
                  : Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.fastfood, color: Colors.grey),
                    ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Chụp ảnh'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Thư viện'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Ghi chú (Tên món, cảm nhận...)',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isLoading || _isAnalyzing
                ? null
                : () async {
                    if (_pickedFile == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng chọn ảnh')),
                      );
                      return;
                    }
                    await _handleLogStory(File(_pickedFile!.path));
                  },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: isLoading || _isAnalyzing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Lưu Nhật Ký',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

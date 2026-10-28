// lib/screens/nutrition/widgets/meal_review_dialog.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models/ai_analysis_result.dart';
import '../../../features/nutrition/domain/repositories/nutrition_repository.dart';
import '../../../services/nutrition_service.dart' show foodAnalysisErrorMessage;

enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeExt on MealType {
  String get label => switch (this) {
        MealType.breakfast => 'Bữa sáng',
        MealType.lunch => 'Bữa trưa',
        MealType.dinner => 'Bữa tối',
        MealType.snack => 'Bữa phụ',
      };
  String get shortLabel => switch (this) {
        MealType.breakfast => 'Sáng',
        MealType.lunch => 'Trưa',
        MealType.dinner => 'Tối',
        MealType.snack => 'Phụ',
      };
  String get value => name;
}

class MealReviewDialog extends StatefulWidget {
  final AIAnalysisResult result;
  final Future<void> Function(MealLogData)? onConfirm;
  final XFile? imageFile;
  final String? imagePath;

  const MealReviewDialog({
    super.key,
    required this.result,
    this.onConfirm,
    this.imageFile,
    this.imagePath,
  });

  static Future<MealLogData?> show(
    BuildContext context,
    AIAnalysisResult result, {
    Future<void> Function(MealLogData)? onConfirm,
    XFile? imageFile,
    String? imagePath,
  }) {
    return showModalBottomSheet<MealLogData>(
      context: context,
      useRootNavigator: true,
      isDismissible: onConfirm == null,
      enableDrag: onConfirm == null,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MealReviewDialog(
        result: result,
        onConfirm: onConfirm,
        imageFile: imageFile,
        imagePath: imagePath,
      ),
    );
  }

  @override
  State<MealReviewDialog> createState() => _MealReviewDialogState();
}

class _MealReviewDialogState extends State<MealReviewDialog> {
  static const Color _bgCanvas = Color(0xFF0F0F0F);
  static const Color _bgSurface = Color(0xFF1C1C1C);
  static const Color _bgCard = Color(0xFF242424);
  static const Color _borderSubtle = Color(0xFF2A2A2A);
  static const Color _borderStrong = Color(0xFF3D3D3D);

  static const Color _brandPrimary = Color(0xFF0E8F5E);
  static const Color _brandPrimaryLight = Color(0x260E8F5E); // rgba(14, 143, 94, 0.15)
  static const Color _aiAccent = Color(0xFFFF8A3D);

  static const Color _proteinColor = Color(0xFF4D96FF);
  static const Color _carbsColor = Color(0xFFFFD93D);
  static const Color _fatColor = Color(0xFFFF6B6B);

  static const Color _textPrimary = Color(0xFFF0F0F0);
  static const Color _textSecondary = Color(0xFFAAAAAA);
  static const Color _textMuted = Color(0xFF707070);
  static const Color _errorColor = Color(0xFFCF6679);

  late AIAnalysisResult _current;
  late double _grams;
  MealType _mealType = MealType.lunch;
  String? _selectedLabel;
  bool _saving = false;
  String? _saveError;
  bool _retryAllowed = true;
  MealLogData? _confirmedData;
  bool _showProvenanceExplanation = false;

  bool get _isAdvanced =>
      _current.nutritionSource.toLowerCase().contains('gemini');

  @override
  void initState() {
    super.initState();
    _current = widget.result;
    _grams = widget.result.grams;
    _selectedLabel = widget.result.foodLabel;

    final hour = DateTime.now().hour;
    _mealType = hour < 10
        ? MealType.breakfast
        : hour < 14
            ? MealType.lunch
            : hour < 19
                ? MealType.dinner
                : MealType.snack;
  }

  void _onGramsChanged(double newGrams) {
    setState(() {
      _grams = newGrams;
      _current = _current.withGrams(newGrams);
    });
  }

  void _onRelabel(FoodPrediction selected) {
    setState(() {
      _selectedLabel = selected.label;
      _current = _current.withLabel(selected).withGrams(_grams);
    });
  }

  Future<void> _confirm() async {
    if (_saving || !_retryAllowed) return;
    final data = _confirmedData ??= MealLogData(
      foodName: _current.foodName,
      foodLabel: _current.foodLabel,
      mealType: _mealType.value,
      grams: _grams,
      calories: _current.calories,
      protein: _current.protein,
      carbs: _current.carbs,
      fat: _current.fat,
      loggedAt: DateTime.now().toIso8601String(),
    );
    if (widget.onConfirm == null) {
      Navigator.of(context).pop(data);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onConfirm!(data);
      if (mounted) Navigator.of(context).pop(data);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error is ConfirmLogException ||
                error is NutritionSessionChanged
            ? error.toString()
            : foodAnalysisErrorMessage(error);
        _retryAllowed = error is ConfirmLogException && error.canRetry;
      });
    }
  }

  Widget _buildDishHeroImage() {
    Widget? imageWidget;

    if (widget.imageFile != null) {
      final path = widget.imageFile!.path;
      imageWidget = kIsWeb
          ? Image.network(
              path,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildPlaceholderGraphic(),
            )
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildPlaceholderGraphic(),
            );
    } else if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      imageWidget = Image.file(
        File(widget.imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildPlaceholderGraphic(),
      );
    }

    return Container(
      width: double.infinity,
      height: 130,
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageWidget ?? _buildPlaceholderGraphic(),
          // Provenance Badge top-left (Honest data source, no Gemini confidence percentage)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isAdvanced
                    ? const Color(0xE6FF8A3D) // rgba(255, 138, 61, 0.9)
                    : const Color(0xD90E8F5E), // rgba(14, 143, 94, 0.85)
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _isAdvanced ? '✨ AI ước tính' : '⚖️ Dữ liệu tham chiếu',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderGraphic() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1F1A), Color(0xFF1A241E)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 44,
          color: Color(0xFF666666),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLowConfidence = _current.lowConfidence;

    return PopScope(
      canPop: !_saving,
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: _bgSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: _borderStrong, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sheet Handle
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

                  // Top Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Kiểm tra món ăn',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        icon: const Icon(Icons.close, color: _textSecondary, size: 20),
                        onPressed: _saving ? null : () => Navigator.of(context).pop(null),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Hero Dish Card with Image & Provenance Badge
                  _buildDishHeroImage(),
                  const SizedBox(height: 12),

                  // Low Confidence Warning (Neutral, no blurry assumption)
                  if (isLowConfidence) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x1ACF6679),
                        border: Border.all(color: const Color(0x66CF6679)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: _errorColor,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '⚠️ Mức độ nhận diện thấp — vui lòng kiểm tra lại món ăn và số gram.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFFB3BA),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Save Error Banner if present
                  if (_saveError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x1ACF6679),
                        border: Border.all(color: const Color(0x66CF6679)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: _errorColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _saveError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFFB3BA),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Food Title & Portion Overview
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          _current.foodName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_grams.toStringAsFixed(0)}g • ${_current.calories.toStringAsFixed(0)} kcal',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),

                  // Top 3 Relabel suggestions if present
                  if (_current.top3.length > 1) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Không đúng? Chọn lại từ gợi ý:',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _current.top3.map((pred) {
                        final isSelected = (_selectedLabel == pred.label ||
                            (_selectedLabel == null && pred.label == _current.foodLabel));
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _confirmedData != null ? null : () => _onRelabel(pred),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected ? _brandPrimaryLight : _bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? _brandPrimary : _borderSubtle,
                              ),
                            ),
                            child: Text(
                              pred.foodName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected ? _brandPrimary : _textSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Grams Slider & Stepper
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _bgCanvas,
                      border: Border.all(color: _borderSubtle),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'KHỐI LƯỢNG',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '${_grams.toStringAsFixed(0)}g',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _brandPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _brandPrimary,
                            inactiveTrackColor: _borderStrong,
                            thumbColor: _brandPrimary,
                            overlayColor: _brandPrimaryLight,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: _grams.clamp(10.0, 500.0),
                            min: 10,
                            max: 500,
                            divisions: 49,
                            onChanged: _confirmedData == null ? _onGramsChanged : null,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('10g', style: TextStyle(fontSize: 10, color: _textMuted)),
                              Text('250g', style: TextStyle(fontSize: 10, color: _textMuted)),
                              Text('500g', style: TextStyle(fontSize: 10, color: _textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Dynamic Macro Cards Grid (4 Columns)
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                          decoration: BoxDecoration(
                            color: _bgCard,
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _current.calories.toStringAsFixed(0),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'KCAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                          decoration: BoxDecoration(
                            color: _bgCard,
                            border: Border.all(color: _borderSubtle),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_current.protein.toStringAsFixed(1)}g',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _proteinColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'ĐẠM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                          decoration: BoxDecoration(
                            color: _bgCard,
                            border: Border.all(color: _borderSubtle),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_current.carbs.toStringAsFixed(1)}g',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _carbsColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'CARB',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                          decoration: BoxDecoration(
                            color: _bgCard,
                            border: Border.all(color: _borderSubtle),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_current.fat.toStringAsFixed(1)}g',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _fatColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'BÉO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Provenance Transparency Bar & Explanation
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      border: Border.all(color: _borderSubtle),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: RichText(
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(fontSize: 11, color: _textSecondary),
                              children: [
                                const TextSpan(text: 'Nguồn số liệu: '),
                                TextSpan(
                                  text: _isAdvanced ? 'AI ước tính' : 'Dữ liệu tham chiếu',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _isAdvanced ? _aiAccent : _brandPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() =>
                              _showProvenanceExplanation = !_showProvenanceExplanation),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Giải thích',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _isAdvanced ? _aiAccent : _brandPrimary,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.info_outline,
                                  size: 12,
                                  color: _isAdvanced ? _aiAccent : _brandPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showProvenanceExplanation) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        border: Border.all(color: _borderStrong),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isAdvanced
                            ? 'Chỉ số calo và macro do AI ước lượng từ hình ảnh thực phẩm. Vui lòng kiểm tra và điều chỉnh gram theo thực tế đĩa ăn.'
                            : 'Dinh dưỡng được tra cứu từ cơ sở dữ liệu tham chiếu theo số gram được phân loại.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Meal Type Row (Sáng, Trưa, Tối, Phụ)
                  Row(
                    children: MealType.values.map((type) {
                      final isSelected = _mealType == type;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _confirmedData == null
                                ? () => setState(() => _mealType = type)
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? _bgSurface : _bgCard,
                                border: Border.all(
                                  color: isSelected ? _brandPrimary : _borderSubtle,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                type.shortLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? _brandPrimary : _textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _brandPrimary.withOpacity(0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving || !_retryAllowed ? null : _confirm,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _saveError != null ? 'Thử lưu lại' : 'Lưu bữa này',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textSecondary,
                        side: const BorderSide(color: _borderSubtle),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving ? null : () => Navigator.of(context).pop(null),
                      child: const Text(
                        'Huỷ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MealLogData {
  final String foodName;
  final String foodLabel;
  final String mealType;
  final double grams;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final String loggedAt;

  const MealLogData({
    required this.foodName,
    required this.foodLabel,
    required this.mealType,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.loggedAt,
  });
}

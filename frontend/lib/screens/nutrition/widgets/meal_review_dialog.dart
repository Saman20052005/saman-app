// lib/screens/nutrition/widgets/meal_review_dialog.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/app_theme.dart';
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

class _MealReviewColors {
  const _MealReviewColors({
    required this.isDark,
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgCard,
    required this.borderSubtle,
    required this.borderStrong,
    required this.brandPrimary,
    required this.brandPrimaryLight,
    required this.onBrandPrimary,
    required this.aiAccent,
    required this.proteinColor,
    required this.carbsColor,
    required this.fatColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.errorColor,
    required this.errorBannerBg,
    required this.errorBannerBorder,
    required this.errorBannerText,
  });

  final bool isDark;
  final Color bgCanvas;
  final Color bgSurface;
  final Color bgCard;
  final Color borderSubtle;
  final Color borderStrong;
  final Color brandPrimary;
  final Color brandPrimaryLight;
  final Color onBrandPrimary;
  final Color aiAccent;
  final Color proteinColor;
  final Color carbsColor;
  final Color fatColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color errorColor;
  final Color errorBannerBg;
  final Color errorBannerBorder;
  final Color errorBannerText;

  factory _MealReviewColors.of(BuildContext context) {
    final palette = SamanPalette.of(context);
    if (palette.isDark) {
      return const _MealReviewColors(
        isDark: true,
        bgCanvas: Color(0xFF0C0D0E),
        bgSurface: Color(0xFF16171B),
        bgCard: Color(0xFF1E2026),
        borderSubtle: Color(0xFF26282F),
        borderStrong: Color(0xFF383A42),
        brandPrimary: Color(0xFF10B981),
        brandPrimaryLight: Color(0x2610B981),
        onBrandPrimary: Color(0xFF052E16),
        aiAccent: Color(0xFFFF8A3D),
        proteinColor: Color(0xFF4D96FF),
        carbsColor: Color(0xFFFFD93D),
        fatColor: Color(0xFFFF6B6B),
        textPrimary: Color(0xFFF9FAFB),
        textSecondary: Color(0xFF9CA3AF),
        textMuted: Color(0xFF9CA3AF),
        errorColor: Color(0xFFCF6679),
        errorBannerBg: Color(0x1ACF6679),
        errorBannerBorder: Color(0x66CF6679),
        errorBannerText: Color(0xFFFFB3BA),
      );
    }
    return _MealReviewColors(
      isDark: false,
      bgCanvas: palette.canvas,
      bgSurface: palette.surface,
      bgCard: palette.surfaceElevated,
      borderSubtle: palette.border,
      borderStrong: const Color(0xFFCBD5E1),
      brandPrimary: palette.accent,
      brandPrimaryLight: const Color(0x1F059669),
      onBrandPrimary: palette.onAccent,
      aiAccent: const Color(0xFFD97706),
      proteinColor: const Color(0xFF2563EB),
      carbsColor: const Color(0xFFD97706),
      fatColor: const Color(0xFFDC2626),
      textPrimary: palette.textPrimary,
      textSecondary: palette.textSecondary,
      textMuted: palette.textSecondary,
      errorColor: palette.danger,
      errorBannerBg: const Color(0xFFFEF2F2),
      errorBannerBorder: const Color(0xFFFECACA),
      errorBannerText: const Color(0xFFB91C1C),
    );
  }
}

class _IngredientBaseline {
  final double calPerG;
  final double proPerG;
  final double carbPerG;
  final double fatPerG;

  const _IngredientBaseline({
    required this.calPerG,
    required this.proPerG,
    required this.carbPerG,
    required this.fatPerG,
  });

  factory _IngredientBaseline.fromItem(IngredientItem item) {
    final g = item.portionGrams;
    if (g <= 0) {
      return const _IngredientBaseline(
        calPerG: 0,
        proPerG: 0,
        carbPerG: 0,
        fatPerG: 0,
      );
    }
    return _IngredientBaseline(
      calPerG: item.calories / g,
      proPerG: item.protein / g,
      carbPerG: item.carbs / g,
      fatPerG: item.fat / g,
    );
  }
}

class _IngredientEntry {
  IngredientItem item;
  final _IngredientBaseline baseline;

  _IngredientEntry(this.item, this.baseline);
}

class _MealReviewDialogState extends State<MealReviewDialog> {

  late AIAnalysisResult _current;
  late double _grams;
  late List<_IngredientEntry> _ingredientEntries;
  final List<_IngredientEntry> _removedEntries = [];
  MealType _mealType = MealType.lunch;
  String? _selectedLabel;
  bool _saving = false;
  String? _saveError;
  bool _retryAllowed = true;
  MealLogData? _confirmedData;
  bool _showProvenanceExplanation = false;

  bool get _isAdvanced =>
      _current.nutritionSource.toLowerCase().contains('gemini');

  List<IngredientItem> get _ingredients =>
      _ingredientEntries.map((e) => e.item).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _current = widget.result;
    _grams = widget.result.grams;
    _selectedLabel = widget.result.foodLabel;
    _initIngredientsFrom(_current);

    final hour = DateTime.now().hour;
    _mealType = hour < 10
        ? MealType.breakfast
        : hour < 14
            ? MealType.lunch
            : hour < 19
                ? MealType.dinner
                : MealType.snack;
  }

  void _initIngredientsFrom(AIAnalysisResult result) {
    _ingredientEntries = result.ingredients
        .map((item) => _IngredientEntry(item, _IngredientBaseline.fromItem(item)))
        .toList();
    _removedEntries.clear();
  }

  void _recalculateFromIngredients() {
    if (_ingredientEntries.isEmpty) return;
    final oldGrams = _grams;
    double totalGrams = 0;
    double totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    for (final entry in _ingredientEntries) {
      final item = entry.item;
      totalGrams += item.portionGrams;
      totalCalories += item.calories;
      totalProtein += item.protein;
      totalCarbs += item.carbs;
      totalFat += item.fat;
    }

    final double? updatedFiber = _current.fiber == null
        ? null
        : (oldGrams > 0 ? _current.fiber! * (totalGrams / oldGrams) : _current.fiber);

    _grams = totalGrams;
    _current = _current.copyWith(
      grams: totalGrams,
      calories: totalCalories,
      protein: totalProtein,
      carbs: totalCarbs,
      fat: totalFat,
      fiber: updatedFiber,
      ingredients: _ingredients,
    );
  }

  void _onGramsChanged(double newGrams) {
    setState(() {
      _confirmedData = null;
      if (_ingredientEntries.isNotEmpty) {
        final oldTotalGrams = _ingredientEntries.fold<double>(
          0,
          (sum, entry) => sum + entry.item.portionGrams,
        );
        if (oldTotalGrams > 0) {
          final scale = newGrams / oldTotalGrams;
          for (final entry in _ingredientEntries) {
            final scaledGrams = (entry.item.portionGrams * scale).clamp(1.0, 5000.0);
            final b = entry.baseline;
            entry.item = IngredientItem(
              name: entry.item.name,
              portionGrams: scaledGrams,
              calories: b.calPerG * scaledGrams,
              protein: b.proPerG * scaledGrams,
              carbs: b.carbPerG * scaledGrams,
              fat: b.fatPerG * scaledGrams,
              confidence: entry.item.confidence,
            );
          }
          _recalculateFromIngredients();
          return;
        }
      }
      _grams = newGrams;
      _current = _current.withGrams(newGrams);
    });
  }

  void _onUpdateIngredientGrams(int index, double newGrams) {
    if (index < 0 || index >= _ingredientEntries.length) return;
    final clampedGrams = newGrams.clamp(5.0, 1500.0);
    setState(() {
      _confirmedData = null;
      final entry = _ingredientEntries[index];
      final oldItem = entry.item;
      final b = entry.baseline;
      if (oldItem.portionGrams > 0) {
        entry.item = IngredientItem(
          name: oldItem.name,
          portionGrams: clampedGrams,
          calories: b.calPerG * clampedGrams,
          protein: b.proPerG * clampedGrams,
          carbs: b.carbPerG * clampedGrams,
          fat: b.fatPerG * clampedGrams,
          confidence: oldItem.confidence,
        );
      } else {
        entry.item = IngredientItem(
          name: oldItem.name,
          portionGrams: clampedGrams,
          calories: oldItem.calories,
          protein: oldItem.protein,
          carbs: oldItem.carbs,
          fat: oldItem.fat,
          confidence: oldItem.confidence,
        );
      }
      _recalculateFromIngredients();
    });
  }

  void _onRemoveIngredient(int index) {
    if (_ingredientEntries.length <= 1) return;
    if (index < 0 || index >= _ingredientEntries.length) return;
    setState(() {
      _confirmedData = null;
      final removed = _ingredientEntries.removeAt(index);
      _removedEntries.add(removed);
      _recalculateFromIngredients();
    });
  }

  void _onUndoRemoveIngredient() {
    if (_removedEntries.isEmpty) return;
    setState(() {
      _confirmedData = null;
      final restored = _removedEntries.removeLast();
      _ingredientEntries.add(restored);
      _recalculateFromIngredients();
    });
  }

  void _onRelabel(FoodPrediction selected) {
    setState(() {
      _confirmedData = null;
      _selectedLabel = selected.label;
      _current = _current.withLabel(selected).withGrams(_grams);
      _initIngredientsFrom(_current);
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
      ingredients: List.unmodifiable(_ingredients),
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

  Widget _buildDishHeroImage(_MealReviewColors c) {
    Widget? imageWidget;

    if (widget.imageFile != null) {
      final path = widget.imageFile!.path;
      imageWidget = kIsWeb
          ? Image.network(
              path,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildPlaceholderGraphic(c),
            )
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildPlaceholderGraphic(c),
            );
    } else if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      imageWidget = Image.file(
        File(widget.imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildPlaceholderGraphic(c),
      );
    }

    return Container(
      width: double.infinity,
      height: 130,
      decoration: BoxDecoration(
        color: c.isDark ? const Color(0xFF252525) : c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageWidget ?? _buildPlaceholderGraphic(c),
          // Provenance Badge top-left (Honest data source, no Gemini confidence percentage)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.isDark
                    ? (_isAdvanced
                        ? const Color(0xE6FF8A3D)
                        : const Color(0xE610B981))
                    : (_isAdvanced
                        ? const Color(0xE6C2410C)
                        : const Color(0xE6047857)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(c.isDark ? 0.4 : 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _isAdvanced ? '✨ AI ước tính' : '⚖️ Dữ liệu tham chiếu',
                style: TextStyle(
                  color: c.isDark
                      ? (_isAdvanced
                          ? const Color(0xFF0C0D0E)
                          : const Color(0xFF052E16))
                      : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderGraphic(_MealReviewColors c) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.isDark
              ? const [Color(0xFF2B1F1A), Color(0xFF1A241E)]
              : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 44,
          color: c.isDark ? const Color(0xFF666666) : c.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _MealReviewColors.of(context);
    final isLowConfidence = _current.lowConfidence;

    return PopScope(
      canPop: !_saving,
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: c.bgSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: c.borderStrong, width: 1),
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
                        color: c.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Top Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kiểm tra món ăn',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                        onPressed: _saving ? null : () => Navigator.of(context).pop(null),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Hero Dish Card with Image & Provenance Badge
                  _buildDishHeroImage(c),
                  const SizedBox(height: 12),

                  // Low Confidence Warning (Neutral, no blurry assumption)
                  if (isLowConfidence) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.errorBannerBg,
                        border: Border.all(color: c.errorBannerBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: c.errorColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '⚠️ Mức độ nhận diện thấp — vui lòng kiểm tra lại món ăn và số gram.',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.errorBannerText,
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
                        color: c.errorBannerBg,
                        border: Border.all(color: c.errorBannerBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: c.errorColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _saveError!,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.errorBannerText,
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_grams.toStringAsFixed(0)}g • ${_current.calories.toStringAsFixed(0)} kcal',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  // Top 3 Relabel suggestions if present
                  if (_current.top3.length > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Không đúng? Chọn lại từ gợi ý:',
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textMuted,
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
                          onTap: _saving ? null : () => _onRelabel(pred),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected ? c.brandPrimaryLight : c.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? c.brandPrimary : c.borderSubtle,
                              ),
                            ),
                            child: Text(
                              pred.foodName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected ? c.brandPrimary : c.textSecondary,
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
                      color: c.bgCanvas,
                      border: Border.all(color: c.borderSubtle),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'KHỐI LƯỢNG',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '${_grams.toStringAsFixed(0)}g',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: c.brandPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: c.brandPrimary,
                            inactiveTrackColor: c.borderStrong,
                            thumbColor: c.brandPrimary,
                            overlayColor: c.brandPrimaryLight,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          ),
                          child: Builder(
                            builder: (context) {
                              final sliderMax = math.max(500.0, _grams);
                              final divisions =
                                  ((sliderMax - 10.0) / 10.0).round().clamp(1, 200);
                              return Slider(
                                value: _grams.clamp(10.0, sliderMax),
                                min: 10,
                                max: sliderMax,
                                divisions: divisions,
                                onChanged: _saving ? null : _onGramsChanged,
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('10g', style: TextStyle(fontSize: 10, color: c.textMuted)),
                              Text('250g', style: TextStyle(fontSize: 10, color: c.textMuted)),
                              Text(
                                '${math.max(500.0, _grams).toStringAsFixed(0)}g',
                                style: TextStyle(fontSize: 10, color: c.textMuted),
                              ),
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
                            color: c.bgCard,
                            border: Border.all(
                              color: c.isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : c.borderSubtle,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _current.calories.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'KCAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: c.textSecondary,
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
                            color: c.bgCard,
                            border: Border.all(color: c.borderSubtle),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_current.protein.toStringAsFixed(1)}g',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.proteinColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ĐẠM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: c.textSecondary,
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
                            color: c.bgCard,
                            border: Border.all(color: c.borderSubtle),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_current.carbs.toStringAsFixed(1)}g',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.carbsColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'CARB',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: c.textSecondary,
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
                            color: c.bgCard,
                            border: Border.all(color: c.borderSubtle),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_current.fat.toStringAsFixed(1)}g',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.fatColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'BÉO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_current.fiber != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: c.bgCard,
                          border: Border.all(color: c.borderSubtle),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Chất xơ  ${_current.fiber!.toStringAsFixed(1)}g',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_ingredientEntries.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    IngredientReviewSection(
                      ingredients: _ingredients,
                      onRemove: _saving ? null : _onRemoveIngredient,
                      onUpdateGrams: _saving ? null : _onUpdateIngredientGrams,
                      onUndo: _saving ? null : _onUndoRemoveIngredient,
                      canUndo: _removedEntries.isNotEmpty,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Provenance Transparency Bar & Explanation
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.isDark
                          ? Colors.white.withOpacity(0.03)
                          : c.bgCard,
                      border: Border.all(color: c.borderSubtle),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: RichText(
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: TextStyle(fontSize: 11, color: c.textSecondary),
                              children: [
                                const TextSpan(text: 'Nguồn số liệu: '),
                                TextSpan(
                                  text: _isAdvanced ? 'AI ước tính' : 'Dữ liệu tham chiếu',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _isAdvanced ? c.aiAccent : c.brandPrimary,
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
                                    color: _isAdvanced ? c.aiAccent : c.brandPrimary,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.info_outline,
                                  size: 12,
                                  color: _isAdvanced ? c.aiAccent : c.brandPrimary,
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
                        color: c.isDark ? const Color(0xFF222222) : c.bgCard,
                        border: Border.all(color: c.borderStrong),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isAdvanced
                            ? 'Chỉ số calo và macro do AI ước lượng từ hình ảnh thực phẩm. Vui lòng kiểm tra và điều chỉnh gram theo thực tế đĩa ăn.'
                            : 'Dinh dưỡng được tra cứu từ cơ sở dữ liệu tham chiếu theo số gram được phân loại.',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.textSecondary,
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
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      _confirmedData = null;
                                      _mealType = type;
                                    }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? c.bgSurface : c.bgCard,
                                border: Border.all(
                                  color: isSelected ? c.brandPrimary : c.borderSubtle,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                type.shortLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? c.brandPrimary : c.textSecondary,
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
                        backgroundColor: c.brandPrimary,
                        foregroundColor: c.onBrandPrimary,
                        disabledBackgroundColor: c.brandPrimary.withOpacity(0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving || !_retryAllowed ? null : _confirm,
                      child: _saving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.onBrandPrimary,
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
                        foregroundColor: c.textSecondary,
                        side: BorderSide(color: c.borderSubtle),
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

class IngredientReviewSection extends StatelessWidget {
  final List<IngredientItem> ingredients;
  final ValueChanged<int>? onRemove;
  final void Function(int index, double newGrams)? onUpdateGrams;
  final VoidCallback? onUndo;
  final bool canUndo;

  const IngredientReviewSection({
    super.key,
    required this.ingredients,
    this.onRemove,
    this.onUpdateGrams,
    this.onUndo,
    this.canUndo = false,
  });

  Future<void> _showEditGramsDialog(
    BuildContext context,
    int index,
    IngredientItem ingredient,
  ) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _EditGramsDialog(
        ingredientName: ingredient.name,
        initialGrams: ingredient.portionGrams,
      ),
    );
    if (result != null) {
      onUpdateGrams?.call(index, result.clamp(5.0, 1500.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _MealReviewColors.of(context);
    final canRemove = ingredients.length > 1 && onRemove != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.isDark ? const Color(0xFF242424) : c.bgCard,
        border: Border.all(
          color: c.isDark ? const Color(0xFF2A2A2A) : c.borderSubtle,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Thành phần ước tính',
                  style: TextStyle(
                    color: c.isDark ? const Color(0xFFF0F0F0) : c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canUndo && onUndo != null)
                InkWell(
                  key: const ValueKey('ingredient_undo_btn'),
                  onTap: onUndo,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.brandPrimaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.brandPrimary.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.undo_rounded, size: 13, color: c.brandPrimary),
                        const SizedBox(width: 4),
                        Text(
                          'Hoàn tác',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.brandPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < ingredients.length; i++) ...[
            if (i > 0)
              Divider(
                height: 12,
                thickness: 0.8,
                color: c.borderSubtle,
              ),
            _IngredientRow(
              index: i,
              ingredient: ingredients[i],
              colors: c,
              canRemove: canRemove,
              onRemove: canRemove ? () => onRemove!(i) : null,
              onDecrement: onUpdateGrams != null && ingredients[i].portionGrams > 5.0
                  ? () => onUpdateGrams!(
                        i,
                        (ingredients[i].portionGrams - 25.0).clamp(5.0, 1500.0),
                      )
                  : null,
              onIncrement: onUpdateGrams != null && ingredients[i].portionGrams < 1500.0
                  ? () => onUpdateGrams!(
                        i,
                        (ingredients[i].portionGrams + 25.0).clamp(5.0, 1500.0),
                      )
                  : null,
              onEditGrams: onUpdateGrams != null
                  ? () => _showEditGramsDialog(context, i, ingredients[i])
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final int index;
  final IngredientItem ingredient;
  final _MealReviewColors colors;
  final bool canRemove;
  final VoidCallback? onRemove;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final VoidCallback? onEditGrams;

  const _IngredientRow({
    required this.index,
    required this.ingredient,
    required this.colors,
    required this.canRemove,
    this.onRemove,
    this.onDecrement,
    this.onIncrement,
    this.onEditGrams,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ingredient.name,
                      style: TextStyle(
                        color: c.isDark ? const Color(0xFFF0F0F0) : c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ingredient.portionGrams.toStringAsFixed(0)}g · ${ingredient.calories.toStringAsFixed(0)} kcal',
                      style: TextStyle(
                        color: c.isDark ? const Color(0xFFAAAAAA) : c.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('ingredient_remove_$index'),
                tooltip: canRemove ? 'Xóa nguyên liệu' : 'Cần ít nhất 1 nguyên liệu',
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: canRemove
                      ? c.textSecondary
                      : c.textSecondary.withOpacity(0.3),
                ),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ],
          ),
          if (onDecrement != null || onIncrement != null || onEditGrams != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _StepChip(
                  key: ValueKey('ingredient_dec_$index'),
                  label: '-25g',
                  colors: c,
                  onTap: onDecrement,
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: ValueKey('ingredient_grams_$index'),
                  onTap: onEditGrams,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.borderStrong),
                    ),
                    child: Text(
                      '${ingredient.portionGrams.toStringAsFixed(0)}g',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _StepChip(
                  key: ValueKey('ingredient_inc_$index'),
                  label: '+25g',
                  colors: c,
                  onTap: onIncrement,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đ ${ingredient.protein.toStringAsFixed(1)} · C ${ingredient.carbs.toStringAsFixed(1)} · B ${ingredient.fat.toStringAsFixed(1)}',
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final _MealReviewColors colors;
  final VoidCallback? onTap;

  const _StepChip({
    super.key,
    required this.label,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: enabled ? colors.bgSurface : colors.bgSurface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? colors.borderSubtle : colors.borderSubtle.withOpacity(0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: enabled ? colors.textPrimary : colors.textMuted.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}

class _EditGramsDialog extends StatefulWidget {
  final String ingredientName;
  final double initialGrams;

  const _EditGramsDialog({
    required this.ingredientName,
    required this.initialGrams,
  });

  @override
  State<_EditGramsDialog> createState() => _EditGramsDialogState();
}

class _EditGramsDialogState extends State<_EditGramsDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialGrams.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      setState(() {
        _errorText = 'Vui lòng nhập số gram > 0';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Chỉnh khối lượng',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.ingredientName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('ingredient_grams_input'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Số gram (g)',
              suffixText: 'g',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          key: const ValueKey('ingredient_grams_confirm_btn'),
          onPressed: _submit,
          child: const Text('Xong'),
        ),
      ],
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
  final List<IngredientItem> ingredients;

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
    this.ingredients = const [],
  });
}

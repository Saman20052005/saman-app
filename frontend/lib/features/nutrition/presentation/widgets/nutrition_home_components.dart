import 'package:flutter/material.dart';

import '../../../../config/app_translations.dart';
import '../../../../models/nutrition_model.dart';
import '../../../../theme/nutrition_home_theme.dart';

export 'nutrition_quick_log_and_usuals.dart';

class NutritionFoodHero extends StatelessWidget {
  const NutritionFoodHero(
      {required this.onReport,
      required this.membershipBadge,
      this.asset = foodAsset,
      super.key});
  static const foodAsset = 'assets/images/nutrition/food-hero.png';
  final VoidCallback onReport;
  final Widget membershipBadge;
  final String asset;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: Stack(children: [
        Positioned.fill(
            child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => ColoredBox(color: s.canvas),
        )),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            s.heroShadow,
            s.canvas.withOpacity(0.8),
            Colors.transparent
          ], stops: const [
            0,
            0.42,
            1
          ]),
        ))),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, s.canvas],
              stops: const [0.55, 1]),
        ))),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: membershipBadge)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  style: s.secondaryAction,
                  onPressed: onReport,
                  icon:
                      Icon(Icons.bar_chart_rounded, size: 16, color: s.accent),
                  label: const Text('Report')),
            ]),
            const SizedBox(height: 25),
            Text('Nutrition', style: s.title),
            const SizedBox(height: 6),
            Text('Fuel, log & track your day', style: s.caption),
          ]),
        ),
      ]),
    );
  }
}

class NutritionMembershipBadge extends StatelessWidget {
  const NutritionMembershipBadge(
      {required this.label, required this.onPressed, super.key});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
          foregroundColor: s.accent,
          backgroundColor: s.surface,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: s.pillRadius),
          side: BorderSide(color: s.border),
          textStyle: s.label),
      child: Text(label, textAlign: TextAlign.start),
    );
  }
}

class NutritionQuickActions extends StatelessWidget {
  const NutritionQuickActions(
      {required this.onLogMeal, required this.onScanFood, super.key});
  final VoidCallback onLogMeal, onScanFood;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return LayoutBuilder(builder: (context, box) {
      final log = FilledButton.icon(
          style: s.primaryAction,
          onPressed: onLogMeal,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Log meal'));
      final scan = OutlinedButton.icon(
          style: s.secondaryAction,
          onPressed: onScanFood,
          icon: const Icon(Icons.camera_alt_outlined, size: 20),
          label: const Text('Scan food'));
      return box.maxWidth < 340 &&
              MediaQuery.textScalerOf(context).scale(14) > 20
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [log, const SizedBox(height: 10), scan])
          : Row(children: [
              Expanded(child: log),
              const SizedBox(width: 12),
              Expanded(child: scan)
            ]);
    });
  }
}

class NutritionMealsHeading extends StatelessWidget {
  const NutritionMealsHeading({required this.onMealStory, super.key});
  final VoidCallback onMealStory;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).extension<NutritionHomeStyle>() ??
        const NutritionHomeStyle();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            context.tr('logged_meals_heading'),
            style: s.section.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: s.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onMealStory,
          style: TextButton.styleFrom(
            foregroundColor: s.accent,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            minimumSize: const Size(48, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.auto_stories_outlined, size: 16),
          label: Text(
            context.tr('meal_story'),
            style: TextStyle(
              color: s.accent,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class NutritionEmptyMeals extends StatelessWidget {
  const NutritionEmptyMeals({
    this.selectedDate,
    this.asset = defaultAsset,
    super.key,
  });

  final DateTime? selectedDate;
  final String asset;
  static const defaultAsset =
      'assets/images/nutrition/logged_meals_empty_toast_egg.webp';

  bool _isToday(DateTime? date) {
    if (date == null) return true;
    final nowVn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final dateVn = date.isUtc ? date.add(const Duration(hours: 7)) : date;
    if (dateVn.year == nowVn.year &&
        dateVn.month == nowVn.month &&
        dateVn.day == nowVn.day) {
      return true;
    }
    final localNow = DateTime.now();
    return date.year == localNow.year &&
        date.month == localNow.month &&
        date.day == localNow.day;
  }

  @override
  Widget build(BuildContext context) {
    return NutritionHomeTheme(
      child: Builder(
        builder: (context) {
          final s = Theme.of(context).extension<NutritionHomeStyle>() ??
              const NutritionHomeStyle();
          final isToday = _isToday(selectedDate);
          final cardRadius = BorderRadius.circular(22);

          return LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final isLargeText = textScaler.scale(14) > 20;
              final isNarrow = constraints.maxWidth < 340;
              final hideSupporting = isNarrow && isLargeText;

              return ClipRRect(
                borderRadius: cardRadius,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: cardRadius,
                    border: Border.all(color: s.border, width: 1),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 185),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            asset,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            excludeFromSemantics: true,
                            errorBuilder: (_, __, ___) =>
                                ColoredBox(color: s.surface),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: const [0.0, 0.40, 0.70, 1.0],
                                colors: [
                                  s.surface,
                                  s.surface.withOpacity(0.96),
                                  s.surface.withOpacity(0.60),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.75, 1.0],
                                colors: [
                                  s.surface.withOpacity(0.40),
                                  Colors.transparent,
                                  s.surface.withOpacity(0.40),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 18),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (isLargeText || isNarrow)
                                  ? double.infinity
                                  : constraints.maxWidth * 0.65,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: s.isDark
                                        ? const Color(0x3326282F)
                                        : s.track.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: s.isDark
                                            ? const Color(0x44353842)
                                            : s.border,
                                        width: 1),
                                  ),
                                  child: Text(
                                    context.tr('empty_meals_eyebrow'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: s.isDark
                                          ? const Color(0xFF94979E)
                                          : s.muted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  context.tr('empty_meals_title'),
                                  style: s.strong.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    height: 1.18,
                                    color: s.ink,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isToday
                                      ? context.tr('empty_meals_today')
                                      : context.tr('empty_meals_other_day'),
                                  style: s.body.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: s.isDark
                                        ? const Color(0xFFD1D5DB)
                                        : s.muted,
                                    height: 1.3,
                                  ),
                                ),
                                if (!hideSupporting) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    context.tr('empty_meals_supporting'),
                                    style: s.caption.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: s.isDark
                                          ? const Color(0xFF94979E)
                                          : s.muted,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Read-only details from the selected logged entry, never a planned meal.
class NutritionLoggedMealDetails extends StatelessWidget {
  const NutritionLoggedMealDetails({
    required this.entry,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final NutritionLogEntry entry;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).extension<NutritionHomeStyle>() ??
        NutritionHomeStyle(brightness: Theme.of(context).brightness);
    return DefaultTextStyle(
      style: s.body,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: 'Close meal details',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: s.muted),
                ),
              ),
              Text(entry.foodName, style: s.section),
              const SizedBox(height: 12),
              Text('${entry.totalCalories} kcal'),
              Text(
                '${entry.protein.toInt()}g pro · ${entry.carbs.toInt()}g carb · ${entry.fat.toInt()}g fat',
              ),
              for (final food in entry.foods)
                if (food['name'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _FoodDetailRow(food: food, style: s),
                  ),
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (onEdit != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('meal_detail_edit_btn'),
                          onPressed: onEdit,
                          style: s.secondaryAction,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Sửa'),
                        ),
                      ),
                    if (onEdit != null && onDelete != null)
                      const SizedBox(width: 12),
                    if (onDelete != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('meal_detail_delete_btn'),
                          onPressed: onDelete,
                          style: s.secondaryAction.copyWith(
                            foregroundColor: WidgetStatePropertyAll(s.fat),
                            side: WidgetStatePropertyAll(
                              BorderSide(color: s.fat.withOpacity(0.5)),
                            ),
                          ),
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: s.fat),
                          label: const Text('Xóa'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodDetailRow extends StatelessWidget {
  const _FoodDetailRow({required this.food, required this.style});

  final Map<String, dynamic> food;
  final NutritionHomeStyle style;

  @override
  Widget build(BuildContext context) {
    final name = food['name']?.toString() ?? '';
    final grams =
        (food['grams'] ?? food['portion_grams'] ?? food['amount']) as num?;
    final calories = (food['calories'] as num?)?.round();
    final parts = <String>[
      if (grams != null && grams > 0) '${grams.round()}g',
      if (calories != null) '$calories kcal',
    ];
    return Row(
      children: [
        Expanded(child: Text(name, style: style.body)),
        if (parts.isNotEmpty)
          Text(parts.join(' · '), style: style.caption),
      ],
    );
  }
}

class _EditableFoodItem {
  _EditableFoodItem({
    required this.raw,
    required this.gramsKey,
    required this.baseGrams,
    required this.baseCalories,
    required this.baseProtein,
    required this.baseCarbs,
    required this.baseFat,
    required this.currentGrams,
    required this.multiplier,
  });

  final Map<String, dynamic> raw;
  final String? gramsKey;
  final double baseGrams;
  final double baseCalories;
  final double baseProtein;
  final double baseCarbs;
  final double baseFat;
  double currentGrams;
  double multiplier;

  bool get hasGrams => gramsKey != null && baseGrams > 0;

  double get ratio => hasGrams ? (currentGrams / baseGrams) : multiplier;

  int get scaledCalories => (baseCalories * ratio).round();
  double get scaledProtein =>
      double.parse((baseProtein * ratio).toStringAsFixed(1));
  double get scaledCarbs =>
      double.parse((baseCarbs * ratio).toStringAsFixed(1));
  double get scaledFat => double.parse((baseFat * ratio).toStringAsFixed(1));

  Map<String, dynamic> toPayload() {
    final updated = Map<String, dynamic>.from(raw);
    if (hasGrams && gramsKey != null) {
      updated[gramsKey!] =
          currentGrams == currentGrams.roundToDouble()
              ? currentGrams.round()
              : double.parse(currentGrams.toStringAsFixed(1));
    }
    updated['calories'] = scaledCalories;
    updated['protein'] = scaledProtein;
    updated['carbs'] = scaledCarbs;
    updated['fat'] = scaledFat;
    return updated;
  }

  factory _EditableFoodItem.fromMap(Map<String, dynamic> food) {
    String? gramsKey;
    double baseGrams = 0;
    for (final key in const ['grams', 'portion_grams', 'amount']) {
      final val = food[key];
      if (val is num && val > 0) {
        gramsKey = key;
        baseGrams = val.toDouble();
        break;
      }
    }
    return _EditableFoodItem(
      raw: Map<String, dynamic>.from(food),
      gramsKey: gramsKey,
      baseGrams: baseGrams,
      baseCalories: (food['calories'] as num?)?.toDouble() ?? 0,
      baseProtein: (food['protein'] as num?)?.toDouble() ?? 0,
      baseCarbs: (food['carbs'] as num?)?.toDouble() ?? 0,
      baseFat: (food['fat'] as num?)?.toDouble() ?? 0,
      currentGrams: baseGrams,
      multiplier: 1.0,
    );
  }
}

class NutritionEditLoggedMealSheet extends StatefulWidget {
  const NutritionEditLoggedMealSheet({
    required this.entry,
    required this.onSave,
    super.key,
  });

  final NutritionLogEntry entry;
  final Future<bool> Function({
    required String mealType,
    List<Map<String, dynamic>>? foods,
    double? portionMultiplier,
  }) onSave;

  @override
  State<NutritionEditLoggedMealSheet> createState() =>
      _NutritionEditLoggedMealSheetState();
}

class _NutritionEditLoggedMealSheetState
    extends State<NutritionEditLoggedMealSheet> {
  static const _mealTypes = <({String value, String label})>[
    (value: 'breakfast', label: 'Sáng'),
    (value: 'lunch', label: 'Trưa'),
    (value: 'dinner', label: 'Tối'),
    (value: 'snack', label: 'Phụ'),
  ];
  static const _multipliers = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  late String _mealType;
  late List<_EditableFoodItem> _items;
  double _portionMultiplier = 1.0;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initialType = widget.entry.mealType.trim().toLowerCase();
    _mealType = _mealTypes.any((t) => t.value == initialType)
        ? initialType
        : 'breakfast';
    _items = widget.entry.foods
        .map((f) => _EditableFoodItem.fromMap(f))
        .toList();
  }

  int get _previewCalories {
    if (_items.isNotEmpty) {
      return _items.fold<int>(0, (sum, item) => sum + item.scaledCalories);
    }
    return (widget.entry.totalCalories * _portionMultiplier).round();
  }

  double get _previewProtein {
    if (_items.isNotEmpty) {
      return _items.fold<double>(0, (sum, item) => sum + item.scaledProtein);
    }
    return widget.entry.protein * _portionMultiplier;
  }

  double get _previewCarbs {
    if (_items.isNotEmpty) {
      return _items.fold<double>(0, (sum, item) => sum + item.scaledCarbs);
    }
    return widget.entry.carbs * _portionMultiplier;
  }

  double get _previewFat {
    if (_items.isNotEmpty) {
      return _items.fold<double>(0, (sum, item) => sum + item.scaledFat);
    }
    return widget.entry.fat * _portionMultiplier;
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final ok = await widget.onSave(
        mealType: _mealType,
        foods: _items.isNotEmpty
            ? _items.map((e) => e.toPayload()).toList()
            : null,
        portionMultiplier: _items.isEmpty ? _portionMultiplier : null,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Không thể lưu thay đổi. Vui lòng thử lại.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Đã xảy ra lỗi kết nối. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).extension<NutritionHomeStyle>() ??
        NutritionHomeStyle(brightness: Theme.of(context).brightness);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return DefaultTextStyle(
      style: s.body,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sửa bữa ăn',
                      style: s.section,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: s.muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.entry.foodName, style: s.strong),
              const SizedBox(height: 16),
              Text('Bữa ăn', style: s.caption),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _mealTypes)
                    ChoiceChip(
                      key: ValueKey('edit_meal_type_${option.value}'),
                      label: Text(option.label),
                      selected: _mealType == option.value,
                      onSelected: _isSaving
                          ? null
                          : (_) => setState(() => _mealType = option.value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_items.isNotEmpty) ...[
                Text('Khẩu phần từng món', style: s.caption),
                const SizedBox(height: 8),
                for (var i = 0; i < _items.length; i++)
                  _buildFoodEditorRow(i, _items[i], s),
              ] else ...[
                Text('Hệ số khẩu phần', style: s.caption),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mult in _multipliers)
                      ChoiceChip(
                        label: Text('${mult}x'),
                        selected: _portionMultiplier == mult,
                        onSelected: _isSaving
                            ? null
                            : (_) => setState(() => _portionMultiplier = mult),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: s.canvas,
                  borderRadius: s.cardRadius,
                  border: Border.all(color: s.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dự kiến dinh dưỡng', style: s.caption),
                    const SizedBox(height: 6),
                    Text(
                      '$_previewCalories kcal',
                      key: const ValueKey('edit_meal_preview_calories'),
                      style: s.strong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_previewProtein.round()}g pro · ${_previewCarbs.round()}g carb · ${_previewFat.round()}g fat',
                      key: const ValueKey('edit_meal_preview_macros'),
                      style: s.caption,
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: s.caption.copyWith(color: s.fat),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('edit_meal_save_btn'),
                  style: s.primaryAction,
                  onPressed: _isSaving ? null : _handleSave,
                  child: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: s.onAccent,
                          ),
                        )
                      : const Text('Lưu thay đổi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFoodEditorRow(
    int index,
    _EditableFoodItem item,
    NutritionHomeStyle s,
  ) {
    final name = item.raw['name']?.toString() ?? 'Món ${index + 1}';
    final portionLabel = item.hasGrams
        ? '${item.currentGrams.round()}g'
        : '${item.multiplier.toStringAsFixed(2)}x';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: s.imageRadius,
        border: Border.all(color: s.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, style: s.strong),
              ),
              if (_items.length > 1)
                IconButton(
                  key: ValueKey('edit_food_remove_$index'),
                  tooltip: 'Xóa món',
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _items.removeAt(index)),
                  icon: Icon(Icons.close, size: 18, color: s.muted),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$portionLabel · ${item.scaledCalories} kcal · ${item.scaledProtein.round()}g pro',
                  style: s.caption,
                ),
              ),
              OutlinedButton(
                key: ValueKey('edit_food_dec_$index'),
                onPressed: _isSaving
                    ? null
                    : () => setState(() {
                          if (item.hasGrams) {
                            item.currentGrams =
                                (item.currentGrams - 25).clamp(25, 5000);
                          } else {
                            item.multiplier =
                                (item.multiplier - 0.25).clamp(0.25, 10.0);
                          }
                        }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(color: s.border),
                ),
                child: Text(item.hasGrams ? '-25g' : '-0.25x'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: ValueKey('edit_food_inc_$index'),
                onPressed: _isSaving
                    ? null
                    : () => setState(() {
                          if (item.hasGrams) {
                            item.currentGrams =
                                (item.currentGrams + 25).clamp(25, 5000);
                          } else {
                            item.multiplier =
                                (item.multiplier + 0.25).clamp(0.25, 10.0);
                          }
                        }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(color: s.border),
                ),
                child: Text(item.hasGrams ? '+25g' : '+0.25x'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

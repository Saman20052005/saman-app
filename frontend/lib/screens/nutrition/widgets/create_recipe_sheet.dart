import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/nutrition/domain/entities/food.dart';
import '../../../features/nutrition/presentation/providers/recipes_supplements_provider.dart';
import '../../../models/nutrition_model.dart';
import '../../../providers/nutrition_provider.dart';

class CreateRecipeSheet extends ConsumerStatefulWidget {
  const CreateRecipeSheet({super.key});

  static Future<RecipeModel?> show(BuildContext context) {
    return showModalBottomSheet<RecipeModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateRecipeSheet(),
    );
  }

  @override
  ConsumerState<CreateRecipeSheet> createState() => _CreateRecipeSheetState();
}

class _CreateRecipeSheetState extends ConsumerState<CreateRecipeSheet> {
  static const Color _sheetBg = Color(0xFF16171B);
  static const Color _cardBg = Color(0xFF1E2026);
  static const Color _borderColor = Color(0xFF26282F);
  static const Color _accentColor = Color(0xFF10B981);
  static const Color _saveBtnColor = Color(0xFFF9FAFB);
  static const Color _textPrimary = Color(0xFFF9FAFB);
  static const Color _textSecondary = Color(0xFF9CA3AF);
  static const Color _errorColor = Color(0xFFEF4444);

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _gramsCtrl = TextEditingController(text: '100');

  Timer? _debounceTimer;
  int _searchRequest = 0;
  bool _isSearching = false;
  String? _searchError;
  List<Food> _searchResults = const [];
  Food? _selectedFood;

  int _servings = 1;
  final List<RecipeIngredientModel> _ingredients = [];

  bool _isSaving = false;
  String? _submitError;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _gramsCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final request = ++_searchRequest;
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchError = null;
        _searchResults = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || request != _searchRequest) return;
      await _executeSearch(trimmed, request);
    });
  }

  Future<void> _executeSearch(String query, int request) async {
    try {
      final repo = ref.read(nutritionRepositoryProvider);
      final results = await repo.searchFoods(query);
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _searchError = null;
      });
    } catch (e) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _searchResults = const [];
        _isSearching = false;
        _searchError = 'Không thể tìm kiếm nguyên liệu: $e';
      });
    }
  }

  void _onSelectFood(Food food) {
    setState(() {
      _selectedFood = food;
      _gramsCtrl.text = '100';
      _submitError = null;
    });
  }

  void _onAddIngredient() {
    final food = _selectedFood;
    if (food == null) return;

    final grams = double.tryParse(_gramsCtrl.text.trim()) ?? 0;
    if (grams <= 0) {
      setState(() {
        _submitError = 'Khối lượng nguyên liệu phải lớn hơn 0g.';
      });
      return;
    }

    final ratio = grams / 100.0;
    final ingredient = RecipeIngredientModel(
      name: food.name,
      quantity: grams,
      unit: 'g',
      calories: food.calories * ratio,
      protein: food.protein * ratio,
      carbs: food.carbs * ratio,
      fat: food.fat * ratio,
    );

    _debounceTimer?.cancel();
    ++_searchRequest;
    _searchCtrl.clear();

    setState(() {
      _ingredients.add(ingredient);
      _selectedFood = null;
      _gramsCtrl.text = '100';
      _searchResults = const [];
      _isSearching = false;
      _searchError = null;
      _submitError = null;
    });
  }

  void _onRemoveIngredient(int index) {
    setState(() {
      _ingredients.removeAt(index);
    });
  }

  double get _totalCalories =>
      _ingredients.fold(0.0, (sum, item) => sum + item.calories);
  double get _totalProtein =>
      _ingredients.fold(0.0, (sum, item) => sum + item.protein);
  double get _totalCarbs =>
      _ingredients.fold(0.0, (sum, item) => sum + item.carbs);
  double get _totalFat =>
      _ingredients.fold(0.0, (sum, item) => sum + item.fat);

  double get _caloriesPerServing =>
      _servings > 0 ? _totalCalories / _servings : 0.0;
  double get _proteinPerServing =>
      _servings > 0 ? _totalProtein / _servings : 0.0;
  double get _carbsPerServing =>
      _servings > 0 ? _totalCarbs / _servings : 0.0;
  double get _fatPerServing =>
      _servings > 0 ? _totalFat / _servings : 0.0;

  Future<void> _handleSaveRecipe() async {
    if (_isSaving) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _submitError = 'Vui lòng nhập tên công thức.';
      });
      return;
    }

    if (_servings < 1) {
      setState(() {
        _submitError = 'Số khẩu phần phải từ 1 trở lên.';
      });
      return;
    }

    if (_ingredients.isEmpty) {
      setState(() {
        _submitError = 'Vui lòng thêm ít nhất 1 nguyên liệu.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _submitError = null;
    });

    final payload = <String, dynamic>{
      'name': name,
      'servings': _servings,
      'ingredients': _ingredients
          .map(
            (item) => <String, dynamic>{
              'name': item.name,
              'quantity': item.quantity,
              'unit': 'g',
              'calories': item.calories.round(),
              'protein': double.parse(item.protein.toStringAsFixed(1)),
              'carbs': double.parse(item.carbs.toStringAsFixed(1)),
              'fat': double.parse(item.fat.toStringAsFixed(1)),
            },
          )
          .toList(),
    };

    try {
      final createdRecipe =
          await ref.read(recipesProvider.notifier).createRecipe(payload);
      if (!mounted) return;

      if (createdRecipe != null) {
        Navigator.of(context).pop(createdRecipe);
      } else {
        final providerError = ref.read(recipesProvider).error;
        setState(() {
          _isSaving = false;
          _submitError = (providerError != null && providerError.isNotEmpty)
              ? providerError
              : 'Không thể lưu công thức. Vui lòng thử lại.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _submitError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: const BoxDecoration(
            color: _sheetBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: _borderColor),
              left: BorderSide(color: _borderColor),
              right: BorderSide(color: _borderColor),
            ),
          ),
          padding: EdgeInsets.fromLTRB(18, 12, 18, 20 + bottomInset),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Tạo công thức mới',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: _textSecondary,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Error Banner
                if (_submitError != null) ...[
                  Container(
                    key: const Key('create_recipe_error_banner'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _errorColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _errorColor.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: _errorColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _submitError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _errorColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Recipe Name TextField
                const Text(
                  'Tên công thức',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('recipe_name_input'),
                  controller: _nameCtrl,
                  onChanged: (_) {
                    if (_submitError != null) {
                      setState(() => _submitError = null);
                    }
                  },
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'VD: Ức gà áp chảo khoai lang',
                    hintStyle: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: _cardBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Servings Stepper
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Số khẩu phần (servings)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          _buildStepperButton(
                            key: const Key('servings_decrement_btn'),
                            icon: Icons.remove,
                            onTap: _servings > 1
                                ? () => setState(() => _servings--)
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              '$_servings',
                              key: const Key('servings_value_text'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                          _buildStepperButton(
                            key: const Key('servings_increment_btn'),
                            icon: Icons.add,
                            onTap: () => setState(() => _servings++),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Add Ingredients Section
                const Text(
                  'Thêm nguyên liệu',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('ingredient_search_input'),
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tìm nguyên liệu (VD: ức gà, cơm, trứng...)',
                    hintStyle: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: _textSecondary,
                      size: 18,
                    ),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _accentColor,
                              ),
                            ),
                          )
                        : (_searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: _textSecondary,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null),
                    isDense: true,
                    filled: true,
                    fillColor: _cardBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accentColor),
                    ),
                  ),
                ),

                if (_searchError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _searchError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _errorColor,
                    ),
                  ),
                ],

                // Compact Search Results List
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: _borderColor,
                      ),
                      itemBuilder: (context, index) {
                        final food = _searchResults[index];
                        final isSelected = _selectedFood?.id == food.id &&
                            _selectedFood?.name == food.name;
                        return InkWell(
                          onTap: () => _onSelectFood(food),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        food.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? _accentColor
                                              : _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${food.calories.round()} kcal / 100g · Đạm ${food.protein.toStringAsFixed(1)}g · Carb ${food.carbs.toStringAsFixed(1)}g · Béo ${food.fat.toStringAsFixed(1)}g',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.add_circle_outline,
                                  color: _accentColor,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // Selected Food Grams Input + Add Button
                if (_selectedFood != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accentColor.withOpacity(0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedFood!.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '${_selectedFood!.calories.round()} kcal / 100g',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: TextField(
                                key: const Key('ingredient_grams_input'),
                                controller: _gramsCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  suffixText: 'g',
                                  suffixStyle: const TextStyle(
                                    color: _textSecondary,
                                    fontSize: 12,
                                  ),
                                  isDense: true,
                                  filled: true,
                                  fillColor: _sheetBg,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        const BorderSide(color: _borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        const BorderSide(color: _accentColor),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 38,
                                child: ElevatedButton(
                                  key: const Key('add_ingredient_btn'),
                                  onPressed: _onAddIngredient,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accentColor,
                                    foregroundColor: const Color(0xFF0C0D0E),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    '+ Thêm nguyên liệu',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Added Ingredients List
                if (_ingredients.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _ingredients.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: _borderColor,
                      ),
                      itemBuilder: (context, index) {
                        final item = _ingredients[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item.name} (${item.quantity.round()}g)',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.calories.round()} kcal · Đạm ${item.protein.toStringAsFixed(1)}g · Carb ${item.carbs.toStringAsFixed(1)}g · Béo ${item.fat.toStringAsFixed(1)}g',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: ValueKey('remove_ingredient_$index'),
                                tooltip: 'Xoá nguyên liệu',
                                onPressed: () => _onRemoveIngredient(index),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: _textSecondary,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Preview Card: Dinh dưỡng / 1 phần (total / servings)
                Container(
                  key: const Key('nutrition_per_serving_card'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Dinh dưỡng / 1 phần',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          Text(
                            'Tổng chia $_servings phần',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMacroMetric(
                              label: 'kcal',
                              value: '${_caloriesPerServing.round()}',
                              isHighlight: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMacroMetric(
                              label: 'Đạm (g)',
                              value: _proteinPerServing.toStringAsFixed(1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMacroMetric(
                              label: 'Carb (g)',
                              value: _carbsPerServing.toStringAsFixed(1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMacroMetric(
                              label: 'Béo (g)',
                              value: _fatPerServing.toStringAsFixed(1),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Save Recipe Button (#F9FAFB)
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('save_recipe_btn'),
                    onPressed: _isSaving ? null : _handleSaveRecipe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _saveBtnColor,
                      foregroundColor: const Color(0xFF0C0D0E),
                      disabledBackgroundColor: _saveBtnColor.withOpacity(0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0C0D0E),
                            ),
                          )
                        : const Text(
                            'Lưu công thức',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
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

  Widget _buildStepperButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF26282F) : _sheetBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? const Color(0xFF383A42) : _borderColor,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? _textPrimary : _textSecondary,
        ),
      ),
    );
  }

  Widget _buildMacroMetric({
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: _sheetBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlight ? _accentColor.withOpacity(0.5) : _borderColor,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isHighlight ? _accentColor : _textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

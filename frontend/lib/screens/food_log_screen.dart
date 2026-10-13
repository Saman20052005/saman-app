import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../features/nutrition/domain/entities/food.dart';
import '../models/food_model.dart';
import '../providers/nutrition_provider.dart';
import '../providers/profile_provider.dart';
import '../services/nutrition_service.dart';

enum FoodLogStep {
  initial,
  searchResults,
  portionReview,
}

class FoodLogScreen extends ConsumerStatefulWidget {
  final String userGoal;
  final DateTime? selectedDate;
  final String? initialMealType;
  final NutritionService? apiService;

  const FoodLogScreen({
    super.key,
    this.userGoal = 'weight_loss',
    this.selectedDate,
    this.initialMealType,
    this.apiService,
  });

  @override
  ConsumerState<FoodLogScreen> createState() => FoodLogScreenState();
}

class FoodLogScreenState extends ConsumerState<FoodLogScreen> {
  @visibleForTesting
  void selectFood(FoodModel food) => _onSelectFood(food);

  @visibleForTesting
  FoodLogStep get currentStep => _currentStep;

  @visibleForTesting
  int get grams => _grams;
  String get selectedMealType => _selectedMealType;

  @visibleForTesting
  void setGramsForTesting(int value) {
    setState(() {
      _grams = value;
      if (value <= 0) {
        _saveError = 'Khẩu phần phải lớn hơn 0g';
      }
    });
  }

  static String? getFoodImageUrl(String foodName) {
    final lower = foodName.toLowerCase();
    if (lower.contains('grilled chicken') || lower.contains('nướng')) {
      return 'https://lh3.googleusercontent.com/aida/AEtjO1Xq89t9QzC5eB7w4Z9M0vKp9Yv1c2X8=s800';
    } else if (lower.contains('boiled chicken') || lower.contains('luộc')) {
      return 'https://lh3.googleusercontent.com/aida/AEtjO1VLKz78bV82w9C8f0M1vN8L09Y7=s800';
    } else if (lower.contains('thigh') || lower.contains('đùi')) {
      return 'https://lh3.googleusercontent.com/aida/AEtjO1Xk2QZ79cM4w8N7Y0P1=s800';
    } else if (lower.contains('shredded') || lower.contains('xé')) {
      return 'https://lh3.googleusercontent.com/aida/AEtjO1X7V8cM91_Z2QZ8=s800';
    } else if (lower.contains('chicken') || lower.contains('gà')) {
      return 'https://lh3.googleusercontent.com/aida/AEtjO1Xq89t9QzC5eB7w4Z9M0vKp9Yv1c2X8=s800';
    } else if (lower.contains('rice') || lower.contains('cơm')) {
      return 'https://images.unsplash.com/photo-1516684732162-798a0062be99?w=400';
    } else if (lower.contains('oat') || lower.contains('yến mạch')) {
      return 'https://images.unsplash.com/photo-1586444248902-2f64eddc13df?w=400';
    } else if (lower.contains('yogurt') || lower.contains('sữa chua')) {
      return 'https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400';
    } else if (lower.contains('beef') || lower.contains('bò')) {
      return 'https://images.unsplash.com/photo-1544025162-d76694265947?w=400';
    } else if (lower.contains('egg') || lower.contains('trứng')) {
      return 'https://images.unsplash.com/photo-1506976785307-8732e854ad03?w=400';
    } else if (lower.contains('salmon') || lower.contains('fish') || lower.contains('cá')) {
      return 'https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=400';
    }
    return null;
  }

  Widget _buildFoodThumbnail(String foodName, {double size = 56, double borderRadius = 12}) {
    final imageUrl = getFoodImageUrl(foodName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF212328),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.restaurant_outlined,
                  size: 22,
                  color: Color(0xFF10B981),
                ),
              ),
            )
          : const Center(
              child: Icon(
                Icons.restaurant_outlined,
                size: 22,
                color: Color(0xFF10B981),
              ),
            ),
    );
  }

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final NutritionService _defaultApiService = NutritionService();
  NutritionService get _apiService => widget.apiService ?? _defaultApiService;

  FoodLogStep _currentStep = FoodLogStep.initial;
  Timer? _debounceTimer;
  List<FoodModel> _results = [];
  bool _isLoading = false;
  int _searchRequest = 0;
  String? _errorMessage;

  late String _selectedMealType;
  FoodModel? _selectedFood;
  int _grams = 100;
  bool _isSaving = false;
  String? _saveError;

  static const List<String> _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
  static const List<String> _commonStaples = [
    'Chicken breast',
    'Jasmine rice',
    'Rolled oats',
    'Greek yogurt',
  ];
  static const List<int> _portionPresets = [100, 150, 200, 250];

  @override
  void initState() {
    super.initState();
    _selectedMealType = widget.initialMealType ?? _resolveDefaultMealType();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _resolveDefaultMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return 'Breakfast';
    if (hour >= 11 && hour < 15) return 'Lunch';
    if (hour >= 15 && hour < 18) return 'Snack';
    return 'Dinner';
  }

  DateTime get _effectiveDate => widget.selectedDate ?? DateTime.now();

  FoodModel _toFoodModel(Food food) {
    return FoodModel(
      id: food.id,
      name: food.name,
      calories: food.calories,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
      tags: food.tags,
    );
  }

  // ─── Search & Debounce ───────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final request = ++_searchRequest;
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _currentStep = FoodLogStep.initial;
        _results = [];
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _currentStep = FoodLogStep.searchResults;
      _isLoading = true;
      _errorMessage = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || request != _searchRequest) return;
      await _executeSearch(trimmed, request);
    });
  }

  Future<void> _executeSearch(String query, int request) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      var foods = await _apiService.searchFoods(query);
      if (foods.isEmpty) {
        const enToVi = {
          'chicken breast': 'uc ga',
          'chicken': 'ga',
          'rice': 'com',
          'jasmine rice': 'com',
          'oats': 'yen mach',
          'rolled oats': 'yen mach',
          'beef': 'bo',
          'egg': 'trung',
        };
        final mapped = enToVi[query.toLowerCase().trim()];
        if (mapped != null) {
          foods = await _apiService.searchFoods(mapped);
        }
      }
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = foods.map(_toFoodModel).toList();
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = [];
        _isLoading = false;
        _errorMessage = 'Không thể tìm kiếm món ăn. Vui lòng thử lại.';
      });
    }
  }

  void _onClearSearch() {
    _debounceTimer?.cancel();
    ++_searchRequest;
    _searchCtrl.clear();
    setState(() {
      _currentStep = FoodLogStep.initial;
      _results = [];
      _isLoading = false;
      _errorMessage = null;
    });
  }

  void _onSelectStaple(String staple) {
    _searchCtrl.text = staple;
    _searchCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: staple.length),
    );
    _onSearchChanged(staple);
  }

  // ─── Selection & Navigation ──────────────────────────────────────

  void _onSelectFood(FoodModel food) {
    setState(() {
      _selectedFood = food;
      _grams = 100;
      _saveError = null;
      _currentStep = FoodLogStep.portionReview;
    });
  }

  void _onBackToSearch() {
    setState(() {
      _saveError = null;
      _currentStep = _searchCtrl.text.trim().isEmpty
          ? FoodLogStep.initial
          : FoodLogStep.searchResults;
    });
  }

  // ─── Portion Calculations ────────────────────────────────────────

  double get _calculatedCalories {
    if (_selectedFood == null) return 0.0;
    return (_selectedFood!.calories * _grams) / 100.0;
  }

  double get _calculatedProtein {
    if (_selectedFood == null) return 0.0;
    return (_selectedFood!.protein * _grams) / 100.0;
  }

  double get _calculatedCarbs {
    if (_selectedFood == null) return 0.0;
    return (_selectedFood!.carbs * _grams) / 100.0;
  }

  double get _calculatedFat {
    if (_selectedFood == null) return 0.0;
    return (_selectedFood!.fat * _grams) / 100.0;
  }

  // ─── Commit / Save Action ────────────────────────────────────────

  Future<void> _handleConfirmLog() async {
    if (_isSaving || _selectedFood == null) return;
    if (_grams <= 0) {
      setState(() => _saveError = 'Khẩu phần phải lớn hơn 0g');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final success = await ref.read(nutritionProvider.notifier).addMeal(
            date: _effectiveDate,
            mealType: _selectedMealType.toLowerCase(),
            foodId: _selectedFood!.id,
            name: _selectedFood!.name,
            calories: _calculatedCalories,
            protein: _calculatedProtein,
            carbs: _calculatedCarbs,
            fat: _calculatedFat,
            weightGrams: _grams,
          );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _saveError = 'Không thể lưu bữa ăn. Vui lòng thử lại.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Lỗi khi lưu bữa ăn: $e';
      });
    }
  }

  // ─── Custom Food Dialog ──────────────────────────────────────────

  void _showCreateFoodDialog() {
    final nameCtrl = TextEditingController(text: _searchCtrl.text.trim());
    final calCtrl = TextEditingController();
    final proCtrl = TextEditingController();
    final carbCtrl = TextEditingController();
    final fatCtrl = TextEditingController();
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16171B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF26282F)),
            ),
            title: const Text(
              'Tạo món mới',
              style: TextStyle(
                color: Color(0xFFF9FAFB),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dinh dưỡng tính trên 100g thực phẩm',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDialogInput(nameCtrl, 'Tên món ăn', isNumeric: false),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDialogInput(calCtrl, 'Calories (kcal)')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDialogInput(proCtrl, 'Protein (g)')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDialogInput(carbCtrl, 'Carbs (g)')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDialogInput(fatCtrl, 'Fat (g)')),
                    ],
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Hủy', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF9FAFB),
                  foregroundColor: const Color(0xFF0C0D0E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final cal = int.tryParse(calCtrl.text.trim());
                  if (name.isEmpty || cal == null || cal <= 0) {
                    setDialogState(() {
                      dialogError = 'Vui lòng nhập Tên và Calories hợp lệ';
                    });
                    return;
                  }

                  Navigator.pop(dialogCtx);
                  setState(() => _isLoading = true);

                  final newFood = await _apiService.createCustomFood(
                    name: name,
                    calories: cal,
                    protein: double.tryParse(proCtrl.text.trim()) ?? 0.0,
                    carbs: double.tryParse(carbCtrl.text.trim()) ?? 0.0,
                    fat: double.tryParse(fatCtrl.text.trim()) ?? 0.0,
                  );

                  if (!mounted) return;

                  if (newFood != null) {
                    _onSelectFood(_toFoodModel(newFood));
                  } else {
                    setState(() {
                      _isLoading = false;
                      _errorMessage = 'Không thể tạo món. Vui lòng thử lại.';
                    });
                  }
                },
                child: const Text('Tạo & Chọn'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDialogInput(
    TextEditingController ctrl,
    String label, {
    bool isNumeric = true,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: const TextStyle(color: Color(0xFFF3F4F6), fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF1E2026),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF26282F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF10B981)),
        ),
      ),
    );
  }

  void _showEditGramsDialog() {
    final gramsCtrl = TextEditingController(text: '$_grams');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16171B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF26282F)),
        ),
        title: const Text(
          'Nhập khối lượng (g)',
          style: TextStyle(
            color: Color(0xFFF9FAFB),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: gramsCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Color(0xFFF3F4F6),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            suffixText: 'g',
            suffixStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFF1E2026),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF26282F)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF10B981)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF9FAFB),
              foregroundColor: const Color(0xFF0C0D0E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final val = int.tryParse(gramsCtrl.text);
              if (val != null && val > 0) {
                setState(() => _grams = val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  // ─── Build Scaffold & Container ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep != FoodLogStep.portionReview,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentStep == FoodLogStep.portionReview) {
          _onBackToSearch();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF16171B),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  _buildSheetHandleAndNav(),
                  Expanded(
                    child: switch (_currentStep) {
                      FoodLogStep.initial => _buildInitialView(),
                      FoodLogStep.searchResults => _buildSearchResultsView(),
                      FoodLogStep.portionReview => _buildPortionReviewView(),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Handle & Top Nav Row ────────────────────────────────────────

  Widget _buildSheetHandleAndNav() {
    final isPortionReview = _currentStep == FoodLogStep.portionReview;
    final dateStr = DateFormat('EEE, MMM d').format(_effectiveDate);
    final isToday = DateUtils.isSameDay(_effectiveDate, DateTime.now());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isPortionReview)
                IconButton(
                  tooltip: 'Quay lại tìm kiếm',
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF9CA3AF), size: 22),
                  onPressed: _onBackToSearch,
                )
              else
                IconButton(
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close, color: Color(0xFF9CA3AF), size: 22),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              // Center Pill
              if (isPortionReview)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2026),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF26282F)),
                    ),
                    child: const Text(
                      'Portion review',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2026),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF26282F)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 13,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFF3F4F6),
                            ),
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 3),
                          const Text(
                            '· Today',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              // Right Action
              if (isPortionReview)
                IconButton(
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close, color: Color(0xFF9CA3AF), size: 20),
                  onPressed: () => Navigator.of(context).pop(false),
                )
              else
                IconButton(
                  tooltip: 'Hướng dẫn dinh dưỡng',
                  icon: const Icon(Icons.help_outline, color: Color(0xFF9CA3AF), size: 20),
                  onPressed: () {},
                ),
            ],
          ),
    );
  }

  // ─── Search Input Field ──────────────────────────────────────────

  Widget _buildSearchInput() {
    final hasText = _searchCtrl.text.isNotEmpty;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasText ? const Color(0xFF10B981).withOpacity(0.5) : const Color(0xFF26282F),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 22,
            color: hasText ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              cursorColor: const Color(0xFF10B981),
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                color: Color(0xFFF3F4F6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                hintText: 'Search foods or meals',
                hintStyle: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              key: const Key('clear_search_button'),
              tooltip: 'Clear search',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _onClearSearch,
              icon: const Icon(Icons.cancel, size: 18, color: Color(0xFF9CA3AF)),
            ),
        ],
      ),
    );
  }

  // ─── Meal Segmented Selector ────────────────────────────────────

  Widget _buildMealSegmentedSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Row(
        children: _mealTypes.map((type) {
          final isSelected = _selectedMealType == type;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedMealType = type),
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
                        type,
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

  // ─── FRAME 1: Initial View ───────────────────────────────────────

  Widget _buildInitialView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Title & subtitle
        const Text(
          'Log meal',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF9FAFB),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Find what you ate.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 14),

        // Search Input
        _buildSearchInput(),
        const SizedBox(height: 12),

        // Meal Selector
        _buildMealSegmentedSelector(),
        const SizedBox(height: 16),

        // Find Your Food Hero Card
        _buildFindYourFoodHeroCard(),
        const SizedBox(height: 18),

        // Common Staples Section
        _buildCommonStaplesSection(),
      ],
    );
  }

  Widget _buildFindYourFoodHeroCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero photo
          SizedBox(
            height: 130,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  'https://lh3.googleusercontent.com/aida/AEtjO1W86QkGkO9s6k_JtH3s8vHlXf4c0X14qH8_s4u5hK_L2y8xVbA2m8z1_qL9p=s800',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/nutrition.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF212328),
                      child: const Center(
                        child: Icon(Icons.restaurant, size: 40, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.15),
                        const Color(0xFF1E2026).withOpacity(0.95),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Text(
                      'EVERYDAY FOODS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Find your food',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF9FAFB),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Search any whole food, meal prep item, or recipe. You will review and adjust your exact portion before confirming.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFF26282F))),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.touch_app, size: 16, color: Color(0xFF10B981)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Search a food, then choose your portion.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFCBD5E1),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommonStaplesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'COMMON STAPLES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _commonStaples.map((staple) {
            return InkWell(
              onTap: () => _onSelectStaple(staple),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2026),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF26282F)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search, size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Text(
                      staple,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── FRAME 2: Search Results View ────────────────────────────────

  Widget _buildSearchResultsView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Column(
            children: [
              _buildSearchInput(),
              const SizedBox(height: 10),
              _buildMealSegmentedSelector(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      _isLoading
                          ? 'SEARCHING...'
                          : 'RESULTS (${_results.length} FOUND)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Basis: per 100g',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildSearchResultsBody(),
        ),
      ],
    );
  }

  Widget _buildSearchResultsBody() {
    if (_isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => Container(
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFF1E2026),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26282F)),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF10B981),
              ),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 36, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFF3F4F6), fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('search_retry_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF212328),
                  foregroundColor: const Color(0xFFF3F4F6),
                  side: const BorderSide(color: Color(0xFF26282F)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _executeSearch(_searchCtrl.text.trim(), ++_searchRequest),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Thử lại tìm kiếm'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off_rounded, size: 40, color: Color(0xFF6B7280)),
              const SizedBox(height: 12),
              Text(
                'Không tìm thấy món "${_searchCtrl.text}"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF3F4F6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Bạn có thể tự tạo món riêng với thông tin dinh dưỡng tùy chọn.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _showCreateFoodDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Tự tạo món mới',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _results.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton.icon(
                onPressed: _showCreateFoodDialog,
                icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF9CA3AF)),
                label: const Text(
                  "Can't find your food? Create custom item",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          );
        }

        final item = _results[index];
        return _buildFoodResultRow(item);
      },
    );
  }

  Widget _buildFoodResultRow(FoodModel item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onSelectFood(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2026),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26282F)),
          ),
          child: Row(
            children: [
              // 56x56 Thumbnail container with photo
              _buildFoodThumbnail(item.name, size: 56, borderRadius: 12),
              const SizedBox(width: 12),
              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF9FAFB),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.calories.round()} kcal',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF3F4F6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'per 100 g',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.protein.toStringAsFixed(0)}g pro · ${item.carbs.toStringAsFixed(0)}g carb · ${item.fat.toStringAsFixed(1)}g fat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── FRAME 3: Portion Review View ────────────────────────────────

  Widget _buildPortionReviewView() {
    if (_selectedFood == null) {
      return const SizedBox.shrink();
    }

    final profile = ref.watch(profileProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              // Selected Food Hero Header Card
              _buildPortionFoodHeroCard(),
              const SizedBox(height: 14),

              // Serving Size Stepper Card
              _buildServingSizeStepperCard(),
              const SizedBox(height: 14),

              // Recalculated Intake Telemetry Card
              _buildRecalculatedIntakeCard(profile),
              const SizedBox(height: 14),

              // Grounding Notice
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Choosing portion does not write to history. Tapping below commits ${_grams}g to $_selectedMealType.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pinned Bottom Action Panel
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFF16171B),
            border: Border(
              top: BorderSide(color: Color(0xFF26282F), width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error banner anchored directly above action
              if (_saveError != null) ...[
                Container(
                  key: const Key('save_error_banner'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _saveError!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        key: const Key('save_retry_button'),
                        onTap: _handleConfirmLog,
                        child: const Text(
                          'Thử lại lưu',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Primary Action: Log meal
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('confirm_log_meal_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9FAFB),
                    foregroundColor: const Color(0xFF0C0D0E),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: (_isSaving || _grams <= 0) ? null : _handleConfirmLog,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
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
                              'Log meal',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              // Secondary Cancel Button
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancel',
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
      ],
    );
  }

  Widget _buildPortionFoodHeroCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Row(
        children: [
          _buildFoodThumbnail(_selectedFood!.name, size: 56, borderRadius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: Text(
                    '$_selectedMealType · Selected Item'.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedFood!.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF9FAFB),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reference: ${_selectedFood!.calories.round()} kcal / 100g',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServingSizeStepperCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Label & Unit switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'SERVING SIZE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16171B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF26282F)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF212328),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF383A42).withOpacity(0.6)),
                      ),
                      child: const Text(
                        'Grams (g)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF3F4F6),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Hệ số chiếc chưa khả dụng cho món này',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        child: const Text(
                          'Pieces',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Stepper Row: Minus, Large Editable Number, Plus
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF16171B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF26282F)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Minus button (-25g)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _grams > 25 ? () => setState(() => _grams -= 25) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF212328),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF26282F)),
                      ),
                      child: Icon(
                        Icons.remove,
                        size: 20,
                        color: _grams > 25 ? const Color(0xFFF3F4F6) : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),

                // Editable Display
                GestureDetector(
                  onTap: _showEditGramsDialog,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$_grams',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF9FAFB),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'g',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit, size: 14, color: Color(0xFF6B7280)),
                    ],
                  ),
                ),

                // Plus button (+25g)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _grams += 25),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF212328),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF26282F)),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Preset Chips (100g, 150g, 200g, 250g)
          Row(
            children: _portionPresets.map((preset) {
              final isSelected = _grams == preset;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => setState(() => _grams = preset),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF212328) : const Color(0xFF16171B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF10B981).withOpacity(0.6)
                              : const Color(0xFF26282F),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${preset}g',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecalculatedIntakeCard(ProfileState profile) {
    final cal = _calculatedCalories;
    final pro = _calculatedProtein;
    final carb = _calculatedCarbs;
    final fat = _calculatedFat;

    final targetCal = profile.targetCalories;
    final calDeltaPercent = (targetCal > 0) ? (cal / targetCal * 100) : null;

    final proTarget = profile.targetProtein;
    final proPercent = (proTarget > 0) ? (pro / proTarget * 100).round() : null;

    final carbTarget = profile.targetCarbs;
    final carbPercent = (carbTarget > 0) ? (carb / carbTarget * 100).round() : null;

    final fatTarget = profile.targetFat;
    final fatPercent = (fatTarget > 0) ? (fat / fatTarget * 100).round() : null;

    final ratio = (_grams / 100.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'RECALCULATED INTAKE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${ratio.toStringAsFixed(1)}x reference portion',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Calorie Hero
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${cal.round()}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF9FAFB),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'kcal',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              if (calDeltaPercent != null)
                Flexible(
                  child: Text(
                    '+${calDeltaPercent.toStringAsFixed(1)}% of daily target',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Macro Strip: Protein, Carbs, Fat
          Row(
            children: [
              // Protein
              Expanded(
                child: _buildMacroBox(
                  label: 'Protein',
                  grams: pro,
                  dotColor: const Color(0xFF10B981),
                  goalPercent: proPercent,
                ),
              ),
              const SizedBox(width: 8),
              // Carbs
              Expanded(
                child: _buildMacroBox(
                  label: 'Carbs',
                  grams: carb,
                  dotColor: const Color(0xFFF59E0B),
                  goalPercent: carbPercent,
                ),
              ),
              const SizedBox(width: 8),
              // Fat
              Expanded(
                child: _buildMacroBox(
                  label: 'Fat',
                  grams: fat,
                  dotColor: const Color(0xFFA855F7),
                  goalPercent: fatPercent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroBox({
    required String label,
    required double grams,
    required Color dotColor,
    required int? goalPercent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${grams.toStringAsFixed(1)}g',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF3F4F6),
            ),
          ),
          if (goalPercent != null) ...[
            const SizedBox(height: 2),
            Text(
              '$goalPercent% of goal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

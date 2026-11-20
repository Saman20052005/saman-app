import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../features/nutrition/data/food_image_attribution.dart';
import '../features/nutrition/data/food_image_manifest.dart';
import '../features/nutrition/domain/entities/food.dart';
import '../features/nutrition/presentation/providers/nutrition_usual_foods_provider.dart';
import '../features/nutrition/presentation/providers/recipes_supplements_provider.dart';
import '../models/food_model.dart';
import '../models/nutrition_model.dart';
import '../providers/nutrition_provider.dart';
import '../providers/profile_provider.dart';
import '../services/nutrition_service.dart';
import 'nutrition/widgets/create_recipe_sheet.dart';

class _FoodLogColors {
  const _FoodLogColors({
    required this.isDark,
    required this.scaffoldBg,
    required this.surface,
    required this.card,
    required this.elevated,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.onAccent,
    required this.ctaBg,
    required this.ctaFg,
    required this.amber,
    required this.violet,
    required this.error,
    required this.sky,
  });

  final bool isDark;
  final Color scaffoldBg;
  final Color surface;
  final Color card;
  final Color elevated;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textBody;
  final Color textSecondary;
  final Color textMuted;
  final Color textSubtle;
  final Color accent;
  final Color onAccent;
  final Color ctaBg;
  final Color ctaFg;
  final Color amber;
  final Color violet;
  final Color error;
  final Color sky;

  factory _FoodLogColors.of(BuildContext context) {
    final palette = SamanPalette.of(context);
    if (palette.isDark) {
      return const _FoodLogColors(
        isDark: true,
        scaffoldBg: Color(0xFF16171B),
        surface: Color(0xFF16171B),
        card: Color(0xFF1E2026),
        elevated: Color(0xFF212328),
        border: Color(0xFF26282F),
        borderStrong: Color(0xFF383A42),
        textPrimary: Color(0xFFF9FAFB),
        textBody: Color(0xFFF3F4F6),
        textSecondary: Color(0xFFCBD5E1),
        textMuted: Color(0xFF9CA3AF),
        textSubtle: Color(0xFF6B7280),
        accent: Color(0xFF10B981),
        onAccent: Color(0xFF0C0D0E),
        ctaBg: Color(0xFFF9FAFB),
        ctaFg: Color(0xFF0C0D0E),
        amber: Color(0xFFF59E0B),
        violet: Color(0xFFA78BFA),
        error: Color(0xFFEF4444),
        sky: Color(0xFF38BDF8),
      );
    }
    return _FoodLogColors(
      isDark: false,
      scaffoldBg: palette.canvas,
      surface: palette.surface,
      card: palette.surface,
      elevated: palette.surfaceElevated,
      border: palette.border,
      borderStrong: const Color(0xFFCBD5E1),
      textPrimary: palette.textPrimary,
      textBody: palette.textPrimary,
      textSecondary: palette.textSecondary,
      textMuted: palette.textSecondary,
      textSubtle: palette.textMuted,
      accent: palette.accent,
      onAccent: palette.onAccent,
      ctaBg: palette.accent,
      ctaFg: palette.onAccent,
      amber: palette.amber,
      violet: palette.violet,
      error: palette.danger,
      sky: const Color(0xFF0284C7),
    );
  }
}

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
  final FoodModel? initialFood;

  const FoodLogScreen({
    super.key,
    this.userGoal = 'weight_loss',
    this.selectedDate,
    this.initialMealType,
    this.apiService,
    this.initialFood,
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

  /// Exact-name lookup into the curated food image manifest (no keyword matching).
  static String? getFoodImageAsset(String foodName) => foodImageAssetFor(foodName);

  Widget _buildFoodThumbnail(String foodName, {double size = 56, double borderRadius = 12}) {
    final c = _FoodLogColors.of(context);
    final imageAsset = getFoodImageAsset(foodName);
    return Container(
      key: ValueKey('food_thumb_$foodName'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.elevated,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageAsset != null
          ? Image.asset(
              imageAsset,
              width: size,
              height: size,
              fit: BoxFit.cover,
              semanticLabel: foodName,
              errorBuilder: (_, __, ___) => Center(
                child: Tooltip(
                  message: 'Không tải được ảnh món',
                  child: Icon(
                    Icons.broken_image_outlined,
                    key: const Key('food_thumb_error'),
                    size: 22,
                    color: c.isDark ? const Color(0xFFF87171) : c.error,
                  ),
                ),
              ),
            )
          : Center(
              child: Tooltip(
                message: 'Món chưa có ảnh',
                child: Icon(
                  Icons.restaurant_outlined,
                  key: const Key('food_thumb_missing'),
                  size: 22,
                  color: c.textSubtle,
                ),
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
  bool _isCatalogVerified = false;
  String? _reselectNotice;
  int _grams = 100;
  bool _isSaving = false;
  String? _saveError;
  bool _showMyRecipes = false;
  bool _recipesLoaded = false;

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
    if (widget.initialFood != null) {
      if (widget.initialFood!.id.trim().isNotEmpty &&
          widget.initialFood!.name.trim().isNotEmpty) {
        _selectedFood = widget.initialFood;
        _grams = 100;
        _currentStep = FoodLogStep.portionReview;
      } else {
        _errorMessage = 'Thông tin món ăn không hợp lệ.';
        _currentStep = FoodLogStep.initial;
      }
    }
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

  DateTime get _effectiveDate {
    if (widget.selectedDate != null) return widget.selectedDate!;
    final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(vn.year, vn.month, vn.day);
  }

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
        _reselectNotice = null;
      });
      return;
    }

    setState(() {
      _currentStep = FoodLogStep.searchResults;
      _isLoading = true;
      _errorMessage = null;
      _reselectNotice = null;
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
      _reselectNotice = null;
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
      _isCatalogVerified = true;
      _grams = 100;
      _saveError = null;
      _errorMessage = null;
      _reselectNotice = null;
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

  bool _hasMacroOrNameChanges(FoodModel a, FoodModel b) {
    return a.name.trim() != b.name.trim() ||
        (a.calories - b.calories).abs() > 0.01 ||
        (a.protein - b.protein).abs() > 0.01 ||
        (a.carbs - b.carbs).abs() > 0.01 ||
        (a.fat - b.fat).abs() > 0.01;
  }

  // ─── Commit / Save Action ────────────────────────────────────────

  Future<void> _handleConfirmLog() async {
    if (_isSaving || _selectedFood == null) return;
    if (_selectedFood!.name.trim().isEmpty ||
        (widget.initialFood != null &&
            !_isCatalogVerified &&
            _selectedFood!.id.trim().isEmpty)) {
      setState(() {
        _errorMessage = 'Thông tin món ăn không hợp lệ.';
        _currentStep = FoodLogStep.initial;
      });
      return;
    }
    if (_grams <= 0) {
      setState(() => _saveError = 'Khẩu phần phải lớn hơn 0g');
      return;
    }

    final profile = ref.read(profileProvider);
    final currentUserId = profile.confirmedUserId ??
        profile.snapshot?.userId ??
        profile.snapshot?.email ??
        'guest';

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    if (widget.initialFood != null && !_isCatalogVerified) {
      final targetId = _selectedFood!.id.trim();
      final isSyntheticClientKey =
          targetId.isEmpty ||
          targetId.startsWith('catalog_') ||
          targetId.startsWith('entry_');

      Food? verifiedFood;

      if (!isSyntheticClientKey) {
        // Direct stable-ID lookup from backend
        try {
          verifiedFood = await _apiService.getFoodById(targetId);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _isSaving = false;
            _saveError =
                'Lỗi kết nối mạng, không thể kiểm tra món ăn. Vui lòng thử lại.';
          });
          return;
        }
      }

      if (verifiedFood == null) {
        // Stable ID cannot be verified (e.g. 404 from getFoodById, missing ID,
        // or synthetic client key like catalog_... / entry_...).
        // Redirect to catalog search with old name so user explicitly picks -> reviews -> confirms.
        List<Food> catalogResults = [];
        try {
          catalogResults = await _apiService.searchFoods(_selectedFood!.name);
          if (catalogResults.isEmpty) {
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
            final mapped = enToVi[_selectedFood!.name.toLowerCase().trim()];
            if (mapped != null) {
              catalogResults = await _apiService.searchFoods(mapped);
            }
          }
        } catch (_) {}

        if (!mounted) return;
        final oldName = _selectedFood!.name.trim();
        _searchCtrl.text = oldName;
        _searchCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: oldName.length),
        );
        setState(() {
          _isSaving = false;
          _selectedFood = null;
          _saveError = null;
          _errorMessage = null;
          _reselectNotice =
              'Vui lòng chọn lại món từ danh mục hiện hành để kiểm tra khẩu phần trước khi lưu.';
          _results = catalogResults.map(_toFoodModel).toList();
          _currentStep = FoodLogStep.searchResults;
        });
        return;
      }

      final latestFood = _toFoodModel(verifiedFood);
      final macrosChanged = _hasMacroOrNameChanges(_selectedFood!, latestFood);
      _selectedFood = latestFood;
      _isCatalogVerified = true;

      if (macrosChanged) {
        setState(() {
          _isSaving = false;
          _saveError =
              'Số liệu dinh dưỡng đã cập nhật theo danh mục mới. Vui lòng kiểm tra lại khẩu phần và bấm Log meal để xác nhận.';
        });
        return;
      }
    }

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
        final postProfile = ref.read(profileProvider);
        final postUserId = postProfile.confirmedUserId ??
            postProfile.snapshot?.userId ??
            postProfile.snapshot?.email ??
            'guest';
        // Only record into user recents if account remained identical throughout the save operation
        if (postUserId == currentUserId) {
          if (widget.initialFood != null &&
              widget.initialFood!.id != _selectedFood!.id) {
            ref.read(usualFoodsProvider.notifier).upgradeLegacyReference(
                  legacyId: widget.initialFood!.id,
                  newFood: _selectedFood!,
                );
          }
          await UsualFoodsNotifier.recordConfirmedFoodGlobally(
            widgetRef: ref,
            food: _selectedFood!,
            userId: currentUserId,
          );
        }
        if (!mounted) return;
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
          final c = _FoodLogColors.of(context);
          return AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: c.border),
            ),
            title: Text(
              'Tạo món mới',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dinh dưỡng tính trên 100g thực phẩm',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textMuted,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: c.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Hủy', style: TextStyle(color: c.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.ctaBg,
                  foregroundColor: c.ctaFg,
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
    final c = _FoodLogColors.of(context);
    return TextField(
      controller: ctrl,
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: TextStyle(color: c.textBody, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textMuted, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: c.isDark ? c.card : c.elevated,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.accent),
        ),
      ),
    );
  }

  void _showEditGramsDialog() {
    final gramsCtrl = TextEditingController(text: '$_grams');
    showDialog(
      context: context,
      builder: (ctx) {
        final c = _FoodLogColors.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: c.border),
          ),
          title: Text(
            'Nhập khối lượng (g)',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: gramsCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              color: c.textBody,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              suffixText: 'g',
              suffixStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.isDark ? c.card : c.elevated,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: TextStyle(color: c.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.ctaBg,
                foregroundColor: c.ctaFg,
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
        );
      },
    );
  }

  // ─── Build Scaffold & Container ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _FoodLogColors.of(context);
    return PopScope(
      canPop: _currentStep != FoodLogStep.portionReview,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentStep == FoodLogStep.portionReview) {
          _onBackToSearch();
        }
      },
      child: Scaffold(
        backgroundColor: c.scaffoldBg,
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
    final c = _FoodLogColors.of(context);
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
                  icon: Icon(Icons.arrow_back, color: c.textMuted, size: 22),
                  onPressed: _onBackToSearch,
                )
              else
                IconButton(
                  tooltip: 'Đóng',
                  icon: Icon(Icons.close, color: c.textMuted, size: 22),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              // Center Pill
              if (isPortionReview)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.isDark ? c.card : c.elevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      'Portion review',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.isDark ? c.card : c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 13,
                          color: c.accent,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: c.textBody,
                            ),
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 3),
                          Text(
                            '· Today',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: c.textMuted,
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
                  icon: Icon(Icons.close, color: c.textMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(false),
                )
              else
                IconButton(
                  tooltip: 'Hướng dẫn dinh dưỡng',
                  icon: Icon(Icons.help_outline, color: c.textMuted, size: 20),
                  onPressed: () {},
                ),
            ],
          ),
    );
  }

  // ─── Search Input Field ──────────────────────────────────────────

  Widget _buildSearchInput() {
    final c = _FoodLogColors.of(context);
    final hasText = _searchCtrl.text.isNotEmpty;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasText ? c.accent.withOpacity(0.5) : c.border,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 22,
            color: hasText ? c.accent : c.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              cursorColor: c.accent,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                color: c.textBody,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: 'Search foods or meals',
                hintStyle: TextStyle(
                  color: c.textSubtle,
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
              icon: Icon(Icons.cancel, size: 18, color: c.textMuted),
            ),
        ],
      ),
    );
  }

  // ─── Meal Segmented Selector ────────────────────────────────────

  Widget _buildMealSegmentedSelector() {
    final c = _FoodLogColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.isDark ? c.card : c.elevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
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
                  color: isSelected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: c.accent.withOpacity(0.4))
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(c.isDark ? 0.2 : 0.06),
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
                        decoration: BoxDecoration(
                          color: c.accent,
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
                          color: isSelected ? c.textPrimary : c.textMuted,
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
    final c = _FoodLogColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: c.error.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: c.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: c.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        // Title & subtitle
        Text(
          'Log meal',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Find what you ate.',
          style: TextStyle(
            fontSize: 13,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 14),

        // Search Input
        _buildSearchInput(),
        const SizedBox(height: 12),

        // Meal Selector
        _buildMealSegmentedSelector(),
        const SizedBox(height: 12),

        // Mode Segmented Pill: Tìm món | Công thức của tôi
        _buildModeSegmentedPill(),
        const SizedBox(height: 16),

        if (!_showMyRecipes) ...[
          // Find Your Food Hero Card
          _buildFindYourFoodHeroCard(),
          const SizedBox(height: 18),

          // Common Staples Section
          _buildCommonStaplesSection(),
        ] else ...[
          _buildMyRecipesSection(),
        ],
      ],
    );
  }

  Widget _buildModeSegmentedPill() {
    final c = _FoodLogColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.isDark ? c.card : c.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: const Key('tab_find_food'),
              onTap: () => setState(() => _showMyRecipes = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: !_showMyRecipes ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Tìm món',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          !_showMyRecipes ? FontWeight.w700 : FontWeight.w500,
                      color: !_showMyRecipes ? c.onAccent : c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('tab_my_recipes'),
              onTap: () {
                setState(() => _showMyRecipes = true);
                if (!_recipesLoaded) {
                  _recipesLoaded = true;
                  ref.read(recipesProvider.notifier).loadRecipes();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _showMyRecipes ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Công thức của tôi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          _showMyRecipes ? FontWeight.w700 : FontWeight.w500,
                      color: _showMyRecipes ? c.onAccent : c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRecipesSection() {
    final c = _FoodLogColors.of(context);
    final recipesState = ref.watch(recipesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: OutlinedButton(
            key: const Key('create_recipe_cta_button'),
            onPressed: () {
              CreateRecipeSheet.show(context);
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: c.card,
              foregroundColor: c.accent,
              side: BorderSide(color: c.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '+ Tạo công thức mới',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (recipesState.isLoading && recipesState.recipes.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              ),
            ),
          )
        else if (recipesState.error != null && recipesState.recipes.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  color: c.error,
                  size: 32,
                ),
                const SizedBox(height: 10),
                Text(
                  recipesState.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textBody,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(recipesProvider.notifier).loadRecipes();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.elevated,
                    foregroundColor: c.textBody,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          )
        else if (recipesState.recipes.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 36,
                  color: c.textMuted,
                ),
                const SizedBox(height: 10),
                Text(
                  'Chưa có công thức nào',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hãy nhấn "+ Tạo công thức mới" để tạo công thức đầu tiên của bạn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (int i = 0; i < recipesState.recipes.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _buildRecipeCard(
                  recipesState.recipes[i],
                  isMutating: recipesState.isMutating,
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildRecipeCard(RecipeModel recipe, {required bool isMutating}) {
    final c = _FoodLogColors.of(context);
    return Container(
      key: ValueKey('recipe_card_${recipe.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${recipe.caloriesPerServing} kcal / phần',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.isDark ? c.surface : c.elevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.border),
                          ),
                          child: Text(
                            '${recipe.servings} phần',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('delete_recipe_${recipe.id}'),
                tooltip: 'Xoá công thức',
                visualDensity: VisualDensity.compact,
                onPressed: isMutating
                    ? null
                    : () => _confirmDeleteRecipe(recipe),
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'P: ${recipe.proteinPerServing.toStringAsFixed(1)}g · C: ${recipe.carbsPerServing.toStringAsFixed(1)}g · F: ${recipe.fatPerServing.toStringAsFixed(1)}g',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  key: ValueKey('log_recipe_${recipe.id}'),
                  onPressed: isMutating
                      ? null
                      : () async {
                          final ok = await ref
                              .read(recipesProvider.notifier)
                              .logRecipeServing(
                                recipe.id,
                                date: DateFormat('yyyy-MM-dd')
                                    .format(_effectiveDate),
                                mealType: _selectedMealType.toLowerCase(),
                                servingsConsumed: 1.0,
                                refreshPlan: false,
                              );
                          if (!mounted) return;
                          if (ok) {
                            Navigator.of(context).pop(true);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Ghi 1 phần',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteRecipe(RecipeModel recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = _FoodLogColors.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.border),
          ),
          title: Text(
            'Xoá công thức?',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Bạn có chắc muốn xoá công thức "${recipe.name}"?',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Huỷ',
                style: TextStyle(color: c.textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Xoá'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await ref.read(recipesProvider.notifier).deleteRecipe(recipe.id);
    }
  }

  Widget _buildFindYourFoodHeroCard() {
    final c = _FoodLogColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
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
                Image.asset(
                  'assets/images/nutrition.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: c.elevated,
                    child: Center(
                      child: Icon(Icons.restaurant, size: 40, color: c.textMuted),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(c.isDark ? 0.15 : 0.04),
                        c.card.withOpacity(0.95),
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
                    child: Text(
                      'EVERYDAY FOODS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: c.isDark
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFFF9FAFB),
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
                Text(
                  'Find your food',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search any whole food, meal prep item, or recipe. You will review and adjust your exact portion before confirming.',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, size: 16, color: c.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Search a food, then choose your portion.',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
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
    final c = _FoodLogColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'COMMON STAPLES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
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
                  color: c.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 14, color: c.accent),
                    const SizedBox(width: 6),
                    Text(
                      staple,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.textSecondary,
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
    final c = _FoodLogColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Column(
            children: [
              _buildSearchInput(),
              const SizedBox(height: 10),
              _buildMealSegmentedSelector(),
              if (_reselectNotice != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('catalog_reselect_notice'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: c.accent.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: c.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _reselectNotice!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: c.textBody,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Basis: per 100g',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.textMuted,
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
    final c = _FoodLogColors.of(context);
    if (_isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => Container(
          height: 76,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.accent,
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
              Icon(Icons.wifi_off_rounded, size: 36, color: c.textMuted),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textBody, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('search_retry_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.elevated,
                  foregroundColor: c.textBody,
                  side: BorderSide(color: c.border),
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
              Icon(Icons.search_off_rounded, size: 40, color: c.textSubtle),
              const SizedBox(height: 12),
              Text(
                'Không tìm thấy món "${_searchCtrl.text}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bạn có thể tự tạo món riêng với thông tin dinh dưỡng tùy chọn.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.isDark ? const Color(0xFF052E16) : c.onAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _showCreateFoodDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Tự tạo món mới',
                  style: TextStyle(fontWeight: FontWeight.w700),
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
                icon: Icon(Icons.add_circle_outline, size: 16, color: c.textMuted),
                label: Text(
                  "Can't find your food? Create custom item",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.textMuted,
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
    final c = _FoodLogColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onSelectFood(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.calories.round()} kcal',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.textBody,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'per 100 g',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
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
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: c.textMuted,
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

    final c = _FoodLogColors.of(context);
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
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textMuted,
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
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(
              top: BorderSide(color: c.border, width: 1),
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
                    color: c.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.error.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: c.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _saveError!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: c.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        key: const Key('save_retry_button'),
                        onTap: _handleConfirmLog,
                        child: Text(
                          'Thử lại lưu',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.error,
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
                    backgroundColor: c.ctaBg,
                    foregroundColor: c.ctaFg,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: (_isSaving || _grams <= 0) ? null : _handleConfirmLog,
                  child: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.ctaFg,
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
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textMuted,
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
    final c = _FoodLogColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showImageAttributionSheet(context, _selectedFood!.name),
            child: _buildFoodThumbnail(_selectedFood!.name, size: 56, borderRadius: 12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.accent.withOpacity(0.3)),
                  ),
                  child: Text(
                    '$_selectedMealType · Selected Item'.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: c.accent,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedFood!.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reference: ${_selectedFood!.calories.round()} kcal / 100g',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  key: const Key('food_attribution_button'),
                  onTap: () => _showImageAttributionSheet(context, _selectedFood!.name),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 13, color: c.accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Nguồn & Ghi công ảnh',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.accent,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
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

  void _showImageAttributionSheet(BuildContext context, String foodName) async {
    final attr = await FoodAttributionService.getByName(foodName);
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _FoodLogColors.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: _FoodLogColors.of(context).border),
      ),
      builder: (ctx) {
        final c = _FoodLogColors.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.isDark
                            ? const Color(0xFF374151)
                            : c.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildFoodThumbnail(foodName, size: 48, borderRadius: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              foodName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              attr == null
                                  ? 'Trạng thái: Chưa có ảnh (Pending)'
                                  : (attr.isAi
                                      ? 'Ảnh minh họa tạo bằng AI'
                                      : 'Ảnh thật (Wikimedia Commons)'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: attr == null
                                    ? c.amber
                                    : (attr.isAi ? c.violet : c.sky),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: c.border, height: 1),
                  const SizedBox(height: 14),
                  if (attr != null) ...[
                    if (attr.isCommons) ...[
                      _buildAttributionRow('Tác giả:', attr.author),
                      const SizedBox(height: 8),
                      _buildAttributionRow('Giấy phép:', attr.license,
                          url: attr.licenseUrl),
                      const SizedBox(height: 8),
                      _buildAttributionRow('Nguồn ảnh:', attr.sourceUrl,
                          url: attr.sourceUrl, isLink: true),
                      const SizedBox(height: 8),
                      _buildAttributionRow('Xử lý ảnh:', attr.modificationNote),
                    ] else ...[
                      _buildAttributionRow('Phân loại:', 'Ảnh minh họa tạo bằng AI'),
                      const SizedBox(height: 8),
                      _buildAttributionRow('Nguồn tạo:', attr.author),
                      if (attr.model.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildAttributionRow('Mô hình AI:', attr.model),
                      ],
                      const SizedBox(height: 8),
                      _buildAttributionRow('Xử lý ảnh:', attr.modificationNote),
                    ],
                  ] else ...[
                    Text(
                      'Món ăn này chưa có ảnh chính thức và đang ở trạng thái Pending. Ảnh sẽ được cập nhật trong phiên bản kế tiếp khi có nguồn mở chuẩn xác hoặc quota AI miễn phí mở lại.',
                      style: TextStyle(
                          fontSize: 13, color: c.textMuted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: c.isDark
                              ? const Color(0xFF374151)
                              : c.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text('Đóng',
                          style: TextStyle(
                              color: c.isDark
                                  ? const Color(0xFFD1D5DB)
                                  : c.textPrimary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttributionRow(String label, String value,
      {String? url, bool isLink = false}) {
    final c = _FoodLogColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: (url != null || isLink)
                  ? c.sky
                  : (c.isDark ? const Color(0xFFE5E7EB) : c.textPrimary),
              decoration:
                  (url != null || isLink) ? TextDecoration.underline : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServingSizeStepperCard() {
    final c = _FoodLogColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Label & Unit switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'SERVING SIZE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.isDark ? c.surface : c.elevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.isDark ? c.elevated : c.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.borderStrong.withOpacity(0.6)),
                      ),
                      child: Text(
                        'Grams (g)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: c.textBody,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Hệ số chiếc chưa khả dụng cho món này',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        child: Text(
                          'Pieces',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: c.textSubtle,
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
              color: c.isDark ? c.surface : c.elevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
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
                        color: c.isDark ? c.elevated : c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Icon(
                        Icons.remove,
                        size: 20,
                        color: _grams > 25 ? c.textBody : c.textSubtle,
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
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'g',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit, size: 14, color: c.textSubtle),
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
                        color: c.isDark ? c.elevated : c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 20,
                        color: c.textBody,
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
                        color: isSelected
                            ? (c.isDark ? c.elevated : c.accent.withOpacity(0.12))
                            : (c.isDark ? c.surface : c.elevated),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? c.accent.withOpacity(0.6)
                              : c.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${preset}g',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? c.accent : c.textSecondary,
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
    final c = _FoodLogColors.of(context);
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
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'RECALCULATED INTAKE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.textMuted,
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
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
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'kcal',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textMuted,
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.accent,
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
                  dotColor: c.accent,
                  goalPercent: proPercent,
                ),
              ),
              const SizedBox(width: 8),
              // Carbs
              Expanded(
                child: _buildMacroBox(
                  label: 'Carbs',
                  grams: carb,
                  dotColor: c.amber,
                  goalPercent: carbPercent,
                ),
              ),
              const SizedBox(width: 8),
              // Fat
              Expanded(
                child: _buildMacroBox(
                  label: 'Fat',
                  grams: fat,
                  dotColor: c.isDark
                      ? const Color(0xFFA855F7)
                      : const Color(0xFF9333EA),
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
    final c = _FoodLogColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: c.isDark ? c.surface : c.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: c.textMuted,
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textBody,
            ),
          ),
          if (goalPercent != null) ...[
            const SizedBox(height: 2),
            Text(
              '$goalPercent% of goal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: c.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

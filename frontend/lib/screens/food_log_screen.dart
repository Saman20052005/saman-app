import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // ✅ Thêm Riverpod
import '../config/app_theme.dart';
import '../services/nutrition_service.dart';
import '../models/food_model.dart';
import '../providers/nutrition_provider.dart'; // ✅ Import Provider
import '../features/nutrition/domain/entities/food.dart';
import '../widgets/nutrition_primitives.dart';

class FoodLogScreen extends ConsumerStatefulWidget {
  final String userGoal;
  final DateTime? selectedDate; // ✅ Nhận ngày được chọn từ màn hình trước

  const FoodLogScreen({
    super.key,
    this.userGoal = 'weight_loss',
    this.selectedDate,
  });

  @override
  ConsumerState<FoodLogScreen> createState() => _FoodLogScreenState();
}

class _FoodLogScreenState extends ConsumerState<FoodLogScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  // Vẫn giữ Service để tìm kiếm (Query), nhưng hành động (Command) sẽ dùng Provider
  final NutritionService _apiService = NutritionService();

  Timer? _debounce;
  List<FoodModel> _results = [];
  bool _isLoading = false;
  int _searchRequest = 0;
  String _selectedMealType = "Snack";
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _scaffoldMessenger = null;
    super.dispose();
  }

  // Adapter: convert domain Food to legacy FoodModel
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

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final request = ++_searchRequest;
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || request != _searchRequest) return;
      setState(() => _isLoading = true);
      try {
        final foods = await _apiService.searchFoods(query);
        if (mounted && request == _searchRequest) {
          setState(() {
            _results = foods.map(_toFoodModel).toList();
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted && request == _searchRequest) {
          setState(() {
            _results = [];
            _isLoading = false;
          });
        }
      }
    });
  }

  // ==================================================================
  //  LOGIC TẠO MÓN (Giữ nguyên hoặc chuyển sang Provider nếu cần)
  // ==================================================================
  void _showCreateFoodDialog() {
    final nameCtrl = TextEditingController(text: _searchCtrl.text);
    final calCtrl = TextEditingController();
    final proCtrl = TextEditingController();
    final carbCtrl = TextEditingController();
    final fatCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tạo món mới"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: "Tên món ăn",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _buildNumInput(calCtrl, "Calories")),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildNumInput(proCtrl, "Protein (g)")),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _buildNumInput(carbCtrl, "Carbs (g)")),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildNumInput(fatCtrl, "Fat (g)")),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || calCtrl.text.isEmpty) {
                _scaffoldMessenger?.showSnackBar(const SnackBar(
                    content: Text("Vui lòng nhập Tên và Calories")));
                return;
              }
              Navigator.pop(context);

              // Tạm thời vẫn dùng service cho custom food (trừ khi bạn muốn chuyển nốt)
              final newFood = await _apiService.createCustomFood(
                name: nameCtrl.text,
                calories: int.tryParse(calCtrl.text) ?? 0,
                protein: double.tryParse(proCtrl.text) ?? 0,
                carbs: double.tryParse(carbCtrl.text) ?? 0,
                fat: double.tryParse(fatCtrl.text) ?? 0,
              );

              if (newFood != null && mounted) {
                _checkAndSelectFood(_toFoodModel(newFood));
              } else if (mounted) {
                _scaffoldMessenger?.showSnackBar(
                    const SnackBar(content: Text("Lỗi tạo món!")));
              }
            },
            child: const Text("Tạo & Thêm"),
          )
        ],
      ),
    );
  }

  Widget _buildNumInput(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        isDense: true,
      ),
    );
  }

  void _checkAndSelectFood(FoodModel item) {
    _showQuantityDialog(item);
  }

  // ==================================================================
  // 🔥 FIX QUAN TRỌNG: GỌI PROVIDER THAY VÌ SERVICE
  // ==================================================================
  void _showQuantityDialog(FoodModel item) {
    final qtyCtrl = TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.name),
        content: StatefulBuilder(builder: (context, setStateDialog) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: _selectedMealType,
                isExpanded: true,
                items: ["Breakfast", "Lunch", "Dinner", "Snack"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMealType = val);
                    setStateDialog(() => _selectedMealType = val);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: 'Khối lượng (g)',
                    suffixText: 'g',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    )),
              ),
            ],
          );
        }),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              final qty = int.tryParse(qtyCtrl.text) ?? 100;
              Navigator.pop(dialogContext); // Đóng dialog nhập số lượng

              // ✅ GỌI PROVIDER (Đã fix lỗi 422 ở bước trước)
              final success = await ref.read(nutritionProvider.notifier).addMeal(
                  date: widget.selectedDate ?? DateTime.now(),

                  // ✅ Đảm bảo gửi "breakfast", "lunch"... (viết thường)
                  mealType: _selectedMealType.toLowerCase(),
                  foodId: item.id,
                  name: item.name,

                  // Tính toán dinh dưỡng theo khối lượng (kết quả là double)
                  calories: (item.calories * qty / 100),
                  protein: (item.protein * qty / 100),
                  carbs: (item.carbs * qty / 100),
                  fat: (item.fat * qty / 100),
                  weightGrams: qty // (int)
                  );

              if (success && mounted) {
                Navigator.pop(context, true); // Đóng màn hình search
                _scaffoldMessenger?.showSnackBar(
                    const SnackBar(content: Text("Đã thêm món!")));
              } else if (mounted) {
                _scaffoldMessenger?.showSnackBar(
                    const SnackBar(content: Text("Lỗi thêm món!")));
              }
            },
            child: const Text("Thêm"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.hairline,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tìm món ăn...',
                prefixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                filled: true,
                fillColor: tokens.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: NutritionSectionHeader(label: 'Meal type'),
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: ["Breakfast", "Lunch", "Dinner", "Snack"].map((type) {
                final isSel = _selectedMealType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: isSel,
                    onSelected: (val) =>
                        setState(() => _selectedMealType = type),
                    selectedColor: colors.primary,
                    side: BorderSide(color: tokens.hairline),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      color: isSel ? colors.onPrimary : colors.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Divider(color: tokens.hairline),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            _searchCtrl.text.isEmpty
                                ? "Nhập tên món để tìm"
                                : "Không tìm thấy kết quả",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tokens.inkMuted,
                            )),
                        if (_searchCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          ElevatedButton.icon(
                            onPressed: _showCreateFoodDialog,
                            icon: const Icon(Icons.add),
                            label: const Text("Tự tạo món mới"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
                            ),
                          )
                        ]
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: tokens.surfaceElevated,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            Icons.restaurant,
                            color: colors.primary,
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              size: 14,
                              color: tokens.inkMuted,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                "${item.calories.toInt()} kcal",
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Icon(
                              Icons.fitness_center,
                              size: 14,
                              color: tokens.inkMuted,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                "${item.protein.toInt()}g pro",
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: tokens.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.add_circle_outline,
                          color: colors.primary,
                        ),
                        onTap: () => _checkAndSelectFood(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

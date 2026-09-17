import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // ✅ Thêm Riverpod
import '../services/nutrition_service.dart';
import '../models/food_model.dart';
import '../providers/nutrition_provider.dart'; // ✅ Import Provider
import '../features/nutrition/domain/entities/food.dart';

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
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isLoading = true);
      final foods = await _apiService.searchFoods(query);
      if (mounted)
        setState(() {
          _results = foods.map(_toFoodModel).toList();
          _isLoading = false;
        });
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
                decoration: const InputDecoration(
                    labelText: "Tên món ăn", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildNumInput(calCtrl, "Calories")),
                  const SizedBox(width: 10),
                  Expanded(child: _buildNumInput(proCtrl, "Protein (g)")),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildNumInput(carbCtrl, "Carbs (g)")),
                  const SizedBox(width: 10),
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
          labelText: label, border: const OutlineInputBorder(), isDense: true),
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
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Khối lượng (g)',
                    suffixText: 'g',
                    border: OutlineInputBorder()),
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tìm món ăn...',
                prefixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: ["Breakfast", "Lunch", "Dinner", "Snack"].map((type) {
                final isSel = _selectedMealType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: isSel,
                    onSelected: (val) =>
                        setState(() => _selectedMealType = type),
                    selectedColor: Colors.green.shade100,
                    labelStyle: TextStyle(
                        color: isSel ? Colors.green.shade900 : Colors.black),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(),
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
                            style: const TextStyle(color: Colors.grey)),
                        if (_searchCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showCreateFoodDialog,
                            icon: const Icon(Icons.add),
                            label: const Text("Tự tạo món mới"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white),
                          )
                        ]
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8)),
                          child:
                              const Icon(Icons.restaurant, color: Colors.green),
                        ),
                        title: Text(item.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Row(
                          children: [
                            const Icon(Icons.local_fire_department,
                                size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                "${item.calories.toInt()} kcal",
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.fitness_center,
                                size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                "${item.protein.toInt()}g pro",
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.add_circle_outline,
                            color: Colors.green),
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

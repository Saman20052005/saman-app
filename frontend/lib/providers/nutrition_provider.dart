// [File: lib/providers/nutrition_provider.dart]
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/nutrition_model.dart';
import '../models/nutrition_model.dart';
import '../features/nutrition/data/models/nutrition_plan_dto.dart';
import '../features/nutrition/data/models/macro_targets_dto.dart';
import '../features/nutrition/data/models/meal_dto.dart';
import '../features/nutrition/data/models/nutrition_log_entry_dto.dart';
import '../features/nutrition/domain/usecases/load_daily_plan_usecase.dart';
import '../features/nutrition/domain/usecases/update_water_usecase.dart';
import '../features/nutrition/domain/usecases/swap_meal_usecase.dart';
import '../features/nutrition/domain/usecases/swap_logged_meal_usecase.dart';
import '../models/meal_log.dart';
import '../models/ai_analysis_result.dart';
import '../services/nutrition_service.dart';
import '../services/nutrition_service.dart';
import '../features/nutrition/domain/repositories/nutrition_repository.dart';
import '../features/nutrition/data/repositories/nutrition_repository_impl.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';

final nutritionRepositoryProvider = Provider<INutritionRepository>((ref) {
  return NutritionRepositoryImpl();
});

final loadDailyPlanUseCaseProvider = Provider<LoadDailyPlanUseCase>((ref) {
  final repository = ref.watch(nutritionRepositoryProvider);
  return LoadDailyPlanUseCase(repository);
});

final updateWaterUseCaseProvider = Provider<UpdateWaterUseCase>((ref) {
  final repository = ref.watch(nutritionRepositoryProvider);
  return UpdateWaterUseCase(repository);
});

final swapMealUseCaseProvider = Provider<SwapMealUseCase>((ref) {
  final repository = ref.watch(nutritionRepositoryProvider);
  return SwapMealUseCase(repository);
});

final swapLoggedMealUseCaseProvider = Provider<SwapLoggedMealUseCase>((ref) {
  final repository = ref.watch(nutritionRepositoryProvider);
  return SwapLoggedMealUseCase(repository);
});

final nutritionProvider =
    StateNotifierProvider<NutritionNotifier, AsyncValue<NutritionPlan?>>((ref) {
  final repository = ref.watch(nutritionRepositoryProvider);
  return NutritionNotifier(
    repository: repository,
    loadDailyPlanUseCase: ref.watch(loadDailyPlanUseCaseProvider),
    updateWaterUseCase: ref.watch(updateWaterUseCaseProvider),
    swapMealUseCase: ref.watch(swapMealUseCaseProvider),
    swapLoggedMealUseCase: ref.watch(swapLoggedMealUseCaseProvider),
  );
});

// Separate provider for macro targets
final macroTargetsProvider = Provider<MacroTargets?>((ref) {
  final nutritionNotifier = ref.watch(nutritionProvider.notifier);
  return nutritionNotifier.macroTargets;
});

class NutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>> {
  final INutritionRepository _repository;
  final LoadDailyPlanUseCase _loadDailyPlanUseCase;
  final UpdateWaterUseCase _updateWaterUseCase;
  final SwapMealUseCase _swapMealUseCase;
  final SwapLoggedMealUseCase _swapLoggedMealUseCase;

  NutritionNotifier({
    required INutritionRepository repository,
    required LoadDailyPlanUseCase loadDailyPlanUseCase,
    required UpdateWaterUseCase updateWaterUseCase,
    required SwapMealUseCase swapMealUseCase,
    required SwapLoggedMealUseCase swapLoggedMealUseCase,
  })  : _repository = repository,
        _loadDailyPlanUseCase = loadDailyPlanUseCase,
        _updateWaterUseCase = updateWaterUseCase,
        _swapMealUseCase = swapMealUseCase,
        _swapLoggedMealUseCase = swapLoggedMealUseCase,
        super(const AsyncValue.loading());

  // ✅ CACHE: Lưu trữ dữ liệu các ngày đã tải
  final Map<String, NutritionPlan> _localCache = {};

  // ✅ Macro targets từ profile
  MacroTargets? _macroTargets;
  MacroTargets? get macroTargets => _macroTargets;

  // ✅ Prevent concurrent generation
  bool _isGenerating = false;

  // ✅ C8: Local loading state for meal plan section
  bool _isMealPlanGenerating = false;
  bool get isMealPlanGenerating => _isMealPlanGenerating;

  // ✅ Current goal for smart plan generation
  String? _currentGoal;
  String? get currentGoal => _currentGoal;

  // ✅ Remember last goal for smart plan generation
  String? _lastGoal; // ← NEW: nhớ goal lần load gần nhất
  int _lastMealCount = 4; // ← NEW: mặc định 4 bữa
  String _lastStyle = 'optimal'; // ← NEW: mặc định optimal

  // =========================================================
  // 1. LOAD DATA (CÓ CACHING)
  // =========================================================
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    // ✅ C10: Clear macro targets if date or goal changes
    if (_localCache.isEmpty ||
        !_localCache.containsKey(dateStr) ||
        _lastGoal != fallbackGoal) {
      _macroTargets = null;
    }

    _lastGoal = fallbackGoal; // ← NEW

    // A. Nếu có cache & không ép refresh -> Show ngay
    if (!forceRefresh && _localCache.containsKey(dateStr)) {
      state = AsyncValue.data(_localCache[dateStr]);
      return;
    }

    try {
      // B. Loading
      if (!forceRefresh) state = const AsyncValue.loading();

      final plan = await _loadDailyPlanUseCase.execute(date);

      // dùng parsed model
      if (plan.meals.isEmpty && plan.entries.isEmpty) {
        debugPrint(
          '🤖 Auto-pilot: no meals, no entries for $dateStr → generating...',
        );

        final savedWater = plan.currentWater;
        final savedWaterTarget = plan.targetWater;

        await generateAutoPlan(
          date,
          targetCalories: fallbackCalories,
          goal: fallbackGoal,
        );

        final newPlan = state.value;
        if (newPlan != null && savedWater > 0) {
          final merged = newPlan.copyWith(
            currentWater: savedWater,
            targetWater: savedWaterTarget,
          );
          _localCache[dateStr] = merged;
          // Prevent memory leak – limit cache to 30 entries
          if (_localCache.length > 30) {
            final sortedKeys = _localCache.keys.toList()..sort();
            _localCache.remove(sortedKeys.first);
          }
          state = AsyncValue.data(merged);
        }
        return;
      }

      // Có data thật → cache và render
      _localCache[dateStr] = plan;
      state = AsyncValue.data(plan);
      return;
    } catch (e) {
      debugPrint('❌ loadDailyPlan error: $e');
      if (_localCache.containsKey(dateStr)) {
        state = AsyncValue.data(_localCache[dateStr]);
      } else {
        // Fallback: thử generate thay vì để trắng
        // BEFORE generate
        final waterBefore = _localCache[dateStr]?.currentWater ?? 0;
        final waterTargetBefore = _localCache[dateStr]?.targetWater ?? 2000;

        await generateAutoPlan(
          date,
          targetCalories: fallbackCalories,
          goal: fallbackGoal,
        );

        // AFTER generate
        if (state.value != null && waterBefore > 0) {
          final patched = state.value!.copyWith(
            currentWater: waterBefore,
            targetWater: waterTargetBefore,
          );
          _localCache[dateStr] = patched;
          state = AsyncValue.data(patched);
        }
      }
    }
  }

  // =========================================================
  // 2. GENERATE PLAN
  // =========================================================
  Future<void> generateAutoPlan(
    DateTime date, {
    required int targetCalories,
    required String goal,
  }) async {
    if (_isGenerating) return;
    _isGenerating = true;

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      // FIX 2A: Map goal value về đúng giá trị backend hiểu (lose, maintain, gain)
      const goalMap = {
        'lose_weight': 'weight_loss',
        'maintain_weight': 'maintain',
        'gain_muscle': 'muscle_gain',
        'weight_loss': 'weight_loss',
        'maintain': 'maintain',
        'muscle_gain': 'muscle_gain',
        'lose': 'weight_loss',
        'gain': 'muscle_gain',
      };
      final mappedGoal = goalMap[goal] ?? 'maintain';

      try {
        if (kDebugMode) {
          debugPrint('[NUTRITION] Generating plan');
        }

        final plan = await _repository.generatePlan(
          goal: mappedGoal,
          targetCalories: 0, // Gửi 0 — backend sẽ tự lấy từ profile
        );

        // Macro targets are now part of the NutritionPlan object or fetched separately if needed.
        // Assuming _repository.generatePlan now returns a NutritionPlan that includes macro targets
        // or that macro targets are updated by a separate mechanism.
        // If macro targets are returned as part of the plan, they would be accessed via plan.macroTargets.
        // For now, we'll assume the plan object itself contains the necessary data.
        // If the API returns macro targets separately, the repository should handle setting them.
        // Macro targets are not available in legacy NutritionPlan model
        // _macroTargets = null; // Commented out since not supported

        // Fetch existing data from API
        int currentWater = 0;
        int targetWater = 2000;
        List<NutritionLogEntry> existingEntries = [];

        try {
          final d = await _repository.getDailyPlan(dateStr);
          currentWater = d.currentWater;
          targetWater = d.targetWater;
          existingEntries = d.entries;
        } catch (_) {
          // Silent error handling
        }

        final planWithWater = plan.copyWith(
          currentWater: currentWater,
          targetWater: targetWater,
          entries: existingEntries,
        );

        _localCache[dateStr] = planWithWater;
        // Prevent memory leak – limit cache to 30 entries (approx 1 month)
        if (_localCache.length > 30) {
          final sortedKeys = _localCache.keys.toList()..sort();
          _localCache.remove(sortedKeys.first); // oldest date first
        }
        state = AsyncValue.data(planWithWater);

        if (kDebugMode) {
          debugPrint('[NUTRITION] Plan generated successfully');
        }
      } on DioException catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[NUTRITION] Plan request failed: '
            'status=${e.response?.statusCode ?? 'none'} type=${e.type.name}',
          );
        }
        state = AsyncValue.error(e, e.stackTrace);
      } catch (e, st) {
        debugPrint('❌ generateAutoPlan error: $e');
        state = AsyncValue.error(e, st);
      }
    } finally {
      _isGenerating = false;
    }
  }

  // =========================================================
  // 3. WATER UPDATE (ATOMIC API)
  // =========================================================
  Future<void> updateWater(int amountMl, {required String date}) async {
    final currentPlan = state.value;
    if (currentPlan == null) return;

    // Lưu lại giá trị cũ để rollback nếu API fail
    final previousWater = currentPlan.currentWater;
    final previousPlan = currentPlan;

    // Optimistic Update
    final updatedPlan = currentPlan.copyWith(currentWater: amountMl);
    state = AsyncValue.data(updatedPlan);
    _localCache[currentPlan.date] = updatedPlan;

    try {
      final ok =
          await _updateWaterUseCase.execute(date: date, amountMl: amountMl);
      if (!ok) {
        throw Exception('Failed to update water intake');
      }
    } catch (e) {
      // Rollback về giá trị cũ
      debugPrint("❌ Sync Water Failed, rolling back: $e");
      state = AsyncValue.data(previousPlan);
      _localCache[currentPlan.date] = previousPlan;
      rethrow; // Đẩy lỗi ra UI xử lý (show SnackBar)
    }
  }

  // =========================================================
  // 4. ADD MEAL (FIX LỖI undefined_method)
  // =========================================================
  Future<bool> addMeal({
    required DateTime date,
    required String mealType,
    required String foodId,
    required String name,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required int weightGrams,
  }) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      // Backend POST /api/nutrition/logs expects NutritionLog: date, meal_type, foods, total_calories, notes
      final body = {
        "date": dateStr,
        "meal_type": mealType,
        "foods": [
          {
            "name": name,
            "calories": calories.round(),
            "protein": protein,
            "carbs": carbs,
            "fat": fat,
            "food_id": foodId,
            "weight_grams": weightGrams,
          },
        ],
        "total_calories": calories.round(),
        "notes": "",
      };

      final ok = await _repository.addMeal(body);

      if (ok) {
        // Reload để lấy data chuẩn từ server (bao gồm ID của meal vừa tạo)
        // forceRefresh = true để cập nhật cache
        await loadDailyPlan(date, forceRefresh: true);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint("❌ Error adding meal: $e");
      return false;
    }
  }

  // =========================================================
  // 5. SWAP MEAL & UPDATE STATUS (FIX LỖI undefined_method)
  // =========================================================
  Future<void> swapMeal(Meal oldMeal, String goal) async {
    final currentPlan = state.value;
    if (currentPlan == null) return;

    try {
      final date = DateFormat('yyyy-MM-dd').parse(currentPlan.date);
      final plan = await _swapMealUseCase.execute(
        date: date,
        oldMeal: oldMeal,
        goal: goal,
      );

      _localCache[currentPlan.date] = plan;
      state = AsyncValue.data(plan);
    } catch (e) {
      debugPrint("Swap suggested meal failed: $e");
    }
  }

  Future<void> swapLoggedMeal(DateTime date, String logId) async {
    final currentPlan = state.value;
    if (currentPlan == null) return;

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final ok =
          await _swapLoggedMealUseCase.execute(date: dateStr, logId: logId);
      if (ok) {
        // Refresh after swap
        await loadDailyPlan(date, forceRefresh: true);
      } else {
        throw Exception('Failed to swap logged meal');
      }
    } catch (e) {
      debugPrint("❌ Error swapping logged meal: $e");
    }
  }

  Future<void> updateMealStatus(Meal meal, bool isEaten) async {
    final currentPlan = state.value;
    if (currentPlan == null) return;

    // Tìm và update status trong list
    final updatedMeals = currentPlan.meals.map((m) {
      if (m.name == meal.name && m.mealType == meal.mealType) {
        return m.copyWith(isEaten: isEaten);
      }
      return m;
    }).toList();

    // Tạo plan mới
    final updatedPlan = currentPlan.copyWith(meals: updatedMeals);

    // Update State & Cache ngay lập tức
    state = AsyncValue.data(updatedPlan);
    _localCache[currentPlan.date] = updatedPlan;
  }

  // =========================================================
  // 7. RESET DAY
  // =========================================================
  Future<bool> resetDay(DateTime date) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    try {
      final ok = await _repository.resetDay(dateStr);
      if (ok) {
        _localCache.remove(dateStr);
        await loadDailyPlan(date, forceRefresh: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ resetDay error: $e");
      return false;
    }
  }

  void clearCache() {
    _localCache.clear();
    _macroTargets = null;
    // Trigger state update to notify listeners
    state = AsyncValue.data(state.value);
  }

  // =========================================================
  // 6. GENERATE SMART PLAN
  // =========================================================
  Future<void> generateSmartPlan({
    required DateTime date,
    required int mealCount,
    required String style,
    bool remainingOnly = true,
  }) async {
    _lastMealCount = mealCount; // ← NEW: lưu lại để dùng cho swap
    _lastStyle = style; // ← NEW: lưu lại để dùng cho swap

    if (_isGenerating || _isMealPlanGenerating) {
      debugPrint('⚠️ generateSmartPlan already running, skip');
      return;
    }

    // ✅ C8: Use local loading instead of entire state loading
    _isMealPlanGenerating = true;
    _isGenerating = true;

    // Notify UI that loading started
    state = AsyncValue.data(state.value);

    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    try {
      final plan = await _repository.generatePlan(
        goal: _lastGoal ?? 'maintain',
        mealCount: mealCount,
        style: style,
        remainingOnly: remainingOnly,
      );

      // Macro targets are not available in legacy NutritionPlan model
      // _macroTargets = null; // Commented out since not supported

      // ===== Merge water + entries từ GET /{date} =====
      List<NutritionLogEntry> existingEntries = [];
      int currentWater = 0;
      int targetWater = 2000;
      int totalCal = 0;
      int totalPro = 0;
      int totalCarbs = 0;
      int totalFat = 0;

      try {
        final d = await _repository.getDailyPlan(dateStr);
        currentWater = d.currentWater;
        targetWater = d.targetWater;
        existingEntries = d.entries;

        totalCal = d.totalCaloriesConsumed;
        totalPro = d.totalProteinConsumed.toInt();
        totalCarbs = d.totalCarbsConsumed.toInt();
        totalFat = d.totalFatConsumed.toInt();
      } catch (e) {
        debugPrint("⚠️ Merge Error: $e");
      }

      final merged = plan.copyWith(
        currentWater: currentWater,
        targetWater: targetWater,
        entries: existingEntries,
        totalCaloriesConsumed: totalCal,
        totalProteinConsumed: totalPro,
        totalCarbsConsumed: totalCarbs,
        totalFatConsumed: totalFat,
      );

      _localCache[dateStr] = merged;
      // Prevent memory leak – limit cache to 30 entries (approx 1 month)
      if (_localCache.length > 30) {
        final sortedKeys = _localCache.keys.toList()..sort();
        _localCache.remove(sortedKeys.first); // oldest date first
      }
      state = AsyncValue.data(merged);

      if (kDebugMode) {
        debugPrint('[NUTRITION] Smart plan generated successfully');
      }
    } catch (e, st) {
      debugPrint('❌ generateSmartPlan error: $e');
      // If error, we might want to show error to user, but let's keep previous data
      state = AsyncValue.data(state.value);
    } finally {
      _isGenerating = false;
      _isMealPlanGenerating = false;
      // Final update to clear loading flag in UI
      state = AsyncValue.data(state.value);
    }
  }
}

// [File: lib/providers/nutrition_provider.dart]
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import '../features/nutrition/domain/repositories/nutrition_repository.dart';
import '../features/nutrition/data/repositories/nutrition_repository_impl.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';
import '../presentation/providers/workout_history_providers.dart';

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
  ref.watch(workoutAuthScopeProvider);
  final session = ref.watch(nutritionSessionProvider);
  final repository = ref.watch(nutritionRepositoryProvider);
  return NutritionNotifier(
    captureSession: session.capture,
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
    Future<NutritionRequestContext> Function()? captureSession,
    required LoadDailyPlanUseCase loadDailyPlanUseCase,
    required UpdateWaterUseCase updateWaterUseCase,
    required SwapMealUseCase swapMealUseCase,
    required SwapLoggedMealUseCase swapLoggedMealUseCase,
  })  : _captureSession = captureSession,
        _repository = repository,
        _loadDailyPlanUseCase = loadDailyPlanUseCase,
        _updateWaterUseCase = updateWaterUseCase,
        _swapMealUseCase = swapMealUseCase,
        _swapLoggedMealUseCase = swapLoggedMealUseCase,
        super(const AsyncValue.loading());

  // ✅ CACHE: Lưu trữ dữ liệu các ngày đã tải
  final Map<String, NutritionPlan> _localCache = {};

  final Future<NutritionRequestContext> Function()? _captureSession;
  NutritionRequestContext? _owner;
  String? _selectedDate;
  int _loadRequest = 0;
  final Map<String, int> _dateEpoch = {};
  final Map<String, int> _dailyReads = {};
  final Map<String, ({int amount, int target, int version})> _waterSnapshots =
      {};
  final Map<String, ({String date, int deltaMl, bool confirmed})>
      _waterOperations = {};
  final Set<String> _waterInFlight = {};

  Future<NutritionRequestContext?> _captureOwner() async {
    final owner = await _captureSession?.call();
    await _validateOwner(owner);
    if (_owner != null &&
        owner != null &&
        (_owner!.generation != owner.generation ||
            _owner!.authorization != owner.authorization)) {
      _localCache.clear();
      _waterSnapshots.clear();
      _waterOperations.clear();
      _dailyReads.clear();
      _dateEpoch.clear();
      _lastFailedWaterKey = null;
      _lastWaterKey = null;
      state = const AsyncValue.loading();
    }
    _owner = owner;
    return owner;
  }

  Future<void> _validateOwner(NutritionRequestContext? owner) async {
    if (!mounted) throw const NutritionSessionChanged();
    await owner?.validate();
    if (!mounted) throw const NutritionSessionChanged();
  }

  NutritionPlan? _knownPlan(String date) {
    final current = state.valueOrNull;
    return current?.date == date ? current : _localCache[date];
  }

  NutritionPlan _preserveWater(NutritionPlan plan) {
    final water = _waterSnapshots[plan.date];
    if (water == null || plan.waterVersion >= water.version) return plan;
    return plan.copyWith(
        currentWater: water.amount,
        targetWater: water.target,
        waterVersion: water.version);
  }

  void _remember(NutritionPlan plan, {bool waterConfirmed = true}) {
    _localCache[plan.date] = plan;
    if (waterConfirmed) {
      _waterSnapshots[plan.date] = (
        amount: plan.currentWater,
        target: plan.targetWater,
        version: plan.waterVersion
      );
    }
    if (_localCache.length > 30) {
      final dates = _localCache.keys.toList()..sort();
      _localCache.remove(dates.first);
    }
    if (_waterSnapshots.length > 30) {
      final dates = _waterSnapshots.keys.toList()..sort();
      _waterSnapshots.remove(dates.first);
    }
  }

  void _acceptDaily(NutritionPlan plan) {
    final merged = _preserveWater(plan);
    _remember(merged);
    _dailyReads[plan.date] = (_dailyReads[plan.date] ?? 0) + 1;
    if (_selectedDate == null || _selectedDate == plan.date) {
      state = AsyncValue.data(merged);
    }
  }

  void _loadError(Object error, StackTrace trace, String date) {
    if (!mounted || (_selectedDate != null && _selectedDate != date)) return;
    final known = _knownPlan(date);
    state = known == null
        ? AsyncValue.error(error, trace)
        : AsyncValue<NutritionPlan?>.error(error, trace)
            .copyWithPrevious(AsyncValue.data(known));
  }

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
  String? _lastWaterKey;
  String? get lastWaterKey => _lastWaterKey;
  String? _lastFailedWaterKey;
  String? get lastFailedWaterKey => _lastFailedWaterKey;

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
    final request = ++_loadRequest;
    _selectedDate = dateStr;
    final epoch = _dateEpoch[dateStr] ?? 0;
    NutritionRequestContext? owner;
    try {
      owner = await _captureOwner();
      if (_localCache.isEmpty ||
          !_localCache.containsKey(dateStr) ||
          _lastGoal != fallbackGoal) _macroTargets = null;
      _lastGoal = fallbackGoal;
      if (!forceRefresh &&
          _localCache.containsKey(dateStr) &&
          !state.hasError) {
        state = AsyncValue.data(_localCache[dateStr]);
        return;
      }
      if (!forceRefresh && _knownPlan(dateStr) == null) {
        state = const AsyncValue.loading();
      }
      final plan = await _loadDailyPlanUseCase.execute(date, session: owner);
      await _validateOwner(owner);
      if (epoch != (_dateEpoch[dateStr] ?? 0)) return;
      _acceptDaily(plan);
    } catch (e, st) {
      if (!mounted) return;
      try {
        await _validateOwner(owner);
      } catch (_) {
        return;
      }
      if (request == _loadRequest && epoch == (_dateEpoch[dateStr] ?? 0)) {
        _loadError(e, st, dateStr);
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
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    _selectedDate ??= dateStr;
    final epoch = _dateEpoch[dateStr] ?? 0;
    NutritionRequestContext? owner;
    try {
      owner = await _captureOwner();
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
      // Repository generation includes an authoritative daily intake read.
      final plan = await _repository.generatePlan(
        dateStr: dateStr,
        goal: goalMap[goal] ?? 'maintain',
        targetCalories: 0,
        session: owner,
      );
      await _validateOwner(owner);
      if (epoch == (_dateEpoch[dateStr] ?? 0)) _acceptDaily(plan);
    } catch (e, st) {
      if (!mounted) return;
      try {
        await _validateOwner(owner);
      } catch (_) {
        return;
      }
      if (epoch == (_dateEpoch[dateStr] ?? 0)) _loadError(e, st, dateStr);
    } finally {
      _isGenerating = false;
    }
  }

  // =========================================================
  // 3. WATER UPDATE & ADD (ATOMIC & OPTIMISTIC CONCURRENCY)
  // =========================================================
  Future<String> addWater(int deltaMl,
      {required String date, String? idempotencyKey}) async {
    final owner = _captureSession == null ? null : await _captureOwner();
    final currentPlan = _knownPlan(date);
    if (currentPlan == null) {
      throw StateError('Load Water for this date before updating.');
    }

    var retryKey = _lastFailedWaterKey;
    if (_waterOperations[retryKey]?.date != date) {
      retryKey = null;
      for (final operation in _waterOperations.entries) {
        if (operation.value.date == date &&
            !operation.value.confirmed &&
            !_waterInFlight.contains(operation.key)) {
          retryKey = operation.key;
          break;
        }
      }
    }
    final failed = _waterOperations[retryKey];
    if (idempotencyKey == null &&
        failed != null &&
        failed.date == date &&
        failed.deltaMl != deltaMl) {
      throw StateError(
          'Retry the pending Water update before changing its amount.');
    }
    final key = idempotencyKey ??
        (failed != null && failed.date == date
            ? retryKey!
            : 'water_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}');
    final prior = _waterOperations[key];
    if (prior != null && (prior.date != date || prior.deltaMl != deltaMl)) {
      throw ArgumentError(
          'A Water retry must keep its original date and amount.');
    }
    if (!_waterInFlight.add(key)) {
      throw StateError('Water update is still pending.');
    }
    _lastWaterKey = key;
    _waterOperations[key] =
        prior ?? (date: date, deltaMl: deltaMl, confirmed: false);
    final readRevision = _dailyReads[date] ?? 0;
    var confirmed = prior?.confirmed ?? false;
    final isNewOperation = prior == null && idempotencyKey == null;
    if (isNewOperation) {
      final optimistic = currentPlan.copyWith(
        currentWater: currentPlan.currentWater + deltaMl,
        waterVersion: currentPlan.waterVersion + 1,
      );
      _remember(optimistic, waterConfirmed: false);
      if (_selectedDate == null || _selectedDate == date) {
        state = AsyncValue.data(optimistic);
      }
    }
    try {
      if (!confirmed) {
        final ok = await _updateWaterUseCase.execute(
          date: date,
          deltaMl: deltaMl,
          idempotencyKey: key,
          session: owner,
        );
        await _validateOwner(owner);
        if (!ok) throw StateError('Failed to add water intake');
        confirmed = true;
        _waterOperations[key] = (date: date, deltaMl: deltaMl, confirmed: true);
        // The acknowledged delta advances this daily document once. Pending
        // optimistic deltas are not server versions. A concurrent GET may
        // already include this key, in which case only the reread can reconcile.
        if (isNewOperation && readRevision == (_dailyReads[date] ?? 0)) {
          final water = _waterSnapshots[date];
          if (water != null) {
            _waterSnapshots[date] = (
              amount: water.amount + deltaMl,
              target: water.target,
              version: water.version + 1
            );
          }
        }
      }
      // A lost response may already have been reflected by an intervening GET.
      // Reread the exact version, including on retry; never add its delta twice.
      final daily = await _repository.getDailyPlan(date, session: owner);
      await _validateOwner(owner);
      _acceptDaily(daily);
      if (_lastFailedWaterKey == key) _lastFailedWaterKey = null;
      // Keep unresolved operations; bound the history of acknowledged keys.
      if (_waterOperations.length > 128) {
        final completed = _waterOperations.keys
            .where((k) =>
                k != key &&
                k != _lastFailedWaterKey &&
                _waterOperations[k]!.confirmed)
            .toList();
        if (completed.isNotEmpty) _waterOperations.remove(completed.first);
      }
      return key;
    } catch (e, st) {
      await _validateOwner(owner);
      _lastFailedWaterKey = key;
      if (isNewOperation &&
          !confirmed &&
          readRevision == (_dailyReads[date] ?? 0)) {
        final current = _knownPlan(date);
        if (current != null) {
          final reverted = current.copyWith(
            currentWater: max(0, current.currentWater - deltaMl),
            waterVersion: max(0, current.waterVersion - 1),
          );
          _remember(reverted, waterConfirmed: false);
          if (_selectedDate == null || _selectedDate == date) {
            state = AsyncValue.data(reverted);
          }
        }
      }
      if (confirmed) {
        final reloadError = StateError(
            'Water update was acknowledged, but reload failed. Retry to reload. $e');
        _loadError(reloadError, st, date);
        throw reloadError;
      }
      _loadError(e, st, date);
      rethrow;
    } finally {
      _waterInFlight.remove(key);
    }
  }

  Future<void> updateWater(int amountMl, {required String date}) async {
    final owner = _captureSession == null ? null : await _captureOwner();
    final currentPlan = _knownPlan(date);
    if (currentPlan == null) return;
    final readRevision = _dailyReads[date] ?? 0;
    final updatedPlan = currentPlan.copyWith(
      currentWater: amountMl,
      waterVersion: currentPlan.waterVersion + 1,
    );
    _remember(updatedPlan, waterConfirmed: false);
    if (_selectedDate == null || _selectedDate == date) {
      state = AsyncValue.data(updatedPlan);
    }
    try {
      final ok = await _updateWaterUseCase.execute(
        date: date,
        amountMl: amountMl,
        version: currentPlan.waterVersion,
        session: owner,
      );
      await _validateOwner(owner);
      if (!ok) throw StateError('Failed to update water intake');
      _acceptDaily(updatedPlan);
    } catch (e, st) {
      await _validateOwner(owner);
      if (readRevision == (_dailyReads[date] ?? 0)) {
        _remember(currentPlan, waterConfirmed: false);
        if (_selectedDate == null || _selectedDate == date) {
          state = AsyncValue.data(currentPlan);
        }
      }
      final isConflict = e.toString().contains('409') ||
          (e is DioException && e.response?.statusCode == 409);
      if (isConflict) {
        await loadDailyPlan(DateTime.parse(date), forceRefresh: true);
      } else {
        _loadError(e, st, date);
      }
      rethrow;
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
    NutritionRequestContext? owner;
    try {
      owner = await _captureOwner();
      // reset-day only resets meal visibility. Water's document/version survives.
      _dateEpoch[dateStr] = (_dateEpoch[dateStr] ?? 0) + 1;
      final ok = await _repository.resetDay(dateStr, session: owner);
      await _validateOwner(owner);
      if (ok) {
        _localCache.remove(dateStr);
        await loadDailyPlan(date, forceRefresh: true);
        return true;
      }
      return false;
    } catch (e, st) {
      if (!mounted) return false;
      try {
        await _validateOwner(owner);
      } catch (_) {
        return false;
      }
      _loadError(e, st, dateStr);
      return false;
    }
  }

  void clearCache() {
    _localCache.clear();
    _macroTargets = null;
    // Trigger state update to notify listeners
    if (!state.hasError) state = AsyncValue.data(state.valueOrNull);
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
    _lastMealCount = mealCount;
    _lastStyle = style;
    if (_isGenerating || _isMealPlanGenerating) return;
    _isMealPlanGenerating = true;
    _isGenerating = true;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    _selectedDate ??= dateStr;
    final epoch = _dateEpoch[dateStr] ?? 0;
    NutritionRequestContext? owner;
    try {
      owner = await _captureOwner();
      state = AsyncValue.data(state.valueOrNull);
      final plan = await _repository.generatePlan(
        dateStr: dateStr,
        goal: _lastGoal ?? 'maintain',
        mealCount: mealCount,
        style: style,
        remainingOnly: remainingOnly,
        session: owner,
      );
      await _validateOwner(owner);
      if (epoch == (_dateEpoch[dateStr] ?? 0)) _acceptDaily(plan);
    } catch (e, st) {
      if (!mounted) return;
      try {
        await _validateOwner(owner);
      } catch (_) {
        return;
      }
      if (epoch == (_dateEpoch[dateStr] ?? 0)) _loadError(e, st, dateStr);
    } finally {
      _isGenerating = false;
      _isMealPlanGenerating = false;
      if (mounted && !state.hasError) {
        state = AsyncValue.data(state.valueOrNull);
      }
    }
  }
}

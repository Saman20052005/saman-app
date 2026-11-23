import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/nutrition_model.dart';
import '../../../../presentation/providers/workout_history_providers.dart';
import '../../../../providers/nutrition_provider.dart';
import '../../../../utils/auth_helper.dart';
import '../../domain/repositories/nutrition_repository.dart';

class RecipesState {
  final List<RecipeModel> recipes;
  final bool isLoading;
  final bool isMutating;
  final String? error;

  const RecipesState({
    this.recipes = const [],
    this.isLoading = false,
    this.isMutating = false,
    this.error,
  });

  RecipesState copyWith({
    List<RecipeModel>? recipes,
    bool? isLoading,
    bool? isMutating,
    String? error,
    bool clearError = false,
  }) {
    return RecipesState(
      recipes: recipes ?? this.recipes,
      isLoading: isLoading ?? this.isLoading,
      isMutating: isMutating ?? this.isMutating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class RecipesNotifier extends StateNotifier<RecipesState> {
  final Ref _ref;
  final INutritionRepository _repo;
  int _epoch = 0;
  Future<void>? _inFlightLoad;
  int _loadSeq = 0;

  RecipesNotifier(this._ref, this._repo) : super(const RecipesState()) {
    _ref.listen<int>(workoutAuthScopeProvider, (_, __) => _reset());
    _ref.listen<bool>(authLoggingOutProvider, (_, next) {
      if (next) _reset();
    });
  }

  void _reset() {
    _epoch++;
    _inFlightLoad = null;
    _loadSeq++;
    if (mounted) {
      state = const RecipesState();
    }
  }

  bool _isStale(int scopeAtStart, int epochAtStart) {
    return !mounted ||
        _ref.read(authLoggingOutProvider) ||
        _ref.read(workoutAuthScopeProvider) != scopeAtStart ||
        _epoch != epochAtStart;
  }

  Future<void> loadRecipes({bool force = false}) {
    if (_ref.read(authLoggingOutProvider)) return Future.value();
    if (!force && _inFlightLoad != null) {
      return _inFlightLoad!;
    }
    final seq = ++_loadSeq;
    late final Future<void> future;
    future = _executeLoadRecipes(seq).whenComplete(() {
      if (identical(_inFlightLoad, future)) {
        _inFlightLoad = null;
      }
    });
    _inFlightLoad = future;
    return future;
  }

  Future<void> _executeLoadRecipes(int seq) async {
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final recipes = await _repo.getRecipes();
      if (_isStale(scopeAtStart, epochAtStart) || seq != _loadSeq) return;
      state = state.copyWith(
        recipes: recipes,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (_isStale(scopeAtStart, epochAtStart) || seq != _loadSeq) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<RecipeModel?> createRecipe(Map<String, dynamic> payload) async {
    if (_ref.read(authLoggingOutProvider)) return null;
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final created = await _repo.createRecipe(payload);
      if (_isStale(scopeAtStart, epochAtStart)) return null;
      state = state.copyWith(
        recipes: [created, ...state.recipes],
        isMutating: false,
        clearError: true,
      );
      return created;
    } catch (e) {
      if (_isStale(scopeAtStart, epochAtStart)) return null;
      state = state.copyWith(
        isMutating: false,
        error: e.toString(),
      );
      return null;
    }
  }

  Future<bool> deleteRecipe(String recipeId) async {
    if (_ref.read(authLoggingOutProvider)) return false;
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final ok = await _repo.deleteRecipe(recipeId);
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      state = state.copyWith(
        recipes: ok
            ? state.recipes.where((r) => r.id != recipeId).toList()
            : state.recipes,
        isMutating: false,
        clearError: true,
      );
      return ok;
    } catch (e) {
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      state = state.copyWith(
        isMutating: false,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<bool> logRecipeServing(
    String recipeId, {
    String? date,
    String mealType = 'snack',
    double servingsConsumed = 1.0,
    bool refreshPlan = true,
  }) async {
    if (_ref.read(authLoggingOutProvider)) return false;
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final ok = await _repo.logRecipe(
        recipeId,
        date: date,
        mealType: mealType,
        servingsConsumed: servingsConsumed,
      );
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      state = state.copyWith(isMutating: false, clearError: true);
      if (ok && refreshPlan) {
        await _ref
            .read(nutritionProvider.notifier)
            .refreshCurrentPlan(dateStr: date);
      }
      return ok;
    } catch (e) {
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      state = state.copyWith(
        isMutating: false,
        error: e.toString(),
      );
      return false;
    }
  }
}

class SupplementsNotifier extends StateNotifier<AsyncValue<List<Supplement>>> {
  final Ref _ref;
  final INutritionRepository _repo;
  final String dateStr;
  int _epoch = 0;
  Future<void>? _inFlightLoad;
  int _loadSeq = 0;

  SupplementsNotifier(this._ref, this._repo, this.dateStr)
      : super(const AsyncValue.loading()) {
    _ref.listen<int>(workoutAuthScopeProvider, (_, __) => _reset());
    _ref.listen<bool>(authLoggingOutProvider, (_, next) {
      if (next) _reset();
    });
    if (_ref.read(authLoggingOutProvider)) {
      state = const AsyncValue.data([]);
    } else {
      load();
    }
  }

  void _reset() {
    _epoch++;
    _inFlightLoad = null;
    _loadSeq++;
    if (mounted) {
      state = const AsyncValue.data([]);
    }
  }

  bool _isStale(int scopeAtStart, int epochAtStart) {
    return !mounted ||
        _ref.read(authLoggingOutProvider) ||
        _ref.read(workoutAuthScopeProvider) != scopeAtStart ||
        _epoch != epochAtStart;
  }

  Future<void> load({bool force = false}) {
    if (_ref.read(authLoggingOutProvider)) {
      if (mounted) state = const AsyncValue.data([]);
      return Future.value();
    }
    if (!force && _inFlightLoad != null) {
      return _inFlightLoad!;
    }
    final seq = ++_loadSeq;
    late final Future<void> future;
    future = _executeLoad(seq).whenComplete(() {
      if (identical(_inFlightLoad, future)) {
        _inFlightLoad = null;
      }
    });
    _inFlightLoad = future;
    return future;
  }

  Future<void> _executeLoad(int seq) async {
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      final supplements = await _repo.getSupplements(dateStr);
      if (_isStale(scopeAtStart, epochAtStart) || seq != _loadSeq) return;
      state = AsyncValue.data(supplements);
    } catch (e, st) {
      if (_isStale(scopeAtStart, epochAtStart) || seq != _loadSeq) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> addSupplement(Map<String, dynamic> payload) async {
    if (_ref.read(authLoggingOutProvider)) return false;
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    try {
      await _repo.addSupplement(payload);
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      await load(force: true);
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      await _ref
          .read(nutritionProvider.notifier)
          .refreshCurrentPlan(dateStr: dateStr);
      return true;
    } catch (e, st) {
      if (!_isStale(scopeAtStart, epochAtStart)) {
        state = AsyncValue.error(e, st);
      }
      return false;
    }
  }

  Future<bool> deleteSupplement(String logId) async {
    if (_ref.read(authLoggingOutProvider)) return false;
    final scopeAtStart = _ref.read(workoutAuthScopeProvider);
    final epochAtStart = _epoch;

    try {
      final ok = await _repo.deleteSupplement(logId);
      if (_isStale(scopeAtStart, epochAtStart)) return false;
      if (ok) {
        await load(force: true);
        if (_isStale(scopeAtStart, epochAtStart)) return false;
        await _ref
            .read(nutritionProvider.notifier)
            .refreshCurrentPlan(dateStr: dateStr);
      }
      return ok;
    } catch (e, st) {
      if (!_isStale(scopeAtStart, epochAtStart)) {
        state = AsyncValue.error(e, st);
      }
      return false;
    }
  }
}

final recipesProvider =
    StateNotifierProvider<RecipesNotifier, RecipesState>((ref) {
  ref.watch(workoutAuthScopeProvider);
  final repo = ref.watch(nutritionRepositoryProvider);
  return RecipesNotifier(ref, repo);
});

final supplementsByDateProvider = StateNotifierProvider.family<
    SupplementsNotifier, AsyncValue<List<Supplement>>, String>((ref, dateStr) {
  ref.watch(workoutAuthScopeProvider);
  final repo = ref.watch(nutritionRepositoryProvider);
  return SupplementsNotifier(ref, repo, dateStr);
});

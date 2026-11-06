import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/food_model.dart';
import '../../../../providers/nutrition_provider.dart';
import '../../../../providers/profile_provider.dart';

class UsualFoodItem {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final List<String> tags;
  final String? imageUrl;
  final DateTime lastUsedAt;

  const UsualFoodItem({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.tags = const [],
    this.imageUrl,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'tags': tags,
        'imageUrl': imageUrl,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory UsualFoodItem.fromJson(Map<String, dynamic> json) {
    double parseD(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return UsualFoodItem(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? 'Unknown').toString(),
      calories: parseD(json['calories']),
      protein: parseD(json['protein']),
      carbs: parseD(json['carbs']),
      fat: parseD(json['fat']),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      imageUrl: json['imageUrl']?.toString(),
      lastUsedAt: parseDate(json['lastUsedAt']),
    );
  }

  FoodModel toFoodModel() => FoodModel(
        id: id,
        name: name,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        tags: tags,
      );

  UsualFoodItem copyWith({
    String? id,
    String? name,
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    List<String>? tags,
    String? imageUrl,
    DateTime? lastUsedAt,
  }) =>
      UsualFoodItem(
        id: id ?? this.id,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        tags: tags ?? this.tags,
        imageUrl: imageUrl ?? this.imageUrl,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );
}

enum UsualsTab { recent, favorites }

class UsualFoodsState {
  final UsualsTab selectedTab;
  final bool isLoading;
  final String? error;
  final List<UsualFoodItem> recents;
  final List<UsualFoodItem> favorites;
  final Set<String> favoriteIds;

  const UsualFoodsState({
    this.selectedTab = UsualsTab.recent,
    this.isLoading = false,
    this.error,
    this.recents = const [],
    this.favorites = const [],
    this.favoriteIds = const {},
  });

  UsualFoodsState copyWith({
    UsualsTab? selectedTab,
    bool? isLoading,
    String? Function()? error,
    List<UsualFoodItem>? recents,
    List<UsualFoodItem>? favorites,
    Set<String>? favoriteIds,
  }) {
    return UsualFoodsState(
      selectedTab: selectedTab ?? this.selectedTab,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      recents: recents ?? this.recents,
      favorites: favorites ?? this.favorites,
      favoriteIds: favoriteIds ?? this.favoriteIds,
    );
  }
}

class UsualFoodsNotifier extends StateNotifier<UsualFoodsState> {
  final String userId;
  final Ref? _ref;

  UsualFoodsNotifier({
    required this.userId,
    Ref? ref,
  })  : _ref = ref,
        super(const UsualFoodsState(isLoading: true));

  static String recentFoodsKey(String uid) => 'nutrition_recent_foods_$uid';
  static String favoritesKey(String uid) => 'nutrition_favorites_$uid';

  void switchTab(UsualsTab tab) {
    if (state.selectedTab != tab) {
      state = state.copyWith(selectedTab: tab);
    }
  }

  Future<void> loadUsuals() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load favorites from local storage
      final favRaw = prefs.getString(favoritesKey(userId));
      final List<UsualFoodItem> favs = [];
      final Set<String> favIds = {};
      if (favRaw != null && favRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(favRaw) as List<dynamic>;
          for (final item in decoded) {
            final f = UsualFoodItem.fromJson(Map<String, dynamic>.from(item as Map));
            if (f.id.isNotEmpty && !favIds.contains(f.id)) {
              favs.add(f);
              favIds.add(f.id);
            }
          }
        } catch (e) {
          debugPrint('Error parsing stored favorites: $e');
        }
      }

      // 2. Load recents from local storage
      final recentRaw = prefs.getString(recentFoodsKey(userId));
      final List<UsualFoodItem> storedRecents = [];
      if (recentRaw != null && recentRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(recentRaw) as List<dynamic>;
          for (final item in decoded) {
            final f = UsualFoodItem.fromJson(Map<String, dynamic>.from(item as Map));
            if (f.id.isNotEmpty) {
              storedRecents.add(f);
            }
          }
        } catch (e) {
          debugPrint('Error parsing stored recents: $e');
        }
      }

      // 3. Extract confirmed entries from current nutrition state
      final currentPlan = _ref?.read(nutritionProvider).valueOrNull;
      final List<UsualFoodItem> currentPlanItems = [];
      if (currentPlan != null && currentPlan.entries.isNotEmpty) {
        for (final entry in currentPlan.entries) {
          if (entry.foods.isNotEmpty) {
            for (final foodMap in entry.foods) {
              final foodId = (foodMap['food_id'] ?? foodMap['id'] ?? foodMap['_id'] ?? entry.logId).toString();
              final foodName = (foodMap['name'] ?? entry.foodName).toString();
              if (foodId.isNotEmpty && foodName.isNotEmpty) {
                currentPlanItems.add(UsualFoodItem(
                  id: foodId,
                  name: foodName,
                  calories: (foodMap['calories'] as num?)?.toDouble() ??
                      entry.totalCalories.toDouble(),
                  protein: (foodMap['protein'] as num?)?.toDouble() ?? entry.protein,
                  carbs: (foodMap['carbs'] as num?)?.toDouble() ?? entry.carbs,
                  fat: (foodMap['fat'] as num?)?.toDouble() ?? entry.fat,
                  tags: const [],
                  imageUrl: entry.imageUrl,
                  lastUsedAt: DateTime.now(),
                ));
              }
            }
          } else if (entry.logId.isNotEmpty && entry.foodName.isNotEmpty) {
            currentPlanItems.add(UsualFoodItem(
              id: entry.logId,
              name: entry.foodName,
              calories: entry.totalCalories.toDouble(),
              protein: entry.protein,
              carbs: entry.carbs,
              fat: entry.fat,
              tags: const [],
              imageUrl: entry.imageUrl,
              lastUsedAt: DateTime.now(),
            ));
          }
        }
      }

      // 4. Merge & Deduplicate recents by food.id, prioritizing latest timestamp
      final allRecents = [...currentPlanItems, ...storedRecents];
      final Map<String, UsualFoodItem> deduplicated = {};
      for (final item in allRecents) {
        if (!deduplicated.containsKey(item.id) ||
            item.lastUsedAt.isAfter(deduplicated[item.id]!.lastUsedAt)) {
          deduplicated[item.id] = item;
        }
      }

      final sortedRecents = deduplicated.values.toList()
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));

      // Limit to 20 items
      final finalRecents = sortedRecents.take(20).toList();

      state = state.copyWith(
        isLoading: false,
        recents: finalRecents,
        favorites: favs,
        favoriteIds: favIds,
        error: () => null,
      );
    } catch (e) {
      debugPrint('Error loading usual foods: $e');
      state = state.copyWith(
        isLoading: false,
        error: () => e.toString(),
      );
    }
  }

  Future<void> toggleFavorite(UsualFoodItem food) async {
    final isFav = state.favoriteIds.contains(food.id);
    final prevFavorites = List<UsualFoodItem>.from(state.favorites);
    final prevFavIds = Set<String>.from(state.favoriteIds);

    List<UsualFoodItem> nextFavorites;
    Set<String> nextFavIds;

    if (isFav) {
      nextFavorites = prevFavorites.where((f) => f.id != food.id).toList();
      nextFavIds = Set<String>.from(prevFavIds)..remove(food.id);
    } else {
      nextFavorites = [food, ...prevFavorites];
      nextFavIds = Set<String>.from(prevFavIds)..add(food.id);
    }

    // Optimistic update
    state = state.copyWith(
      favorites: nextFavorites,
      favoriteIds: nextFavIds,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(nextFavorites.map((f) => f.toJson()).toList());
      await prefs.setString(favoritesKey(userId), jsonStr);
    } catch (e) {
      debugPrint('Failed to persist favorite: $e');
      // Rollback on persistence error
      state = state.copyWith(
        favorites: prevFavorites,
        favoriteIds: prevFavIds,
        error: () => 'Failed to save favorite: $e',
      );
    }
  }

  Future<void> recordRecent(FoodModel food) async {
    final effectiveId = food.id.trim().isNotEmpty
        ? food.id.trim()
        : 'catalog_${food.name.trim().toLowerCase()}';
    final newItem = UsualFoodItem(
      id: effectiveId,
      name: food.name,
      calories: food.calories,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
      tags: food.tags,
      lastUsedAt: DateTime.now(),
    );

    final updated = [
      newItem,
      ...state.recents.where((f) => f.id != effectiveId),
    ];
    final limited = updated.take(20).toList();

    state = state.copyWith(recents: limited);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(limited.map((f) => f.toJson()).toList());
      await prefs.setString(recentFoodsKey(userId), jsonStr);
    } catch (e) {
      debugPrint('Failed to persist recent food: $e');
    }
  }


  Future<void> upgradeLegacyReference({
    required String legacyId,
    required FoodModel newFood,
  }) async {
    if (legacyId.isEmpty || newFood.id.trim().isEmpty) return;
    final newId = newFood.id.trim();
    if (newId == legacyId) return;
    if (state.favoriteIds.contains(legacyId)) {
      final updatedFavorites = state.favorites.map((f) {
        if (f.id == legacyId) {
          return UsualFoodItem(
            id: newId,
            name: newFood.name,
            calories: newFood.calories,
            protein: newFood.protein,
            carbs: newFood.carbs,
            fat: newFood.fat,
            tags: newFood.tags,
            imageUrl: f.imageUrl,
            lastUsedAt: DateTime.now(),
          );
        }
        return f;
      }).toList();
      final updatedFavIds = Set<String>.from(state.favoriteIds)
        ..remove(legacyId)
        ..add(newId);
      state = state.copyWith(
        favorites: updatedFavorites,
        favoriteIds: updatedFavIds,
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = jsonEncode(updatedFavorites.map((f) => f.toJson()).toList());
        await prefs.setString(favoritesKey(userId), jsonStr);
      } catch (e) {
        debugPrint('Failed to persist upgraded favorite: ');
      }
    }
  }

  Future<void> retry() => loadUsuals();

  static Future<void> recordConfirmedFoodGlobally({
    WidgetRef? widgetRef,
    Ref? ref,
    required FoodModel food,
    String? userId,
  }) async {
    String resolvedUserId = userId ?? '';

    if (resolvedUserId.isEmpty) {
      try {
        ProfileState? profile;
        if (widgetRef != null) {
          profile = widgetRef.read(profileProvider);
        } else if (ref != null) {
          profile = ref.read(profileProvider);
        }
        if (profile != null) {
          resolvedUserId = profile.confirmedUserId ??
              profile.snapshot?.userId ??
              profile.snapshot?.email ??
              'guest';
        }
      } catch (_) {}
    }
    if (resolvedUserId.isEmpty) resolvedUserId = 'guest';

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = recentFoodsKey(resolvedUserId);
      final raw = prefs.getString(key);
      List<UsualFoodItem> current = [];
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          current = decoded
              .map((e) => UsualFoodItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .where((f) => f.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }

      final effectiveId = food.id.trim().isNotEmpty
          ? food.id.trim()
          : 'catalog_${food.name.trim().toLowerCase()}';
      final newItem = UsualFoodItem(
        id: effectiveId,
        name: food.name,
        calories: food.calories,
        protein: food.protein,
        carbs: food.carbs,
        fat: food.fat,
        tags: food.tags,
        lastUsedAt: DateTime.now(),
      );

      final nextList =
          [newItem, ...current.where((f) => f.id != effectiveId)].take(20).toList();
      await prefs.setString(key, jsonEncode(nextList.map((f) => f.toJson()).toList()));
    } catch (e) {
      debugPrint('Error recording recent food globally: $e');
    }
  }
}

final usualFoodsProvider =
    StateNotifierProvider.autoDispose<UsualFoodsNotifier, UsualFoodsState>((ref) {
  final profile = ref.watch(profileProvider);
  final userId = profile.confirmedUserId ??
      profile.snapshot?.userId ??
      profile.snapshot?.email ??
      'guest';

  final notifier = UsualFoodsNotifier(userId: userId, ref: ref);
  notifier.loadUsuals();
  return notifier;
});

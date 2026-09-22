import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/services/api_client.dart';

import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences not initialized');
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return ProfileRepositoryImpl(
    remoteDataSource: ProfileRemoteDataSourceImpl(dio: dio),
    localDataSource: ProfileLocalDataSourceImpl(sharedPreferences: prefs),
  );
});

// ─────────────────────────────────────────
// ProfileState
// ─────────────────────────────────────────
class ProfileState {
  final ProfileEntity profile;
  final int targetCalories;
  final int targetProtein;
  final int targetCarbs;
  final int targetFat;
  final int targetBurned;
  final int waterTargetMl; // ✅ ADD: water target từ backend
  final bool isLoading;

  ProfileState({
    required this.profile,
    this.targetCalories = 0,
    this.targetProtein = 0,
    this.targetCarbs = 0,
    this.targetFat = 0,
    this.targetBurned = 300,
    this.waterTargetMl = 2000, // ✅ default 2000ml
    this.isLoading = true,
  });

  factory ProfileState.initial() =>
      ProfileState(profile: ProfileEntity.empty(), isLoading: true);

  bool get isProfileValid => profile.isValid;

  ProfileState copyWith({
    ProfileEntity? profile,
    int? targetCalories,
    int? targetProtein,
    int? targetCarbs,
    int? targetFat,
    int? targetBurned,
    int? waterTargetMl,
    bool? isLoading,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      targetCalories: targetCalories ?? this.targetCalories,
      targetProtein: targetProtein ?? this.targetProtein,
      targetCarbs: targetCarbs ?? this.targetCarbs,
      targetFat: targetFat ?? this.targetFat,
      targetBurned: targetBurned ?? this.targetBurned,
      waterTargetMl: waterTargetMl ?? this.waterTargetMl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ─────────────────────────────────────────
// Provider
// ─────────────────────────────────────────
final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repository);
});

// ─────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────
class ProfileNotifier extends StateNotifier<ProfileState> {
  final ProfileRepository _repository;

  ProfileNotifier(this._repository) : super(ProfileState.initial());

  Future<void> loadProfile() async {
    try {
      final profile = await _repository.fetchProfile();
      if (profile != null) {
        await _loadStatsFromBackend(profile);
      } else {
        debugPrint("⚠️ Profile null");
        if (mounted) state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint("❌ Load Profile Error: $e");
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> updateProfile(ProfileEntity newProfile) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repository.syncProfile(newProfile);
      await _loadStatsFromBackend(newProfile);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  /// ✅ FIX: Lấy health_stats trực tiếp từ API thay vì tự tính.
  /// Backend là source of truth cho calories/macro/water.
  Future<void> _loadStatsFromBackend(ProfileEntity profile) async {
    try {
      // Gọi thẳng API profile để lấy health_stats mới nhất
      final response = await ApiClient.dio.get('/api/user/profile');
      final data = response.data as Map<String, dynamic>;
      final healthStats = data['health_stats'] as Map<String, dynamic>? ?? {};

      // ✅ Đọc từ backend — không tự tính
      final calories = _toInt(healthStats['daily_calories'] ??
          healthStats['target_calories'] ??
          healthStats['daily_calorie_needs']);
      final protein = _toInt(healthStats['target_protein']);
      final carbs = _toInt(healthStats['target_carbs']);
      final fat = _toInt(healthStats['target_fat']);
      final water = _toInt(healthStats['water_target_ml']);

      if (kDebugMode) {
        debugPrint('[PROFILE] Profile and health stats synchronized');
      }

      if (mounted) {
        state = ProfileState(
          profile: profile,
          targetCalories: calories > 0 ? calories : _calcLocalFallback(profile),
          targetProtein: protein,
          targetCarbs: carbs,
          targetFat: fat,
          waterTargetMl: water > 0 ? water : 2000,
          targetBurned: _calcBurned(profile),
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint(
          "⚠️ Could not load health_stats from backend: $e — using local calc");
      // Fallback: tính local nếu API fail
      _calculateStatsLocal(profile);
    }
  }

  /// Fallback tính local khi không có backend (offline hoặc lỗi)
  void _calculateStatsLocal(ProfileEntity profile) {
    final calories = _calcLocalFallback(profile);

    double pRatio = 0.25, cRatio = 0.50, fRatio = 0.25;
    if (profile.goal == Goal.gain_muscle) {
      pRatio = 0.30;
      cRatio = 0.45;
    }
    if (profile.goal == Goal.lose_weight) {
      pRatio = 0.40;
      cRatio = 0.30;
      fRatio = 0.30;
    }

    if (mounted) {
      state = ProfileState(
        profile: profile,
        targetCalories: calories,
        targetProtein: ((calories * pRatio) / 4).round(),
        targetCarbs: ((calories * cRatio) / 4).round(),
        targetFat: ((calories * fRatio) / 9).round(),
        targetBurned: _calcBurned(profile),
        waterTargetMl: 2000,
        isLoading: false,
      );
    }
  }

  int _calcLocalFallback(ProfileEntity profile) {
    if (!profile.isValid) return 2000;
    final bmr = profile.gender == Gender.male
        ? (10 * profile.weight!) +
            (6.25 * profile.height!) -
            (5 * profile.age!) +
            5
        : (10 * profile.weight!) +
            (6.25 * profile.height!) -
            (5 * profile.age!) -
            161;
    final mult = profile.activityLevel == ActivityLevel.high
        ? 1.9
        : profile.activityLevel == ActivityLevel.medium
            ? 1.55
            : 1.2;
    final maintenance = bmr * mult;
    return profile.goal == Goal.gain_muscle
        ? (maintenance + 300).round()
        : profile.goal == Goal.lose_weight
            ? (maintenance - 500).round()
            : maintenance.round();
  }

  int _calcBurned(ProfileEntity profile) {
    return profile.activityLevel == ActivityLevel.high
        ? 700
        : profile.activityLevel == ActivityLevel.medium
            ? 500
            : 250;
  }

  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.round();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
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
// ProfileStatus
// ─────────────────────────────────────────
/// Status contract for Profile state.
///
/// NOTE: [ready] means age, height, and weight pass legacy validation rules.
/// It is NOT proof that all optional health fields or onboarding steps were confirmed.
enum ProfileStatus {
  initial, // Application launching / uninitialized
  loading, // Network request in flight
  ready, // Valid biometric data available
  incomplete, // Loaded, but required fields (height/weight/age) missing or <= 0
  offline, // Network request failed; displaying cached data
  error, // Network request failed; no cached data available
  unauthorized, // 401 response; authentication token invalid/expired
}

// ─────────────────────────────────────────
// ProfileState
// ─────────────────────────────────────────
class ProfileState {
  final ProfileStatus status;
  final ProfileEntity profile;
  final int targetCalories;
  final int targetProtein;
  final int targetCarbs;
  final int targetFat;
  final int targetBurned;
  final int waterTargetMl;
  final String? errorMessage;
  final bool isFromCache;

  ProfileState({
    this.status = ProfileStatus.initial,
    required this.profile,
    this.targetCalories = 0,
    this.targetProtein = 0,
    this.targetCarbs = 0,
    this.targetFat = 0,
    this.targetBurned = 300,
    this.waterTargetMl = 2000,
    this.errorMessage,
    this.isFromCache = false,
    bool? isLoading,
  }) : _legacyIsLoading = isLoading;

  final bool? _legacyIsLoading;

  factory ProfileState.initial() => ProfileState(
        status: ProfileStatus.initial,
        profile: ProfileEntity.empty(),
      );

  // Backward-compatible getters
  bool get isLoading =>
      _legacyIsLoading ??
      (status == ProfileStatus.loading || status == ProfileStatus.initial);
  bool get isProfileValid => profile.isValid;
  bool get hasError => status == ProfileStatus.error;
  bool get isOffline => status == ProfileStatus.offline || isFromCache;
  bool get isUnauthorized => status == ProfileStatus.unauthorized;
  bool get isReady => status == ProfileStatus.ready;
  bool get isIncomplete => status == ProfileStatus.incomplete;

  ProfileState copyWith({
    ProfileStatus? status,
    ProfileEntity? profile,
    int? targetCalories,
    int? targetProtein,
    int? targetCarbs,
    int? targetFat,
    int? targetBurned,
    int? waterTargetMl,
    String? errorMessage,
    bool? isFromCache,
    bool? isLoading,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      targetCalories: targetCalories ?? this.targetCalories,
      targetProtein: targetProtein ?? this.targetProtein,
      targetCarbs: targetCarbs ?? this.targetCarbs,
      targetFat: targetFat ?? this.targetFat,
      targetBurned: targetBurned ?? this.targetBurned,
      waterTargetMl: waterTargetMl ?? this.waterTargetMl,
      errorMessage: errorMessage ?? this.errorMessage,
      isFromCache: isFromCache ?? this.isFromCache,
      isLoading: isLoading,
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

  // In-flight deduplication guard
  Future<void>? _ongoingLoad;

  // Session epoch: incremented on logout to discard late in-flight responses
  int _sessionEpoch = 0;

  /// Session epoch counter used to invalidate late responses across user sessions.
  int get sessionEpoch => _sessionEpoch;

  /// Resets profile state and increments epoch to ignore any pending network requests.
  void resetSession() {
    _sessionEpoch++;
    _ongoingLoad = null;
    state = ProfileState.initial();
  }

  /// Initiates a single authenticated profile load.
  /// Deduplicates concurrent invocations and discards out-of-date session responses.
  Future<void> loadProfile() async {
    if (_ongoingLoad != null) {
      return _ongoingLoad!;
    }

    final loadEpoch = _sessionEpoch;
    final loadFuture = _executeLoadProfile(loadEpoch);
    _ongoingLoad = loadFuture;

    try {
      await loadFuture;
    } finally {
      if (identical(_ongoingLoad, loadFuture)) {
        _ongoingLoad = null;
      }
    }
  }

  Future<void> _executeLoadProfile(int currentEpoch) async {
    // Set loading state
    state = state.copyWith(status: ProfileStatus.loading);

    try {
      // Single GET request through repository (fetches profile + health stats together)
      // Do NOT auto-cache in repository before epoch validation!
      final snapshot =
          await _repository.fetchProfileSnapshot(cacheOnSuccess: false);

      // Guard: If session was reset or user logged out while request was in-flight, discard
      if (currentEpoch != _sessionEpoch || !mounted) {
        debugPrint(
            '[PROFILE] Discarding stale profile response from epoch $currentEpoch (current: $_sessionEpoch)');
        return;
      }

      if (snapshot != null) {
        // Safe to commit to persistent cache because session is confirmed active!
        if (!snapshot.isFromCache) {
          await _repository.cacheSnapshot(snapshot);
        }

        // Post-cache epoch guard: check if session was reset while cache write was in-flight
        if (currentEpoch != _sessionEpoch || !mounted) {
          debugPrint(
              '[PROFILE] Discarding state application from epoch $currentEpoch after cache write (current: $_sessionEpoch)');
          return;
        }

        _applySnapshot(snapshot);
      } else {
        // 404 or empty profile from backend -> incomplete state
        state = ProfileState(
          status: ProfileStatus.incomplete,
          profile: ProfileEntity.empty(),
        );
      }
    } on UnauthorizedException catch (e) {
      if (currentEpoch != _sessionEpoch || !mounted) return;
      debugPrint('[PROFILE] Session unauthorized (401)');
      state = ProfileState(
        status: ProfileStatus.unauthorized,
        profile: ProfileEntity.empty(),
        errorMessage: e.message,
      );
    } catch (e) {
      if (currentEpoch != _sessionEpoch || !mounted) return;
      debugPrint('[PROFILE] Load Profile Error: $e');

      // If existing profile was already valid from cache, keep offline status
      if (state.profile.isValid) {
        state = state.copyWith(
          status: ProfileStatus.offline,
          isFromCache: true,
          errorMessage: e.toString(),
        );
      } else {
        state = ProfileState(
          status: ProfileStatus.error,
          profile: ProfileEntity.empty(),
          errorMessage: e.toString(),
        );
      }
    }
  }

  Future<void> updateProfile(ProfileEntity newProfile) async {
    state = state.copyWith(status: ProfileStatus.loading);
    try {
      await _repository.syncProfile(newProfile);
      await loadProfile();
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          status: state.profile.isValid
              ? (state.isFromCache
                  ? ProfileStatus.offline
                  : ProfileStatus.ready)
              : ProfileStatus.incomplete,
          errorMessage: e.toString(),
        );
      }
      rethrow;
    }
  }

  void _applySnapshot(ProfileSnapshot snapshot) {
    final profile = snapshot.profile;
    final isCache = snapshot.isFromCache;

    // Calculate in-memory runtime fallback if backend stats are missing
    final int calories = snapshot.targetCalories > 0
        ? snapshot.targetCalories
        : (profile.isValid ? _calcLocalFallback(profile) : 0);
    final int protein = snapshot.targetProtein > 0
        ? snapshot.targetProtein
        : (profile.isValid ? _calcLocalProtein(calories, profile.goal) : 0);
    final int carbs = snapshot.targetCarbs > 0
        ? snapshot.targetCarbs
        : (profile.isValid ? _calcLocalCarbs(calories, profile.goal) : 0);
    final int fat = snapshot.targetFat > 0
        ? snapshot.targetFat
        : (profile.isValid ? _calcLocalFat(calories, profile.goal) : 0);

    final status = isCache
        ? ProfileStatus.offline
        : (profile.isValid ? ProfileStatus.ready : ProfileStatus.incomplete);

    state = ProfileState(
      status: status,
      profile: profile,
      targetCalories: calories,
      targetProtein: protein,
      targetCarbs: carbs,
      targetFat: fat,
      targetBurned: snapshot.targetBurned > 0
          ? snapshot.targetBurned
          : _calcBurned(profile),
      waterTargetMl: snapshot.waterTargetMl > 0 ? snapshot.waterTargetMl : 2000,
      isFromCache: isCache,
    );
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

  int _calcLocalProtein(int calories, Goal goal) {
    final ratio = goal == Goal.gain_muscle
        ? 0.30
        : (goal == Goal.lose_weight ? 0.40 : 0.25);
    return ((calories * ratio) / 4).round();
  }

  int _calcLocalCarbs(int calories, Goal goal) {
    final ratio = goal == Goal.gain_muscle
        ? 0.45
        : (goal == Goal.lose_weight ? 0.30 : 0.50);
    return ((calories * ratio) / 4).round();
  }

  int _calcLocalFat(int calories, Goal goal) {
    final ratio = goal == Goal.gain_muscle
        ? 0.25
        : (goal == Goal.lose_weight ? 0.30 : 0.25);
    return ((calories * ratio) / 9).round();
  }

  int _calcBurned(ProfileEntity profile) {
    return profile.activityLevel == ActivityLevel.high
        ? 700
        : profile.activityLevel == ActivityLevel.medium
            ? 500
            : 250;
  }
}

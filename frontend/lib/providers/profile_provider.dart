import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';

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
  saving, // Save POST in flight
  readbackPending, // POST succeeded, fresh GET readback in flight
  saveError, // Save failed (422 or write error)
  saveConflict, // Save failed with 409 conflict
  saveTimeoutUnknown, // Save POST timed out, outcome unknown
  identityMismatch, // Readback returned wrong owner identity
}

// ─────────────────────────────────────────
// ProfileState
// ─────────────────────────────────────────
class ProfileState {
  final ProfileStatus status;
  final ProfileEntity profile;
  final ProfileSnapshot? snapshot;
  final String? confirmedUserId;
  final bool isNetworkConfirmed;
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
    this.snapshot,
    this.confirmedUserId,
    this.isNetworkConfirmed = false,
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
  bool get isSaving =>
      (status == ProfileStatus.saving ||
          status == ProfileStatus.readbackPending) &&
      errorMessage == null;
  bool get isReadbackPending => status == ProfileStatus.readbackPending;
  bool get isSaveConflict => status == ProfileStatus.saveConflict;
  bool get isSaveTimeoutUnknown => status == ProfileStatus.saveTimeoutUnknown;
  bool get isSaveError => status == ProfileStatus.saveError;
  bool get isIdentityMismatch => status == ProfileStatus.identityMismatch;

  // Stable Identity & Provenance getters
  String? get userId => confirmedUserId ?? snapshot?.userId ?? profile.userId;
  bool get isComplete => profile.isComplete;
  bool get isCompleteAndConfirmed =>
      isNetworkConfirmed &&
      !isFromCache &&
      profile.isComplete &&
      userId != null &&
      userId!.isNotEmpty;
  bool get isIncompleteAndConfirmed =>
      isNetworkConfirmed &&
      !isFromCache &&
      !profile.isComplete &&
      userId != null &&
      userId!.isNotEmpty;

  ProfileState copyWith({
    ProfileStatus? status,
    ProfileEntity? profile,
    ProfileSnapshot? snapshot,
    String? confirmedUserId,
    bool? isNetworkConfirmed,
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
      snapshot: snapshot ?? this.snapshot,
      confirmedUserId: confirmedUserId ?? this.confirmedUserId,
      isNetworkConfirmed: isNetworkConfirmed ?? this.isNetworkConfirmed,
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

      // If existing profile was already valid, keep offline status
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

  // --- Onboarding Draft Management (Owner-scoped, confirmed identity only) ---

  Future<void> saveOnboardingDraft(OnboardingDraft draft) async {
    final currentId = state.confirmedUserId;
    if (currentId == null || currentId.isEmpty) {
      throw StateError('Cannot save draft without verified user identity');
    }
    if (draft.userId != currentId) {
      throw StateError('Draft owner mismatch: cannot save draft for different user');
    }
    await _repository.saveDraft(draft);
  }

  /// Reads the stored draft of the confirmed owner (no compatibility check).
  Future<OnboardingDraft?> getOnboardingDraft() async {
    final currentId = state.confirmedUserId;
    if (currentId == null || currentId.isEmpty) {
      return null;
    }
    return await _repository.getDraft(currentId);
  }

  /// Returns the stored draft only if it may be auto-resumed against the
  /// current network-confirmed snapshot (owner, schema, step, base values,
  /// still incomplete). The snapshot in [state] is never modified.
  Future<OnboardingDraft?> restoreOnboardingDraft() async {
    final epoch = _sessionEpoch;
    final snapshot = state.snapshot;
    if (!state.isNetworkConfirmed || snapshot == null) return null;
    final draft = await getOnboardingDraft();
    if (draft == null || epoch != _sessionEpoch || !mounted) return null;
    return draft.isCompatibleWith(snapshot) ? draft : null;
  }

  Future<void> clearOnboardingDraft() async {
    final currentId = state.confirmedUserId;
    if (currentId == null || currentId.isEmpty) return;
    await _repository.clearDraft(currentId);
  }

  /// CP4: Saves onboarding draft and performs verified fresh readback.
  /// Strictly prevents double submit, respects session epoch, compares exact
  /// decimals, and only completes after server confirmation.
  Future<bool> saveAndVerifyOnboarding(OnboardingDraft draft) async {
    if (state.status == ProfileStatus.saving ||
        state.status == ProfileStatus.readbackPending ||
        state.status == ProfileStatus.saveTimeoutUnknown ||
        state.status == ProfileStatus.identityMismatch) {
      return false;
    }

    final epoch = _sessionEpoch;
    final ownerId = state.confirmedUserId;

    if (ownerId == null || ownerId.isEmpty || !state.isNetworkConfirmed) {
      throw StateError('Cannot save onboarding: unconfirmed user identity');
    }
    if (draft.userId != ownerId) {
      throw StateError(
          'Draft owner mismatch: draft for ${draft.userId}, active owner $ownerId');
    }

    state = state.copyWith(status: ProfileStatus.saving, errorMessage: null);

    final profileModel = ProfileModel(
      userId: ownerId,
      age: draft.age,
      height: draft.height,
      weight: draft.weight,
      gender: draft.gender,
      activityLevel: draft.activityChoice?.toLegacy(),
      activityCanonical: draft.activityChoice?.name,
      goal: draft.goal,
    );

    try {
      await _repository.syncProfile(profileModel);
    } on ProfileConflictException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      try {
        await _fetchFreshSnapshot(cacheOnSuccess: false);
      } catch (_) {}
      state = state.copyWith(
        status: ProfileStatus.saveConflict,
        errorMessage: e.message,
      );
      return false;
    } on ProfileValidationException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveError,
        errorMessage: e.message,
      );
      return false;
    } on ProfileTimeoutException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveTimeoutUnknown,
        errorMessage: e.message,
      );
      return false;
    } on UnauthorizedException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = ProfileState(
        status: ProfileStatus.unauthorized,
        profile: ProfileEntity.empty(),
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveError,
        errorMessage: e.toString(),
      );
      return false;
    }

    if (epoch != _sessionEpoch || !mounted) return false;

    return await verifyReadback(
      immutableDraft: draft,
      epoch: epoch,
      ownerId: ownerId,
    );
  }

  /// Performs fresh GET readback without cache fallback and strictly validates
  /// owner ID, all 6 submitted fields (exact decimals), and server stats.
  Future<bool> verifyReadback({
    required OnboardingDraft immutableDraft,
    required int epoch,
    required String ownerId,
  }) async {
    state = state.copyWith(
      status: ProfileStatus.readbackPending,
      errorMessage: null,
    );

    ProfileSnapshot? readback;
    try {
      readback = await _fetchFreshSnapshot(cacheOnSuccess: false);
    } on UnauthorizedException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = ProfileState(
        status: ProfileStatus.unauthorized,
        profile: ProfileEntity.empty(),
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Lỗi tải lại dữ liệu từ máy chủ. Vui lòng kiểm tra lại.',
      );
      return false;
    }

    if (epoch != _sessionEpoch || !mounted) return false;

    if (readback == null || readback.isFromCache) {
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Phản hồi từ máy chủ không hợp lệ.',
      );
      return false;
    }

    // 1. Owner check
    if (readback.userId != ownerId) {
      state = state.copyWith(
        status: ProfileStatus.identityMismatch,
        errorMessage: 'Xác thực thất bại: Chủ tài khoản không khớp.',
      );
      return false;
    }

    final p = readback.profile;
    // 2. All 6 fields presence
    if (!p.isComplete) {
      state = state.copyWith(
        status: ProfileStatus.saveError,
        errorMessage: 'Dữ liệu hồ sơ trên máy chủ chưa hoàn thiện.',
      );
      return false;
    }

    // 3. Exact comparison of 6 submitted values (no broad rounding)
    final ageMatches = p.age == immutableDraft.age;
    final genderMatches = p.rawGender == immutableDraft.gender;
    final heightMatches = p.height != null &&
        immutableDraft.height != null &&
        (p.height! - immutableDraft.height!).abs() == 0;
    final weightMatches = p.weight != null &&
        immutableDraft.weight != null &&
        (p.weight! - immutableDraft.weight!).abs() == 0;
    final goalMatches = p.rawGoal == immutableDraft.goal;

    final actMatches = (p.rawActivityCanonical != null &&
            p.rawActivityCanonical == immutableDraft.activityChoice?.name) ||
        (immutableDraft.activityChoice != null &&
            OnboardingActivityChoice.fromApi(p.rawActivityCanonical) ==
                immutableDraft.activityChoice);

    if (!ageMatches ||
        !genderMatches ||
        !heightMatches ||
        !weightMatches ||
        !goalMatches ||
        !actMatches) {
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Dữ liệu máy chủ không khớp với thông tin đã nhập.',
      );
      return false;
    }

    // 4. Verified! Commit cache, clear draft, apply snapshot
    await _repository.cacheSnapshot(readback);

    try {
      await _repository.clearDraft(ownerId);
    } catch (_) {}

    _applySnapshot(readback);
    return true;
  }

  /// Reconciles state after timeout / unknown save status via GET only.
  Future<bool> reconcileOnboarding(OnboardingDraft draft) async {
    final epoch = _sessionEpoch;
    final ownerId = state.confirmedUserId;
    if (ownerId == null || ownerId.isEmpty) return false;
    return await verifyReadback(
      immutableDraft: draft,
      epoch: epoch,
      ownerId: ownerId,
    );
  }

  /// CP5: Saves edited profile and performs verified fresh readback.
  /// Strictly prevents double submit, respects session epoch, compares exact
  /// decimals across all 6 fields, preserves onboarding draft isolation,
  /// and updates confirmed profile state only upon verified server confirmation.
  Future<bool> saveAndVerifyEditProfile({
    required int age,
    required double height,
    required double weight,
    required Gender gender,
    required Goal goal,
    required OnboardingActivityChoice activityChoice,
  }) async {
    // 1. Single-flight mutation guards
    if (state.status == ProfileStatus.saving ||
        state.status == ProfileStatus.readbackPending ||
        state.status == ProfileStatus.saveTimeoutUnknown ||
        state.status == ProfileStatus.identityMismatch) {
      return false;
    }

    final epoch = _sessionEpoch;
    final ownerId = state.confirmedUserId;

    // 2. Strict owner & backend confirmation guard (no test_owner fallback)
    if (ownerId == null ||
        ownerId.isEmpty ||
        !state.isCompleteAndConfirmed) {
      state = state.copyWith(
        status: ProfileStatus.saveError,
        errorMessage:
            'Cần tải lại dữ liệu từ máy chủ để xác minh danh tính trước khi lưu.',
      );
      return false;
    }

    state = state.copyWith(status: ProfileStatus.saving, errorMessage: null);

    final profileModel = ProfileModel(
      userId: ownerId,
      age: age,
      height: height,
      weight: weight,
      gender: gender,
      activityLevel: activityChoice.toLegacy(),
      activityCanonical: activityChoice.name,
      goal: goal,
    );

    try {
      await _repository.syncProfile(profileModel);
    } on ProfileConflictException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      try {
        await _fetchFreshSnapshot(cacheOnSuccess: false);
      } catch (_) {}
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveConflict,
        errorMessage: e.message,
      );
      return false;
    } on ProfileValidationException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveError,
        errorMessage: e.message,
      );
      return false;
    } on ProfileTimeoutException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveTimeoutUnknown,
        errorMessage: e.message,
      );
      return false;
    } on UnauthorizedException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = ProfileState(
        status: ProfileStatus.unauthorized,
        profile: ProfileEntity.empty(),
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.saveError,
        errorMessage: e.toString(),
      );
      return false;
    }

    if (epoch != _sessionEpoch || !mounted) return false;

    return await verifyEditReadback(
      age: age,
      height: height,
      weight: weight,
      gender: gender,
      goal: goal,
      activityChoice: activityChoice,
      epoch: epoch,
      ownerId: ownerId,
    );
  }

  /// Performs fresh GET readback without cache fallback and strictly validates
  /// owner ID, all 6 submitted fields (exact decimals), and server stats for Edit Profile.
  Future<bool> verifyEditReadback({
    required int age,
    required double height,
    required double weight,
    required Gender gender,
    required Goal goal,
    required OnboardingActivityChoice activityChoice,
    required int epoch,
    required String ownerId,
  }) async {
    if (epoch != _sessionEpoch || !mounted) return false;

    state = state.copyWith(
      status: ProfileStatus.readbackPending,
      errorMessage: null,
    );

    ProfileSnapshot? readback;
    try {
      readback = await _fetchFreshSnapshot(cacheOnSuccess: false);
    } on UnauthorizedException catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = ProfileState(
        status: ProfileStatus.unauthorized,
        profile: ProfileEntity.empty(),
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      if (epoch != _sessionEpoch || !mounted) return false;
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Lỗi tải lại dữ liệu từ máy chủ. Vui lòng kiểm tra lại.',
      );
      return false;
    }

    if (epoch != _sessionEpoch || !mounted) return false;

    if (readback == null || readback.isFromCache) {
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Phản hồi từ máy chủ không hợp lệ.',
      );
      return false;
    }

    // 1. Owner check
    final snapUserId = readback.userId;
    final profileUserId = readback.profile.userId;

    if ((snapUserId == null || snapUserId.isEmpty) &&
        (profileUserId == null || profileUserId.isEmpty)) {
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Phản hồi từ máy chủ thiếu thông tin xác thực chủ tài khoản.',
      );
      return false;
    }

    final hasSnapshotMismatch = snapUserId != null &&
        snapUserId.isNotEmpty &&
        snapUserId != ownerId;
    final hasProfileMismatch = profileUserId != null &&
        profileUserId.isNotEmpty &&
        profileUserId != ownerId;

    if (hasSnapshotMismatch || hasProfileMismatch) {
      state = state.copyWith(
        status: ProfileStatus.identityMismatch,
        errorMessage: 'Xác thực thất bại: Chủ tài khoản không khớp.',
      );
      return false;
    }

    final p = readback.profile;
    // 2. All 6 fields presence
    if (!p.isComplete) {
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Dữ liệu hồ sơ trên máy chủ chưa hoàn thiện.',
      );
      return false;
    }

    // 3. Exact comparison of 6 submitted values (no broad rounding)
    final ageMatches = p.age == age;
    final genderMatches = p.rawGender == gender;
    final heightMatches = p.height != null && (p.height! - height).abs() == 0;
    final weightMatches = p.weight != null && (p.weight! - weight).abs() == 0;
    final goalMatches = p.rawGoal == goal;
    final actMatches = (p.rawActivityCanonical != null &&
            p.rawActivityCanonical == activityChoice.name) ||
        (OnboardingActivityChoice.fromApi(p.rawActivityCanonical) == activityChoice);

    if (!ageMatches ||
        !genderMatches ||
        !heightMatches ||
        !weightMatches ||
        !goalMatches ||
        !actMatches) {
      state = state.copyWith(
        status: ProfileStatus.readbackPending,
        errorMessage: 'Dữ liệu máy chủ không khớp với thông tin đã nhập.',
      );
      return false;
    }

    // 4. Verified! Commit cache, apply snapshot. Does NOT clear onboarding draft.
    if (epoch != _sessionEpoch || !mounted) return false;

    await _repository.cacheSnapshot(readback);

    if (epoch != _sessionEpoch || !mounted) return false;

    _applySnapshot(readback);
    return true;
  }

  /// Reconciles Edit profile state via GET only (no retry POST).
  Future<bool> reconcileEditProfile({
    required int age,
    required double height,
    required double weight,
    required Gender gender,
    required Goal goal,
    required OnboardingActivityChoice activityChoice,
  }) async {
    final epoch = _sessionEpoch;
    final ownerId = state.confirmedUserId;
    if (ownerId == null ||
        ownerId.isEmpty ||
        !state.isCompleteAndConfirmed) {
      return false;
    }
    return await verifyEditReadback(
      age: age,
      height: height,
      weight: weight,
      gender: gender,
      goal: goal,
      activityChoice: activityChoice,
      epoch: epoch,
      ownerId: ownerId,
    );
  }

  Future<ProfileSnapshot?> _fetchFreshSnapshot({bool cacheOnSuccess = false}) async {
    final snapshot = await _repository.fetchProfileSnapshot(cacheOnSuccess: cacheOnSuccess);
    if (snapshot == null || snapshot.isFromCache) {
      throw const FormatException('Empty profile snapshot returned');
    }
    return snapshot;
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
    final isConfirmed =
        !isCache && snapshot.userId != null && snapshot.userId!.isNotEmpty;

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
      snapshot: snapshot,
      confirmedUserId: isConfirmed ? snapshot.userId : null,
      isNetworkConfirmed: isConfirmed,
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

  int _calcLocalProtein(int calories, Goal? goal) {
    final ratio = goal == Goal.gain_muscle
        ? 0.30
        : (goal == Goal.lose_weight ? 0.40 : 0.25);
    return ((calories * ratio) / 4).round();
  }

  int _calcLocalCarbs(int calories, Goal? goal) {
    final ratio = goal == Goal.gain_muscle
        ? 0.45
        : (goal == Goal.lose_weight ? 0.30 : 0.50);
    return ((calories * ratio) / 4).round();
  }

  int _calcLocalFat(int calories, Goal? goal) {
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

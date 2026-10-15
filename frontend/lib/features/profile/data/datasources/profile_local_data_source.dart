import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';

abstract class ProfileLocalDataSource {
  Future<void> cacheProfile(ProfileModel profile);
  Future<void> cacheSnapshot(ProfileSnapshotModel snapshot);
  Future<ProfileSnapshotModel?> getLastSnapshot({String? expectedUserId});
  Future<ProfileModel?> getLastProfile({String? expectedUserId});
  Future<void> clearCache({String? userId});

  // Onboarding draft operations
  Future<void> saveDraft(OnboardingDraft draft);
  Future<OnboardingDraft?> getDraft(String userId);
  Future<void> clearDraft(String userId);
}

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  final SharedPreferences? sharedPreferences;

  ProfileLocalDataSourceImpl({this.sharedPreferences});

  static const String CACHED_PROFILE_KEY = 'cached_profile';
  static const String cachedProfileSnapshotV2Key =
      'cached_profile_snapshot_v2';

  static String userSnapshotKey(String userId) =>
      'cached_profile_snapshot_v2_$userId';
  static String draftKey(String userId) => 'onboarding_draft_$userId';

  // Sequential FIFO queue for Profile cache mutations (writes and deletions)
  Future<void> _mutationQueue = Future.value();

  Future<T> _synchronizedMutation<T>(Future<T> Function() operation) {
    final next =
        _mutationQueue.then((_) => operation(), onError: (_) => operation());
    _mutationQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshotModel snapshot) {
    return _synchronizedMutation(() async {
      final prefs = sharedPreferences;
      if (prefs == null) return;

      try {
        final jsonStr = jsonEncode(snapshot.toJson());
        // 1. Write partitioned cache if userId is present
        if (snapshot.userId != null && snapshot.userId!.isNotEmpty) {
          await prefs.setString(userSnapshotKey(snapshot.userId!), jsonStr);
        }
        // 2. Also write legacy key for backward compatibility
        await prefs.setString(cachedProfileSnapshotV2Key, jsonStr);
      } catch (e) {
        debugPrint('[CACHE] Error caching profile snapshot v2: $e');
      }
    });
  }

  @override
  Future<void> cacheProfile(ProfileModel profile) {
    return _synchronizedMutation(() async {
      final prefs = sharedPreferences;
      if (prefs == null) return;

      await prefs.setString(
        CACHED_PROFILE_KEY,
        jsonEncode(profile.toJson()),
      );
    });
  }

  @override
  Future<ProfileSnapshotModel?> getLastSnapshot({String? expectedUserId}) async {
    final prefs = sharedPreferences;
    if (prefs == null) return null;

    // 1. If an expectedUserId is specified, only return cache that belongs to that exact user
    if (expectedUserId != null && expectedUserId.isNotEmpty) {
      final userKey = userSnapshotKey(expectedUserId);
      final userString = prefs.getString(userKey);
      if (userString != null && userString.isNotEmpty) {
        try {
          final decoded = jsonDecode(userString);
          if (decoded is Map<String, dynamic>) {
            return ProfileSnapshotModel.fromJson(decoded, isFromCache: true);
          }
        } catch (e) {
          debugPrint('[CACHE] Corrupted partitioned cache for $expectedUserId: $e');
        }
      }

      // Check legacy v2 snapshot ONLY if it has matching userId
      final v2String = prefs.getString(cachedProfileSnapshotV2Key);
      if (v2String != null && v2String.isNotEmpty) {
        try {
          final decoded = jsonDecode(v2String);
          if (decoded is Map<String, dynamic>) {
            final rawId = decoded['user_id'] ?? decoded['userId'];
            if (rawId == expectedUserId) {
              return ProfileSnapshotModel.fromJson(decoded, isFromCache: true);
            }
          }
        } catch (_) {}
      }

      // Legacy unowned cache MUST NOT be applied to a newly authenticated user session
      return null;
    }

    // 2. Fallback when no expectedUserId is specified (backward compatibility with legacy callers/tests)
    final v2String = prefs.getString(cachedProfileSnapshotV2Key);
    if (v2String != null && v2String.isNotEmpty) {
      try {
        final decoded = jsonDecode(v2String);
        if (decoded is Map<String, dynamic>) {
          return ProfileSnapshotModel.fromJson(decoded, isFromCache: true);
        }
      } catch (e) {
        debugPrint('[CACHE] Corrupted v2 cache, attempting fallback: $e');
      }
    }

    // Fallback to v1 legacy flat cache
    final v1String = prefs.getString(CACHED_PROFILE_KEY);
    if (v1String != null && v1String.isNotEmpty) {
      try {
        final decoded = jsonDecode(v1String);
        if (decoded is Map<String, dynamic>) {
          final legacyProfile = ProfileModel.fromJson(decoded);
          // Do not fabricate server statistics during migration
          return ProfileSnapshotModel(
            profile: legacyProfile,
            targetCalories: 0,
            targetProtein: 0,
            targetCarbs: 0,
            targetFat: 0,
            targetBurned: 300,
            waterTargetMl: 2000,
            isFromCache: true,
          );
        }
      } catch (e) {
        debugPrint('[CACHE] Corrupted v1 cache: $e');
      }
    }

    return null;
  }

  @override
  Future<ProfileModel?> getLastProfile({String? expectedUserId}) async {
    final snapshot = await getLastSnapshot(expectedUserId: expectedUserId);
    if (snapshot == null) return null;
    if (snapshot.profile is ProfileModel) {
      return snapshot.profile as ProfileModel;
    }
    return ProfileModel.fromEntity(snapshot.profile);
  }

  @override
  Future<void> clearCache({String? userId}) {
    return _synchronizedMutation(() async {
      final prefs = sharedPreferences;
      if (prefs == null) return;
      if (userId != null && userId.isNotEmpty) {
        await prefs.remove(userSnapshotKey(userId));
        await prefs.remove(draftKey(userId));
      }
      await prefs.remove(CACHED_PROFILE_KEY);
      await prefs.remove(cachedProfileSnapshotV2Key);
    });
  }

  @override
  Future<void> saveDraft(OnboardingDraft draft) {
    return _synchronizedMutation(() async {
      final prefs = sharedPreferences;
      if (prefs == null) return;
      if (draft.userId.isEmpty) {
        throw ArgumentError('Cannot save onboarding draft without verified userId');
      }
      if (!draft.isSupported) {
        throw ArgumentError(
            'Cannot save onboarding draft with unsupported schema or step');
      }
      await prefs.setString(draftKey(draft.userId), jsonEncode(draft.toJson()));
    });
  }

  @override
  Future<OnboardingDraft?> getDraft(String userId) async {
    final prefs = sharedPreferences;
    if (prefs == null || userId.isEmpty) return null;
    final str = prefs.getString(draftKey(userId));
    if (str == null || str.isEmpty) return null;
    try {
      final decoded = jsonDecode(str);
      if (decoded is Map<String, dynamic>) {
        final draft = OnboardingDraft.tryParse(decoded);
        // A draft stored under this owner's key must also declare that owner.
        if (draft != null && draft.userId == userId) return draft;
      }
    } catch (e) {
      debugPrint('[DRAFT] Corrupted draft JSON for $userId');
    }
    return null;
  }

  @override
  Future<void> clearDraft(String userId) {
    return _synchronizedMutation(() async {
      final prefs = sharedPreferences;
      if (prefs == null || userId.isEmpty) return;
      await prefs.remove(draftKey(userId));
    });
  }
}

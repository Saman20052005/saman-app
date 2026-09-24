import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';

abstract class ProfileLocalDataSource {
  Future<void> cacheProfile(ProfileModel profile);
  Future<void> cacheSnapshot(ProfileSnapshotModel snapshot);
  Future<ProfileSnapshotModel?> getLastSnapshot();
  Future<ProfileModel?> getLastProfile();
  Future<void> clearCache();
}

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  final SharedPreferences? sharedPreferences;

  ProfileLocalDataSourceImpl({this.sharedPreferences});

  static const String CACHED_PROFILE_KEY = 'cached_profile';
  static const String CACHED_PROFILE_SNAPSHOT_V2_KEY =
      'cached_profile_snapshot_v2';

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
        await prefs.setString(
          CACHED_PROFILE_SNAPSHOT_V2_KEY,
          jsonEncode(snapshot.toJson()),
        );
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
  Future<ProfileSnapshotModel?> getLastSnapshot() async {
    final prefs = sharedPreferences;
    if (prefs == null) return null;

    // 1. Prefer v2 snapshot
    final v2String = prefs.getString(CACHED_PROFILE_SNAPSHOT_V2_KEY);
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

    // 2. Fallback to v1 legacy flat cache
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
  Future<ProfileModel?> getLastProfile() async {
    final snapshot = await getLastSnapshot();
    if (snapshot == null) return null;
    if (snapshot.profile is ProfileModel) {
      return snapshot.profile as ProfileModel;
    }
    return ProfileModel.fromEntity(snapshot.profile);
  }

  @override
  Future<void> clearCache() {
    return _synchronizedMutation(() async {
      final prefs = sharedPreferences;
      if (prefs == null) return;
      await prefs.remove(CACHED_PROFILE_KEY);
      await prefs.remove(CACHED_PROFILE_SNAPSHOT_V2_KEY);
    });
  }
}

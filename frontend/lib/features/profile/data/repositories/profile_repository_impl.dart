import 'package:flutter/foundation.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';

export 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;
  final ProfileLocalDataSource localDataSource;

  ProfileRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<ProfileSnapshot> syncProfile(ProfileEntity profile) async {
    final model =
        (profile is ProfileModel) ? profile : ProfileModel.fromEntity(profile);

    // Send update to remote backend and return canonical snapshot directly.
    // Caching is managed after session epoch validation in the notifier.
    final snapshot = await remoteDataSource.updateProfile(model);
    return snapshot;
  }

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    try {
      // 1. Network First
      final remoteSnapshot = await remoteDataSource.getProfileSnapshot();
      if (remoteSnapshot != null) {
        if (cacheOnSuccess) {
          await cacheSnapshot(remoteSnapshot);
        }
        return remoteSnapshot;
      }
    } on UnauthorizedException {
      // Re-throw so Provider / UI distinguishes 401 Unauthorized
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[REPOSITORY] Remote fetch failed, falling back to cache: $e');
      }
    }

    // 2. Fallback to local cache (handles v2 snapshot & v1 flat fallback)
    final cached = await localDataSource.getLastSnapshot();
    if (cached != null) {
      return cached;
    }

    return null;
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    final model = ProfileSnapshotModel.fromSnapshot(snapshot);
    await localDataSource.cacheSnapshot(model);
  }

  @override
  Future<ProfileEntity?> fetchProfile() async {
    final snapshot = await fetchProfileSnapshot();
    return snapshot?.profile;
  }

  @override
  Future<void> clearLocalProfile() async {
    await localDataSource.clearCache();
  }
}

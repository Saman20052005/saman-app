import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';

import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';

export 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;
  final ProfileLocalDataSource localDataSource;

  ProfileRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    final model =
        (profile is ProfileModel) ? profile : ProfileModel.fromEntity(profile);

    // 1. Send update to remote backend (save-only mutation without optimistic cache)
    final success = await remoteDataSource.updateProfile(model);
    if (!success) {
      throw Exception('Cập nhật hồ sơ không thành công');
    }
  }

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    // 1. Direct Network First: propagates errors cleanly without falling back to cache
    final remoteSnapshot = await remoteDataSource.getProfileSnapshot();
    if (remoteSnapshot != null) {
      if (cacheOnSuccess) {
        await cacheSnapshot(remoteSnapshot);
      }
      return remoteSnapshot;
    }

    // 2. Fallback to local cache only if server returned null (empty profile)
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
  Future<void> clearLocalProfile({String? userId}) async {
    await localDataSource.clearCache(userId: userId);
  }

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {
    await localDataSource.saveDraft(draft);
  }

  @override
  Future<OnboardingDraft?> getDraft(String userId) async {
    return await localDataSource.getDraft(userId);
  }

  @override
  Future<void> clearDraft(String userId) async {
    await localDataSource.clearDraft(userId);
  }
}

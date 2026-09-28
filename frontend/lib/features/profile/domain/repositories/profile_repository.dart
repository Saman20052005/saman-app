import '../entities/profile_entity.dart';
import '../entities/profile_snapshot.dart';

// Kept for the tracked legacy adapter under frontend/features/profile.
// New production code uses ProfileRepository below.
abstract class IProfileRepository {
  Future<ProfileEntity> getProfile();
  Future<void> saveProfile(ProfileEntity profile);
}

abstract class ProfileRepository {
  Future<void> syncProfile(ProfileEntity profile);
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false});
  Future<void> cacheSnapshot(ProfileSnapshot snapshot);
  Future<ProfileEntity?> fetchProfile();
  Future<void> clearLocalProfile();
}

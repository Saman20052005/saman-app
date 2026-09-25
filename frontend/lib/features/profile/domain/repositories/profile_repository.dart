import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';

abstract class ProfileRepository {
  Future<dynamic> syncProfile(ProfileEntity profile);
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false});
  Future<void> cacheSnapshot(ProfileSnapshot snapshot);
  Future<ProfileEntity?> fetchProfile();
  Future<void> clearLocalProfile();
}

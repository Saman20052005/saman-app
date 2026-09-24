// [File: lib/features/profile/domain/repositories/profile_repository.dart]
import '../entities/profile_entity.dart'; // ✅ Thêm dòng này

abstract class IProfileRepository {
  Future<ProfileEntity> getProfile();
  Future<void> saveProfile(ProfileEntity profile);
}

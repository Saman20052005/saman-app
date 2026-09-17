// [File: lib/features/profile/domain/repositories/profile_repository.dart]

// ✅ IMPORT TUYỆT ĐỐI (Sửa lỗi undefined class)
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

abstract class IProfileRepository {
  Future<ProfileEntity> getProfile();
  Future<void> saveProfile(ProfileEntity profile);
}
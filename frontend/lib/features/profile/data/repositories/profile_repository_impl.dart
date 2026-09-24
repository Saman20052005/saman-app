import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';

// Interface ProfileRepository giữ nguyên trong Domain
abstract class ProfileRepository {
  Future<void> syncProfile(ProfileEntity profile);
  Future<ProfileEntity?> fetchProfile();
}

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;
  final ProfileLocalDataSource localDataSource;

  ProfileRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    final model = ProfileModel.fromEntity(profile);

    // 1. Gửi lên Server (Ưu tiên)
    await remoteDataSource.updateProfile(model);

    // 2. Nếu thành công, lưu Local để đồng bộ
    await localDataSource.cacheProfile(model);
  }

  @override
  Future<ProfileEntity?> fetchProfile() async {
    try {
      // 1. Network First
      final remoteProfile = await remoteDataSource.getProfile();

      if (remoteProfile != null) {
        // Cache lại ngay
        await localDataSource.cacheProfile(remoteProfile);
        return remoteProfile;
      }
    } catch (e) {
      // Log lỗi nhưng không chặn app chạy
      // print("Sync error: $e");
    }

    // 3. Fallback: Lấy từ Local Cache nếu mạng lỗi
    return await localDataSource.getLastProfile();
  }
}

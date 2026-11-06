import 'package:image_picker/image_picker.dart';
import 'package:health_ai_app/features/profile/domain/repositories/avatar_repository.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';

export 'package:health_ai_app/features/profile/domain/repositories/avatar_repository.dart';

class AvatarRepositoryImpl implements AvatarRepository {
  final ProfileRemoteDataSource remoteDataSource;

  AvatarRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Map<String, dynamic>> uploadAvatar(XFile file, {bool Function()? isSessionCurrent}) async {
    return await remoteDataSource.uploadAvatar(file, isSessionCurrent: isSessionCurrent);
  }

  @override
  Future<Map<String, dynamic>> useGoogleAvatar({bool Function()? isSessionCurrent}) async {
    return await remoteDataSource.useGoogleAvatar(isSessionCurrent: isSessionCurrent);
  }
}


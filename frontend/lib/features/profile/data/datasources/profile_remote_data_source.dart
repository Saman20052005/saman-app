import 'package:dio/dio.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Unauthorized']);
  @override
  String toString() => message;
}

abstract class ProfileRemoteDataSource {
  Future<ProfileSnapshotModel> updateProfile(ProfileModel profile);
  Future<ProfileSnapshotModel?> getProfileSnapshot();
  Future<ProfileModel?> getProfile();
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  final Dio dio;

  ProfileRemoteDataSourceImpl({required this.dio}) {
    dio.options.connectTimeout = const Duration(seconds: 60);
    dio.options.receiveTimeout = const Duration(seconds: 60);
    dio.options.sendTimeout = const Duration(seconds: 60);
    dio.options.contentType = Headers.jsonContentType;
  }

  @override
  Future<ProfileSnapshotModel> updateProfile(ProfileModel profile) async {
    try {
      final response = await dio.post(
        ApiConfig.profileUpdateEndpoint,
        data: profile.toUpdateJson(),
        options: Options(contentType: Headers.jsonContentType),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return ProfileSnapshotModel.fromJson(data);
        }
        throw const FormatException('Invalid profile response structure');
      }
      throw Exception(
        'Lỗi Server: ${response.statusCode} - ${response.statusMessage}',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const UnauthorizedException('Session expired');
      }
      throw Exception(
        'Lỗi Server: ${e.response?.statusCode} - ${e.response?.statusMessage}',
      );
    }
  }

  @override
  Future<ProfileSnapshotModel?> getProfileSnapshot() async {
    try {
      final response = await dio.get(ApiConfig.getProfileEndpoint);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return ProfileSnapshotModel.fromJson(data);
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const UnauthorizedException('Session expired');
      }
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<ProfileModel?> getProfile() async {
    final snapshot = await getProfileSnapshot();
    if (snapshot != null) {
      if (snapshot.profile is ProfileModel) {
        return snapshot.profile as ProfileModel;
      }
      return ProfileModel.fromEntity(snapshot.profile);
    }
    return null;
  }
}

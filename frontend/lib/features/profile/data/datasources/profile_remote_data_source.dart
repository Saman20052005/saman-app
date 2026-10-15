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

class ProfileConflictException implements Exception {
  final String message;
  const ProfileConflictException([this.message = 'Conflict: profile was updated concurrently (409)']);
  @override
  String toString() => message;
}

class ProfileValidationException implements Exception {
  final String message;
  const ProfileValidationException([this.message = 'Validation error (422)']);
  @override
  String toString() => message;
}

class ProfileTimeoutException implements Exception {
  final String message;
  const ProfileTimeoutException([this.message = 'Request timed out']);
  @override
  String toString() => message;
}

abstract class ProfileRemoteDataSource {
  Future<bool> updateProfile(ProfileModel profile);
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
  Future<bool> updateProfile(ProfileModel profile) async {
    try {
      final response = await dio.post(
        ApiConfig.profileUpdateEndpoint,
        data: profile.toUpdateJson(),
        options: Options(contentType: Headers.jsonContentType),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const UnauthorizedException('Session expired');
      }
      if (e.response?.statusCode == 409) {
        throw ProfileConflictException(
          e.response?.data?['detail']?.toString() ??
              'Profile was modified concurrently. Please refresh and try again.',
        );
      }
      if (e.response?.statusCode == 422) {
        throw ProfileValidationException(
          e.response?.data?['detail']?.toString() ?? 'Validation failed (422)',
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const ProfileTimeoutException('Save request timed out');
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
          final rawUserId = data['user_id'] ?? data['userId'];
          if (rawUserId == null ||
              rawUserId is! String ||
              rawUserId.trim().isEmpty) {
            throw const FormatException(
              'Missing or invalid user_id in profile response',
            );
          }
          return ProfileSnapshotModel.fromJson(data);
        }
        throw const FormatException('Invalid profile response structure');
      }
      throw Exception('Unexpected status code: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const UnauthorizedException('Session expired');
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

import 'package:dio/dio.dart';
import 'package:health_ai_app/config/api_config.dart'; // Để lấy URL endpoint
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';
import 'package:flutter/foundation.dart';

abstract class ProfileRemoteDataSource {
  Future<bool> updateProfile(ProfileModel profile);
  Future<ProfileModel?> getProfile();
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  final Dio dio;

  // Dio instance này cần được cấu hình sẵn Interceptor để tự add Token
  ProfileRemoteDataSourceImpl({required this.dio}) {
    // Configure timeouts
    dio.options.connectTimeout = const Duration(seconds: 60);
    dio.options.receiveTimeout = const Duration(seconds: 60);
    dio.options.sendTimeout = const Duration(seconds: 60);
    dio.options.contentType = Headers.jsonContentType;

    // Add debugging interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (!kReleaseMode && ApiConfig.isDebug) {
          print('[DIO] request: ${options.method} ${options.uri}');
          print('[DIO] request headers: ${options.headers}');
          print('[DIO] request data: ${options.data}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (!kReleaseMode && ApiConfig.isDebug) {
          print(
              '[DIO] response: ${response.statusCode} ${response.requestOptions.uri}');
          print('[DIO] response data: ${response.data}');
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (!kReleaseMode && ApiConfig.isDebug) {
          print('[DIO] error: ${error.message}');
          print(
              '[DIO] status: ${error.response?.statusCode} ${error.requestOptions.uri}');
          print('[DIO] error response.data: ${error.response?.data}');
          print('[DIO] error request headers: ${error.requestOptions.headers}');
          print('[DIO] error request data: ${error.requestOptions.data}');
        }
        handler.next(error);
      },
    ));
  }

  @override
  Future<bool> updateProfile(ProfileModel profile) async {
    try {
      final response = await dio.post(
        ApiConfig
            .profileUpdateEndpoint, // Đảm bảo endpoint là string: '/api/profile/update'
        data: profile.toJson(),
        options: Options(contentType: Headers.jsonContentType),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      // Ném lỗi để Repository hoặc Controller xử lý
      throw Exception(
        'Lỗi Server: ${e.response?.statusCode} - ${e.response?.statusMessage} - ${e.response?.data}',
      );
    }
  }

  @override
  Future<ProfileModel?> getProfile() async {
    try {
      final response = await dio.get(ApiConfig.getProfileEndpoint);

      if (response.statusCode == 200) {
        final data = response.data; // Dio tự decode JSON thành Map

        // Logic cũ của bạn: check key 'profile' hoặc lấy trực tiếp
        if (data is Map<String, dynamic>) {
          if (data['profile'] != null) {
            return ProfileModel.fromJson(data['profile']);
          } else if (data.containsKey('height')) {
            // Giả định nếu có key 'height' thì là object profile phẳng
            return ProfileModel.fromJson(data);
          }
        }
      }
      return null;
    } on DioException catch (e) {
      // Nếu 401 (Unauthorized) hoặc 404 (Not found), trả về null để app dùng cache
      if (e.response?.statusCode == 404 || e.response?.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }
}

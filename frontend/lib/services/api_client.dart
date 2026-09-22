import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

class ApiClient {
  static final Dio dio = _buildDio();

  static Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.requestTimeout,
        receiveTimeout: ApiConfig.requestTimeout,
        sendTimeout: ApiConfig.requestTimeout,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          const storage = FlutterSecureStorage();
          final token = await storage.read(key: 'auth_token') ??
              await storage.read(key: 'jwt_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Cache-Control'] = 'no-cache';
          if (kDebugMode) {
            debugPrint('[DIO] Request: ${options.method} ${options.uri.path}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint(
              '[DIO] Response: ${response.statusCode} '
              '${response.requestOptions.method} '
              '${response.requestOptions.uri.path}',
            );
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          if (kDebugMode) {
            debugPrint(
              '[DIO] Error: ${e.type.name} '
              'status=${e.response?.statusCode ?? 'none'} '
              '${e.requestOptions.method} ${e.requestOptions.uri.path}',
            );
          }
          return handler.next(e);
        },
      ),
    );

    return dio;
  }
}

final dioProvider = Provider<Dio>((ref) {
  return ApiClient.dio;
});

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class AuthHelper {
  static const String _tokenKey = 'auth_token';
  static const String _emailKey = 'user_email';
  static const String _nameKey = 'user_fullname';
  static const _storage = FlutterSecureStorage();

  static void logToken(String? token) {
    if (kReleaseMode) return;
    if (token == null || token.isEmpty) return;
    final visible = token.length > 10
        ? '${token.substring(0, 6)}...${token.substring(token.length - 4)}'
        : '***';
    print('[AUTH] token preview: $visible');
  }

  static Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  static Future<String?> getUserEmail() async {
    return await _storage.read(key: _emailKey);
  }

  static Future<String?> getUserName() async {
    return await _storage.read(key: _nameKey);
  }

  static Future<void> clearAuth() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _nameKey);
  }

  static Future<void> printAuthStatus() async {
    if (kReleaseMode) return;
    final token = await _storage.read(key: _tokenKey);
    final email = await _storage.read(key: _emailKey);
    final name = await _storage.read(key: _nameKey);

    print('🔍 [AUTH] ===== AUTH STATUS =====');
    print('🔍 [AUTH] Logged in: ${token != null ? "YES" : "NO"}');
    if (token != null) {
      print('🔍 [AUTH] Token length: ${token.length}');
      logToken(token);
    }
    print('🔍 [AUTH] Email: ${email ?? "NULL"}');
    print('🔍 [AUTH] Name: ${name ?? "NULL"}');
    print('🔍 [AUTH] =========================');
  }
}

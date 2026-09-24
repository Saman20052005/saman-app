import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class AuthHelper {
  static const String _tokenKey = 'auth_token';
  static const String _emailKey = 'user_email';
  static const String _nameKey = 'user_fullname';
  static const _storage = FlutterSecureStorage();

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
    if (!kDebugMode) return;
    final token = await _storage.read(key: _tokenKey);
    debugPrint(
      '🔍 [AUTH] Logged in: '
      '${token != null && token.isNotEmpty ? "YES" : "NO"}',
    );
  }
}

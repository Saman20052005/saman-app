import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';
import '../presentation/providers/workout_home_providers.dart';

class AuthHelper {
  static const String _tokenKey = 'auth_token';
  static const String _jwtTokenKey = 'jwt_token';
  static const String _emailKey = 'user_email';
  static const String _nameKey = 'user_fullname';
  static const _storage = FlutterSecureStorage();

  /// Checks if either primary auth_token or fallback jwt_token exists.
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Alias for clean session verification.
  static Future<bool> hasValidSession() async => isLoggedIn();

  /// Retrieves auth_token with jwt_token fallback.
  static Future<String?> getToken() async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null && token.isNotEmpty) return token;
    return await _storage.read(key: _jwtTokenKey);
  }

  static Future<String?> getUserEmail() async {
    return await _storage.read(key: _emailKey);
  }

  static Future<String?> getUserName() async {
    return await _storage.read(key: _nameKey);
  }

  /// Removes all authentication tokens and credentials from FlutterSecureStorage.
  static Future<void> clearAuth() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _jwtTokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _nameKey);
  }

  /// Logout procedure clearing session, tokens, and caches safely.
  ///
  /// Steps:
  /// 1. Increments ProfileNotifier session epoch to cancel/discard in-flight fetches.
  /// 2. Clears secure authentication tokens (both auth_token & jwt_token).
  /// 3. Deletes user-specific cached profile snapshots from SharedPreferences.
  /// 4. Preserves global application preferences (language_code, is_dark_mode).
  /// 5. Invalidates user-scoped Riverpod state providers.
  static Future<void> logout(dynamic ref) async {
    // 1. Invalidate session epoch immediately
    ref.read(profileProvider.notifier).resetSession();

    // 2. Clear secure storage tokens
    await clearAuth();

    // 3. Clear user-specific cache via synchronized repository queue
    try {
      await ref.read(profileRepositoryProvider).clearLocalProfile();
    } catch (e) {
      debugPrint('[AUTH] Error clearing local profile via repository: $e');
    }

    // Direct removal for any legacy credentials in SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_profile');
      await prefs.remove('cached_profile_snapshot_v2');
      await prefs.remove('user_email');
      await prefs.remove('user_fullname');
    } catch (e) {
      debugPrint('[AUTH] Error removing user cache on logout: $e');
    }

    // 4. Invalidate user-scoped state providers
    ref.invalidate(profileProvider);
    ref.invalidate(nutritionProvider);
    ref.invalidate(macroTargetsProvider);
    ref.invalidate(weeklyGoalNotifierProvider);
  }

  static Future<void> printAuthStatus() async {
    if (!kDebugMode) return;
    final token = await getToken();
    debugPrint(
      '🔍 [AUTH] Logged in: '
      '${token != null && token.isNotEmpty ? "YES" : "NO"}',
    );
  }
}

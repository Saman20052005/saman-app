import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';
import '../presentation/providers/workout_home_providers.dart';
import '../presentation/providers/workout_history_providers.dart';
import '../presentation/providers/active_workout_providers.dart';
import '../presentation/providers/session_detail_providers.dart';

enum AuthTokenState {
  confirmedRetained,
  confirmedLost,
  indeterminate,
}

class LogoutException implements Exception {
  final String message;
  final AuthTokenState tokenState;
  final List<String> failedKeys;

  const LogoutException(
    this.message, {
    this.tokenState = AuthTokenState.indeterminate,
    this.failedKeys = const [],
  });

  @override
  String toString() => message;
}

final authLoggingOutProvider = StateProvider<bool>((ref) => false);

class AuthHelper {
  static const String _tokenKey = 'auth_token';
  static const String _jwtTokenKey = 'jwt_token';
  static const String _emailKey = 'user_email';
  static const String _nameKey = 'user_fullname';
  static FlutterSecureStorage _storage = const FlutterSecureStorage();

  @visibleForTesting
  static void setStorageForTesting(FlutterSecureStorage storage) {
    _storage = storage;
  }

  @visibleForTesting
  static void resetStorageForTesting() {
    _storage = const FlutterSecureStorage();
  }

  /// Inventory of all authentication and session credentials stored in FlutterSecureStorage.
  static const List<String> _credentialKeys = [
    _tokenKey,
    _jwtTokenKey,
    _emailKey,
    _nameKey,
  ];

  static ProviderContainer _getContainer(dynamic ref) {
    if (ref is ProviderContainer) {
      return ref;
    }
    if (ref is WidgetRef) {
      return ProviderScope.containerOf(ref.context, listen: false);
    }
    throw ArgumentError('ref must be a WidgetRef or ProviderContainer');
  }

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
  /// Strictly targets the credential inventory without calling deleteAll().
  /// Throws [LogoutException] if any credentials cannot be removed.
  static Future<void> clearAuth() async {
    final failedKeys = <String>[];
    for (final key in _credentialKeys) {
      try {
        await _storage.delete(key: key);
      } catch (e) {
        debugPrint('[AUTH] Error deleting key $key: $e');
        failedKeys.add(key);
      }
    }

    // Verification: ensure each credential key is genuinely deleted
    for (final key in _credentialKeys) {
      try {
        final val = await _storage.read(key: key);
        if (val != null && val.isNotEmpty) {
          if (!failedKeys.contains(key)) failedKeys.add(key);
        }
      } catch (e) {
        debugPrint('[AUTH] Error reading $key during verification: $e');
        if (!failedKeys.contains(key)) failedKeys.add(key);
      }
    }

    if (failedKeys.isNotEmpty) {
      AuthTokenState tokenState;
      try {
        final authVal = await _storage.read(key: _tokenKey);
        final jwtVal = await _storage.read(key: _jwtTokenKey);
        final hasToken = (authVal != null && authVal.isNotEmpty) ||
            (jwtVal != null && jwtVal.isNotEmpty);
        tokenState = hasToken
            ? AuthTokenState.confirmedRetained
            : AuthTokenState.confirmedLost;
      } catch (e) {
        tokenState = AuthTokenState.indeterminate;
      }

      throw LogoutException(
        'Failed to clear credentials from storage: ${failedKeys.join(', ')}',
        tokenState: tokenState,
        failedKeys: failedKeys,
      );
    }
  }

  /// Logout procedure clearing session, tokens, and caches safely.
  ///
  /// Steps:
  /// 1. Resolves ProviderContainer before any await to decouple from widget lifecycle.
  /// 2. Sets authLoggingOutProvider to ensure ProfileGate retains Main until navigation.
  /// 3. Extracts notifiers and dependencies before any await point.
  /// 4. Clears secure authentication tokens with verification FIRST.
  ///    If deletion fails, throws LogoutException: session epoch and profile are NOT reset.
  /// 5. Increments ProfileNotifier session epoch to cancel/discard in-flight fetches.
  /// 6. Deletes user-specific cached profile snapshots from SharedPreferences.
  /// 7. Invalidates user-scoped Riverpod state providers.
  /// 8. Guarantees authLoggingOutProvider is released on stable container without hiding errors.
  static Future<void> logout(dynamic ref) async {
    // 0. Resolve ProviderContainer BEFORE any await point so lifecycle is decoupled from WidgetRef
    final container = _getContainer(ref);

    // 1. Mark logout in progress on root container so ProfileGate retains Main until navigation
    container.read(authLoggingOutProvider.notifier).state = true;

    // 2. Extract dependencies BEFORE any await point while everything is intact
    final profileNotifier = container.read(profileProvider.notifier);
    final workoutAuthScopeNotifier =
        container.read(workoutAuthScopeProvider.notifier);
    final profileRepo = container.read(profileRepositoryProvider);
    final currentUserId = container.read(profileProvider).userId;

    try {
      // 3. Clear secure storage tokens FIRST.
      // If credential deletion fails, this throws LogoutException.
      // Session epoch is NOT bumped, profile is NOT reset, and user remains safely on screen.
      await clearAuth();

      // 4. Invalidate session epoch immediately to discard late in-flight responses
      profileNotifier.resetSession();
      workoutAuthScopeNotifier.state++;

      // 5. Clear user-specific cache via synchronized repository queue and prefs
      try {
        await profileRepo.clearLocalProfile(userId: currentUserId);
      } catch (e) {
        debugPrint('[AUTH] Error clearing local profile via repository: $e');
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('cached_profile');
        await prefs.remove('cached_profile_snapshot_v2');
        if (currentUserId != null && currentUserId.isNotEmpty) {
          await prefs.remove('cached_profile_snapshot_v2_$currentUserId');
          await prefs.remove('onboarding_draft_$currentUserId');
        }
        await prefs.remove('user_email');
        await prefs.remove('user_fullname');
      } catch (e) {
        debugPrint('[AUTH] Error removing user cache on logout: $e');
      }

      // 6. Invalidate user-scoped state providers on the stable container
      container.invalidate(profileProvider);
      container.invalidate(nutritionProvider);
      container.invalidate(macroTargetsProvider);
      container.invalidate(weeklyGoalNotifierProvider);
      container.invalidate(workoutHistoryProvider);
      container.invalidate(activeWorkoutSessionProvider);
      container.invalidate(sessionDetailProvider);
    } on LogoutException catch (e) {
      if (e.tokenState == AuthTokenState.confirmedLost ||
          e.tokenState == AuthTokenState.indeterminate) {
        // Credentials are lost or indeterminate:
        // Invalidate session epoch and scope to discard all pending responses
        profileNotifier.resetSession();
        workoutAuthScopeNotifier.state++;

        try {
          await profileRepo.clearLocalProfile(userId: currentUserId);
        } catch (_) {}

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('cached_profile');
          await prefs.remove('cached_profile_snapshot_v2');
          if (currentUserId != null && currentUserId.isNotEmpty) {
            await prefs.remove('cached_profile_snapshot_v2_$currentUserId');
            await prefs.remove('onboarding_draft_$currentUserId');
          }
          await prefs.remove('user_email');
          await prefs.remove('user_fullname');
        } catch (_) {}

        container.invalidate(profileProvider);
        container.invalidate(nutritionProvider);
        container.invalidate(macroTargetsProvider);
        container.invalidate(weeklyGoalNotifierProvider);
        container.invalidate(workoutHistoryProvider);
        container.invalidate(activeWorkoutSessionProvider);
        container.invalidate(sessionDetailProvider);
      }
      rethrow;
    } finally {
      // 7. Guarantee authLoggingOutProvider is released on the stable container.
      container.read(authLoggingOutProvider.notifier).state = false;
    }
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

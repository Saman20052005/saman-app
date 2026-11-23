import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

import '../../config/api_config.dart';
import '../../services/api_client.dart';

/// What a successful auth operation produced. Only [authenticated] creates a
/// session; [registered] and [passwordReset] never do.
enum AuthOutcome { authenticated, registered, passwordReset }

// State lưu trạng thái UI
class LoginState {
  final bool isLoading;
  final String? errorMessage;
  final bool isSuccess;
  final String? successMessage;
  final bool isGuestLogin;

  /// One-shot trigger: set only on the state emitted right after an operation
  /// succeeded (and, for [AuthOutcome.authenticated], after auth data was
  /// saved). Reset by the next state change.
  final AuthOutcome? outcome;

  LoginState({
    this.isLoading = false,
    this.errorMessage,
    this.isSuccess = false,
    this.successMessage,
    this.isGuestLogin = false,
    this.outcome,
  });

  LoginState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? isSuccess,
    String? successMessage,
    bool? isGuestLogin,
    AuthOutcome? outcome,
  }) {
    return LoginState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage, // Reset error khi state mới
      isSuccess: isSuccess ?? false, // Reset success trigger
      successMessage: successMessage,
      isGuestLogin: isGuestLogin ?? false,
      outcome: outcome, // Reset outcome trigger
    );
  }
}

class LoginController extends StateNotifier<LoginState> {
  LoginController() : super(LoginState());
  static const _storage = FlutterSecureStorage();

  static const String socialLoginInterruptedMessage =
      'Đăng nhập tạm thời gián đoạn. Vui lòng dùng Đăng nhập Email/Mật khẩu hoặc Guest Mode (nếu có)';

  static const String _guestEmail = 'guest@saman.ai';
  static const String _guestPassword = 'GuestPassword123!';
  static const String _guestFullName = 'Saman Guest';
  static const String _guestFallbackToken = 'guest_dev_mode_token';

  // Google config
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? "501146398294-uu3k94aukcmmik9j64huamsfaf9q9056.apps.googleusercontent.com"
        : null,
    serverClientId: kIsWeb
        ? null
        : "501146398294-uu3k94aukcmmik9j64huamsfaf9q9056.apps.googleusercontent.com",
    scopes: ['email', 'profile'],
  );

  // --- 1. EMAIL/PASSWORD LOGIN & REGISTER ---
  Future<void> submitEmailAuth({
    required bool isLoginMode,
    required String email,
    required String password,
    String? fullName,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final endpoint =
          isLoginMode ? ApiConfig.loginEndpoint : ApiConfig.registerEndpoint;
      final body = {
        'email': email.trim(),
        'password': password,
        if (!isLoginMode) 'full_name': fullName?.trim(),
        if (!isLoginMode && (phone?.isNotEmpty ?? false)) 'phone': phone?.trim(),
      };

      final response = await ApiClient.dio
          .post(
            endpoint,
            data: body,
            options: Options(contentType: Headers.jsonContentType),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (isLoginMode) {
          final data = response.data is String
              ? jsonDecode(response.data as String)
              : response.data;
          await _saveAuthData(
              data['access_token'], email.trim(), fullName?.trim());
          state = state.copyWith(
              isLoading: false,
              isSuccess: true,
              successMessage: 'Welcome back!',
              outcome: AuthOutcome.authenticated);
        } else {
          // Register success -> Switch mode logic handled in UI
          state = state.copyWith(
              isLoading: false,
              isSuccess: true,
              successMessage: 'Account created! Please login.',
              outcome: AuthOutcome.registered);
        }
      } else {
        final errorMsg = extractErrorMessage(response.data, response.statusCode);
        state = state.copyWith(isLoading: false, errorMessage: errorMsg);
      }
    } on DioException catch (e) {
      final errorMsg = extractErrorMessage(e);
      state = state.copyWith(isLoading: false, errorMessage: errorMsg);
    } catch (e) {
      final errorMsg = extractErrorMessage(e);
      state = state.copyWith(isLoading: false, errorMessage: errorMsg);
    }
  }

  static String extractErrorMessage(dynamic error, [int? statusCode]) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out. Please check your internet connection.';
      }
      if (error.type == DioExceptionType.connectionError) {
        return 'Cannot connect to server. Please check your network connection.';
      }

      final response = error.response;
      if (response != null) {
        return _formatResponseError(response.data, response.statusCode);
      }
      return 'Network error occurred. Please try again.';
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    }

    if (error is FormatException) {
      return 'Invalid response from server. Please try again.';
    }

    if (error is Map || error is List || error is String) {
      return _formatResponseError(error, statusCode);
    }

    return 'Authentication failed. Please try again.';
  }

  static String _formatResponseError(dynamic data, int? statusCode) {
    if (statusCode != null && statusCode >= 500) {
      return 'Server error occurred. Please try again later.';
    }

    dynamic parsed = data;
    if (parsed is String && parsed.isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        // Not JSON
      }
    }

    if (parsed is Map) {
      final detail = parsed['detail'];
      if (detail != null) {
        return _formatDetailError(detail, statusCode);
      }
      final message = parsed['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }

    if (parsed is String && parsed.isNotEmpty) {
      return _formatDetailError(parsed, statusCode);
    }

    if (statusCode == 400) {
      return 'Invalid request. Please check your information.';
    } else if (statusCode == 401) {
      return 'Invalid email or password.';
    } else if (statusCode == 403) {
      return 'Access denied.';
    } else if (statusCode == 404) {
      return 'Resource not found.';
    } else if (statusCode == 409) {
      return 'This email is already registered. Please log in or use another email.';
    } else if (statusCode == 422) {
      return 'Invalid input format. Please check your email and password.';
    } else if (statusCode != null && statusCode >= 500) {
      return 'Server error occurred. Please try again later.';
    }

    return 'Authentication failed. Please check your information.';
  }

  static String _formatDetailError(dynamic detail, int? statusCode) {
    if (detail is String) {
      if (detail.toLowerCase().contains('already exists')) {
        return 'This email is already registered. Please log in or use another email.';
      }
      if (detail.toLowerCase().contains('invalid email or password')) {
        return 'Invalid email or password.';
      }
      return detail;
    }

    if (detail is List) {
      final messages = <String>[];
      for (final item in detail) {
        if (item is Map) {
          final loc = item['loc'];
          final locList =
              loc is List ? loc.map((e) => e.toString()).toList() : <String>[];
          final type = item['type']?.toString() ?? '';

          if (locList.contains('password')) {
            if (type == 'string_too_short' || type.contains('too_short')) {
              messages.add('Password must be at least 8 characters.');
            } else {
              messages.add('Invalid password format.');
            }
          } else if (locList.contains('email')) {
            messages.add('Please enter a valid email address.');
          } else {
            final msg = item['msg'];
            if (msg is String && msg.isNotEmpty) {
              messages.add(msg);
            }
          }
        } else if (item is String && item.isNotEmpty) {
          messages.add(item);
        }
      }

      if (messages.isNotEmpty) {
        return messages.toSet().join(' ');
      }
    }

    if (statusCode == 422) {
      return 'Invalid input format. Please check your email and password.';
    }
    return 'Authentication failed. Please check your details.';
  }

  // --- 2. SOCIAL LOGIN HANDLERS ---
  static bool _isUserCancelledSocialError(Object error) {
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('cancel') || code == 'sign_in_canceled') {
        return true;
      }
    }
    if (error is SignInWithAppleAuthorizationException &&
        error.code == AuthorizationErrorCode.canceled) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('sign_in_canceled') ||
        text.contains('authorizationerrorcode.canceled');
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // User cancelled

      state = state.copyWith(isLoading: true);
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? tokenToSend = googleAuth.idToken ?? googleAuth.accessToken;

      if (tokenToSend != null) {
        await _authenticateSocialWithBackend(
          provider: 'google',
          token: tokenToSend,
          email: googleUser.email,
          fullName: googleUser.displayName,
        );
      } else {
        throw Exception('No Google Token found');
      }
    } on PlatformException catch (e) {
      debugPrint('[AUTH] Google Sign-In PlatformException: ${e.code} - ${e.message}');
      if (_isUserCancelledSocialError(e)) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    } on MissingPluginException catch (e) {
      debugPrint('[AUTH] Google Sign-In MissingPluginException: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    } catch (e) {
      debugPrint('[AUTH] Google Sign-In Error: $e');
      if (_isUserCancelledSocialError(e)) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    }
  }

  Future<void> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance
          .login(permissions: ['public_profile', 'email']);
      if (result.status == LoginStatus.success && result.accessToken != null) {
        state = state.copyWith(isLoading: true);
        await _authenticateSocialWithBackend(
          provider: 'facebook',
          token: result.accessToken!.token,
        );
      } else if (result.status == LoginStatus.cancelled) {
        state = state.copyWith(isLoading: false);
        return;
      } else {
        throw Exception(result.message ?? 'Facebook login failed');
      }
    } on PlatformException catch (e) {
      debugPrint('[AUTH] Facebook Sign-In PlatformException: ${e.code} - ${e.message}');
      if (_isUserCancelledSocialError(e)) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    } on MissingPluginException catch (e) {
      debugPrint('[AUTH] Facebook Sign-In MissingPluginException: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    } catch (e) {
      debugPrint('[AUTH] Facebook Sign-In Error: $e');
      if (_isUserCancelledSocialError(e)) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    }
  }

  Future<void> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName
        ],
      );

      if (credential.identityToken != null) {
        state = state.copyWith(isLoading: true);
        String? name;
        if (credential.givenName != null) {
          name = "${credential.givenName} ${credential.familyName}";
        }
        await _authenticateSocialWithBackend(
          provider: 'apple',
          token: credential.identityToken!,
          email: credential.email,
          fullName: name,
        );
      } else {
        throw Exception('Apple Sign In failed: No Identity Token');
      }
    } on PlatformException catch (e) {
      debugPrint('[AUTH] Apple Sign-In PlatformException: ${e.code} - ${e.message}');
      if (_isUserCancelledSocialError(e)) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    } on MissingPluginException catch (e) {
      debugPrint('[AUTH] Apple Sign-In MissingPluginException: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    } catch (e) {
      debugPrint('[AUTH] Apple Sign-In Error: $e');
      if (_isUserCancelledSocialError(e)) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: socialLoginInterruptedMessage,
      );
    }
  }

  // --- 2B. GUEST / DEV MODE LOGIN ---
  Future<void> signInAsGuest() async {
    state = state.copyWith(isLoading: true);
    String tokenToPersist = _guestFallbackToken;

    try {
      final loginResponse = await ApiClient.dio
          .post(
            ApiConfig.loginEndpoint,
            data: {
              'email': _guestEmail,
              'password': _guestPassword,
            },
            options: Options(
              contentType: Headers.jsonContentType,
              validateStatus: (status) => status != null && status < 500,
            ),
          )
          .timeout(const Duration(seconds: 3));

      if (loginResponse.statusCode == 200) {
        final data = loginResponse.data is String
            ? jsonDecode(loginResponse.data as String)
            : loginResponse.data;
        final token = data is Map ? data['access_token']?.toString() : null;
        if (token != null && token.isNotEmpty) {
          tokenToPersist = token;
        }
      } else if (loginResponse.statusCode == 401 ||
          loginResponse.statusCode == 404) {
        await ApiClient.dio
            .post(
              ApiConfig.registerEndpoint,
              data: {
                'email': _guestEmail,
                'password': _guestPassword,
                'full_name': _guestFullName,
              },
              options: Options(
                contentType: Headers.jsonContentType,
                validateStatus: (status) => status != null && status < 500,
              ),
            )
            .timeout(const Duration(seconds: 3));

        final retryLogin = await ApiClient.dio
            .post(
              ApiConfig.loginEndpoint,
              data: {
                'email': _guestEmail,
                'password': _guestPassword,
              },
              options: Options(
                contentType: Headers.jsonContentType,
                validateStatus: (status) => status != null && status < 500,
              ),
            )
            .timeout(const Duration(seconds: 3));

        if (retryLogin.statusCode == 200) {
          final data = retryLogin.data is String
              ? jsonDecode(retryLogin.data as String)
              : retryLogin.data;
          final token = data is Map ? data['access_token']?.toString() : null;
          if (token != null && token.isNotEmpty) {
            tokenToPersist = token;
          }
        }
      }
    } catch (e) {
      debugPrint('[AUTH] Guest backend auth skipped, using local guest session: $e');
    }

    try {
      await _saveAuthData(tokenToPersist, _guestEmail, _guestFullName);
    } catch (e) {
      debugPrint('[AUTH] Guest storage write warning: $e');
    }

    state = state.copyWith(
      isLoading: false,
      isSuccess: true,
      isGuestLogin: true,
      successMessage: 'Welcome to Saman Guest Mode!',
      outcome: AuthOutcome.authenticated,
    );
  }

  // --- 3. HELPER: SOCIAL AUTH BACKEND ---
  Future<void> _authenticateSocialWithBackend({
    required String provider,
    required String token,
    String? email,
    String? fullName,
  }) async {
    try {
      final response = await ApiClient.dio
          .post(
            '${ApiConfig.baseUrl}/api/auth/social-login',
            data: {
              'provider': provider,
              'token': token,
              'email': email,
              'full_name': fullName,
            },
            options: Options(contentType: Headers.jsonContentType),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        await _saveAuthData(
            data['access_token'],
            data['user']?['email'] ?? email,
            data['user']?['full_name'] ?? fullName);
        state = state.copyWith(
            isLoading: false,
            isSuccess: true,
            successMessage: 'Login with $provider success!',
            outcome: AuthOutcome.authenticated);
      } else {
        final errorBody = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        throw Exception((errorBody is Map && errorBody['detail'] != null)
            ? errorBody['detail']
            : 'Social login failed');
      }
    } catch (e) {
      rethrow; // Để catch block bên ngoài xử lý
    }
  }

  Future<void> _saveAuthData(String token, String? email, String? name) async {
    await _storage.write(key: 'auth_token', value: token);
    if (email != null) await _storage.write(key: 'user_email', value: email);
    if (name != null) await _storage.write(key: 'user_fullname', value: name);
  }

  // --- 4. FORGOT PASSWORD ---
  Future<bool> sendOtp(String email) async {
    // Return true nếu gửi thành công để UI chuyển bước
    try {
      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/auth/forgot-password",
        data: {"email": email},
        options: Options(contentType: Headers.jsonContentType),
      );
      if (response.statusCode == 200) return true;
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      throw Exception((data is Map && data['detail'] != null)
          ? data['detail']
          : "Error sending OTP");
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> resetPassword(String email, String otp, String newPass) async {
    try {
      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/auth/reset-password",
        data: {"email": email, "otp": otp, "new_password": newPass},
        options: Options(contentType: Headers.jsonContentType),
      );
      if (response.statusCode == 200) {
        state = state.copyWith(
            isSuccess: true,
            successMessage: "Password reset successful! Please login.",
            outcome: AuthOutcome.passwordReset);
        return true;
      }
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      throw Exception((data is Map && data['detail'] != null)
          ? data['detail']
          : "Reset failed");
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>(
        (ref) => LoginController());

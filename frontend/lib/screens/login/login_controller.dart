import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

import '../../config/api_config.dart';
import '../../services/api_client.dart';

// State lưu trạng thái UI
class LoginState {
  final bool isLoading;
  final String? errorMessage;
  final bool isSuccess;
  final String? successMessage;

  LoginState({
    this.isLoading = false,
    this.errorMessage,
    this.isSuccess = false,
    this.successMessage,
  });

  LoginState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? isSuccess,
    String? successMessage,
  }) {
    return LoginState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage, // Reset error khi state mới
      isSuccess: isSuccess ?? false, // Reset success trigger
      successMessage: successMessage,
    );
  }
}

class LoginController extends StateNotifier<LoginState> {
  LoginController() : super(LoginState());
  static const _storage = FlutterSecureStorage();

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
        'email': email,
        'password': password,
        if (!isLoginMode) 'full_name': fullName,
        if (!isLoginMode && (phone?.isNotEmpty ?? false)) 'phone': phone,
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
          await _saveAuthData(data['access_token'], email, fullName);
          state = state.copyWith(
              isLoading: false,
              isSuccess: true,
              successMessage: 'Welcome back!');
        } else {
          // Register success -> Switch mode logic handled in UI
          state = state.copyWith(
              isLoading: false,
              isSuccess: true,
              successMessage: 'Account created! Please login.');
        }
      } else {
        final error = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        throw Exception((error is Map && error['detail'] != null)
            ? error['detail']
            : 'Auth failed');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  // --- 2. SOCIAL LOGIN HANDLERS ---
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
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: 'Google Sign In Error: $e');
    }
  }

  Future<void> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance
          .login(permissions: ['public_profile', 'email']);
      if (result.status == LoginStatus.success) {
        state = state.copyWith(isLoading: true);
        await _authenticateSocialWithBackend(
          provider: 'facebook',
          token: result.accessToken!.token,
        );
      } else if (result.status == LoginStatus.failed) {
        throw Exception(result.message);
      }
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: 'Facebook Error: $e');
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
    } catch (e) {
      if (!e.toString().contains('canceled')) {
        state =
            state.copyWith(isLoading: false, errorMessage: 'Apple Error: $e');
      }
    }
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
            successMessage: 'Login with $provider success!');
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
            successMessage: "Password reset successful! Please login.");
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

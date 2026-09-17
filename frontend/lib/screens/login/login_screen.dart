import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../widgets/app_logo.dart';
import 'login_controller.dart';
import 'widgets/login_form.dart';
import 'widgets/social_login_row.dart';
import 'widgets/forgot_password_sheet.dart'; // Bạn cần tạo file này dựa trên code cũ (đã tách)
import '../../config/routes.dart';
import '../../providers/profile_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoginMode = true;

  @override
  Widget build(BuildContext context) {
    // Lắng nghe State từ Controller
    ref.listen<LoginState>(loginControllerProvider, (previous, next) {
      if (next.errorMessage != null) {
        Fluttertoast.showToast(
            msg: next.errorMessage!, backgroundColor: Colors.red);
      }
      if (next.isSuccess && next.successMessage != null) {
        Fluttertoast.showToast(msg: next.successMessage!);
        // Nếu login thành công -> Chuyển màn hình
        if (_isLoginMode) {
          ref.read(profileProvider.notifier).loadProfile();
          Navigator.pushReplacementNamed(context, AppRoutes.main);
        } else {
          // Nếu Register thành công -> Chuyển sang Tab Login
          setState(() => _isLoginMode = true);
        }
      }
    });

    final loginState = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);

    const primaryBlack = Color(0xFF1E1E1E);
    const bgGrey = Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: bgGrey,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                LoginForm(
                  isLoginMode: _isLoginMode,
                  isLoading: loginState.isLoading,
                  onSubmit: (email, pass, name, phone) {
                    controller.submitEmailAuth(
                        isLoginMode: _isLoginMode,
                        email: email,
                        password: pass,
                        fullName: name,
                        phone: phone);
                  },
                  onForgotPassword: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) =>
                          const ForgotPasswordSheet(), // Cần tách file này ra
                    );
                  },
                ),
                const SizedBox(height: 24),
                _buildSwitchModeButton(primaryBlack),
                const SizedBox(height: 30),
                _buildDivider(),
                const SizedBox(height: 24),
                SocialLoginRow(
                  isLoading: loginState.isLoading,
                  onGoogleTap: controller.signInWithGoogle,
                  onAppleTap: controller.signInWithApple,
                  onFacebookTap: controller.signInWithFacebook,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const AppLogo(size: 90)
            .animate()
            .scale(duration: 600.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 20),
        const Text(
          'SAMAN',
          style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E1E1E),
              letterSpacing: 3.0),
        ).animate().fadeIn().slideY(begin: 0.2, end: 0),
        const SizedBox(height: 8),
        Text(
          'Solid Body. Balanced Mind.',
          style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 32),
        Text(
          _isLoginMode ? 'Welcome Back!' : 'Create Account',
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1E1E)),
        ),
      ],
    );
  }

  Widget _buildSwitchModeButton(Color primaryColor) {
    return GestureDetector(
      onTap: () => setState(() => _isLoginMode = !_isLoginMode),
      child: RichText(
        text: TextSpan(
          text: _isLoginMode
              ? "Don't have an account? "
              : "Already have an account? ",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          children: [
            TextSpan(
                text: _isLoginMode ? "Sign Up" : "Log In",
                style: TextStyle(
                    color: primaryColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(children: [
      Expanded(child: Divider(color: Colors.grey.shade300)),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text("OR CONTINUE WITH",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400))),
      Expanded(child: Divider(color: Colors.grey.shade300))
    ]);
  }
}

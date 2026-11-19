import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../config/app_translations.dart';
import '../../features/profile/domain/entities/profile_entity.dart';
import '../../features/profile/domain/entities/profile_snapshot.dart';
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
  bool _hasNavigatedToMain = false;

  void _showAuthSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF26282D),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleSocialLogin(
    Future<void> Function() socialSignInAction,
  ) async {
    try {
      await socialSignInAction();
    } on PlatformException catch (e) {
      debugPrint('[LOGIN_UI] Social login PlatformException: $e');
      _showAuthSnackBar(LoginController.socialLoginInterruptedMessage);
    } on MissingPluginException catch (e) {
      debugPrint('[LOGIN_UI] Social login MissingPluginException: $e');
      _showAuthSnackBar(LoginController.socialLoginInterruptedMessage);
    } catch (e) {
      debugPrint('[LOGIN_UI] Social login error: $e');
      _showAuthSnackBar(LoginController.socialLoginInterruptedMessage);
    }
  }

  Future<void> _handleGuestLogin(LoginController controller) async {
    try {
      await controller.signInAsGuest();
    } catch (e) {
      debugPrint('[LOGIN_UI] Guest login fallback: $e');
      if (!mounted || _hasNavigatedToMain) return;
      _hasNavigatedToMain = true;
      ref.read(profileProvider.notifier).resetSession();
      _seedGuestProfileSession();
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    }
  }

  void _seedGuestProfileSession() {
    const guestUserId = 'guest_dev_user';
    const guestProfile = ProfileEntity(
      userId: guestUserId,
      age: 26,
      height: 172.0,
      weight: 68.0,
      gender: Gender.male,
      activityLevel: ActivityLevel.medium,
      activityCanonical: 'moderately_active',
      goal: Goal.maintain_weight,
    );
    const guestSnapshot = ProfileSnapshot(
      userId: guestUserId,
      profile: guestProfile,
      targetCalories: 2200,
      targetProtein: 140,
      targetCarbs: 250,
      targetFat: 70,
      targetBurned: 450,
      waterTargetMl: 2200,
      email: 'guest@saman.ai',
      fullName: 'Saman Guest',
      isFromCache: false,
      hasConfirmedServerHealthStats: true,
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ref.read(profileProvider.notifier).state = ProfileState(
      status: ProfileStatus.ready,
      profile: guestProfile,
      snapshot: guestSnapshot,
      confirmedUserId: guestUserId,
      isNetworkConfirmed: true,
      targetCalories: 2200,
      targetProtein: 140,
      targetCarbs: 250,
      targetFat: 70,
      targetBurned: 450,
      waterTargetMl: 2200,
      isFromCache: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe State từ Controller
    ref.listen<LoginState>(loginControllerProvider, (previous, next) {
      if (next.errorMessage != null) {
        _showAuthSnackBar(next.errorMessage!);
        try {
          Fluttertoast.showToast(
            msg: next.errorMessage!,
            backgroundColor: const Color(0xFF26282D),
            textColor: const Color(0xFFF3F4F6),
          );
        } catch (_) {}
      }
      final outcome = next.outcome;
      if (outcome == null) return;
      if (next.successMessage != null) {
        try {
          Fluttertoast.showToast(
            msg: next.successMessage!,
            backgroundColor: const Color(0xFF26282D),
            textColor: const Color(0xFFF3F4F6),
          );
        } catch (_) {}
      }
      switch (outcome) {
        case AuthOutcome.authenticated:
          // Navigation follows the operation that just authenticated, never a
          // token that may already be in storage. Drop any previous session's
          // profile so the gate must confirm the new owner over the network.
          if (_hasNavigatedToMain) return;
          _hasNavigatedToMain = true;
          ref.read(profileProvider.notifier).resetSession();
          if (next.isGuestLogin) {
            _seedGuestProfileSession();
          }
          Navigator.pushReplacementNamed(context, AppRoutes.main);
          break;
        case AuthOutcome.registered:
          // Registration creates no session -> back to the login form.
          setState(() => _isLoginMode = true);
          break;
        case AuthOutcome.passwordReset:
          // Password reset creates no session; the user stays on login.
          break;
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
                  onGoogleTap: () =>
                      _handleSocialLogin(controller.signInWithGoogle),
                  onAppleTap: () =>
                      _handleSocialLogin(controller.signInWithApple),
                  onFacebookTap: () =>
                      _handleSocialLogin(controller.signInWithFacebook),
                ),
                const SizedBox(height: 16),
                _buildGuestModeButton(
                  isLoading: loginState.isLoading,
                  onTap: () => _handleGuestLogin(controller),
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
        const AppLogo(size: 90, color: Color(0xFF1E1E1E))
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
          context.tr('login_tagline'),
          style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 32),
        Text(
          _isLoginMode
              ? context.tr('welcome_back')
              : context.tr('create_account'),
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
              ? context.tr('dont_have_account')
              : context.tr('already_have_account'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          children: [
            TextSpan(
                text: _isLoginMode
                    ? context.tr('sign_up')
                    : context.tr('log_in'),
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
          child: Text(context.tr('or_continue_with'),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400))),
      Expanded(child: Divider(color: Colors.grey.shade300))
    ]);
  }

  Widget _buildGuestModeButton({
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('guest_login_button'),
        onPressed: isLoading ? null : onTap,
        icon: const Icon(
          Icons.explore_outlined,
          size: 18,
          color: Color(0xFF1E1E1E),
        ),
        label: const Text(
          'Bỏ qua / Trải nghiệm ngay (Guest Mode)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E1E1E),
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          side: BorderSide(color: Colors.grey.shade300, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }
}

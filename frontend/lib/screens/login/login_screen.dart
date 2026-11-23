import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../config/app_theme.dart';
import '../../config/app_translations.dart';
import '../../config/routes.dart';
import '../../features/profile/domain/entities/profile_entity.dart';
import '../../features/profile/domain/entities/profile_snapshot.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/app_logo.dart';
import 'login_controller.dart';
import 'widgets/forgot_password_sheet.dart';
import 'widgets/login_form.dart';
import 'widgets/social_login_row.dart';

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
    final palette = SamanPalette.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: palette.textPrimary),
        ),
        backgroundColor: palette.surfaceElevated,
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
    final palette = SamanPalette.of(context);

    // Lắng nghe State từ Controller
    ref.listen<LoginState>(loginControllerProvider, (previous, next) {
      if (next.errorMessage != null) {
        _showAuthSnackBar(next.errorMessage!);
        try {
          Fluttertoast.showToast(
            msg: next.errorMessage!,
            backgroundColor: palette.surfaceElevated,
            textColor: palette.textPrimary,
          );
        } catch (_) {}
      }
      final outcome = next.outcome;
      if (outcome == null) return;
      if (next.successMessage != null) {
        try {
          Fluttertoast.showToast(
            msg: next.successMessage!,
            backgroundColor: palette.surfaceElevated,
            textColor: palette.textPrimary,
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

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              children: [
                _LoginHeader(
                  isLoginMode: _isLoginMode,
                  palette: palette,
                ),
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
                      phone: phone,
                    );
                  },
                  onForgotPassword: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const ForgotPasswordSheet(),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                _SwitchModeButton(
                  isLoginMode: _isLoginMode,
                  palette: palette,
                  onTap: () => setState(() => _isLoginMode = !_isLoginMode),
                ),
                const SizedBox(height: 30),
                _SocialDivider(palette: palette),
                const SizedBox(height: AppSpacing.xl),
                SocialLoginRow(
                  isLoading: loginState.isLoading,
                  onGoogleTap: () =>
                      _handleSocialLogin(controller.signInWithGoogle),
                  onAppleTap: () =>
                      _handleSocialLogin(controller.signInWithApple),
                  onFacebookTap: () =>
                      _handleSocialLogin(controller.signInWithFacebook),
                ),
                const SizedBox(height: AppSpacing.lg),
                _GuestModeButton(
                  isLoading: loginState.isLoading,
                  palette: palette,
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
}

class _LoginHeader extends StatelessWidget {
  final bool isLoginMode;
  final SamanPalette palette;

  const _LoginHeader({
    required this.isLoginMode,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppLogo(size: 90, color: palette.textPrimary)
            .animate()
            .scale(duration: 600.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 20),
        Text(
          'SAMAN',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: palette.textPrimary,
            letterSpacing: 3.0,
          ),
        ).animate().fadeIn().slideY(begin: 0.2, end: 0),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.tr('login_tagline'),
          style: TextStyle(
            fontSize: 14,
            color: palette.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          isLoginMode
              ? context.tr('welcome_back')
              : context.tr('create_account'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SwitchModeButton extends StatelessWidget {
  final bool isLoginMode;
  final SamanPalette palette;
  final VoidCallback onTap;

  const _SwitchModeButton({
    required this.isLoginMode,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RichText(
        text: TextSpan(
          text: isLoginMode
              ? context.tr('dont_have_account')
              : context.tr('already_have_account'),
          style: TextStyle(color: palette.textSecondary, fontSize: 14),
          children: [
            TextSpan(
              text: isLoginMode
                  ? context.tr('sign_up')
                  : context.tr('log_in'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialDivider extends StatelessWidget {
  final SamanPalette palette;

  const _SocialDivider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: palette.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            context.tr('or_continue_with'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.textMuted,
            ),
          ),
        ),
        Expanded(child: Divider(color: palette.border)),
      ],
    );
  }
}

class _GuestModeButton extends StatelessWidget {
  final bool isLoading;
  final SamanPalette palette;
  final VoidCallback onTap;

  const _GuestModeButton({
    required this.isLoading,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: const Key('guest_login_button'),
      onPressed: isLoading ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: palette.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 10,
        ),
      ),
      child: Text(
        'Dùng thử không cần tài khoản',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

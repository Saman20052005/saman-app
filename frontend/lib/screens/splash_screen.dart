import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/app_logo.dart';
import '../utils/auth_helper.dart';
// ✅ MỚI: Import Routes config
import '../config/routes.dart';

// ❌ BỎ: Không cần import trực tiếp màn hình nữa
// import 'login/login_screen.dart';
// import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.enableAnimations = true});

  final bool enableAnimations;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _authTimer;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() {
    // Keep the splash duration while allowing disposal to cancel the redirect.
    _authTimer = Timer(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;

      final isLoggedIn = await AuthHelper.isLoggedIn();

      if (!mounted) return;
      if (isLoggedIn) {
        Navigator.pushReplacementNamed(context, AppRoutes.main);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    });
  }

  @override
  void dispose() {
    _authTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1E1E1E);
    final logo = widget.enableAnimations
        ? const AppLogo(size: 130)
            .animate()
            .fade(duration: 600.ms)
            .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.0, 1.0),
                duration: 1000.ms,
                curve: Curves.elasticOut)
            .then()
            .shimmer(duration: 1500.ms, color: Colors.grey.shade300, angle: 45)
        : const AppLogo(size: 130);
    final title = widget.enableAnimations
        ? const Text(
            'SAMAN',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: primaryColor,
              letterSpacing: 4.0,
            ),
          ).animate().fadeIn(delay: 500.ms, duration: 600.ms).slideY(
            begin: 0.3, end: 0, duration: 600.ms, curve: Curves.easeOutBack)
        : const Text(
            'SAMAN',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: primaryColor,
              letterSpacing: 4.0,
            ),
          );
    final slogan = Text(
      'Solid Body. Balanced Mind.',
      style: TextStyle(
        fontSize: 15,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
    final animatedSlogan = widget.enableAnimations
        ? slogan.animate().fadeIn(delay: 800.ms, duration: 600.ms)
        : slogan;
    final loading = SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        valueColor:
            AlwaysStoppedAnimation<Color>(primaryColor.withOpacity(0.8)),
      ),
    );
    final animatedLoading = widget.enableAnimations
        ? loading.animate().fadeIn(delay: 1200.ms, duration: 400.ms)
        : loading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- 1. LOGO ĐỘNG ---
            logo,

            const SizedBox(height: 30),

            // --- 2. TÊN & SLOGAN ---
            Column(
              children: [
                title,
                const SizedBox(height: 12),
                animatedSlogan,
              ],
            ),

            const SizedBox(height: 100),

            // --- 3. LOADING ---
            animatedLoading,
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';

class SocialLoginRow extends StatelessWidget {
  final VoidCallback onGoogleTap;
  final VoidCallback onAppleTap;
  final VoidCallback onFacebookTap;
  final bool isLoading;

  const SocialLoginRow({
    super.key,
    required this.onGoogleTap,
    required this.onAppleTap,
    required this.onFacebookTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final showApple = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialButton(
          key: const ValueKey('google_login_button'),
          icon: Icons.g_mobiledata,
          isLoading: isLoading,
          onTap: onGoogleTap,
        ),
        if (showApple) ...[
          const SizedBox(width: 16),
          _SocialButton(
            key: const ValueKey('apple_login_button'),
            icon: Icons.apple,
            isLoading: isLoading,
            onTap: onAppleTap,
          ),
        ],
        const SizedBox(width: 16),
        _SocialButton(
          key: const ValueKey('facebook_login_button'),
          icon: Icons.facebook,
          isLoading: isLoading,
          onTap: onFacebookTap,
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;

  const _SocialButton({
    super.key,
    required this.icon,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final borderRadius = BorderRadius.circular(AppRadius.lg);

    return Material(
      color: palette.surface,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: borderRadius,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: palette.border),
            boxShadow: [context.softShadow],
          ),
          child: Icon(icon, size: 30, color: palette.textPrimary),
        ),
      ),
    );
  }
}

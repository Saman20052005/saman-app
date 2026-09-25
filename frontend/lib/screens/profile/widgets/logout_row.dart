import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Quiet, understated destructive text action row for logging out.
///
/// Features:
/// - Placed below grouped account settings
/// - Restrained muted-red treatment (never a large primary button)
/// - Clean exit icon with accessible touch target
class LogoutRow extends StatelessWidget {
  const LogoutRow({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  static const Color _mutedRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
          splashColor: _mutedRed.withOpacity(0.08),
          highlightColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: SamanHomeTokens.spacingSm,
              vertical: 12,
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: _mutedRed,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Log out',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _mutedRed,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

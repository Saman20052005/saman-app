import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Quiet, understated destructive text action row for logging out.
///
/// Features:
/// - Placed below grouped account settings
/// - Restrained muted-red treatment
/// - Clean exit icon with accessible 48x48 touch target
///
/// Hardened behavior:
/// - Customizable label for localization.
/// - Ensures minimum 48x48 touch target.
/// - Creates no fake button/InkWell when [onTap] is null.
class LogoutRow extends StatelessWidget {
  const LogoutRow({
    super.key,
    this.onTap,
    this.label = 'Log out',
  });

  final VoidCallback? onTap;
  final String label;

  static const Color _mutedRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final isActionable = onTap != null;

    Widget content = Container(
      constraints: const BoxConstraints(
        minHeight: 48,
        minWidth: 48,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingSm,
        vertical: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.logout_rounded,
            size: 18,
            color: isActionable ? _mutedRed : SamanHomeTokens.textMuted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActionable ? _mutedRed : SamanHomeTokens.textMuted,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: isActionable
          ? Semantics(
              button: true,
              enabled: true,
              label: label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
                  splashColor: _mutedRed.withOpacity(0.08),
                  highlightColor: Colors.transparent,
                  child: content,
                ),
              ),
            )
          : Semantics(
              button: false,
              enabled: false,
              label: label,
              child: content,
            ),
    );
  }
}

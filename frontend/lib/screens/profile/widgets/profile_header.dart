import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Clean, authoritative top header for the Profile screen.
///
/// Displays:
/// - Title: customizable, default "Profile"
/// - Subtitle: customizable, default "Your health, progress & account"
/// - Compact square Settings button on the right (min 48x48 hit target)
///
/// Hardened behavior:
/// - Supports full localization of strings.
/// - Minimum 48x48 logical pixel touch target for settings button.
/// - Button semantics applied only when [onSettingsTap] is actionable.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    this.title = 'Profile',
    this.subtitle = 'Your health, progress & account',
    this.onSettingsTap,
    this.settingsLabel = 'Settings',
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSettingsTap;
  final String settingsLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
        vertical: SamanHomeTokens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SamanHomeTokens.screenTitle,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SamanHomeTokens.headerSubtitle,
                  ),
                ],
              ],
            ),
          ),
          if (onSettingsTap != null) ...[
            const SizedBox(width: SamanHomeTokens.spacingSm),
            _SettingsSquareButton(
              onTap: onSettingsTap,
              settingsLabel: settingsLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsSquareButton extends StatelessWidget {
  const _SettingsSquareButton({
    this.onTap,
    required this.settingsLabel,
  });

  final VoidCallback? onTap;
  final String settingsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: settingsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: SamanHomeTokens.cardSurfaceElevated,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
                  border: Border.all(
                    color: SamanHomeTokens.border,
                    width: 1,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.settings_outlined,
                    size: 19,
                    color: SamanHomeTokens.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

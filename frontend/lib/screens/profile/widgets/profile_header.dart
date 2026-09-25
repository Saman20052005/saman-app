import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Clean, authoritative top header for the Profile screen.
///
/// Displays:
/// - Title: "Profile"
/// - Subtitle: "Your health, progress & account"
/// - Compact square Settings button on the right
///
/// Excludes:
/// - Back arrow (Profile is a root navigation tab)
/// - Theme toggles or redundant monograms
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    this.title = 'Profile',
    this.subtitle = 'Your health, progress & account',
    this.onSettingsTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onSettingsTap;

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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SamanHomeTokens.headerSubtitle,
                ),
              ],
            ),
          ),
          const SizedBox(width: SamanHomeTokens.spacingSm),
          _SettingsSquareButton(onTap: onSettingsTap),
        ],
      ),
    );
  }
}

class _SettingsSquareButton extends StatelessWidget {
  const _SettingsSquareButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
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
    );
  }
}

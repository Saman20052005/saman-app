import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Personal identity card for the athlete.
///
/// Features:
/// - 52x52 circular avatar container with athlete initials fallback
/// - Athlete full name with safe overflow truncation
/// - Athlete email with safe overflow truncation
/// - "FREE PLAN" badge + "Member since 2026"
/// - Compact circular edit profile action button
///
/// Excludes:
/// - Social network metrics (followers, posts, likes)
/// - Misplaced health metrics (BMI is housed in Health & Goals)
class PersonalIdentityCard extends StatelessWidget {
  const PersonalIdentityCard({
    super.key,
    required this.userName,
    required this.userEmail,
    this.planLabel,
    this.memberSince,
    this.onEditProfileTap,
  });

  final String userName;
  final String userEmail;
  final String? planLabel;
  final String? memberSince;
  final VoidCallback? onEditProfileTap;

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'SA';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(userName);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
      decoration: BoxDecoration(
        color: SamanHomeTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(
          color: SamanHomeTokens.border,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular Avatar (52x52)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SamanHomeTokens.iconContainerBg,
              border: Border.all(
                color: SamanHomeTokens.borderHigh,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: SamanHomeTokens.spacingMd),

          // User details (Name, Email, Plan & Member Since)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userName.isNotEmpty ? userName : 'Athlete',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.textWhite,
                    letterSpacing: -0.3,
                  ),
                ),
                if (userEmail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    userEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: SamanHomeTokens.textSecondary,
                    ),
                  ),
                ],
                if ((planLabel != null && planLabel!.isNotEmpty) ||
                    (memberSince != null && memberSince!.isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (planLabel != null && planLabel!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: SamanHomeTokens.actionButtonSurface,
                            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXs),
                            border: Border.all(
                              color: SamanHomeTokens.borderSubtle,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            planLabel!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: SamanHomeTokens.textSecondary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      if (memberSince != null && memberSince!.isNotEmpty)
                        Text(
                          memberSince!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: SamanHomeTokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: SamanHomeTokens.spacingSm),

          // Edit Profile Action Button (touch target >= 48x48)
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('edit_profile_cta_button'),
              onTap: onEditProfileTap,
              borderRadius: BorderRadius.circular(24),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SamanHomeTokens.actionButtonSurface,
                        border: Border.fromBorderSide(
                          BorderSide(
                            color: SamanHomeTokens.border,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: SamanHomeTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

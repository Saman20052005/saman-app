import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Personal identity card for the athlete.
///
/// Features:
/// - 52x52 circular avatar container with athlete initials fallback
/// - Athlete full name with safe overflow truncation
/// - Athlete email with safe overflow truncation
/// - Optional plan badge & optional memberSince info (rendered only when provided)
/// - Optional 48x48 interactive edit profile action button
///
/// Hardened behavior:
/// - No default plan or memberSince values.
/// - Handles null/empty name, email, plan, memberSince, and callback gracefully.
/// - Unicode-safe initials supporting Vietnamese and multi-word names.
/// - Minimum 48x48 hit target and button semantics when edit button is present.
class PersonalIdentityCard extends StatelessWidget {
  const PersonalIdentityCard({
    super.key,
    required this.userName,
    required this.userEmail,
    this.planLabel,
    this.memberSince,
    this.onEditProfileTap,
    this.editProfileLabel = 'Edit profile',
    this.defaultNameLabel = 'Athlete',
    this.fallbackInitials = 'SA',
  });

  final String userName;
  final String userEmail;
  final String? planLabel;
  final String? memberSince;
  final VoidCallback? onEditProfileTap;

  final String editProfileLabel;
  final String defaultNameLabel;
  final String fallbackInitials;

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      final defaultClean = defaultNameLabel.trim();
      return defaultClean.isNotEmpty ? _getInitials(defaultClean) : fallbackInitials;
    }

    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fallbackInitials;

    if (parts.length == 1) {
      final chars = parts[0].characters;
      return chars.take(2).toString().toUpperCase();
    }

    final firstChar = parts.first.characters.first;
    final lastChar = parts.last.characters.first;
    return '$firstChar$lastChar'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(userName);
    final displayName = userName.trim().isNotEmpty ? userName.trim() : defaultNameLabel;
    final displayEmail = userEmail.trim();

    final hasPlan = planLabel != null && planLabel!.trim().isNotEmpty;
    final hasMemberSince = memberSince != null && memberSince!.trim().isNotEmpty;
    final hasMembershipRow = hasPlan || hasMemberSince;

    final isEditable = onEditProfileTap != null;

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
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.textWhite,
                    letterSpacing: -0.3,
                  ),
                ),
                if (displayEmail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    displayEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: SamanHomeTokens.textSecondary,
                    ),
                  ),
                ],
                if (hasMembershipRow) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasPlan)
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
                            planLabel!.trim().toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: SamanHomeTokens.textSecondary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      if (hasMemberSince)
                        Text(
                          memberSince!.trim(),
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

          if (isEditable) ...[
            const SizedBox(width: SamanHomeTokens.spacingSm),
            // Edit Profile Action Button (min 48x48 hit target)
            Semantics(
              button: true,
              enabled: true,
              label: editProfileLabel,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onEditProfileTap,
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SamanHomeTokens.actionButtonSurface,
                          border: Border.all(
                            color: SamanHomeTokens.border,
                            width: 1,
                          ),
                        ),
                        child: const Center(
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
        ],
      ),
    );
  }
}

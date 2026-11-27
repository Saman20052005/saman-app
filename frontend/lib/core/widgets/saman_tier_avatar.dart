import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/membership/domain/models/membership_plan.dart';
import '../../features/membership/presentation/providers/membership_providers.dart';
import '../../widgets/saman_avatar.dart';

/// Placement of the tier pill badge relative to the avatar ring.
enum SamanTierBadgePosition {
  bottomCenter,
  topCenter,
  none,
}

/// Visual specification for each [MembershipTier].
class _TierVisualSpec {
  const _TierVisualSpec({
    required this.label,
    required this.ringGradient,
    required this.ringWidth,
    required this.pillBackground,
    required this.pillTextColor,
    required this.pillBorderColor,
  });

  final String label;
  final Gradient ringGradient;
  final double ringWidth;
  final Color pillBackground;
  final Color pillTextColor;
  final Color pillBorderColor;

  static _TierVisualSpec of(MembershipTier tier, {required bool isDark}) {
    switch (tier) {
      case MembershipTier.ultra:
        return const _TierVisualSpec(
          label: 'ULTRA',
          ringGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF9333EA), // Royal Purple
              Color(0xFFD946EF), // Magenta Orchid
              Color(0xFFF59E0B), // Warm Gold
              Color(0xFFFDE68A), // Platinum Gold
            ],
          ),
          ringWidth: 2.5,
          pillBackground: Color(0xFF2E1065),
          pillTextColor: Color(0xFFFDE68A),
          pillBorderColor: Color(0xFFF59E0B),
        );
      case MembershipTier.pro:
        return const _TierVisualSpec(
          label: 'PRO',
          ringGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF38BDF8), // Sky Blue
              Color(0xFF3B82F6), // Royal Blue
              Color(0xFF6366F1), // Indigo
            ],
          ),
          ringWidth: 2.2,
          pillBackground: Color(0xFF1E3A8A),
          pillTextColor: Colors.white,
          pillBorderColor: Color(0xFF60A5FA),
        );
      case MembershipTier.plus:
        return const _TierVisualSpec(
          label: 'PLUS',
          ringGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF10B981), // Emerald
              Color(0xFF14B8A6), // Teal
            ],
          ),
          ringWidth: 2.0,
          pillBackground: Color(0xFF064E3B),
          pillTextColor: Colors.white,
          pillBorderColor: Color(0xFF34D399),
        );
      case MembershipTier.free:
        return _TierVisualSpec(
          label: 'FREE',
          ringGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF475569), Color(0xFF64748B)]
                : const [Color(0xFFCBD5E1), Color(0xFF94A3B8)],
          ),
          ringWidth: 1.4,
          pillBackground:
              isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          pillTextColor:
              isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          pillBorderColor:
              isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
        );
    }
  }
}

/// Reusable tier-aware avatar wrapper (Gemini/ChatGPT style).
///
/// Reads [currentMembershipTierProvider] dynamically unless [tier] is explicitly
/// provided. Renders a tier-styled gradient ring and a compact plan pill badge
/// (`FREE`, `PLUS`, `PRO`, `ULTRA`) anchored cleanly to the avatar edge without
/// causing overflow on small avatars or overlapping corner action icons.
class SamanTierAvatar extends ConsumerWidget {
  const SamanTierAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 52.0,
    this.tier,
    this.badgePosition = SamanTierBadgePosition.bottomCenter,
    this.child,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final MembershipTier? tier;
  final SamanTierBadgePosition badgePosition;
  final Widget? child;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MembershipTier resolvedTier =
        tier ?? ref.watch(currentMembershipTierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spec = _TierVisualSpec.of(resolvedTier, isDark: isDark);

    final isCompact = size < 42.0;
    final ringPadding = spec.ringWidth + (isCompact ? 1.0 : 1.5);
    final outerSize = size + ringPadding * 2;
    final badgeFontSize = isCompact ? 7.5 : 8.5;
    final badgeHorizontalPad = isCompact ? 5.0 : 6.0;
    final badgeVerticalPad = isCompact ? 1.5 : 2.0;
    final badgeOffset = isCompact ? -5.0 : -6.0;

    final avatarContent = child ??
        SamanAvatar(
          name: name,
          avatarUrl: avatarUrl,
          size: size,
          borderWidth: 0,
          borderColor: Colors.transparent,
          backgroundColor: backgroundColor,
          textColor: textColor,
          fontSize: fontSize,
        );

    final badgeWidget = badgePosition == SamanTierBadgePosition.none
        ? null
        : Container(
            key: ValueKey('saman_tier_badge_${resolvedTier.name}'),
            padding: EdgeInsets.symmetric(
              horizontal: badgeHorizontalPad,
              vertical: badgeVerticalPad,
            ),
            decoration: BoxDecoration(
              color: spec.pillBackground,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: spec.pillBorderColor,
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.45 : 0.14),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              spec.label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: badgeFontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                height: 1.0,
                color: spec.pillTextColor,
              ),
            ),
          );

    final extraBottomPad =
        badgePosition == SamanTierBadgePosition.bottomCenter ? 6.0 : 0.0;
    final extraTopPad =
        badgePosition == SamanTierBadgePosition.topCenter ? 6.0 : 0.0;

    return Padding(
      padding: EdgeInsets.only(top: extraTopPad, bottom: extraBottomPad),
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: outerSize,
              height: outerSize,
              padding: EdgeInsets.all(spec.ringWidth),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: spec.ringGradient,
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                padding: EdgeInsets.all(isCompact ? 1.0 : 1.5),
                child: ClipOval(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: avatarContent,
                  ),
                ),
              ),
            ),
            if (badgeWidget != null &&
                badgePosition == SamanTierBadgePosition.bottomCenter)
              Positioned(
                bottom: badgeOffset,
                child: badgeWidget,
              ),
            if (badgeWidget != null &&
                badgePosition == SamanTierBadgePosition.topCenter)
              Positioned(
                top: badgeOffset,
                child: badgeWidget,
              ),
          ],
        ),
      ),
    );
  }
}

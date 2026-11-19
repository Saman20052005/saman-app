import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../../../features/membership/data/models/account_membership_dto.dart';
import '../../../../features/membership/domain/models/membership_plan.dart';
import '../../../../features/membership/presentation/providers/membership_providers.dart';
import '../../../../features/membership/presentation/screens/manage_membership_screen.dart';
import '../../../../features/membership/presentation/screens/membership_overview_screen.dart';
import '../../../../widgets/app_logo.dart';

class MembershipBannerCard extends ConsumerWidget {
  final VoidCallback? onTap;
  final AccountMembershipState? membershipState;
  final bool hasUpdate;
  final String? updateMessage;

  const MembershipBannerCard({
    super.key,
    this.onTap,
    this.membershipState,
    this.hasUpdate = false,
    this.updateMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final AccountMembershipState accountState =
        membershipState ?? ref.watch(accountMembershipProvider);

    // 1. Paid active plan
    final hasActivePaidPlan = accountState.hasValidData &&
        accountState.isKnown &&
        accountState.tier != MembershipTier.free &&
        accountState.isActiveSubscription;

    // 2. Confirmed free user who can upgrade
    final isConfirmedFreeCanUpgrade = accountState.hasValidData &&
        accountState.isKnown &&
        accountState.tier == MembershipTier.free;

    // Content strings
    final titleText = context.tr('membership_banner_title');

    final String badgeText;
    final String descriptionText;
    final String ctaText;

    if (hasActivePaidPlan) {
      badgeText = accountState.tier.displayName.toUpperCase();
      final activeTemplate = context.tr('membership_card_desc_active');
      descriptionText = activeTemplate.contains('{plan}')
          ? activeTemplate.replaceAll('{plan}', accountState.tier.displayName)
          : '${context.tr('your_active_plan')}: ${accountState.tier.displayName}';
      ctaText = context.tr('membership_card_cta_your_plan');
    } else if (isConfirmedFreeCanUpgrade) {
      badgeText = context.tr('membership_card_badge_preview');
      descriptionText = context.tr('membership_card_desc_preview');
      ctaText = context.tr('membership_card_cta_upgrade');
    } else {
      // Preview / Loading / Unknown / Logged out fallback
      badgeText = context.tr('membership_card_badge_preview');
      descriptionText = context.tr('membership_card_desc_preview');
      ctaText = context.tr('membership_card_cta_explore');
    }

    final updateBadgeText = context.tr('membership_card_badge_updated');

    void handleTap() {
      if (onTap != null) {
        onTap!();
        return;
      }
      if (hasActivePaidPlan) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ManageMembershipScreen(),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            settings:
                const RouteSettings(name: MembershipOverviewScreen.routeName),
            builder: (_) => const MembershipOverviewScreen(),
          ),
        );
      }
    }

    // Colors: Signature dark palette (#18181B)
    // ProfileScreen in Saman App is styled under Dark Calm Athleticism (dark background 0xFF0C0D0E).
    const cardBg = Color(0xFF18181B);
    const cardBorder = Color(0xFF26282F);
    const logoBoxBg = Color(0xFF242427);
    const logoColor = Color(0xFFF4F0E8);
    const champagneAccent = Color(0xFFC9AA78);
    final logoBorderColor = champagneAccent.withOpacity(0.35);

    const titleColor = Color(0xFFF3F4F6);
    const descColor = Color(0xFF9CA3AF);
    const previewBadgeBg = Color(0xFF242427);
    const previewBadgeBorder = Color(0xFF383A42);
    const previewBadgeText = Color(0xFF94979E);

    final semanticLabel =
        '$titleText, $badgeText, $descriptionText. $ctaText';

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('profile_membership_banner_card'),
          onTap: handleTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: isDark
              ? Colors.white.withOpacity(0.04)
              : Colors.black.withOpacity(0.03),
          focusColor: champagneAccent.withOpacity(0.12),
          highlightColor: champagneAccent.withOpacity(0.08),
          splashColor: champagneAccent.withOpacity(0.12),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cardBorder,
                width: 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Graphite logo box with champagne border & ivory S mark
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: logoBoxBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: logoBorderColor,
                      width: 1.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AppLogo(
                    size: 24,
                    color: logoColor,
                    isLightMode: !isDark,
                  ),
                ),
                const SizedBox(width: 14),
                // Content section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title row with Wrap to prevent overflow on narrow screens
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            titleText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: previewBadgeBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: previewBadgeBorder,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: previewBadgeText,
                              ),
                            ),
                          ),
                          if (hasUpdate)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: champagneAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: champagneAccent.withOpacity(0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                updateBadgeText,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: champagneAccent,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Description
                      Text(
                        (hasUpdate &&
                                updateMessage != null &&
                                updateMessage!.isNotEmpty)
                            ? updateMessage!
                            : descriptionText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                          color: descColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Bottom CTA text label with chevron
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              ctaText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: champagneAccent,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: champagneAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

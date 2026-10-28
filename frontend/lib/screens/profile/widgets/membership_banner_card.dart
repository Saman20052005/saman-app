import 'package:flutter/material.dart';
import 'package:health_ai_app/features/membership/presentation/tokens/membership_tokens.dart';

class MembershipBannerCard extends StatelessWidget {
  final VoidCallback? onTap;

  const MembershipBannerCard({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Saman Membership Preview',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('profile_membership_banner_card'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16171B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF26282F),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0x1A10B981),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0x3310B981),
                      width: 1.0,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: MembershipTokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Saman Membership',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MembershipTokens.headline(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: MembershipTokens.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: MembershipTokens.surfaceHigh,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: MembershipTokens.border,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              'PREVIEW',
                              style: MembershipTokens.mono(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: MembershipTokens.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Explore planned tiers: Plus, Pro & Ultra.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFF71717A),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/membership_app_bar.dart';
import 'membership_overview_screen.dart';

class MembershipComingSoonScreen extends ConsumerWidget {
  final MembershipTier tier;
  final VoidCallback? onBack;
  final VoidCallback? onBackToMembership;

  const MembershipComingSoonScreen({
    super.key,
    required this.tier,
    this.onBack,
    this.onBackToMembership,
  });

  String _getExploringDescription(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.plus:
        return 'Planned Gemini food photo analysis with a monthly AI allowance.';
      case MembershipTier.pro:
        return 'Planned Workout CV, movement analysis, and rep counting, alongside Nutrition AI.';
      case MembershipTier.ultra:
        return 'Planned Advanced Thinking, extended history and personalized memory, with 5x Pro AI allowance.';
      case MembershipTier.free:
        return 'Everyday tracking essentials.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billingPeriod = ref.watch(billingPeriodProvider);
    final plan = ref.watch(membershipPlanProvider(tier));

    return Scaffold(
      backgroundColor: MembershipTokens.canvas,
      appBar: MembershipAppBar(
        title: context.tr('membership_banner_title'),
        onBack: onBack,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: MembershipTokens.screenGutter,
            vertical: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Availability Status & Hero
              _buildHeroSection(context),
              const SizedBox(height: 24),

              // 2. You're Exploring Card
              _buildExploringCard(context, plan, billingPeriod),
              const SizedBox(height: 16),

              // 3. Account Reassurance Card
              _buildReassuranceCard(context),
              const SizedBox(height: 28),

              // 4. Primary Navigation Action
              _buildPrimaryAction(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MembershipTokens.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: MembershipTokens.border,
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.schedule,
                size: 22,
                color: MembershipTokens.textMuted,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: MembershipTokens.surfaceHigh,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: MembershipTokens.border,
                  width: 1.0,
                ),
              ),
              child: Text(
                context.tr('coming_soon_badge'),
                style: MembershipTokens.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: MembershipTokens.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('coming_soon_hero_title'),
          style: MembershipTokens.headline(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: MembershipTokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('coming_soon_hero_desc'),
          style: MembershipTokens.body(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: MembershipTokens.textMuted,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildExploringCard(
      BuildContext context, MembershipPlan plan, BillingPeriod period) {
    final priceText = plan.priceDisplay(period);
    final unitText = plan.unitDisplay(period);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            context.tr('youre_exploring'),
            style: MembershipTokens.mono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    plan.name,
                    style: MembershipTokens.headline(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: MembershipTokens.textPrimary,
                    ),
                  ),
                  Text(
                    plan.subtitle.toUpperCase(),
                    style: MembershipTokens.mono(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _getExploringDescription(plan.tier),
                style: MembershipTokens.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textPrimary.withOpacity(0.9),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(
                color: MembershipTokens.border,
                height: 1,
                thickness: 1,
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        priceText,
                        style: MembershipTokens.mono(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: plan.isRecommended
                              ? MembershipTokens.accent
                              : MembershipTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unitText,
                        style: MembershipTokens.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: MembershipTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (period.isYearly)
                    Text(
                      plan.yearlyEquivalentText,
                      style: MembershipTokens.body(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: plan.isRecommended
                            ? MembershipTokens.accent.withOpacity(0.9)
                            : MembershipTokens.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('demo_pricing_disclaimer'),
                style: MembershipTokens.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReassuranceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: MembershipTokens.card,
        borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
        border: Border.all(
          color: MembershipTokens.border,
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: MembershipTokens.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MembershipTokens.border,
                width: 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.info_outline,
              size: 18,
              color: MembershipTokens.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('account_stays_free_title'),
                  style: MembershipTokens.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr('account_stays_free_desc'),
                  style: MembershipTokens.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: MembershipTokens.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MembershipTokens.primaryCtaMinHeight,
          child: ElevatedButton(
            onPressed: () {
              if (onBackToMembership != null) {
                onBackToMembership!();
              } else {
                safePopOrNavigateToMembership(context);
              }
            },
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: MembershipTokens.primaryCtaBg,
              foregroundColor: MembershipTokens.primaryCtaText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  MembershipTokens.buttonRadius,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return MembershipTokens.primaryCtaPressed;
                }
                return null;
              }),
            ),
            child: Text(
              context.tr('back_to_membership'),
              style: MembershipTokens.body(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: MembershipTokens.primaryCtaText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            context.tr('coming_soon_footer_note'),
            style: MembershipTokens.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/billing_period_selector.dart';
import '../widgets/membership_app_bar.dart';
import '../widgets/primary_membership_button.dart';
import 'compare_plans_screen.dart';
import 'plan_detail_screen.dart';

/// Pops intermediate membership screens back to [MembershipOverviewScreen] if present
/// in the stack, or pops intermediate membership screens and pushes a new instance
/// on top of the origin screen, preserving the caller/feature route.
void safePopOrNavigateToMembership(BuildContext context) {
  final navigator = Navigator.of(context);
  bool hasOverview = false;

  navigator.popUntil((route) {
    if (route.settings.name == MembershipOverviewScreen.routeName) {
      hasOverview = true;
      return true;
    }
    // Stop popping if we encounter the origin screen (not a membership sub-route)
    if (!_isMembershipSubRoute(route)) {
      return true;
    }
    return false;
  });

  if (!hasOverview) {
    navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: MembershipOverviewScreen.routeName),
        builder: (_) => const MembershipOverviewScreen(),
      ),
    );
  }
}

bool _isMembershipSubRoute(Route<dynamic> route) {
  if (route.isFirst) return false;
  final name = route.settings.name;
  if (name == null) return false;
  return name.startsWith('/membership/') &&
      name != MembershipOverviewScreen.routeName;
}

class MembershipOverviewScreen extends ConsumerWidget {
  static const String routeName = '/membership/overview';

  final VoidCallback? onBack;
  final VoidCallback? onComparePlans;
  final void Function(MembershipTier tier)? onExplorePlan;

  const MembershipOverviewScreen({
    super.key,
    this.onBack,
    this.onComparePlans,
    this.onExplorePlan,
  });

  void _navigateToDetail(BuildContext context, MembershipTier tier) {
    if (onExplorePlan != null) {
      onExplorePlan!(tier);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: RouteSettings(name: '/membership/detail/${tier.name}'),
          builder: (_) => PlanDetailScreen(
            tier: tier,
            onBackToMembership: () => safePopOrNavigateToMembership(context),
          ),
        ),
      );
    }
  }

  void _navigateToCompare(BuildContext context) {
    if (onComparePlans != null) {
      onComparePlans!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/membership/compare'),
          builder: (_) => ComparePlansScreen(
            onBackToMembership: () => safePopOrNavigateToMembership(context),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billingPeriod = ref.watch(billingPeriodProvider);
    final plans = ref.watch(membershipCatalogProvider);

    final freePlan = plans.firstWhere((p) => p.tier == MembershipTier.free);
    final plusPlan = plans.firstWhere((p) => p.tier == MembershipTier.plus);
    final proPlan = plans.firstWhere((p) => p.tier == MembershipTier.pro);
    final ultraPlan = plans.firstWhere((p) => p.tier == MembershipTier.ultra);

    return Scaffold(
      backgroundColor: MembershipTokens.canvas,
      appBar: MembershipAppBar(
        title: 'Membership',
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
              // 1. Introduction Header
              _buildIntroSection(),
              const SizedBox(height: 16),

              // 2. Account Current Status Card
              _buildCurrentAccountCard(),
              const SizedBox(height: 20),

              // 3. Billing Selector
              const BillingPeriodSelector(
                isInsideCard: false,
                showDisclaimer: true,
              ),
              const SizedBox(height: 20),

              // 4. Plan Cards (Free, Plus, Pro, Ultra)
              _buildFreePlanCard(freePlan),
              const SizedBox(height: 16),

              _buildPaidPlanCard(
                context: context,
                plan: plusPlan,
                period: billingPeriod,
              ),
              const SizedBox(height: 16),

              _buildPaidPlanCard(
                context: context,
                plan: proPlan,
                period: billingPeriod,
                isRecommended: true,
              ),
              const SizedBox(height: 16),

              _buildPaidPlanCard(
                context: context,
                plan: ultraPlan,
                period: billingPeriod,
              ),
              const SizedBox(height: 24),

              // 5. Compare All Plans Banner / CTA
              _buildCompareCtaSection(context),
              const SizedBox(height: 24),

              // 6. Quiet Footer Disclaimers
              _buildFooter(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          child: Text(
            'MEMBERSHIP PREVIEW',
            style: MembershipTokens.mono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Elevate your training.',
          style: MembershipTokens.headline(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: MembershipTokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Explore planned tiers designed for nutrition intelligence and workout computer vision.',
          style: MembershipTokens.body(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: MembershipTokens.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentAccountCard() {
    return Container(
      padding: const EdgeInsets.all(14.0),
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0x1A10B981),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0x3310B981),
                width: 1.0,
              ),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: MembershipTokens.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'CURRENT PLAN: FREE',
                        overflow: TextOverflow.ellipsis,
                        style: MembershipTokens.mono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MembershipTokens.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '\$0',
                      style: MembershipTokens.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MembershipTokens.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your account stays on Free with core tracking. Paid plans are Coming Soon.',
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

  Widget _buildFreePlanCard(MembershipPlan plan) {
    return Container(
      padding: const EdgeInsets.all(18.0),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: MembershipTokens.headline(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: MembershipTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.subtitle,
                      style: MembershipTokens.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: MembershipTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MembershipTokens.surfaceHigh,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: MembershipTokens.border,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  'CURRENT',
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
          const SizedBox(height: 14),

          // Price Tag
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '\$0',
                style: MembershipTokens.mono(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: MembershipTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Free forever',
                style: MembershipTokens.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan.heroDescription,
            style: MembershipTokens.body(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: MembershipTokens.border, height: 1),
          const SizedBox(height: 14),

          // Free Key Inclusions
          _buildBenefitRow(
            icon: Icons.check,
            iconColor: MembershipTokens.textPrimary,
            text: 'Nutrition logging',
          ),
          const SizedBox(height: 8),
          _buildBenefitRow(
            icon: Icons.check,
            iconColor: MembershipTokens.textPrimary,
            text: 'Manual workout tracking',
          ),
          const SizedBox(height: 8),
          _buildBenefitRow(
            icon: Icons.check,
            iconColor: MembershipTokens.textPrimary,
            text: 'Free food photo analysis',
          ),
          const SizedBox(height: 8),
          _buildBenefitRow(
            icon: Icons.check,
            iconColor: MembershipTokens.textPrimary,
            text: 'Basic health metrics',
          ),
          const SizedBox(height: 16),

          // Disabled/Calm Active Plan Indicator
          Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: MembershipTokens.surfaceHigh,
              borderRadius:
                  BorderRadius.circular(MembershipTokens.buttonRadius),
              border: Border.all(
                color: MembershipTokens.border,
                width: 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check,
                  size: 16,
                  color: MembershipTokens.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Your Active Plan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MembershipTokens.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaidPlanCard({
    required BuildContext context,
    required MembershipPlan plan,
    required BillingPeriod period,
    bool isRecommended = false,
  }) {
    final priceText = plan.priceDisplay(period);
    final unitText = plan.unitDisplay(period);

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: MembershipTokens.card,
        borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
        border: Border.all(
          color: isRecommended
              ? MembershipTokens.accent.withOpacity(0.4)
              : MembershipTokens.border,
          width: isRecommended ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: MembershipTokens.headline(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: MembershipTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.subtitle,
                      style: MembershipTokens.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: isRecommended
                            ? MembershipTokens.accent
                            : MembershipTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isRecommended) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MembershipTokens.accentBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: MembershipTokens.accentBorder,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        'RECOMMENDED',
                        style: MembershipTokens.mono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: MembershipTokens.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
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
                      'COMING SOON',
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
            ],
          ),
          const SizedBox(height: 14),

          // Price Tag
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                priceText,
                style: MembershipTokens.mono(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isRecommended
                      ? MembershipTokens.accent
                      : MembershipTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unitText,
                style: MembershipTokens.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted,
                ),
              ),
            ],
          ),
          if (period.isYearly) ...[
            const SizedBox(height: 2),
            Text(
              plan.yearlyEquivalentText,
              style: MembershipTokens.body(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isRecommended
                    ? MembershipTokens.accent.withOpacity(0.9)
                    : MembershipTokens.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            plan.heroDescription,
            style: MembershipTokens.body(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: MembershipTokens.border, height: 1),
          const SizedBox(height: 14),

          // Key Planned Benefits from catalog
          ...plan.plannedBenefits.map((b) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _buildBenefitRow(
                icon: Icons.schedule,
                iconColor: isRecommended
                    ? MembershipTokens.accent
                    : const Color(0xFF10B981),
                text: b.title,
                subtext: b.description,
              ),
            );
          }),
          const SizedBox(height: 8),

          // Allowance summary
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: Text(
              'AI Allowance: ${plan.aiAllowanceText}',
              style: MembershipTokens.mono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: MembershipTokens.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Primary Button to Explore Plan
          PrimaryMembershipButton(
            text: 'Explore ${plan.name}',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => _navigateToDetail(context, plan.tier),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    String? subtext,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: MembershipTokens.surfaceHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 13,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: MembershipTokens.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: MembershipTokens.textPrimary,
                ),
              ),
              if (subtext != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtext,
                  style: MembershipTokens.body(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: MembershipTokens.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompareCtaSection(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  Icons.table_chart_outlined,
                  size: 18,
                  color: MembershipTokens.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Feature Matrix',
                      style: MembershipTokens.headline(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MembershipTokens.textPrimary,
                      ),
                    ),
                    Text(
                      'Side-by-side comparison across all 4 tiers',
                      style: MembershipTokens.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: MembershipTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => _navigateToCompare(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: MembershipTokens.textPrimary,
                side: const BorderSide(
                  color: MembershipTokens.borderStrong,
                  width: 1.0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    MembershipTokens.buttonRadius,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Compare all plans',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MembershipTokens.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MembershipTokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: MembershipTokens.textPrimary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Demo pricing · Subject to change',
          style: MembershipTokens.mono(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: MembershipTokens.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Paid memberships are not available yet. Features, limits, and prices may change before launch.',
          style: MembershipTokens.body(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: MembershipTokens.textMuted,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

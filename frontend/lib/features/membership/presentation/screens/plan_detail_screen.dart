import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/billing_period_selector.dart';
import '../widgets/membership_app_bar.dart';
import '../widgets/primary_membership_button.dart';
import 'membership_coming_soon_screen.dart';
import 'membership_overview_screen.dart';

class PlanDetailScreen extends ConsumerStatefulWidget {
  final MembershipTier tier;
  final VoidCallback? onBack;
  final VoidCallback? onComingSoon;
  final VoidCallback? onBackToMembership;

  const PlanDetailScreen({
    super.key,
    required this.tier,
    this.onBack,
    this.onComingSoon,
    this.onBackToMembership,
  });

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  bool _isInheritedExpanded = false;

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _handleBackToMembership() {
    if (widget.onBackToMembership != null) {
      widget.onBackToMembership!();
    } else {
      safePopOrNavigateToMembership(context);
    }
  }

  void _handleComingSoon() {
    if (widget.onComingSoon != null) {
      widget.onComingSoon!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: RouteSettings(
              name: '/membership/coming_soon/${widget.tier.name}'),
          builder: (_) => MembershipComingSoonScreen(
            tier: widget.tier,
            onBackToMembership: widget.onBackToMembership,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final billingPeriod = ref.watch(billingPeriodProvider);
    final plan = ref.watch(membershipPlanProvider(widget.tier));

    return Scaffold(
      backgroundColor: MembershipTokens.canvas,
      appBar: MembershipAppBar(
        title: plan.name,
        onBack: _handleBack,
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
              // 1. Plan Hero
              _buildPlanHero(plan),
              const SizedBox(height: 24),

              // 2. Demo Price Card
              _buildPriceCard(plan, billingPeriod),
              const SizedBox(height: 24),

              // 3. Planned Benefits
              _buildPlannedBenefits(plan),
              const SizedBox(height: 24),

              // 4. Allowance Summary
              _buildAllowanceSummary(plan),
              const SizedBox(height: 24),

              // 5. Inherited Benefits (Expandable)
              _buildInheritedBenefits(plan),
              const SizedBox(height: 24),

              // 6. Availability Notice
              _buildAvailabilityNotice(plan),
              const SizedBox(height: 24),

              // 7. Primary Action Dock
              PrimaryMembershipButton(
                text: 'Coming Soon',
                icon: Icons.arrow_forward,
                subtext: 'Preview only · Your account stays on Free',
                onPressed: _handleComingSoon,
              ),
              const SizedBox(height: 12),

              // 8. Secondary Navigation
              Center(
                child: InkWell(
                  onTap: _handleBackToMembership,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: MembershipTokens.minTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Back to Membership',
                      style: MembershipTokens.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: MembershipTokens.accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanHero(MembershipPlan plan) {
    final isPro = plan.tier.isPro;

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
                color: MembershipTokens.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPro
                      ? MembershipTokens.accentBorder
                      : MembershipTokens.border,
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                plan.icon,
                size: 22,
                color: isPro
                    ? MembershipTokens.accent
                    : MembershipTokens.textMuted,
              ),
            ),
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
                'COMING SOON',
                style: MembershipTokens.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MembershipTokens.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (plan.isRecommended)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          plan.name,
          style: MembershipTokens.headline(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: MembershipTokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          plan.subtitle.toUpperCase(),
          style: MembershipTokens.mono(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: MembershipTokens.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          plan.heroDescription,
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

  Widget _buildPriceCard(MembershipPlan plan, BillingPeriod period) {
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Control
          const BillingPeriodSelector(
            isInsideCard: true,
            showDisclaimer: false,
          ),
          const SizedBox(height: 16),

          // Price Figure
          if (period.isMonthly)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '\$${plan.monthlyPrice}',
                  style: MembershipTokens.mono(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ month',
                  style: MembershipTokens.mono(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: MembershipTokens.textMuted,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '\$${plan.yearlyPrice}',
                      style: MembershipTokens.mono(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: MembershipTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/ year',
                      style: MembershipTokens.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: MembershipTokens.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Equivalent to \$${plan.yearlyEquivalentMonthlyPrice} / month',
                  style: MembershipTokens.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MembershipTokens.textMuted,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 14),
          const Divider(
            color: MembershipTokens.border,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: 14),

          // Disclaimer Note
          Text(
            'Demo pricing · Subject to change',
            style: MembershipTokens.mono(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannedBenefits(MembershipPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Planned with ${plan.name}'.toUpperCase(),
                style: MembershipTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MembershipTokens.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: MembershipTokens.surfaceHigh,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: MembershipTokens.border,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  'Roadmap',
                  style: MembershipTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: MembershipTokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < plan.plannedBenefits.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: MembershipTokens.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: MembershipTokens.border,
                            width: 1.0,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          plan.plannedBenefits[i].icon,
                          size: 19,
                          color: MembershipTokens.textMuted,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    plan.plannedBenefits[i].title,
                                    style: MembershipTokens.body(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: MembershipTokens.textPrimary,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.schedule,
                                  size: 16,
                                  color: MembershipTokens.textMuted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              plan.plannedBenefits[i].description,
                              style: MembershipTokens.body(
                                fontSize: 14,
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
                ),
                if (i < plan.plannedBenefits.length - 1)
                  const Divider(
                    color: MembershipTokens.border,
                    height: 1,
                    thickness: 1,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAllowanceSummary(MembershipPlan plan) {
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
          // Row 1
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.tier.isPro ? 'NUTRITION AI' : 'AI ALLOWANCE',
                  style: MembershipTokens.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MembershipTokens.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
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
                  plan.aiAllowanceText,
                  style: MembershipTokens.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          if (plan.workoutCvAllowanceText != null) ...[
            const SizedBox(height: 12),
            const Divider(
              color: MembershipTokens.border,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'WORKOUT CV',
                    style: MembershipTokens.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
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
                    plan.workoutCvAllowanceText!,
                    style: MembershipTokens.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: MembershipTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          const Divider(
            color: MembershipTokens.border,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: 12),
          Text(
            plan.allowanceSubtext,
            style: MembershipTokens.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInheritedBenefits(MembershipPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'ALSO INCLUDED',
                style: MembershipTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MembershipTokens.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: MembershipTokens.accentBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: MembershipTokens.accentBorder,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  plan.tier.isUltra ? 'Tier Inherited' : 'Baseline Active',
                  style: MembershipTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: MembershipTokens.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Toggle
              InkWell(
                onTap: () {
                  setState(() {
                    _isInheritedExpanded = !_isInheritedExpanded;
                  });
                },
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
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
                        Icons.check,
                        size: 16,
                        color: MembershipTokens.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.inheritedSectionTitle,
                            style: MembershipTokens.body(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: MembershipTokens.textPrimary,
                            ),
                          ),
                          if (!_isInheritedExpanded) ...[
                            const SizedBox(height: 2),
                            Text(
                              plan.inheritedSectionSubtitle,
                              style: MembershipTokens.body(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: MembershipTokens.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      _isInheritedExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: MembershipTokens.textMuted,
                    ),
                  ],
                ),
              ),

              // Expanded Breakdown
              if (_isInheritedExpanded) ...[
                const SizedBox(height: 12),
                const Divider(
                  color: MembershipTokens.border,
                  height: 1,
                  thickness: 1,
                ),
                const SizedBox(height: 12),
                for (final group in plan.inheritedGroups) ...[
                  if (group.groupTitle != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 6.0),
                      child: Text(
                        group.groupTitle!,
                        style: MembershipTokens.mono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: MembershipTokens.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                  for (final item in group.items) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            item.isPlanned ? Icons.schedule : Icons.check,
                            size: 16,
                            color: item.isPlanned
                                ? MembershipTokens.textMuted
                                : MembershipTokens.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.title,
                              style: MembershipTokens.body(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: MembershipTokens.textSubtle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (group != plan.inheritedGroups.last) ...[
                    const SizedBox(height: 6),
                    const Divider(
                      color: MembershipTokens.border,
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvailabilityNotice(MembershipPlan plan) {
    return Center(
      child: Text(
        plan.availabilityNotice,
        style: MembershipTokens.body(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: MembershipTokens.textMuted,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/billing_period_selector.dart';
import '../widgets/membership_app_bar.dart';
import '../widgets/primary_membership_button.dart';
import 'membership_coming_soon_screen.dart';
import 'membership_overview_screen.dart';
import 'payos_checkout_screen.dart';

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
    final t = MembershipTokens.of(context);
    final billingPeriod = ref.watch(billingPeriodProvider);
    final plan = ref.watch(membershipPlanProvider(widget.tier));

    return Scaffold(
      backgroundColor: t.canvas,
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
              _buildPlanHero(plan, t),
              const SizedBox(height: 24),

              // 2. Demo Price Card
              _buildPriceCard(plan, billingPeriod, t),
              const SizedBox(height: 24),

              // 3. Planned Benefits
              _buildPlannedBenefits(plan, t),
              const SizedBox(height: 24),

              // 4. Allowance Summary
              _buildAllowanceSummary(plan, t),
              const SizedBox(height: 24),

              // 5. Inherited Benefits (Expandable)
              _buildInheritedBenefits(plan, t),
              const SizedBox(height: 24),

              // 6. Availability Notice
              _buildAvailabilityNotice(plan, t),
              const SizedBox(height: 24),

              // 7. Primary Action Dock
              if (plan.purchasable)
                _buildUpgradeCtaButton(
                  t: t,
                  text: 'Nâng cấp ngay · ${plan.priceDisplay(billingPeriod)}',
                  subtext: 'Thanh toán tự động qua VietQR / PayOS',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        settings: RouteSettings(
                            name: '/membership/checkout/${widget.tier.name}'),
                        builder: (_) => PayosCheckoutScreen(
                          tier: widget.tier,
                          billingPeriod: billingPeriod,
                        ),
                      ),
                    );
                  },
                )
              else
                PrimaryMembershipButton(
                  text: context.tr('coming_soon_btn'),
                  icon: Icons.arrow_forward,
                  subtext: context.tr('preview_only_notice'),
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
                      context.tr('back_to_membership'),
                      style: t.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: t.accent,
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

  Widget _buildPlanHero(MembershipPlan plan, MembershipPalette t) {
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
                color: t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPro ? t.accentBorder : t.border,
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                plan.icon,
                size: 22,
                color: isPro ? t.accent : t.textMuted,
              ),
            ),
            if (!plan.purchasable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: t.border,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  context.tr('coming_soon_badge'),
                  style: t.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.textMuted,
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
                  color: t.accentBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: t.accentBorder,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  context.tr('recommended_badge'),
                  style: t.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          plan.name,
          style: t.headline(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          plan.subtitle.toUpperCase(),
          style: t.mono(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: t.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          plan.heroDescription,
          style: t.body(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: t.textMuted,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceCard(
      MembershipPlan plan, BillingPeriod period, MembershipPalette t) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
        border: Border.all(
          color: t.border,
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    plan.priceDisplay(BillingPeriod.monthly),
                    style: t.mono(
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    plan.unitDisplay(BillingPeriod.monthly),
                    style: t.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        plan.priceDisplay(BillingPeriod.yearly),
                        style: t.mono(
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        plan.unitDisplay(BillingPeriod.yearly),
                        style: t.mono(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  plan.yearlyEquivalentText,
                  style: t.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 14),
          Divider(
            color: t.border,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: 14),

          // Disclaimer Note
          Text(
            plan.purchasable
                ? 'Giá niêm yết VNĐ · Thanh toán tự động qua VietQR / PayOS.'
                : context.tr('demo_pricing_disclaimer'),
            style: t.mono(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: t.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannedBenefits(MembershipPlan plan, MembershipPalette t) {
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
                plan.purchasable
                    ? 'INCLUDED WITH ${plan.name.toUpperCase()}'
                    : '${context.tr('planned_with').toUpperCase()} ${plan.name.toUpperCase()}',
                style: t.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: plan.purchasable ? t.accentBg : t.surfaceHigh,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: plan.purchasable ? t.accentBorder : t.border,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  plan.purchasable ? 'ACTIVE' : context.tr('roadmap_badge'),
                  style: t.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: plan.purchasable ? t.accent : t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: t.border,
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
                          color: t.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: t.border,
                            width: 1.0,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          plan.plannedBenefits[i].icon,
                          size: 19,
                          color: t.textMuted,
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
                                    style: t.body(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  plan.plannedBenefits[i].isPlanned
                                      ? Icons.schedule
                                      : Icons.check_circle_outline,
                                  size: 16,
                                  color: plan.plannedBenefits[i].isPlanned
                                      ? t.textMuted
                                      : t.accent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              plan.plannedBenefits[i].description,
                              style: t.body(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: t.textMuted,
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
                  Divider(
                    color: t.border,
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

  Widget _buildAllowanceSummary(MembershipPlan plan, MembershipPalette t) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
        border: Border.all(
          color: t.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  plan.tier.isPro ? 'NUTRITION AI' : 'AI ALLOWANCE',
                  style: t.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: t.surfaceHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: t.border,
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    plan.aiAllowanceText,
                    style: t.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (plan.workoutCvAllowanceText != null) ...[
            const SizedBox(height: 12),
            Divider(
              color: t.border,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    'WORKOUT CV',
                    style: t.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: t.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: t.surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: t.border,
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      plan.workoutCvAllowanceText!,
                      style: t.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Divider(
            color: t.border,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: 12),
          Text(
            plan.allowanceSubtext,
            style: t.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: t.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInheritedBenefits(MembershipPlan plan, MembershipPalette t) {
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
                style: t.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: t.accentBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: t.accentBorder,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  plan.tier.isUltra
                      ? context.tr('tier_inherited')
                      : context.tr('baseline_active'),
                  style: t.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: t.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: t.border,
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
                        color: t.surfaceHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: t.border,
                          width: 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.inheritedSectionTitle,
                            style: t.body(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary,
                            ),
                          ),
                          if (!_isInheritedExpanded) ...[
                            const SizedBox(height: 2),
                            Text(
                              plan.inheritedSectionSubtitle,
                              style: t.body(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: t.textMuted,
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
                      color: t.textMuted,
                    ),
                  ],
                ),
              ),

              // Expanded Breakdown
              if (_isInheritedExpanded) ...[
                const SizedBox(height: 12),
                Divider(
                  color: t.border,
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
                        style: t.mono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: t.textMuted,
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
                            color: item.isPlanned ? t.textMuted : t.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.title,
                              style: t.body(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: t.textSubtle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (group != plan.inheritedGroups.last) ...[
                    const SizedBox(height: 6),
                    Divider(
                      color: t.border,
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

  Widget _buildAvailabilityNotice(MembershipPlan plan, MembershipPalette t) {
    return Center(
      child: Text(
        plan.availabilityNotice,
        style: t.body(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: t.textMuted,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildUpgradeCtaButton({
    required MembershipPalette t,
    required String text,
    required String subtext,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MembershipTokens.primaryCtaMinHeight,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: t.primaryCtaBg,
              foregroundColor: t.primaryCtaText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  MembershipTokens.buttonRadius,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return t.primaryCtaPressed;
                }
                return null;
              }),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.primaryCtaText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: t.primaryCtaText,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            subtext,
            style: t.mono(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: t.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

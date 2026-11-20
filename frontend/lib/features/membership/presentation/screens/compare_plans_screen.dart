import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/billing_period_selector.dart';
import '../widgets/comparison_matrix_table.dart';
import '../widgets/membership_app_bar.dart';
import 'membership_overview_screen.dart';
import 'plan_detail_screen.dart';

class ComparePlansScreen extends ConsumerWidget {
  final VoidCallback? onBack;
  final VoidCallback? onBackToMembership;
  final void Function(MembershipTier tier)? onExplorePlan;

  const ComparePlansScreen({
    super.key,
    this.onBack,
    this.onBackToMembership,
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
            onBackToMembership: onBackToMembership ??
                () => safePopOrNavigateToMembership(context),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = MembershipTokens.of(context);
    final billingPeriod = ref.watch(billingPeriodProvider);
    final plans = ref.watch(membershipCatalogProvider);
    final plusPlan = plans.firstWhere((p) => p.tier == MembershipTier.plus);
    final proPlan = plans.firstWhere((p) => p.tier == MembershipTier.pro);
    final ultraPlan = plans.firstWhere((p) => p.tier == MembershipTier.ultra);

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: MembershipAppBar(
        title: context.tr('membership_compare_title'),
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
              // 1. Introduction
              _buildIntroSection(context, t),
              const SizedBox(height: 24),

              // 2. Billing Selector
              const BillingPeriodSelector(
                isInsideCard: false,
                showDisclaimer: true,
              ),
              const SizedBox(height: 24),

              // 3. Compact Price Summary
              _buildCompactPriceSummary(
                context,
                t,
                billingPeriod,
                plusPlan,
                proPlan,
                ultraPlan,
              ),
              const SizedBox(height: 24),

              // 4. Comparison Legend
              _buildLegendSection(context, t),
              const SizedBox(height: 24),

              // 5. Mobile Comparison Matrix
              const ComparisonMatrixTable(),
              const SizedBox(height: 24),

              // 6. Plan Exploration Navigation Rows
              _buildExploreRows(context, t),
              const SizedBox(height: 24),

              // 7. Footer
              _buildFooter(context, t),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroSection(BuildContext context, MembershipPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            context.tr('membership_preview_badge'),
            style: t.mono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('membership_find_your_fit'),
          style: t.headline(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('membership_find_your_fit_desc'),
          style: t.body(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: t.textMuted,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactPriceSummary(
    BuildContext context,
    MembershipPalette t,
    BillingPeriod period,
    MembershipPlan plus,
    MembershipPlan pro,
    MembershipPlan ultra,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: t.border,
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              // Free Row
              _buildSummaryRow(
                t: t,
                title: 'Free',
                subtitle: context.tr('summary_free_sub'),
                badgeText: context.tr('current_badge'),
                badgeBg: t.surfaceHigh,
                badgeBorder: t.border,
                badgeColor: t.textMuted,
                priceContent: Text(
                  '\$0',
                  style: t.mono(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                isFirst: true,
              ),

              // Plus Row
              _buildSummaryRow(
                t: t,
                title: 'Plus',
                subtitle: context.tr('summary_plus_sub'),
                priceContent: _buildPriceCell(
                  context: context,
                  t: t,
                  period: period,
                  plan: plus,
                  isPro: false,
                ),
              ),

              // Pro Row (Recommended)
              _buildSummaryRow(
                t: t,
                title: 'Pro',
                subtitle: context.tr('summary_pro_sub'),
                badgeText: context.tr('recommended_badge'),
                badgeBg: t.accentBg,
                badgeBorder: t.accentBorder,
                badgeColor: t.accent,
                priceContent: _buildPriceCell(
                  context: context,
                  t: t,
                  period: period,
                  plan: pro,
                  isPro: true,
                ),
              ),

              // Ultra Row
              _buildSummaryRow(
                t: t,
                title: 'Ultra',
                subtitle: context.tr('summary_ultra_sub'),
                priceContent: _buildPriceCell(
                  context: context,
                  t: t,
                  period: period,
                  plan: ultra,
                  isPro: false,
                ),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            context.tr('paid_coming_soon_note'),
            style: t.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: t.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow({
    required MembershipPalette t,
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeBg,
    Color? badgeBorder,
    Color? badgeColor,
    required Widget priceContent,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: !isLast
            ? Border(
                bottom: BorderSide(
                  color: t.border.withOpacity(0.8),
                  width: 1.0,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: t.headline(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: badgeBorder ?? Colors.transparent,
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: t.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: badgeColor ?? t.textMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: t.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          priceContent,
        ],
      ),
    );
  }

  Widget _buildPriceCell({
    required BuildContext context,
    required MembershipPalette t,
    required BillingPeriod period,
    required MembershipPlan plan,
    required bool isPro,
  }) {
    final priceColor = isPro ? t.accent : t.textPrimary;

    if (period.isMonthly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '\$${plan.monthlyPrice}',
            style: t.mono(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: priceColor,
            ),
          ),
          Text(
            context.tr('per_month'),
            style: t.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: t.textMuted,
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '\$${plan.yearlyPrice}',
                style: t.mono(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: priceColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.tr('per_year'),
                style: t.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${context.tr('equiv_to')} \$${plan.yearlyEquivalentMonthlyPrice} ${context.tr('per_month')}',
            style: t.body(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: isPro ? t.accent.withOpacity(0.9) : t.textMuted,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLegendSection(BuildContext context, MembershipPalette t) {
    return Container(
      padding: const EdgeInsets.all(14.0),
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
          Text(
            context.tr('status_legend_title'),
            style: t.mono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          _buildLegendItem(
            t: t,
            icon: Icon(
              Icons.check,
              size: 15,
              color: t.textPrimary,
            ),
            label: context.tr('legend_included_free'),
          ),
          const SizedBox(height: 8),
          _buildLegendItem(
            t: t,
            icon: Icon(
              Icons.schedule,
              size: 15,
              color: t.accent,
            ),
            label: context.tr('legend_planned_inclusion'),
          ),
          const SizedBox(height: 8),
          _buildLegendItem(
            t: t,
            icon: Text(
              '—',
              style: t.mono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: t.textMuted,
              ),
            ),
            label: context.tr('legend_not_in_tier'),
            labelColor: t.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required MembershipPalette t,
    required Widget icon,
    required String label,
    Color? labelColor,
  }) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: t.surfaceHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: t.border,
              width: 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: icon,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: t.body(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: labelColor ?? t.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildExploreRows(BuildContext context, MembershipPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            context.tr('explore_plan_details_title'),
            style: t.mono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
              letterSpacing: 0.5,
            ),
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
              // Explore Plus
              _buildExploreRowItem(
                t: t,
                icon: Icons.restaurant,
                title: context.tr('explore_plus'),
                subtitle: context.tr('explore_plus_sub'),
                onTap: () => _navigateToDetail(context, MembershipTier.plus),
                isFirst: true,
              ),
              // Explore Pro (Recommended Accent)
              _buildExploreRowItem(
                t: t,
                icon: Icons.fitness_center,
                title: context.tr('explore_pro'),
                subtitle: context.tr('explore_pro_sub'),
                badgeText: context.tr('recommended_badge_mixed'),
                isPro: true,
                onTap: () => _navigateToDetail(context, MembershipTier.pro),
              ),
              // Explore Ultra
              _buildExploreRowItem(
                t: t,
                icon: Icons.psychology_outlined,
                title: context.tr('explore_ultra'),
                subtitle: context.tr('explore_ultra_sub'),
                onTap: () => _navigateToDetail(context, MembershipTier.ultra),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExploreRowItem({
    required MembershipPalette t,
    required IconData icon,
    required String title,
    required String subtitle,
    String? badgeText,
    bool isPro = false,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 56.0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: !isLast
                ? Border(
                    bottom: BorderSide(
                      color: t.border,
                      width: 1.0,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isPro ? t.accentBg : t.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPro ? t.accentBorder : t.border,
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: isPro ? t.accent : t.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: t.headline(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.textPrimary,
                          ),
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: t.accentBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: t.mono(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: t.accent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: isPro ? t.accent : t.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, MembershipPalette t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Center(
        child: Text(
          context.tr('paid_notice_footer'),
          style: t.body(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: t.textMuted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

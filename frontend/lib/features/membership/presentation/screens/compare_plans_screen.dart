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
    final billingPeriod = ref.watch(billingPeriodProvider);
    final plans = ref.watch(membershipCatalogProvider);
    final plusPlan = plans.firstWhere((p) => p.tier == MembershipTier.plus);
    final proPlan = plans.firstWhere((p) => p.tier == MembershipTier.pro);
    final ultraPlan = plans.firstWhere((p) => p.tier == MembershipTier.ultra);

    return Scaffold(
      backgroundColor: MembershipTokens.canvas,
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
              _buildIntroSection(context),
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
                billingPeriod,
                plusPlan,
                proPlan,
                ultraPlan,
              ),
              const SizedBox(height: 24),

              // 4. Comparison Legend
              _buildLegendSection(context),
              const SizedBox(height: 24),

              // 5. Mobile Comparison Matrix
              const ComparisonMatrixTable(),
              const SizedBox(height: 24),

              // 6. Plan Exploration Navigation Rows
              _buildExploreRows(context),
              const SizedBox(height: 24),

              // 7. Footer
              _buildFooter(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroSection(BuildContext context) {
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
            context.tr('membership_preview_badge'),
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
          context.tr('membership_find_your_fit'),
          style: MembershipTokens.headline(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: MembershipTokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('membership_find_your_fit_desc'),
          style: MembershipTokens.body(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: MembershipTokens.textMuted,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactPriceSummary(
    BuildContext context,
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
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              // Free Row
              _buildSummaryRow(
                title: 'Free',
                subtitle: context.tr('summary_free_sub'),
                badgeText: context.tr('current_badge'),
                badgeBg: MembershipTokens.surfaceHigh,
                badgeBorder: MembershipTokens.border,
                badgeColor: MembershipTokens.textMuted,
                priceContent: Text(
                  '\$0',
                  style: MembershipTokens.mono(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.textPrimary,
                  ),
                ),
                isFirst: true,
              ),

              // Plus Row
              _buildSummaryRow(
                title: 'Plus',
                subtitle: context.tr('summary_plus_sub'),
                priceContent: _buildPriceCell(
                  context: context,
                  period: period,
                  plan: plus,
                  isPro: false,
                ),
              ),

              // Pro Row (Recommended)
              _buildSummaryRow(
                title: 'Pro',
                subtitle: context.tr('summary_pro_sub'),
                badgeText: context.tr('recommended_badge'),
                badgeBg: MembershipTokens.accentBg,
                badgeBorder: MembershipTokens.accentBorder,
                badgeColor: MembershipTokens.accent,
                priceContent: _buildPriceCell(
                  context: context,
                  period: period,
                  plan: pro,
                  isPro: true,
                ),
              ),

              // Ultra Row
              _buildSummaryRow(
                title: 'Ultra',
                subtitle: context.tr('summary_ultra_sub'),
                priceContent: _buildPriceCell(
                  context: context,
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
            style: MembershipTokens.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow({
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
                  color: MembershipTokens.border.withOpacity(0.8),
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
                      style: MembershipTokens.headline(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MembershipTokens.textPrimary,
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
                          style: MembershipTokens.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: badgeColor ?? MembershipTokens.textMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: MembershipTokens.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: MembershipTokens.textMuted,
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
    required BillingPeriod period,
    required MembershipPlan plan,
    required bool isPro,
  }) {
    final priceColor =
        isPro ? MembershipTokens.accent : MembershipTokens.textPrimary;

    if (period.isMonthly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '\$${plan.monthlyPrice}',
            style: MembershipTokens.mono(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: priceColor,
            ),
          ),
          Text(
            context.tr('per_month'),
            style: MembershipTokens.body(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
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
                style: MembershipTokens.mono(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: priceColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.tr('per_year'),
                style: MembershipTokens.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${context.tr('equiv_to')} \$${plan.yearlyEquivalentMonthlyPrice} ${context.tr('per_month')}',
            style: MembershipTokens.body(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: isPro
                  ? MembershipTokens.accent.withOpacity(0.9)
                  : MembershipTokens.textMuted,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLegendSection(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('status_legend_title'),
            style: MembershipTokens.mono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          _buildLegendItem(
            icon: const Icon(
              Icons.check,
              size: 15,
              color: MembershipTokens.textPrimary,
            ),
            label: context.tr('legend_included_free'),
          ),
          const SizedBox(height: 8),
          _buildLegendItem(
            icon: const Icon(
              Icons.schedule,
              size: 15,
              color: MembershipTokens.accent,
            ),
            label: context.tr('legend_planned_inclusion'),
          ),
          const SizedBox(height: 8),
          _buildLegendItem(
            icon: Text(
              '—',
              style: MembershipTokens.mono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: MembershipTokens.textMuted,
              ),
            ),
            label: context.tr('legend_not_in_tier'),
            labelColor: MembershipTokens.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Widget icon,
    required String label,
    Color labelColor = MembershipTokens.textPrimary,
  }) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: MembershipTokens.surfaceHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: icon,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: MembershipTokens.body(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: labelColor,
          ),
        ),
      ],
    );
  }

  Widget _buildExploreRows(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            context.tr('explore_plan_details_title'),
            style: MembershipTokens.mono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textMuted,
              letterSpacing: 0.5,
            ),
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
              // Explore Plus
              _buildExploreRowItem(
                icon: Icons.restaurant,
                title: context.tr('explore_plus'),
                subtitle: context.tr('explore_plus_sub'),
                onTap: () => _navigateToDetail(context, MembershipTier.plus),
                isFirst: true,
              ),
              // Explore Pro (Recommended Accent)
              _buildExploreRowItem(
                icon: Icons.fitness_center,
                title: context.tr('explore_pro'),
                subtitle: context.tr('explore_pro_sub'),
                badgeText: context.tr('recommended_badge_mixed'),
                isPro: true,
                onTap: () => _navigateToDetail(context, MembershipTier.pro),
              ),
              // Explore Ultra
              _buildExploreRowItem(
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
                ? const Border(
                    bottom: BorderSide(
                      color: MembershipTokens.border,
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
                  color: isPro
                      ? MembershipTokens.accentBg
                      : MembershipTokens.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPro
                        ? MembershipTokens.accentBorder
                        : MembershipTokens.border,
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: isPro
                      ? MembershipTokens.accent
                      : MembershipTokens.textMuted,
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
                          style: MembershipTokens.headline(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: MembershipTokens.textPrimary,
                          ),
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: MembershipTokens.accentBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: MembershipTokens.mono(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: MembershipTokens.accent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: MembershipTokens.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: MembershipTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: isPro
                    ? MembershipTokens.accent
                    : MembershipTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Center(
        child: Text(
          context.tr('paid_notice_footer'),
          style: MembershipTokens.body(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: MembershipTokens.textMuted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

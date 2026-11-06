import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/membership_app_bar.dart';
import 'membership_overview_screen.dart';
import '../providers/membership_providers.dart';
import '../../data/models/account_membership_dto.dart';

class ManageMembershipScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onExplorePlans;

  const ManageMembershipScreen({
    super.key,
    this.onBack,
    this.onExplorePlans,
  });

  @override
  ConsumerState<ManageMembershipScreen> createState() =>
      _ManageMembershipScreenState();
}

class _ManageMembershipScreenState
    extends ConsumerState<ManageMembershipScreen> {
  final Set<int> _expandedFaqIndices = {};

  void _handleExplorePlans() {
    if (widget.onExplorePlans != null) {
      widget.onExplorePlans!();
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

  void _toggleFaq(int index) {
    setState(() {
      if (_expandedFaqIndices.contains(index)) {
        _expandedFaqIndices.remove(index);
      } else {
        _expandedFaqIndices.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountMembership =
        ref.watch(accountMembershipProvider);

    return Scaffold(
      backgroundColor: MembershipTokens.canvas,
      appBar: MembershipAppBar(
        title: context.tr('manage_membership_title'),
        onBack: widget.onBack,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          child: Text(
            context.tr('account_badge').toUpperCase(),
            style: MembershipTokens.mono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
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
              // 1. Current Plan Card
              _buildCurrentPlanCard(context, accountMembership),
              const SizedBox(height: 20),

              // 2. Your Free Benefits
              _buildFreeBenefitsSection(context),
              const SizedBox(height: 20),

              // 3. Membership Discovery Card
              _buildDiscoveryCard(context),
              const SizedBox(height: 20),

              // 4. Membership FAQ
              _buildFaqSection(context),
              const SizedBox(height: 24),

              // 5. Quiet Footer
              _buildFooter(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPlanCard(BuildContext context, [dynamic account]) {
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                context.tr('current_plan_heading'),
                style: MembershipTokens.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MembershipTokens.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: MembershipTokens.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: MembershipTokens.border,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  (account is AccountMembershipState && account.isUnknown)
                      ? 'UNAVAILABLE'
                      : ((account is AccountMembershipState && account.isLoggedOut)
                          ? 'GUEST'
                          : ((account is AccountMembershipState && account.isStale)
                              ? 'OFFLINE'
                              : context.tr('current_badge'))),
                  style: MembershipTokens.mono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  Icons.card_membership,
                  size: 22,
                  color: MembershipTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                        (account is AccountMembershipState && account.isUnknown)
                            ? 'Status Unavailable'
                            : ((account is AccountMembershipState && account.isLoggedOut)
                                ? 'Not Signed In'
                                : ((account is AccountMembershipState ? account.tier : (account is AccountMembershipDto ? account.tier : null))?.displayName ?? 'Free')),
                          style: MembershipTokens.headline(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: MembershipTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· \$0',
                          style: MembershipTokens.mono(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: MembershipTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (account is AccountMembershipState && account.isUnknown)
                          ? 'Could not verify membership status. Please check your connection.'
                          : ((account is AccountMembershipState && account.isLoggedOut)
                              ? 'Sign in to access your plan features and AI usage limits.'
                              : ((account is AccountMembershipState && account.isStale)
                                  ? 'Offline cache ? Showing last-known plan status.'
                                  : context.tr('everyday_tracking_essentials'))),
                      style: MembershipTokens.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: MembershipTokens.textMuted,
                      ),
                    ),
                  ],
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
          const SizedBox(height: 12),
          if (account is AccountMembershipState && account.isActiveSubscription) ...[
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: account.inGracePeriod
                        ? Colors.orangeAccent
                        : (account.cancelAtPeriodEnd
                            ? Colors.amberAccent
                            : Colors.greenAccent),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    account.inGracePeriod
                        ? '${context.tr('in_grace_period_notice')}${account.gracePeriodExpiresAt != null ? ' (${account.gracePeriodExpiresAt!.toLocal().toIso8601String().split('T').first})' : ''}'
                        : (account.cancelAtPeriodEnd
                            ? '${context.tr('auto_renew_canceled')}${account.currentPeriodEnd != null ? ' · ${context.tr('active_until_notice')} ${account.currentPeriodEnd!.toLocal().toIso8601String().split('T').first}' : ''}'
                            : '${context.tr('auto_renew_active')}${account.currentPeriodEnd != null ? ' · ${context.tr('active_until_notice')} ${account.currentPeriodEnd!.toLocal().toIso8601String().split('T').first}' : ''}'),
                    style: MembershipTokens.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: MembershipTokens.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('no_paid_activated'),
                    style: MembershipTokens.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final uid = (account is AccountMembershipState) ? account.userId : '';
                ref.read(membershipPurchaseProvider.notifier).restorePurchases(
                      accountId: uid,
                    );
              },
              icon: const Icon(Icons.restore, size: 16),
              label: Text(
                context.tr('restore_purchases_action'),
                style: MembershipTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MembershipTokens.textPrimary,
                side: const BorderSide(color: MembershipTokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeBenefitsSection(BuildContext context) {
    final freeItems = [
      (
        title: context.tr('benefit_nutrition_logging'),
        subtitle: context.tr('benefit_nutrition_logging_sub'),
      ),
      (
        title: context.tr('benefit_workout_tracking'),
        subtitle: context.tr('benefit_workout_tracking_sub'),
      ),
      (
        title: context.tr('benefit_food_analysis'),
        subtitle: context.tr('benefit_food_analysis_sub'),
      ),
      (
        title: context.tr('benefit_basic_metrics'),
        subtitle: context.tr('benefit_basic_metrics_sub'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            context.tr('your_free_benefits').toUpperCase(),
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
              for (int i = 0; i < freeItems.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
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
                          size: 15,
                          color: MembershipTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              freeItems[i].title,
                              style: MembershipTokens.body(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: MembershipTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              freeItems[i].subtitle,
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
                ),
                if (i < freeItems.length - 1)
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

  Widget _buildDiscoveryCard(BuildContext context) {
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: MembershipTokens.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
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
          const SizedBox(height: 12),
          Text(
            context.tr('explore_whats_next'),
            style: MembershipTokens.headline(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('explore_whats_next_desc'),
            style: MembershipTokens.body(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: MembershipTokens.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: MembershipTokens.primaryCtaMinHeight,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleExplorePlans,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.tr('explore_plans_btn'),
                    style: MembershipTokens.body(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: MembershipTokens.primaryCtaText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: MembershipTokens.primaryCtaText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqSection(BuildContext context) {
    final faqs = [
      (
        question: context.tr('faq_q1'),
        answer: context.tr('faq_a1'),
      ),
      (
        question: context.tr('faq_q2'),
        answer: context.tr('faq_a2'),
      ),
      (
        question: context.tr('faq_q3'),
        answer: context.tr('faq_a3'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            context.tr('membership_faq_title').toUpperCase(),
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
              for (int i = 0; i < faqs.length; i++) ...[
                _buildFaqItem(
                  index: i,
                  question: faqs[i].question,
                  answer: faqs[i].answer,
                ),
                if (i < faqs.length - 1)
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

  Widget _buildFaqItem({
    required int index,
    required String question,
    required String answer,
  }) {
    final isExpanded = _expandedFaqIndices.contains(index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _toggleFaq(index),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: MembershipTokens.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 12.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    question,
                    style: MembershipTokens.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: MembershipTokens.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            padding: const EdgeInsets.only(
              left: 14.0,
              right: 14.0,
              bottom: 14.0,
              top: 4.0,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF121316).withOpacity(0.5),
              border: const Border(
                top: BorderSide(
                  color: MembershipTokens.border,
                  width: 0.5,
                ),
              ),
            ),
            child: Text(
              answer,
              style: MembershipTokens.body(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: MembershipTokens.textMuted,
                height: 1.45,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Center(
      child: Text(
        context.tr('quiet_footer_notice'),
        style: MembershipTokens.mono(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: MembershipTokens.textMuted,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

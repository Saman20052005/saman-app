import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/membership_app_bar.dart';
import 'membership_overview_screen.dart';

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
    return Scaffold(
      backgroundColor: MembershipTokens.canvas,
      appBar: MembershipAppBar(
        title: 'Manage membership',
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
            'ACCOUNT',
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
              _buildCurrentPlanCard(),
              const SizedBox(height: 20),

              // 2. Your Free Benefits
              _buildFreeBenefitsSection(),
              const SizedBox(height: 20),

              // 3. Membership Discovery Card
              _buildDiscoveryCard(),
              const SizedBox(height: 20),

              // 4. Membership FAQ
              _buildFaqSection(),
              const SizedBox(height: 24),

              // 5. Quiet Footer
              _buildFooter(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPlanCard() {
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
                'CURRENT PLAN',
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
                  'CURRENT',
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
                          'Free',
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
                      'Your everyday tracking essentials.',
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
                  'No paid membership activated.',
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
      ),
    );
  }

  Widget _buildFreeBenefitsSection() {
    const freeItems = [
      (
        title: 'Nutrition logging',
        subtitle: 'Keep a record of your meals.',
      ),
      (
        title: 'Manual workout tracking',
        subtitle: 'Log your workouts manually.',
      ),
      (
        title: 'Free food photo analysis',
        subtitle: 'Use the existing free analysis model.',
      ),
      (
        title: 'Basic health metrics',
        subtitle: 'Track your core health measurements.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            'YOUR FREE BENEFITS',
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

  Widget _buildDiscoveryCard() {
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
              'COMING SOON',
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
            "Explore what's next.",
            style: MembershipTokens.headline(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MembershipTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Discover planned Nutrition AI, Workout Intelligence, and personalized features across Plus, Pro, and Ultra.',
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
                    'Explore Plans',
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

  Widget _buildFaqSection() {
    const faqs = [
      (
        question: 'What does my Free plan include?',
        answer:
            'Nutrition logging, manual workout tracking, the existing free food photo analysis model, and basic health metrics.',
      ),
      (
        question: 'Can I upgrade now?',
        answer:
            'Paid memberships are Coming Soon. You can explore the planned benefits, but this preview does not purchase or activate a plan.',
      ),
      (
        question: 'Are prices and AI limits final?',
        answer:
            'No. Displayed prices are demo estimates, and AI limits will be announced. Features, limits, and pricing may change before launch.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            'MEMBERSHIP FAQ',
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

  Widget _buildFooter() {
    return Center(
      child: Text(
        'Membership preview · Paid plans are not available yet.',
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

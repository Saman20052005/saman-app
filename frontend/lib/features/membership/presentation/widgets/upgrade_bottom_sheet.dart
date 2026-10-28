import 'package:flutter/material.dart';
import '../../domain/models/membership_plan.dart';
import '../tokens/membership_tokens.dart';
import 'primary_membership_button.dart';

/// Modal bottom sheet showcasing planned upgrades for Nutrition AI (Plus)
/// and Workout Intelligence (Pro).
///
/// Returns [MembershipTier] if the user chooses to explore the plan,
/// or `null` if the sheet was dismissed.
Future<MembershipTier?> showUpgradeBottomSheet(
  BuildContext context, {
  required MembershipTier tier,
}) {
  return showModalBottomSheet<MembershipTier>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.75),
    builder: (modalContext) => UpgradeBottomSheet(
      tier: tier,
      onClose: () => Navigator.of(modalContext).pop(null),
      onSecondary: () => Navigator.of(modalContext).pop(null),
      onExplore: () => Navigator.of(modalContext).pop(tier),
    ),
  );
}

class UpgradeBottomSheet extends StatelessWidget {
  final MembershipTier tier;
  final VoidCallback? onClose;
  final VoidCallback? onExplore;
  final VoidCallback? onSecondary;

  const UpgradeBottomSheet({
    super.key,
    required this.tier,
    this.onClose,
    this.onExplore,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final isPlus = tier == MembershipTier.plus;
    final title =
        isPlus ? 'Explore Nutrition AI' : 'Explore Workout Intelligence';
    final description = isPlus
        ? 'Discover planned Gemini food photo analysis with Saman Plus.'
        : 'Discover planned Workout CV benefits with Saman Pro.';

    final benefits = isPlus
        ? const [
            'Gemini food photo analysis',
            'Monthly AI allowance',
          ]
        : const [
            'Workout CV AI',
            'Movement analysis and rep counting',
            'Separate Workout CV allowance',
          ];

    final secondaryText = isPlus ? 'Continue with Free' : 'Back to Workout';
    final exploreText = isPlus ? 'Explore Plus' : 'Explore Pro';
    final tierLabel = isPlus ? 'PLUS' : 'PRO';

    return Container(
      decoration: const BoxDecoration(
        color: MembershipTokens.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: MembershipTokens.border),
          left: BorderSide(color: MembershipTokens.border),
          right: BorderSide(color: MembershipTokens.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Sheet Controls: Drag handle and Close button
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MembershipTokens.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      key: const ValueKey('upgrade_sheet_close_button'),
                      icon: const Icon(Icons.close, size: 20),
                      color: MembershipTokens.textMuted,
                      tooltip: 'Close',
                      onPressed: () {
                        if (onClose != null) {
                          onClose!();
                        } else {
                          Navigator.of(context).pop(null);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Introduction Icon Tile
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: MembershipTokens.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MembershipTokens.border),
                  ),
                  child: Icon(
                    isPlus ? Icons.restaurant : Icons.fitness_center,
                    size: 24,
                    color: MembershipTokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Neutral Badge: TIER · PREVIEW
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MembershipTokens.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MembershipTokens.border),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: tierLabel,
                          style: MembershipTokens.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: MembershipTokens.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                        TextSpan(
                          text: ' · PREVIEW',
                          style: MembershipTokens.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: MembershipTokens.textMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Heading & Subtitle
              Text(
                title,
                style: MembershipTokens.headline(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: MembershipTokens.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  description,
                  style: MembershipTokens.body(
                    fontSize: 14,
                    color: MembershipTokens.textMuted,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // Benefit Preview Card (Compact Inset Card)
              Container(
                decoration: BoxDecoration(
                  color: MembershipTokens.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MembershipTokens.border),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < benefits.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            color: MembershipTokens.border.withOpacity(0.6),
                          ),
                        ),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: MembershipTokens.card,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: MembershipTokens.border),
                            ),
                            child: const Icon(
                              Icons.schedule,
                              size: 16,
                              color: MembershipTokens.textMuted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              benefits[i],
                              style: MembershipTokens.body(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: MembershipTokens.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Divider(
                      height: 1,
                      color: MembershipTokens.border.withOpacity(0.8),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Limits to be announced.',
                            style: MembershipTokens.mono(
                              fontSize: 11,
                              color: MembershipTokens.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: MembershipTokens.card,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: MembershipTokens.border.withOpacity(0.6),
                            ),
                          ),
                          child: Text(
                            'PLANNED',
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
              ),
              const SizedBox(height: 20),

              // Primary Action: Explore Plus / Pro
              PrimaryMembershipButton(
                key: ValueKey('upgrade_sheet_explore_${tier.name}_button'),
                text: exploreText,
                onPressed: () {
                  if (onExplore != null) {
                    onExplore!();
                  } else {
                    Navigator.of(context).pop(tier);
                  }
                },
              ),
              const SizedBox(height: 8),

              // Secondary Action: Continue with Free / Back to Workout
              Center(
                child: TextButton(
                  key: const ValueKey('upgrade_sheet_secondary_button'),
                  onPressed: () {
                    if (onSecondary != null) {
                      onSecondary!();
                    } else {
                      Navigator.of(context).pop(null);
                    }
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: MembershipTokens.textMuted,
                  ),
                  child: Text(
                    secondaryText,
                    style: MembershipTokens.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: MembershipTokens.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Preview Only Notice
              Center(
                child: Text(
                  'Preview only · Paid memberships are not available yet.',
                  style: MembershipTokens.body(
                    fontSize: 12,
                    color: MembershipTokens.textMuted.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

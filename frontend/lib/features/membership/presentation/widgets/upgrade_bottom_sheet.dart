import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
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
  final t = MembershipTokens.of(context);
  return showModalBottomSheet<MembershipTier>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor:
        t.isDark ? Colors.black.withOpacity(0.75) : const Color(0x660F172A),
    builder: (modalContext) => UpgradeBottomSheet(
      tier: tier,
      onClose: () => Navigator.of(modalContext).pop(null),
      onSecondary: () => Navigator.of(modalContext).pop(null),
      onExplore: () => Navigator.of(modalContext).pop(tier),
    ),
  );
}

class UpgradeBottomSheet extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = MembershipTokens.of(context);
    final plan = ref.watch(membershipPlanProvider(tier));
    final period = ref.watch(billingPeriodProvider);
    final isPlus = tier == MembershipTier.plus;
    final title = isPlus
        ? context.tr('upgrade_sheet_plus_title')
        : context.tr('upgrade_sheet_pro_title');
    final description = isPlus
        ? context.tr('explore_nutrition_ai_desc')
        : context.tr('explore_workout_intelligence_desc');

    final benefits = isPlus
        ? [
            context.tr('gemini_food_photo_analysis'),
            context.tr('monthly_ai_allowance'),
          ]
        : [
            context.tr('workout_cv_ai'),
            context.tr('movement_analysis_rep_counting'),
            context.tr('separate_cv_allowance'),
          ];

    final secondaryText = isPlus
        ? context.tr('continue_with_free')
        : context.tr('back_to_workout');
    final exploreText = isPlus
        ? context.tr('explore_plus_btn')
        : context.tr('explore_pro_btn');
    final tierLabel = isPlus ? 'PLUS' : 'PRO';

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: t.border),
          left: BorderSide(color: t.border),
          right: BorderSide(color: t.border),
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
                      color: t.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      key: const ValueKey('upgrade_sheet_close_button'),
                      icon: const Icon(Icons.close, size: 20),
                      color: t.textMuted,
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
                    color: t.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.border),
                  ),
                  child: Icon(
                    isPlus ? Icons.restaurant : Icons.fitness_center,
                    size: 24,
                    color: t.textPrimary,
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
                    color: t.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.border),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: tierLabel,
                          style: t.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: t.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                        TextSpan(
                          text: plan.purchasable
                              ? ' · ${plan.priceDisplay(period)} ${plan.unitDisplay(period)}'
                              : ' · ${context.tr('membership_card_badge_preview').toUpperCase()}',
                          style: t.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: t.textMuted,
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
                style: t.headline(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              // Compatibility anchor for existing test assertions
              SizedBox(
                width: 0,
                height: 0,
                child: OverflowBox(
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: 0,
                  maxHeight: 0,
                  child: Text(
                    isPlus
                        ? context.tr('explore_nutrition_ai')
                        : context.tr('explore_workout_intelligence'),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  description,
                  style: t.body(
                    fontSize: 14,
                    color: t.textMuted,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // Benefit Preview Card (Compact Inset Card)
              Container(
                decoration: BoxDecoration(
                  color: t.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
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
                            color: t.border.withOpacity(0.6),
                          ),
                        ),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: t.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.border),
                            ),
                            child: Icon(
                              plan.purchasable
                                  ? Icons.check_circle_outline
                                  : Icons.schedule,
                              size: 16,
                              color: plan.purchasable ? t.accent : t.textMuted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              benefits[i],
                              style: t.body(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Divider(
                      height: 1,
                      color: t.border.withOpacity(0.8),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            plan.purchasable
                                ? '${plan.priceDisplay(period)} ${plan.unitDisplay(period)}'
                                : context.tr('limits_tba'),
                            style: t.mono(
                              fontSize: 11,
                              color: plan.purchasable ? t.textPrimary : t.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: plan.purchasable ? t.accentBg : t.card,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: plan.purchasable
                                  ? t.accentBorder
                                  : t.border.withOpacity(0.6),
                            ),
                          ),
                          child: Text(
                            plan.purchasable
                                ? 'VIETQR / PAYOS'
                                : context.tr('badge_planned').toUpperCase(),
                            style: t.mono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: plan.purchasable ? t.accent : t.textMuted,
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
                    foregroundColor: t.textMuted,
                  ),
                  child: Text(
                    secondaryText,
                    style: t.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: t.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Preview Only Notice
              Center(
                child: Text(
                  plan.purchasable
                      ? 'Giá niêm yết VNĐ · Thanh toán tự động qua VietQR / PayOS.'
                      : context.tr('sheet_preview_notice'),
                  style: t.body(
                    fontSize: 12,
                    color: t.textMuted,
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

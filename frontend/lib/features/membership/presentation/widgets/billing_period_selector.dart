import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';

class BillingPeriodSelector extends ConsumerWidget {
  final BillingPeriod? period;
  final ValueChanged<BillingPeriod>? onChanged;
  final bool isInsideCard;
  final bool showDisclaimer;

  const BillingPeriodSelector({
    super.key,
    this.period,
    this.onChanged,
    this.isInsideCard = false,
    this.showDisclaimer = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BillingPeriod activePeriod =
        period ?? ref.watch(billingPeriodProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            color:
                isInsideCard ? MembershipTokens.canvas : MembershipTokens.card,
            borderRadius: BorderRadius.circular(
              isInsideCard ? 12.0 : MembershipTokens.cardRadius,
            ),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              // Monthly Button
              Expanded(
                child: _SegmentButton(
                  title: 'Monthly',
                  isSelected: activePeriod.isMonthly,
                  onTap: () {
                    if (onChanged != null) {
                      onChanged!(BillingPeriod.monthly);
                    } else {
                      ref.read(billingPeriodProvider.notifier).state =
                          BillingPeriod.monthly;
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              // Yearly Button
              Expanded(
                child: _SegmentButton(
                  title: 'Yearly',
                  isSelected: activePeriod.isYearly,
                  onTap: () {
                    if (onChanged != null) {
                      onChanged!(BillingPeriod.yearly);
                    } else {
                      ref.read(billingPeriodProvider.notifier).state =
                          BillingPeriod.yearly;
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (showDisclaimer) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              'Demo pricing · Subject to change',
              style: MembershipTokens.mono(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: MembershipTokens.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: MembershipTokens.minTouchTarget,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? MembershipTokens.surfaceHigh
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(
                      color: MembershipTokens.borderStrong,
                      width: 1.0,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              title,
              style: MembershipTokens.body(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? MembershipTokens.textPrimary
                    : MembershipTokens.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

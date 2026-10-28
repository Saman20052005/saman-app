import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/membership_plan.dart';

/// Single source of truth for billing period (Monthly vs Yearly).
/// Shared across Compare, Plan Details, and ready for Membership Overview.
final billingPeriodProvider =
    StateProvider<BillingPeriod>((ref) => BillingPeriod.monthly);

/// Provides the unified static catalog of 4 membership plans.
final membershipCatalogProvider =
    Provider<List<MembershipPlan>>((ref) => MembershipCatalog.plans);

/// Provides a single plan by tier.
final membershipPlanProvider =
    Provider.family<MembershipPlan, MembershipTier>((ref, tier) {
  return MembershipCatalog.getPlan(tier);
});

/// Current user entitlement tier (Demo account is always Free).
final currentMembershipTierProvider =
    Provider<MembershipTier>((ref) => MembershipTier.free);

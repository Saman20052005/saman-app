import 'package:flutter/material.dart';
import '../../domain/models/membership_plan.dart';

/// Data Transfer Objects for Saman Revenue Catalog.
/// Maps backend /api/revenue/catalog responses to domain entities.
/// Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-06).

class PriceDto {
  final String priceId;
  final String planId;
  final String period;
  final int amountCents;
  final String currency;
  final int? yearlyEquivalentMonthlyCents;
  final bool purchasable;

  const PriceDto({
    required this.priceId,
    required this.planId,
    required this.period,
    required this.amountCents,
    required this.currency,
    this.yearlyEquivalentMonthlyCents,
    required this.purchasable,
  });

  factory PriceDto.fromJson(Map<String, dynamic> json) {
    return PriceDto(
      priceId: json['price_id'] as String? ?? '',
      planId: json['plan_id'] as String? ?? '',
      period: json['period'] as String? ?? 'monthly',
      amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?)?.toUpperCase() ?? 'USD',
      yearlyEquivalentMonthlyCents:
          (json['yearly_equivalent_monthly_cents'] as num?)?.toInt(),
      purchasable: json['purchasable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'price_id': priceId,
        'plan_id': planId,
        'period': period,
        'amount_cents': amountCents,
        'currency': currency,
        if (yearlyEquivalentMonthlyCents != null)
          'yearly_equivalent_monthly_cents': yearlyEquivalentMonthlyCents,
        'purchasable': purchasable,
      };
}

class PlanDto {
  final String planId;
  final String tier;
  final String name;
  final String subtitle;
  final String heroDescription;
  final bool isRecommended;
  final bool isCurrent;
  final String iconName;
  final List<String> featureIds;
  final List<PriceDto> prices;
  final String availabilityNotice;

  const PlanDto({
    required this.planId,
    required this.tier,
    required this.name,
    required this.subtitle,
    required this.heroDescription,
    this.isRecommended = false,
    this.isCurrent = false,
    required this.iconName,
    this.featureIds = const [],
    this.prices = const [],
    required this.availabilityNotice,
  });

  factory PlanDto.fromJson(Map<String, dynamic> json) {
    final rawPrices = json['prices'] as List<dynamic>? ?? [];
    final rawFeatures = json['feature_ids'] as List<dynamic>? ?? [];

    return PlanDto(
      planId: json['plan_id'] as String? ?? '',
      tier: (json['tier'] as String?)?.toLowerCase() ?? 'free',
      name: json['name'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      heroDescription: json['hero_description'] as String? ?? '',
      isRecommended: json['is_recommended'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
      iconName: json['icon_name'] as String? ?? '',
      featureIds: rawFeatures.map((f) => f.toString()).toList(),
      prices: rawPrices
          .map((p) => PriceDto.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      availabilityNotice: json['availability_notice'] as String? ?? '',
    );
  }

  MembershipTier get membershipTier {
    switch (tier.toLowerCase()) {
      case 'plus':
        return MembershipTier.plus;
      case 'pro':
        return MembershipTier.pro;
      case 'ultra':
        return MembershipTier.ultra;
      case 'free':
      default:
        return MembershipTier.free;
    }
  }

  IconData get iconData {
    switch (iconName) {
      case 'check_circle_outline':
        return Icons.check_circle_outline;
      case 'restaurant':
        return Icons.restaurant;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'psychology':
        return Icons.psychology;
      default:
        return Icons.star_border;
    }
  }
}

class MatrixFeatureDto {
  final String id;
  final String title;
  final String group;
  final Map<String, String> statusMap;

  const MatrixFeatureDto({
    required this.id,
    required this.title,
    required this.group,
    required this.statusMap,
  });

  factory MatrixFeatureDto.fromJson(Map<String, dynamic> json) {
    final rawMap = json['status_map'] as Map<dynamic, dynamic>? ?? {};
    return MatrixFeatureDto(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      group: json['group'] as String? ?? '',
      statusMap: rawMap.map(
        (key, value) => MapEntry(key.toString().toLowerCase(), value.toString().toLowerCase()),
      ),
    );
  }

  MatrixFeature toDomain() {
    FeatureGroup fGroup;
    final gLower = group.toLowerCase();
    if (gLower.contains('nutrition')) {
      fGroup = FeatureGroup.nutritionAi;
    } else if (gLower.contains('workout') || gLower.contains('cv')) {
      fGroup = FeatureGroup.workoutCv;
    } else if (gLower.contains('advanced')) {
      fGroup = FeatureGroup.advancedIntelligence;
    } else {
      fGroup = FeatureGroup.coreEssentials;
    }

    final Map<MembershipTier, InclusionStatus> domainStatusMap = {};
    for (final tier in MembershipTier.values) {
      final statusStr = statusMap[tier.name.toLowerCase()];
      switch (statusStr) {
        case 'included':
          domainStatusMap[tier] = InclusionStatus.included;
          break;
        case 'planned':
          domainStatusMap[tier] = InclusionStatus.planned;
          break;
        case 'not_included':
        default:
          domainStatusMap[tier] = InclusionStatus.notIncluded;
          break;
      }
    }

    return MatrixFeature(
      id: id,
      title: title,
      group: fGroup,
      statusMap: domainStatusMap,
    );
  }
}

class CatalogResponseDto {
  final String versionId;
  final String status;
  final String currency;
  final bool previewMode;
  final String disclaimer;
  final List<PlanDto> plans;
  final List<PriceDto> prices;
  final List<MatrixFeatureDto> matrixFeatures;
  final DateTime? publishedAt;

  const CatalogResponseDto({
    required this.versionId,
    required this.status,
    required this.currency,
    required this.previewMode,
    required this.disclaimer,
    required this.plans,
    required this.prices,
    required this.matrixFeatures,
    this.publishedAt,
  });

  factory CatalogResponseDto.fromJson(Map<String, dynamic> json) {
    final rawPlans = json['plans'] as List<dynamic>? ?? [];
    final rawPrices = json['prices'] as List<dynamic>? ?? [];
    final rawFeatures = json['matrix_features'] as List<dynamic>? ?? [];

    DateTime? pubAt;
    if (json['published_at'] != null) {
      pubAt = DateTime.tryParse(json['published_at'].toString());
    }

    return CatalogResponseDto(
      versionId: json['version_id'] as String? ?? 'v1.0-preview',
      status: json['status'] as String? ?? 'published',
      currency: (json['currency'] as String?)?.toUpperCase() ?? 'USD',
      previewMode: json['preview_mode'] as bool? ?? true,
      disclaimer: json['disclaimer'] as String? ??
          'Demo pricing · Subject to change. Not purchasable.',
      plans: rawPlans
          .map((p) => PlanDto.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      prices: rawPrices
          .map((p) => PriceDto.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      matrixFeatures: rawFeatures
          .map((f) =>
              MatrixFeatureDto.fromJson(Map<String, dynamic>.from(f as Map)))
          .toList(),
      publishedAt: pubAt,
    );
  }

  /// Converts backend catalog to list of domain MembershipPlan objects.
  /// Falls back to static catalog definitions for content (benefits, text)
  /// while ensuring all prices, tiers, and purchasable status are dynamic from backend.
  List<MembershipPlan> toDomainPlans() {
    return plans.map((planDto) {
      final tier = planDto.membershipTier;
      final baseline = MembershipCatalog.getPlan(tier);

      // Find monthly and yearly price DTOs
      PriceDto? monthlyPrice;
      PriceDto? yearlyPrice;

      final allPrices = planDto.prices.isNotEmpty ? planDto.prices : prices;
      for (final p in allPrices) {
        if (p.planId == planDto.planId || p.planId.contains(tier.name)) {
          if (p.period == 'monthly') monthlyPrice = p;
          if (p.period == 'yearly') yearlyPrice = p;
        }
      }

      final monthlyAmount = (monthlyPrice?.amountCents ?? 0) ~/ 100;
      final yearlyAmount = (yearlyPrice?.amountCents ?? 0) ~/ 100;
      final equivAmount =
          ((yearlyPrice?.yearlyEquivalentMonthlyCents ?? (yearlyPrice?.amountCents ?? 0) ~/ 12)) ~/ 100;

      final isPurchasable = monthlyPrice?.purchasable ?? false;

      return MembershipPlan(
        tier: tier,
        name: planDto.name.isNotEmpty ? planDto.name : baseline.name,
        subtitle: planDto.subtitle.isNotEmpty ? planDto.subtitle : baseline.subtitle,
        heroDescription: planDto.heroDescription.isNotEmpty
            ? planDto.heroDescription
            : baseline.heroDescription,
        monthlyPrice: monthlyAmount,
        yearlyPrice: yearlyAmount,
        yearlyEquivalentMonthlyPrice: equivAmount,
        isRecommended: planDto.isRecommended,
        isCurrent: planDto.isCurrent,
        purchasable: isPurchasable,
        icon: planDto.iconName.isNotEmpty ? planDto.iconData : baseline.icon,
        plannedBenefits: baseline.plannedBenefits,
        aiAllowanceText: baseline.aiAllowanceText,
        workoutCvAllowanceText: baseline.workoutCvAllowanceText,
        allowanceSubtext: baseline.allowanceSubtext,
        inheritedSectionTitle: baseline.inheritedSectionTitle,
        inheritedSectionSubtitle: baseline.inheritedSectionSubtitle,
        inheritedGroups: baseline.inheritedGroups,
        availabilityNotice: planDto.availabilityNotice.isNotEmpty
            ? planDto.availabilityNotice
            : baseline.availabilityNotice,
      );
    }).toList();
  }
}

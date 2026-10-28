import 'package:flutter/material.dart';

enum BillingPeriod {
  monthly,
  yearly;

  bool get isMonthly => this == BillingPeriod.monthly;
  bool get isYearly => this == BillingPeriod.yearly;
}

enum MembershipTier {
  free,
  plus,
  pro,
  ultra;

  bool get isFree => this == MembershipTier.free;
  bool get isPlus => this == MembershipTier.plus;
  bool get isPro => this == MembershipTier.pro;
  bool get isUltra => this == MembershipTier.ultra;
  bool get isPaid => !isFree;

  String get displayName {
    switch (this) {
      case MembershipTier.free:
        return 'Free';
      case MembershipTier.plus:
        return 'Plus';
      case MembershipTier.pro:
        return 'Pro';
      case MembershipTier.ultra:
        return 'Ultra';
    }
  }
}

enum InclusionStatus {
  included, // Free inclusions / baseline (check icon)
  planned, // Planned inclusions (schedule icon)
  notIncluded; // Not in tier (dash —)

  bool get isIncluded => this == InclusionStatus.included;
  bool get isPlanned => this == InclusionStatus.planned;
  bool get isNotIncluded => this == InclusionStatus.notIncluded;
}

enum FeatureGroup {
  coreEssentials('CORE ESSENTIALS'),
  nutritionAi('NUTRITION AI'),
  workoutCv('WORKOUT CV INTELLIGENCE'),
  advancedIntelligence('ADVANCED INTELLIGENCE');

  final String title;
  const FeatureGroup(this.title);
}

class MatrixFeature {
  final String id;
  final String title;
  final FeatureGroup group;
  final Map<MembershipTier, InclusionStatus> statusMap;

  const MatrixFeature({
    required this.id,
    required this.title,
    required this.group,
    required this.statusMap,
  });

  InclusionStatus statusFor(MembershipTier tier) =>
      statusMap[tier] ?? InclusionStatus.notIncluded;
}

class PlannedBenefit {
  final IconData icon;
  final String title;
  final String description;
  final bool isPlanned;

  const PlannedBenefit({
    required this.icon,
    required this.title,
    required this.description,
    this.isPlanned = true,
  });
}

class InheritedBenefitItem {
  final String title;
  final bool isPlanned; // false: check, true: schedule

  const InheritedBenefitItem({
    required this.title,
    this.isPlanned = false,
  });
}

class InheritedBenefitGroup {
  final String? groupTitle;
  final List<InheritedBenefitItem> items;

  const InheritedBenefitGroup({
    this.groupTitle,
    required this.items,
  });
}

class MembershipPlan {
  final MembershipTier tier;
  final String name;
  final String subtitle;
  final String heroDescription;
  final int monthlyPrice;
  final int yearlyPrice;
  final int yearlyEquivalentMonthlyPrice;
  final bool isRecommended;
  final bool isCurrent;
  final IconData icon;
  final List<PlannedBenefit> plannedBenefits;
  final String aiAllowanceText;
  final String? workoutCvAllowanceText;
  final String allowanceSubtext;
  final String inheritedSectionTitle;
  final String inheritedSectionSubtitle;
  final List<InheritedBenefitGroup> inheritedGroups;
  final String availabilityNotice;

  const MembershipPlan({
    required this.tier,
    required this.name,
    required this.subtitle,
    required this.heroDescription,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.yearlyEquivalentMonthlyPrice,
    this.isRecommended = false,
    this.isCurrent = false,
    required this.icon,
    required this.plannedBenefits,
    required this.aiAllowanceText,
    this.workoutCvAllowanceText,
    required this.allowanceSubtext,
    required this.inheritedSectionTitle,
    required this.inheritedSectionSubtitle,
    required this.inheritedGroups,
    required this.availabilityNotice,
  });

  int priceFor(BillingPeriod period) =>
      period.isMonthly ? monthlyPrice : yearlyPrice;

  String priceDisplay(BillingPeriod period) => '\$${priceFor(period)}';

  String unitDisplay(BillingPeriod period) =>
      period.isMonthly ? '/ month' : '/ year';

  String get yearlyEquivalentText =>
      'Equivalent to \$$yearlyEquivalentMonthlyPrice / month';
}

class MembershipCatalog {
  const MembershipCatalog._();

  static const List<MembershipPlan> plans = [
    // 1. FREE
    MembershipPlan(
      tier: MembershipTier.free,
      name: 'Free',
      subtitle: 'Core essentials',
      heroDescription:
          'Everyday food tracking, workout logging, and basic health metrics.',
      monthlyPrice: 0,
      yearlyPrice: 0,
      yearlyEquivalentMonthlyPrice: 0,
      isCurrent: true,
      icon: Icons.check_circle_outline,
      plannedBenefits: [],
      aiAllowanceText: 'Included baseline',
      allowanceSubtext: 'Standard free access.',
      inheritedSectionTitle: '',
      inheritedSectionSubtitle: '',
      inheritedGroups: [],
      availabilityNotice: 'Included with your free Saman account.',
    ),

    // 2. PLUS
    MembershipPlan(
      tier: MembershipTier.plus,
      name: 'Plus',
      subtitle: 'Nutrition AI',
      heroDescription:
          'A planned step beyond everyday food tracking, with Gemini food photo analysis.',
      monthlyPrice: 10,
      yearlyPrice: 60,
      yearlyEquivalentMonthlyPrice: 5,
      icon: Icons.restaurant,
      plannedBenefits: [
        PlannedBenefit(
          icon: Icons.photo_camera_outlined,
          title: 'Gemini food photo analysis',
          description: 'Planned Gemini-powered analysis of food photos.',
        ),
        PlannedBenefit(
          icon: Icons.auto_awesome,
          title: 'Monthly AI allowance',
          description: 'A planned monthly allowance for Nutrition AI.',
        ),
      ],
      aiAllowanceText: 'To be announced',
      allowanceSubtext: 'Monthly limits will be confirmed before launch.',
      inheritedSectionTitle: 'Everything in Free',
      inheritedSectionSubtitle:
          'Nutrition logging, manual workouts, and basic tracking.',
      inheritedGroups: [
        InheritedBenefitGroup(
          groupTitle: null,
          items: [
            InheritedBenefitItem(title: 'Nutrition logging'),
            InheritedBenefitItem(title: 'Manual workout tracking'),
            InheritedBenefitItem(title: 'Free food photo analysis'),
            InheritedBenefitItem(title: 'Basic health metrics'),
          ],
        ),
      ],
      availabilityNotice:
          'Plus is not available yet. Planned features, limits, and pricing may change before launch.',
    ),

    // 3. PRO
    MembershipPlan(
      tier: MembershipTier.pro,
      name: 'Pro',
      subtitle: 'Workout Intelligence',
      heroDescription:
          'Planned movement analysis and rep counting, alongside Nutrition AI.',
      monthlyPrice: 15,
      yearlyPrice: 120,
      yearlyEquivalentMonthlyPrice: 10,
      isRecommended: true,
      icon: Icons.fitness_center,
      plannedBenefits: [
        PlannedBenefit(
          icon: Icons.visibility_outlined,
          title: 'Workout CV AI',
          description:
              'Planned computer-vision support for workout movement analysis.',
        ),
        PlannedBenefit(
          icon: Icons.fitness_center,
          title: 'Movement analysis and rep counting',
          description:
              'Planned tools to analyze movement and count repetitions.',
        ),
        PlannedBenefit(
          icon: Icons.donut_small_outlined,
          title: 'Separate Workout CV allowance',
          description:
              'A dedicated allowance for Workout CV, separate from Nutrition AI.',
        ),
      ],
      aiAllowanceText: 'To be announced',
      workoutCvAllowanceText: 'To be announced',
      allowanceSubtext:
          'AI and Workout CV limits will be confirmed before launch.',
      inheritedSectionTitle: 'Everything in Plus',
      inheritedSectionSubtitle: 'Free essentials and planned Nutrition AI.',
      inheritedGroups: [
        InheritedBenefitGroup(
          groupTitle: 'Free Essentials',
          items: [
            InheritedBenefitItem(title: 'Nutrition logging'),
            InheritedBenefitItem(title: 'Manual workout tracking'),
            InheritedBenefitItem(title: 'Free food photo analysis'),
            InheritedBenefitItem(title: 'Basic health metrics'),
          ],
        ),
        InheritedBenefitGroup(
          groupTitle: 'Planned Nutrition AI',
          items: [
            InheritedBenefitItem(
              title: 'Gemini food photo analysis',
              isPlanned: true,
            ),
            InheritedBenefitItem(
              title: 'Monthly AI allowance',
              isPlanned: true,
            ),
          ],
        ),
      ],
      availabilityNotice:
          'Pro is not available yet. Planned features, limits, and pricing may change before launch.',
    ),

    // 4. ULTRA
    MembershipPlan(
      tier: MembershipTier.ultra,
      name: 'Ultra',
      subtitle: 'Personalized Intelligence',
      heroDescription:
          'Planned advanced intelligence, a larger AI allowance, and more personalized context.',
      monthlyPrice: 30,
      yearlyPrice: 240,
      yearlyEquivalentMonthlyPrice: 20,
      icon: Icons.psychology_outlined,
      plannedBenefits: [
        PlannedBenefit(
          icon: Icons.bolt,
          title: '5x Pro AI allowance',
          description: 'A planned AI allowance five times the Pro tier.',
        ),
        PlannedBenefit(
          icon: Icons.psychology,
          title: 'Advanced Thinking',
          description: 'Planned advanced reasoning capabilities.',
        ),
        PlannedBenefit(
          icon: Icons.memory,
          title: 'Extended history and personalized memory',
          description:
              'Planned expanded history and memory for personalized context.',
        ),
      ],
      aiAllowanceText: '5x Pro · Planned',
      workoutCvAllowanceText: 'To be announced',
      allowanceSubtext:
          'Absolute limits will be confirmed before launch. The 5x multiplier applies to AI allowance, not the separate Workout CV allowance.',
      inheritedSectionTitle: 'Everything in Pro',
      inheritedSectionSubtitle:
          'Free essentials, planned Nutrition AI, and planned Workout CV.',
      inheritedGroups: [
        InheritedBenefitGroup(
          groupTitle: 'Free Essentials (Included Today)',
          items: [
            InheritedBenefitItem(title: 'Nutrition logging'),
            InheritedBenefitItem(title: 'Manual workout tracking'),
            InheritedBenefitItem(title: 'Free food photo analysis'),
            InheritedBenefitItem(title: 'Basic health metrics'),
          ],
        ),
        InheritedBenefitGroup(
          groupTitle: 'Planned Nutrition AI (From Plus)',
          items: [
            InheritedBenefitItem(
              title: 'Gemini food photo analysis',
              isPlanned: true,
            ),
            InheritedBenefitItem(
              title: 'Monthly AI allowance',
              isPlanned: true,
            ),
          ],
        ),
        InheritedBenefitGroup(
          groupTitle: 'Planned Workout Intelligence (From Pro)',
          items: [
            InheritedBenefitItem(
              title: 'Workout CV AI',
              isPlanned: true,
            ),
            InheritedBenefitItem(
              title: 'Movement analysis and rep counting',
              isPlanned: true,
            ),
            InheritedBenefitItem(
              title: 'Separate Workout CV allowance',
              isPlanned: true,
            ),
          ],
        ),
      ],
      availabilityNotice:
          'Ultra is not available yet. Planned features, limits, and pricing may change before launch.',
    ),
  ];

  static MembershipPlan getPlan(MembershipTier tier) {
    return plans.firstWhere(
      (plan) => plan.tier == tier,
      orElse: () => plans.first,
    );
  }

  static const List<MatrixFeature> matrixFeatures = [
    // Group 1: Core Essentials
    MatrixFeature(
      id: 'nutrition_logging',
      title: 'Nutrition logging',
      group: FeatureGroup.coreEssentials,
      statusMap: {
        MembershipTier.free: InclusionStatus.included,
        MembershipTier.plus: InclusionStatus.included,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
    MatrixFeature(
      id: 'manual_workouts',
      title: 'Manual workouts',
      group: FeatureGroup.coreEssentials,
      statusMap: {
        MembershipTier.free: InclusionStatus.included,
        MembershipTier.plus: InclusionStatus.included,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
    MatrixFeature(
      id: 'free_food_photo_model',
      title: 'Free food photo model',
      group: FeatureGroup.coreEssentials,
      statusMap: {
        MembershipTier.free: InclusionStatus.included,
        MembershipTier.plus: InclusionStatus.included,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
    MatrixFeature(
      id: 'basic_health_metrics',
      title: 'Basic health metrics',
      group: FeatureGroup.coreEssentials,
      statusMap: {
        MembershipTier.free: InclusionStatus.included,
        MembershipTier.plus: InclusionStatus.included,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),

    // Group 2: Nutrition AI
    MatrixFeature(
      id: 'gemini_food_analysis',
      title: 'Gemini food analysis',
      group: FeatureGroup.nutritionAi,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.planned,
        MembershipTier.pro: InclusionStatus.planned,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),
    MatrixFeature(
      id: 'monthly_ai_allowance',
      title: 'Monthly AI allowance',
      group: FeatureGroup.nutritionAi,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.planned,
        MembershipTier.pro: InclusionStatus.planned,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),

    // Group 3: Workout CV Intelligence
    MatrixFeature(
      id: 'workout_cv_ai',
      title: 'Workout CV AI',
      group: FeatureGroup.workoutCv,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.planned,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),
    MatrixFeature(
      id: 'movement_rep_counting',
      title: 'Movement analysis & rep counting',
      group: FeatureGroup.workoutCv,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.planned,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),
    MatrixFeature(
      id: 'separate_cv_allowance',
      title: 'Separate CV allowance',
      group: FeatureGroup.workoutCv,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.planned,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),

    // Group 4: Advanced Intelligence
    MatrixFeature(
      id: 'advanced_thinking',
      title: 'Advanced Thinking',
      group: FeatureGroup.advancedIntelligence,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.notIncluded,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),
    MatrixFeature(
      id: 'extended_history_memory',
      title: 'Extended history & memory',
      group: FeatureGroup.advancedIntelligence,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.notIncluded,
        MembershipTier.ultra: InclusionStatus.planned,
      },
    ),
  ];
}

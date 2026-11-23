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
  final String currency;
  final int monthlyPrice;
  final int yearlyPrice;
  final int yearlyEquivalentMonthlyPrice;
  final bool isRecommended;
  final bool isCurrent;
  final bool purchasable;
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
    this.currency = 'VND',
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.yearlyEquivalentMonthlyPrice,
    this.isRecommended = false,
    this.isCurrent = false,
    this.purchasable = false,
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

  MembershipPlan copyWith({
    MembershipTier? tier,
    String? name,
    String? subtitle,
    String? heroDescription,
    String? currency,
    int? monthlyPrice,
    int? yearlyPrice,
    int? yearlyEquivalentMonthlyPrice,
    bool? isRecommended,
    bool? isCurrent,
    bool? purchasable,
    IconData? icon,
    List<PlannedBenefit>? plannedBenefits,
    String? aiAllowanceText,
    String? workoutCvAllowanceText,
    String? allowanceSubtext,
    String? inheritedSectionTitle,
    String? inheritedSectionSubtitle,
    List<InheritedBenefitGroup>? inheritedGroups,
    String? availabilityNotice,
  }) {
    return MembershipPlan(
      tier: tier ?? this.tier,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      heroDescription: heroDescription ?? this.heroDescription,
      currency: currency ?? this.currency,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      yearlyPrice: yearlyPrice ?? this.yearlyPrice,
      yearlyEquivalentMonthlyPrice:
          yearlyEquivalentMonthlyPrice ?? this.yearlyEquivalentMonthlyPrice,
      isRecommended: isRecommended ?? this.isRecommended,
      isCurrent: isCurrent ?? this.isCurrent,
      purchasable: purchasable ?? this.purchasable,
      icon: icon ?? this.icon,
      plannedBenefits: plannedBenefits ?? this.plannedBenefits,
      aiAllowanceText: aiAllowanceText ?? this.aiAllowanceText,
      workoutCvAllowanceText:
          workoutCvAllowanceText ?? this.workoutCvAllowanceText,
      allowanceSubtext: allowanceSubtext ?? this.allowanceSubtext,
      inheritedSectionTitle:
          inheritedSectionTitle ?? this.inheritedSectionTitle,
      inheritedSectionSubtitle:
          inheritedSectionSubtitle ?? this.inheritedSectionSubtitle,
      inheritedGroups: inheritedGroups ?? this.inheritedGroups,
      availabilityNotice: availabilityNotice ?? this.availabilityNotice,
    );
  }

  static String formatVnd(int amount) {
    final absStr = amount.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < absStr.length; i++) {
      if (i > 0 && (absStr.length - i) % 3 == 0) {
        buf.write('.');
      }
      buf.write(absStr[i]);
    }
    return amount < 0 ? '-${buf.toString()}đ' : '${buf.toString()}đ';
  }

  bool get isVnd => currency.toUpperCase() == 'VND';

  int priceFor(BillingPeriod period) =>
      period.isMonthly ? monthlyPrice : yearlyPrice;

  String priceDisplay(BillingPeriod period) =>
      isVnd ? formatVnd(priceFor(period)) : '\$${priceFor(period)}';

  String unitDisplay(BillingPeriod period) {
    if (isVnd) {
      return period.isMonthly ? '/ tháng' : '/ năm';
    }
    return period.isMonthly ? '/ month' : '/ year';
  }

  String get yearlyEquivalentText => isVnd
      ? 'Tương đương ${formatVnd(yearlyEquivalentMonthlyPrice)} / tháng'
      : 'Equivalent to \$$yearlyEquivalentMonthlyPrice / month';
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
          'Ghi nhận dinh dưỡng, lịch tập thủ công và 1 ảnh món ăn mỗi ngày.',
      currency: 'VND',
      monthlyPrice: 0,
      yearlyPrice: 0,
      yearlyEquivalentMonthlyPrice: 0,
      isCurrent: true,
      purchasable: false,
      icon: Icons.check_circle_outline,
      plannedBenefits: [],
      aiAllowanceText: '1 ảnh/ngày · 5 Swift 3/ngày',
      allowanceSubtext: 'Hạn mức miễn phí hàng ngày cho tài khoản Saman.',
      inheritedSectionTitle: '',
      inheritedSectionSubtitle: '',
      inheritedGroups: [],
      availabilityNotice: 'Đã bao gồm trong tài khoản Saman miễn phí.',
    ),

    // 2. PLUS
    MembershipPlan(
      tier: MembershipTier.plus,
      name: 'Plus',
      subtitle: 'Nutrition AI',
      heroDescription:
          'Mở khóa phân tích ảnh món ăn bằng Gemini (5 ảnh/ngày), Swift 3 (30/ngày) và Core 3 (10/ngày).',
      currency: 'VND',
      monthlyPrice: 59000,
      yearlyPrice: 588000,
      yearlyEquivalentMonthlyPrice: 49000,
      purchasable: true,
      icon: Icons.restaurant,
      plannedBenefits: [
        PlannedBenefit(
          icon: Icons.photo_camera_outlined,
          title: 'Gemini food photo analysis',
          description: 'Phân tích ảnh món ăn chính xác bằng Gemini (5 ảnh/ngày).',
          isPlanned: false,
        ),
        PlannedBenefit(
          icon: Icons.auto_awesome,
          title: 'Daily AI allowance',
          description: '30 lượt Swift 3 và 10 lượt Core 3 mỗi ngày cùng Saman Coach.',
          isPlanned: false,
        ),
      ],
      aiAllowanceText: '5 ảnh/ngày · 30 Swift 3 · 10 Core 3',
      allowanceSubtext: 'Làm mới mỗi ngày theo giờ Việt Nam (GMT+7).',
      inheritedSectionTitle: 'Everything in Free',
      inheritedSectionSubtitle:
          'Nutrition logging, manual workouts, and basic tracking.',
      inheritedGroups: [
        InheritedBenefitGroup(
          groupTitle: null,
          items: [
            InheritedBenefitItem(title: 'Nutrition logging'),
            InheritedBenefitItem(title: 'Manual workout tracking'),
            InheritedBenefitItem(title: 'Free food photo analysis (1/ngày)'),
            InheritedBenefitItem(title: 'Basic health metrics'),
          ],
        ),
      ],
      availabilityNotice:
          'Kích hoạt ngay sau khi thanh toán VietQR · Nutrition AI & Saman Coach.',
    ),

    // 3. PRO
    MembershipPlan(
      tier: MembershipTier.pro,
      name: 'Pro',
      subtitle: 'Workout Intelligence',
      heroDescription:
          'Workout CV AI đếm rep không giới hạn cùng Nutrition AI (10 ảnh/ngày) và Core 3 (30/ngày).',
      currency: 'VND',
      monthlyPrice: 119000,
      yearlyPrice: 1188000,
      yearlyEquivalentMonthlyPrice: 99000,
      isRecommended: true,
      purchasable: true,
      icon: Icons.fitness_center,
      plannedBenefits: [
        PlannedBenefit(
          icon: Icons.visibility_outlined,
          title: 'Workout CV AI',
          description:
              'Nhận diện chuyển động và phân tích kỹ thuật bài tập bằng camera.',
          isPlanned: false,
        ),
        PlannedBenefit(
          icon: Icons.fitness_center,
          title: 'Movement analysis and rep counting',
          description:
              'Đếm rep tự động và chấm điểm biên độ chuyển động theo thời gian thực.',
          isPlanned: false,
        ),
        PlannedBenefit(
          icon: Icons.donut_small_outlined,
          title: 'Unlimited Workout CV allowance',
          description:
              'Sử dụng Workout CV AI không giới hạn, cùng 10 ảnh Nutrition AI/ngày.',
          isPlanned: false,
        ),
      ],
      aiAllowanceText: '10 ảnh/ngày · 50 Swift 3 · 30 Core 3',
      workoutCvAllowanceText: 'Không giới hạn',
      allowanceSubtext:
          'Bao gồm Workout CV không giới hạn và Nutrition AI hàng ngày.',
      inheritedSectionTitle: 'Everything in Plus',
      inheritedSectionSubtitle: 'Free essentials and Nutrition AI.',
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
          groupTitle: 'Nutrition AI (From Plus)',
          items: [
            InheritedBenefitItem(
              title: 'Gemini food photo analysis (10/ngày)',
              isPlanned: false,
            ),
            InheritedBenefitItem(
              title: 'Daily AI allowance (50 Swift 3 · 30 Core 3)',
              isPlanned: false,
            ),
          ],
        ),
      ],
      availabilityNotice:
          'Gói khuyên dùng · Mở khóa không giới hạn Workout CV AI & Nutrition AI.',
    ),

    // 4. ULTRA
    MembershipPlan(
      tier: MembershipTier.ultra,
      name: 'Ultra',
      subtitle: 'Personalized Intelligence',
      heroDescription:
          'Mở khóa Pro 3 (15 lượt/ngày), Suy luận nâng cao, Bộ nhớ dài hạn và 20 ảnh món ăn/ngày.',
      currency: 'VND',
      monthlyPrice: 199000,
      yearlyPrice: 2028000,
      yearlyEquivalentMonthlyPrice: 169000,
      purchasable: true,
      icon: Icons.psychology_outlined,
      plannedBenefits: [
        PlannedBenefit(
          icon: Icons.bolt,
          title: 'Pro 3 & 20 ảnh Nutrition AI/ngày',
          description: '15 lượt Pro 3/ngày cùng 20 ảnh phân tích món ăn bằng Gemini.',
          isPlanned: false,
        ),
        PlannedBenefit(
          icon: Icons.psychology,
          title: 'Advanced Thinking',
          description: 'Khả năng suy luận chuyên sâu với mô hình Pro 3.',
          isPlanned: false,
        ),
        PlannedBenefit(
          icon: Icons.memory,
          title: 'Extended history and personalized memory',
          description:
              'Lưu trữ lịch sử dài hạn và cá nhân hóa ngữ cảnh tập luyện.',
          isPlanned: false,
        ),
      ],
      aiAllowanceText: '20 ảnh/ngày · 15 Pro 3/ngày',
      workoutCvAllowanceText: 'Không giới hạn',
      allowanceSubtext:
          'Bao gồm toàn bộ tính năng Pro 3, Suy luận nâng cao và Bộ nhớ dài hạn.',
      inheritedSectionTitle: 'Everything in Pro',
      inheritedSectionSubtitle:
          'Free essentials, Nutrition AI, and Unlimited Workout CV.',
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
          groupTitle: 'Nutrition AI (From Plus)',
          items: [
            InheritedBenefitItem(
              title: 'Gemini food photo analysis (20/ngày)',
              isPlanned: false,
            ),
            InheritedBenefitItem(
              title: 'Daily AI allowance (50 Swift 3 · 30 Core 3 · 15 Pro 3)',
              isPlanned: false,
            ),
          ],
        ),
        InheritedBenefitGroup(
          groupTitle: 'Workout Intelligence (From Pro)',
          items: [
            InheritedBenefitItem(
              title: 'Workout CV AI',
              isPlanned: false,
            ),
            InheritedBenefitItem(
              title: 'Movement analysis and rep counting',
              isPlanned: false,
            ),
            InheritedBenefitItem(
              title: 'Unlimited Workout CV allowance',
              isPlanned: false,
            ),
          ],
        ),
      ],
      availabilityNotice:
          'Gói cao cấp nhất · Mở khóa Pro 3, Suy luận nâng cao và Bộ nhớ dài hạn.',
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
        MembershipTier.plus: InclusionStatus.included,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
    MatrixFeature(
      id: 'monthly_ai_allowance',
      title: 'Daily AI allowance',
      group: FeatureGroup.nutritionAi,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.included,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
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
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
    MatrixFeature(
      id: 'movement_rep_counting',
      title: 'Movement analysis & rep counting',
      group: FeatureGroup.workoutCv,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
    MatrixFeature(
      id: 'separate_cv_allowance',
      title: 'Unlimited CV allowance',
      group: FeatureGroup.workoutCv,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.included,
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),

    // Group 4: Advanced Intelligence
    MatrixFeature(
      id: 'advanced_thinking',
      title: 'Pro 3 & Advanced Thinking',
      group: FeatureGroup.advancedIntelligence,
      statusMap: {
        MembershipTier.free: InclusionStatus.notIncluded,
        MembershipTier.plus: InclusionStatus.notIncluded,
        MembershipTier.pro: InclusionStatus.notIncluded,
        MembershipTier.ultra: InclusionStatus.included,
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
        MembershipTier.ultra: InclusionStatus.included,
      },
    ),
  ];
}

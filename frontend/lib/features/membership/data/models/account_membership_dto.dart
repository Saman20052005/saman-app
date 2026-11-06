import '../../domain/models/membership_plan.dart';

/// Data Transfer Object for current authenticated user membership & quota usage.
/// Maps backend GET /api/revenue/membership/me.
/// Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-06).

class BenefitUsageDto {
  final String benefitId;
  final int consumedUnits;
  final int reservedUnits;
  final int remainingUnits;
  final int limitUnits;
  final String periodKey;
  final DateTime? resetAt;

  const BenefitUsageDto({
    required this.benefitId,
    required this.consumedUnits,
    required this.reservedUnits,
    required this.remainingUnits,
    required this.limitUnits,
    required this.periodKey,
    this.resetAt,
  });

  factory BenefitUsageDto.fromJson(Map<String, dynamic> json) {
    DateTime? rAt;
    if (json['reset_at'] != null) {
      rAt = DateTime.tryParse(json['reset_at'].toString());
    }
    return BenefitUsageDto(
      benefitId: json['benefit_id'] as String? ?? '',
      consumedUnits: (json['consumed_units'] as num?)?.toInt() ?? 0,
      reservedUnits: (json['reserved_units'] as num?)?.toInt() ?? 0,
      remainingUnits: (json['remaining_units'] as num?)?.toInt() ?? 0,
      limitUnits: (json['limit_units'] as num?)?.toInt() ?? 0,
      periodKey: json['period_key'] as String? ?? '',
      resetAt: rAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'benefit_id': benefitId,
        'consumed_units': consumedUnits,
        'reserved_units': reservedUnits,
        'remaining_units': remainingUnits,
        'limit_units': limitUnits,
        'period_key': periodKey,
        if (resetAt != null) 'reset_at': resetAt!.toIso8601String(),
      };
}

class AccountMembershipDto {
  final String userId;
  final String? accountId;
  final MembershipTier tier;
  final String status;
  final bool isActiveSubscription;
  final DateTime? currentPeriodEnd;
  final bool autoRenewStatus;
  final bool inGracePeriod;
  final DateTime? gracePeriodExpiresAt;
  final bool cancelAtPeriodEnd;
  final String? ownershipStatus;
  final String? opaqueAppUserId;
  final List<Map<String, dynamic>> entitlements;
  final Map<String, BenefitUsageDto> usage;
  final DateTime asOf;

  const AccountMembershipDto({
    required this.userId,
    this.accountId,
    required this.tier,
    required this.status,
    required this.isActiveSubscription,
    this.currentPeriodEnd,
    this.autoRenewStatus = true,
    this.inGracePeriod = false,
    this.gracePeriodExpiresAt,
    this.cancelAtPeriodEnd = false,
    this.ownershipStatus,
    this.opaqueAppUserId,
    required this.entitlements,
    required this.usage,
    required this.asOf,
  });

  factory AccountMembershipDto.fromJson(Map<String, dynamic> json) {
    MembershipTier mTier = MembershipTier.free;
    final rawTier = json['tier']?.toString().toLowerCase();
    if (rawTier == 'plus') {
      mTier = MembershipTier.plus;
    } else if (rawTier == 'pro') {
      mTier = MembershipTier.pro;
    } else if (rawTier == 'ultra') {
      mTier = MembershipTier.ultra;
    }

    DateTime? pEnd;
    if (json['current_period_end'] != null) {
      pEnd = DateTime.tryParse(json['current_period_end'].toString());
    }

    DateTime? gEnd;
    if (json['grace_period_expires_at'] != null) {
      gEnd = DateTime.tryParse(json['grace_period_expires_at'].toString());
    }

    DateTime asOfDate = DateTime.now();
    if (json['as_of'] != null) {
      asOfDate = DateTime.tryParse(json['as_of'].toString()) ?? DateTime.now();
    }

    final rawEntitlements = json['entitlements'] as List<dynamic>? ?? [];
    final entitlementsList = rawEntitlements
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final rawUsage = json['usage'] as Map<dynamic, dynamic>? ?? {};
    final usageMap = <String, BenefitUsageDto>{};
    rawUsage.forEach((key, val) {
      if (val is Map) {
        usageMap[key.toString()] =
            BenefitUsageDto.fromJson(Map<String, dynamic>.from(val));
      }
    });

    return AccountMembershipDto(
      userId: json['user_id'] as String? ?? '',
      accountId: json['account_id'] as String?,
      tier: mTier,
      status: json['status'] as String? ?? 'none',
      isActiveSubscription: json['is_active_subscription'] as bool? ?? false,
      currentPeriodEnd: pEnd,
      autoRenewStatus: json['auto_renew_status'] as bool? ?? true,
      inGracePeriod: json['in_grace_period'] as bool? ?? false,
      gracePeriodExpiresAt: gEnd,
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      ownershipStatus: json['ownership_status'] as String?,
      opaqueAppUserId: json['opaque_app_user_id'] as String?,
      entitlements: entitlementsList,
      usage: usageMap,
      asOf: asOfDate,
    );
  }

  /// Safe default baseline Free entitlement state.
  factory AccountMembershipDto.defaultFree([String? userId]) {
    return AccountMembershipDto(
      userId: userId ?? '',
      tier: MembershipTier.free,
      status: 'none',
      isActiveSubscription: false,
      currentPeriodEnd: null,
      autoRenewStatus: false,
      inGracePeriod: false,
      gracePeriodExpiresAt: null,
      cancelAtPeriodEnd: false,
      ownershipStatus: null,
      entitlements: const [],
      usage: const {
        'ai.nutrition_gemini': BenefitUsageDto(
          benefitId: 'ai.nutrition_gemini',
          consumedUnits: 0,
          reservedUnits: 0,
          remainingUnits: 30,
          limitUnits: 30,
          periodKey: '',
        ),
      },
      asOf: DateTime.now(),
    );
  }

  BenefitUsageDto? get nutritionGeminiUsage => usage['ai.nutrition_gemini'];
}

enum MembershipStateStatus {
  loggedOut,
  demoBaseline,
  loading,
  authenticatedKnown,
  staleKnown,
  unknownError,
}

/// Comprehensive state of user membership and quota.
/// Subsystem: Saman Revenue (CP-06A).
/// Guarantees:
/// - Distinguishes authoritative Free from unknown/failure.
/// - Never treats network/storage failures as Free tier.
/// - Tracks stale cache vs unknown without cache.
/// - Enforces loggedOut != Free.
class AccountMembershipState {
  final MembershipStateStatus stateStatus;
  final AccountMembershipDto? data;
  final String? accountId;
  final DateTime? fetchedAt;
  final String? errorMessage;

  const AccountMembershipState({
    required this.stateStatus,
    this.data,
    this.accountId,
    this.fetchedAt,
    this.errorMessage,
  });

  bool get isLoggedOut => stateStatus == MembershipStateStatus.loggedOut;
  bool get isLoading => stateStatus == MembershipStateStatus.loading;
  bool get isKnown => stateStatus == MembershipStateStatus.authenticatedKnown;
  bool get isStale => stateStatus == MembershipStateStatus.staleKnown;
  bool get isUnknown => stateStatus == MembershipStateStatus.unknownError;
  bool get isDemo => stateStatus == MembershipStateStatus.demoBaseline;

  bool get hasValidData => data != null && (isKnown || isStale || isDemo);

  MembershipTier get tier => data?.tier ?? MembershipTier.free;
  String get status => data?.status ?? 'none';
  String? get opaqueAppUserId => data?.opaqueAppUserId;

  BenefitUsageDto? get nutritionGeminiUsage => data?.nutritionGeminiUsage;
  Map<String, BenefitUsageDto> get usage => data?.usage ?? const {};
  List<Map<String, dynamic>> get entitlements => data?.entitlements ?? const [];
  bool get isActiveSubscription => data?.isActiveSubscription ?? false;
  DateTime? get currentPeriodEnd => data?.currentPeriodEnd;
  bool get autoRenewStatus => data?.autoRenewStatus ?? true;
  bool get inGracePeriod => data?.inGracePeriod ?? false;
  DateTime? get gracePeriodExpiresAt => data?.gracePeriodExpiresAt;
  bool get cancelAtPeriodEnd => data?.cancelAtPeriodEnd ?? false;
  String? get ownershipStatus => data?.ownershipStatus;
  String get userId => accountId ?? data?.userId ?? '';

  factory AccountMembershipState.loggedOut() => const AccountMembershipState(
        stateStatus: MembershipStateStatus.loggedOut,
      );

  factory AccountMembershipState.demoBaseline([String? userId]) =>
      AccountMembershipState(
        stateStatus: MembershipStateStatus.demoBaseline,
        data: AccountMembershipDto.defaultFree(userId ?? 'demo_user'),
        accountId: userId ?? 'demo_user',
        fetchedAt: DateTime.now(),
      );

  factory AccountMembershipState.loading(
          {AccountMembershipDto? previousData, String? accountId}) =>
      AccountMembershipState(
        stateStatus: MembershipStateStatus.loading,
        data: previousData,
        accountId: accountId,
      );

  factory AccountMembershipState.known(AccountMembershipDto data,
          {DateTime? fetchedAt}) =>
      AccountMembershipState(
        stateStatus: MembershipStateStatus.authenticatedKnown,
        data: data,
        accountId: data.userId,
        fetchedAt: fetchedAt ?? DateTime.now(),
      );

  factory AccountMembershipState.stale(
          AccountMembershipDto cachedData, DateTime fetchedAt,
          {String? errorMessage}) =>
      AccountMembershipState(
        stateStatus: MembershipStateStatus.staleKnown,
        data: cachedData,
        accountId: cachedData.userId,
        fetchedAt: fetchedAt,
        errorMessage: errorMessage,
      );

  factory AccountMembershipState.unknownError(String message,
          {String? accountId}) =>
      AccountMembershipState(
        stateStatus: MembershipStateStatus.unknownError,
        accountId: accountId,
        errorMessage: message,
      );
}

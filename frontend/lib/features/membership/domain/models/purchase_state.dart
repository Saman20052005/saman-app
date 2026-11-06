import 'membership_plan.dart';

/// Explicit purchase lifecycle states required by CP-07 Section 5.E.
enum PurchaseFlowStatus {
  /// Payment provider/config/product is not ready or plan remains in preview mode.
  unavailable,

  /// Loading store product or initializing purchase intent.
  loading,

  /// Store payment sheet is open or transaction is pending deferred settlement (e.g., Ask to Buy / pending).
  pending,

  /// Store SDK returned a purchase proof; awaiting authoritative backend verification & membership refresh.
  verifying,

  /// Authoritative backend verification succeeded AND membership state was refreshed for the same account.
  confirmed,

  /// User or store canceled the purchase without charging or granting entitlement.
  canceled,

  /// Store, verification, or account-session check failed; no entitlement granted.
  failed,
}

/// Outcome returned by the client-side store adapter before backend verification.
/// IMPORTANT: [tokenReadyForVerification] is NEVER treated as an active membership grant.
enum StoreClientOutcomeStatus {
  unavailable,
  pending,
  canceled,
  failed,
  tokenReadyForVerification,
}

class StorePurchasePayload {
  final String provider;
  final String environment;
  final String appId;
  final String productId;
  final String verificationToken;
  final String? transactionId;
  final String? originalTransactionId;
  final String? clientRequestId;

  const StorePurchasePayload({
    required this.provider,
    required this.environment,
    required this.appId,
    required this.productId,
    required this.verificationToken,
    this.transactionId,
    this.originalTransactionId,
    this.clientRequestId,
  });

  Map<String, dynamic> toVerificationJson() {
    return {
      'provider': provider,
      'environment': environment,
      'app_id': appId,
      'product_id': productId,
      'verification_token': verificationToken,
      if (transactionId != null) 'transaction_id': transactionId,
      if (originalTransactionId != null)
        'original_transaction_id': originalTransactionId,
      if (clientRequestId != null) 'client_request_id': clientRequestId,
    };
  }
}

class StoreClientOutcome {
  final StoreClientOutcomeStatus status;
  final StorePurchasePayload? payload;
  final String? errorCode;
  final String? message;

  const StoreClientOutcome._({
    required this.status,
    this.payload,
    this.errorCode,
    this.message,
  });

  factory StoreClientOutcome.unavailable([String? message]) =>
      StoreClientOutcome._(
        status: StoreClientOutcomeStatus.unavailable,
        errorCode: 'PAYMENT_CONFIG_NOT_READY',
        message: message ??
            'Payment provider and store products are not yet configured.',
      );

  factory StoreClientOutcome.pending([String? message]) =>
      StoreClientOutcome._(
        status: StoreClientOutcomeStatus.pending,
        message: message ?? 'Purchase is pending store confirmation.',
      );

  factory StoreClientOutcome.canceled([String? message]) =>
      StoreClientOutcome._(
        status: StoreClientOutcomeStatus.canceled,
        message: message ?? 'Purchase was canceled.',
      );

  factory StoreClientOutcome.failed({String? errorCode, String? message}) =>
      StoreClientOutcome._(
        status: StoreClientOutcomeStatus.failed,
        errorCode: errorCode ?? 'STORE_PURCHASE_FAILED',
        message: message ?? 'Store purchase failed.',
      );

  factory StoreClientOutcome.tokenReady(StorePurchasePayload payload) =>
      StoreClientOutcome._(
        status: StoreClientOutcomeStatus.tokenReadyForVerification,
        payload: payload,
      );
}

class BackendPurchaseVerificationResult {
  final String outcome;
  final String userId;
  final String provider;
  final String environment;
  final String? transactionId;
  final String? originalTransactionId;
  final String? subscriptionId;
  final MembershipTier tier;
  final bool isActiveSubscription;
  final DateTime? currentPeriodEnd;
  final bool duplicateIgnored;
  final String? errorCode;
  final String? message;

  const BackendPurchaseVerificationResult({
    required this.outcome,
    required this.userId,
    required this.provider,
    required this.environment,
    this.transactionId,
    this.originalTransactionId,
    this.subscriptionId,
    this.tier = MembershipTier.free,
    this.isActiveSubscription = false,
    this.currentPeriodEnd,
    this.duplicateIgnored = false,
    this.errorCode,
    this.message,
  });

  factory BackendPurchaseVerificationResult.fromJson(
      Map<String, dynamic> json) {
    final tierStr = (json['tier'] as String?)?.toLowerCase() ?? 'free';
    MembershipTier parsedTier = MembershipTier.free;
    if (tierStr == 'plus') {
      parsedTier = MembershipTier.plus;
    } else if (tierStr == 'pro') {
      parsedTier = MembershipTier.pro;
    }

    return BackendPurchaseVerificationResult(
      outcome: json['outcome'] as String? ?? 'failed',
      userId: json['user_id'] as String? ?? '',
      provider: json['provider'] as String? ?? 'unconfigured',
      environment: json['environment'] as String? ?? 'sandbox',
      transactionId: json['transaction_id'] as String?,
      originalTransactionId: json['original_transaction_id'] as String?,
      subscriptionId: json['subscription_id'] as String?,
      tier: parsedTier,
      isActiveSubscription: json['is_active_subscription'] as bool? ?? false,
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.tryParse(json['current_period_end'].toString())
          : null,
      duplicateIgnored: json['duplicate_ignored'] as bool? ?? false,
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
    );
  }
}

class RestorePurchasesResult {
  final String outcome;
  final String userId;
  final String provider;
  final String environment;
  final String ownershipStatus;
  final String? transactionId;
  final String? originalTransactionId;
  final String? subscriptionId;
  final MembershipTier tier;
  final bool isActiveSubscription;
  final DateTime? currentPeriodEnd;
  final bool autoRenewStatus;
  final bool inGracePeriod;
  final DateTime? gracePeriodExpiresAt;
  final int restoredGrantsCount;
  final bool duplicateIgnored;
  final String firstOwnerPolicy;
  final String? errorCode;
  final String? message;

  const RestorePurchasesResult({
    required this.outcome,
    required this.userId,
    required this.provider,
    required this.environment,
    this.ownershipStatus = 'unresolved_conflict',
    this.transactionId,
    this.originalTransactionId,
    this.subscriptionId,
    this.tier = MembershipTier.free,
    this.isActiveSubscription = false,
    this.currentPeriodEnd,
    this.autoRenewStatus = true,
    this.inGracePeriod = false,
    this.gracePeriodExpiresAt,
    this.restoredGrantsCount = 0,
    this.duplicateIgnored = false,
    this.firstOwnerPolicy = 'PROPOSED',
    this.errorCode,
    this.message,
  });

  factory RestorePurchasesResult.fromJson(Map<String, dynamic> json) {
    final tierStr = (json['tier'] as String?)?.toLowerCase() ?? 'free';
    MembershipTier parsedTier = MembershipTier.free;
    if (tierStr == 'plus') {
      parsedTier = MembershipTier.plus;
    } else if (tierStr == 'pro') {
      parsedTier = MembershipTier.pro;
    }

    return RestorePurchasesResult(
      outcome: json['outcome'] as String? ?? 'failed',
      userId: json['user_id'] as String? ?? '',
      provider: json['provider'] as String? ?? 'unconfigured',
      environment: json['environment'] as String? ?? 'sandbox',
      ownershipStatus:
          json['ownership_status'] as String? ?? 'unresolved_conflict',
      transactionId: json['transaction_id'] as String?,
      originalTransactionId: json['original_transaction_id'] as String?,
      subscriptionId: json['subscription_id'] as String?,
      tier: parsedTier,
      isActiveSubscription: json['is_active_subscription'] as bool? ?? false,
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.tryParse(json['current_period_end'].toString())
          : null,
      autoRenewStatus: json['auto_renew_status'] as bool? ?? true,
      inGracePeriod: json['in_grace_period'] as bool? ?? false,
      gracePeriodExpiresAt: json['grace_period_expires_at'] != null
          ? DateTime.tryParse(json['grace_period_expires_at'].toString())
          : null,
      restoredGrantsCount:
          (json['restored_grants_count'] as num?)?.toInt() ?? 0,
      duplicateIgnored: json['duplicate_ignored'] as bool? ?? false,
      firstOwnerPolicy: json['first_owner_policy'] as String? ?? 'PROPOSED',
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
    );
  }
}

class PurchaseIntent {
  final String accountId;
  final MembershipPlan plan;
  final BillingPeriod billingPeriod;
  final String? productId;

  const PurchaseIntent({
    required this.accountId,
    required this.plan,
    required this.billingPeriod,
    this.productId,
  });
}

class PurchaseState {
  final PurchaseFlowStatus status;
  final String? accountId;
  final MembershipTier? targetTier;
  final BillingPeriod? billingPeriod;
  final String? transactionId;
  final String? subscriptionId;
  final String? errorCode;
  final String? message;
  final bool previewMode;

  const PurchaseState({
    required this.status,
    this.accountId,
    this.targetTier,
    this.billingPeriod,
    this.transactionId,
    this.subscriptionId,
    this.errorCode,
    this.message,
    this.previewMode = true,
  });

  factory PurchaseState.unavailable({
    String? accountId,
    MembershipTier? targetTier,
    BillingPeriod? billingPeriod,
    String? errorCode,
    String? message,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.unavailable,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        errorCode: errorCode ?? 'PAYMENT_CONFIG_NOT_READY',
        message: message ??
            'Membership plans are currently in preview mode. Purchasing is not yet enabled.',
        previewMode: true,
      );

  factory PurchaseState.loading({
    required String accountId,
    MembershipTier? targetTier,
    BillingPeriod? billingPeriod,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.loading,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        previewMode: false,
      );

  factory PurchaseState.pending({
    required String accountId,
    MembershipTier? targetTier,
    BillingPeriod? billingPeriod,
    String? transactionId,
    String? message,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.pending,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        transactionId: transactionId,
        message: message ?? 'Purchase is pending store settlement.',
        previewMode: false,
      );

  factory PurchaseState.verifying({
    required String accountId,
    MembershipTier? targetTier,
    BillingPeriod? billingPeriod,
    String? transactionId,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.verifying,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        transactionId: transactionId,
        message: 'Verifying purchase with Saman server...',
        previewMode: false,
      );

  factory PurchaseState.confirmed({
    required String accountId,
    required MembershipTier targetTier,
    BillingPeriod? billingPeriod,
    String? transactionId,
    String? subscriptionId,
    String? message,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.confirmed,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        transactionId: transactionId,
        subscriptionId: subscriptionId,
        message: message ?? 'Membership verified and activated.',
        previewMode: false,
      );

  factory PurchaseState.canceled({
    required String accountId,
    MembershipTier? targetTier,
    BillingPeriod? billingPeriod,
    String? message,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.canceled,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        message: message ?? 'Purchase canceled.',
        previewMode: false,
      );

  factory PurchaseState.failed({
    String? accountId,
    MembershipTier? targetTier,
    BillingPeriod? billingPeriod,
    String? errorCode,
    String? message,
  }) =>
      PurchaseState(
        status: PurchaseFlowStatus.failed,
        accountId: accountId,
        targetTier: targetTier,
        billingPeriod: billingPeriod,
        errorCode: errorCode ?? 'PURCHASE_FAILED',
        message: message ?? 'Purchase could not be verified.',
        previewMode: false,
      );

  bool get isGranted => status == PurchaseFlowStatus.confirmed;
}


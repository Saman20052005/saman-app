import '../models/purchase_state.dart';

/// Abstraction over the platform/store payment SDK (e.g., StoreKit, Play Billing, RevenueCat).
/// While CP-01 Decision 2 is unapproved, the default implementation is
/// [UnconfiguredStorePaymentClientAdapter], which reports `isConfigured = false`
/// and keeps the UI in preview/unavailable mode.
abstract class StorePaymentClientAdapter {
  bool get isConfigured;

  /// Launches the store purchase sheet for [intent] and returns the raw store outcome.
  /// Note: [StoreClientOutcomeStatus.tokenReadyForVerification] does NOT grant membership;
  /// it only provides the verification token for authoritative backend verification.
  Future<StoreClientOutcome> initiateStorePurchase(PurchaseIntent intent);

  /// Queries past purchases from native StoreKit/Play Billing receipts for restore.
  Future<StoreClientOutcome> queryPastPurchases();
}

class UnconfiguredStorePaymentClientAdapter
    implements StorePaymentClientAdapter {
  const UnconfiguredStorePaymentClientAdapter();

  @override
  bool get isConfigured => false;

  @override
  Future<StoreClientOutcome> initiateStorePurchase(
      PurchaseIntent intent) async {
    return StoreClientOutcome.unavailable(
      'Payment provider is not yet configured. Plans remain in preview mode.',
    );
  }

  @override
  Future<StoreClientOutcome> queryPastPurchases() async {
    return StoreClientOutcome.unavailable(
      'Payment provider is not yet configured. Live restore is unavailable.',
    );
  }
}

/// Repository boundary for membership purchase execution and backend verification.
abstract class PaymentRepository {
  bool get isPaymentConfigured;

  Future<StoreClientOutcome> startStorePurchase(PurchaseIntent intent);

  Future<BackendPurchaseVerificationResult> verifyPurchaseWithBackend(
    StorePurchasePayload payload,
  );

  Future<StoreClientOutcome> startStoreRestore();

  Future<RestorePurchasesResult> restorePurchasesWithBackend(
    StorePurchasePayload payload,
  );
}


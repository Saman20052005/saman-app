import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../domain/models/membership_plan.dart';
import '../../domain/models/purchase_state.dart';
import '../../domain/repositories/payment_repository.dart';

final RegExp _rcCustomerIdPattern = RegExp(r'^rc_cus_[0-9a-f]{32}$');

/// Validates that an App User ID is a server-issued random RevenueCat customer ID
/// (`rc_cus_<32-hex>`). Rejects raw emails (`@`), RevenueCat anonymous IDs
/// (`$RCAnonymousID:`), and retired R02 email-hash IDs (`saman_usr_*`).
bool isValidRevenueCatAppUserId(String? value) {
  if (value == null) return false;
  final cleaned = value.trim();
  if (cleaned.isEmpty ||
      cleaned.contains('@') ||
      cleaned.startsWith(r'$RCAnonymousID:') ||
      cleaned.toLowerCase().startsWith('saman_usr_')) {
    return false;
  }
  return _rcCustomerIdPattern.hasMatch(cleaned);
}

/// Abstract delegate to decouple RevenueCat SDK interactions for testability
/// and fallback on unsupported desktop/web platforms.
abstract class IRevenueCatPurchasesClient {
  Future<bool> get isConfigured;
  Future<void> configure(String apiKey, {String? appUserID});
  Future<String> getAppUserID();
  Future<void> logIn(String appUserID);
  Future<void> logOut();
  Future<CustomerInfo> purchaseProduct(String productIdentifier);
  Future<CustomerInfo> restorePurchases();
}

/// Default production delegate that forwards calls to native `Purchases`.
class DefaultRevenueCatPurchasesClient implements IRevenueCatPurchasesClient {
  const DefaultRevenueCatPurchasesClient();

  @override
  Future<bool> get isConfigured => Purchases.isConfigured;

  @override
  Future<void> configure(String apiKey, {String? appUserID}) async {
    final configuration = PurchasesConfiguration(apiKey)
      ..appUserID = appUserID;
    await Purchases.configure(configuration);
  }

  @override
  Future<String> getAppUserID() => Purchases.appUserID;

  @override
  Future<void> logIn(String appUserID) async {
    await Purchases.logIn(appUserID);
  }

  @override
  Future<void> logOut() async {
    await Purchases.logOut();
  }

  @override
  Future<CustomerInfo> purchaseProduct(String productIdentifier) async {
    try {
      final products = await Purchases.getProducts([productIdentifier]);
      if (products.isNotEmpty) {
        final result = await Purchases.purchase(
          PurchaseParams.storeProduct(products.first),
        );
        return result.customerInfo;
      }
    } catch (_) {}
    // ignore: deprecated_member_use
    final fallbackResult = await Purchases.purchaseProduct(productIdentifier);
    return fallbackResult.customerInfo;
  }

  @override
  Future<CustomerInfo> restorePurchases() => Purchases.restorePurchases();
}

/// RevenueCat client-side payment adapter implementing [StorePaymentClientAdapter] (REVENUE-R02A / REVENUE-R03).
///
/// Invariants enforced:
/// - Client NEVER hashes email or generates its own RevenueCat App User ID.
/// - Requires a server-owned `rc_cus_<32-hex>` customer ID obtained from authenticated
///   backend `/api/revenue/membership/me` and bound to the active account.
/// - Client outcomes (including tokenReady) NEVER self-activate membership; they
///   provide proof for backend `/api/revenue/purchases/verify`.
/// - Live restore separates three required gates:
///   1) `isRestorePolicyApproved` (business policy approval),
///   2) `isRestoreBehaviorVerified` (dashboard setting verified), and
///   3) `configuredRestoreBehavior == 'keep_with_original_app_user_id'`
///      (never `transfer_to_new_app_user_id` or `transfer_if_no_active_subscription`).
///   Until all three are satisfied, live restore fails closed (`unavailable`).
/// - Unconfigured or missing credentials fail closed to `unavailable` mode.
class RevenueCatStorePaymentClientAdapter implements StorePaymentClientAdapter {
  final IRevenueCatPurchasesClient _client;
  String _environment;
  String _defaultAppId;
  String? _apiKey;
  String? _currentAppUserId;
  String? _boundAccountId;
  bool _isConfigured = false;
  bool _isRestorePolicyApproved;
  bool _isRestoreBehaviorVerified;
  String _configuredRestoreBehavior;

  RevenueCatStorePaymentClientAdapter({
    IRevenueCatPurchasesClient? client,
    String? apiKey,
    String? appUserId,
    String? boundAccountId,
    String environment = 'sandbox',
    String defaultAppId = 'com.saman.health',
    bool isRestorePolicyVerified = false,
    bool? isRestorePolicyApproved,
    bool? isRestoreBehaviorVerified,
    String? configuredRestoreBehavior,
  })  : _client = client ?? const DefaultRevenueCatPurchasesClient(),
        _apiKey = apiKey,
        _currentAppUserId =
            isValidRevenueCatAppUserId(appUserId) ? appUserId!.trim() : null,
        _boundAccountId = boundAccountId?.trim(),
        _environment = environment,
        _defaultAppId = defaultAppId,
        _isRestorePolicyApproved =
            isRestorePolicyApproved ?? isRestorePolicyVerified,
        _isRestoreBehaviorVerified =
            isRestoreBehaviorVerified ?? isRestorePolicyVerified,
        _configuredRestoreBehavior = (configuredRestoreBehavior ??
                (isRestorePolicyVerified
                    ? 'keep_with_original_app_user_id'
                    : 'unverified'))
            .trim()
            .toLowerCase() {
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      _isConfigured = true;
    }
  }

  @override
  bool get isConfigured =>
      _isConfigured && (_apiKey != null && _apiKey!.trim().isNotEmpty);

  bool get isRestorePolicyApproved => _isRestorePolicyApproved;
  bool get isRestoreBehaviorVerified => _isRestoreBehaviorVerified;
  String get configuredRestoreBehavior => _configuredRestoreBehavior;
  bool get isRestorePolicyVerified =>
      _isRestorePolicyApproved &&
      _isRestoreBehaviorVerified &&
      _configuredRestoreBehavior == 'keep_with_original_app_user_id';
  String? get apiKey => _apiKey;
  String? get currentAppUserId => _currentAppUserId;
  String? get boundAccountId => _boundAccountId;
  String get environment => _environment;
  String get defaultAppId => _defaultAppId;

  String get restoreUnavailableReason {
    if (!_isRestorePolicyApproved) {
      return 'RevenueCat restore policy is not yet business-approved (RESTORE_POLICY_NOT_APPROVED).';
    }
    if (!_isRestoreBehaviorVerified) {
      return 'RevenueCat restore behavior policy is not yet verified in dashboard configuration (RESTORE_DASHBOARD_NOT_VERIFIED).';
    }
    if (_configuredRestoreBehavior != 'keep_with_original_app_user_id') {
      return "RevenueCat restore behavior '$_configuredRestoreBehavior' is blocked; required 'keep_with_original_app_user_id' to prevent cross-account transfer (RESTORE_BEHAVIOR_MUST_KEEP_ORIGINAL).";
    }
    return 'Restore policy and dashboard keep_with_original_app_user_id verified.';
  }

  /// Initializes the RevenueCat SDK with the public API key and optional
  /// server-issued `rc_cus_<32-hex>` customer ID.
  Future<void> configure({
    required String apiKey,
    String? appUserId,
    String? boundAccountId,
    String? environment,
    String? defaultAppId,
    bool? isRestorePolicyVerified,
    bool? isRestorePolicyApproved,
    bool? isRestoreBehaviorVerified,
    String? configuredRestoreBehavior,
  }) async {
    if (apiKey.trim().isEmpty) {
      _isConfigured = false;
      _apiKey = null;
      return;
    }
    if (environment != null && environment.trim().isNotEmpty) {
      _environment = environment.trim();
    }
    if (defaultAppId != null && defaultAppId.trim().isNotEmpty) {
      _defaultAppId = defaultAppId.trim();
    }
    if (isRestorePolicyVerified != null) {
      _isRestorePolicyApproved = isRestorePolicyVerified;
      _isRestoreBehaviorVerified = isRestorePolicyVerified;
      _configuredRestoreBehavior = isRestorePolicyVerified
          ? 'keep_with_original_app_user_id'
          : 'unverified';
    }
    if (isRestorePolicyApproved != null) {
      _isRestorePolicyApproved = isRestorePolicyApproved;
    }
    if (isRestoreBehaviorVerified != null) {
      _isRestoreBehaviorVerified = isRestoreBehaviorVerified;
    }
    if (configuredRestoreBehavior != null &&
        configuredRestoreBehavior.trim().isNotEmpty) {
      _configuredRestoreBehavior =
          configuredRestoreBehavior.trim().toLowerCase();
    }
    if (appUserId != null && appUserId.trim().isNotEmpty) {
      if (!isValidRevenueCatAppUserId(appUserId)) {
        _isConfigured = false;
        _currentAppUserId = null;
        return;
      }
      _currentAppUserId = appUserId.trim();
    }
    if (boundAccountId != null && boundAccountId.trim().isNotEmpty) {
      _boundAccountId = boundAccountId.trim();
    }
    _apiKey = apiKey.trim();
    try {
      await _client.configure(_apiKey!, appUserID: _currentAppUserId);
      _isConfigured = true;
    } catch (e) {
      _isConfigured = false;
      if (kDebugMode) {
        debugPrint('[RevenueCatStorePaymentClientAdapter] configure error: $e');
      }
    }
  }

  /// Binds the authenticated account to the server-issued `rc_cus_<32-hex>`
  /// customer ID returned by `/api/revenue/membership/me`.
  Future<bool> bindBackendCustomerIdentity({
    required String accountId,
    required String opaqueAppUserId,
  }) async {
    final cleanAccount = accountId.trim();
    final cleanRcId = opaqueAppUserId.trim();
    if (cleanAccount.isEmpty || !isValidRevenueCatAppUserId(cleanRcId)) {
      return false;
    }
    final changed =
        _currentAppUserId != cleanRcId || _boundAccountId != cleanAccount;
    _boundAccountId = cleanAccount;
    _currentAppUserId = cleanRcId;
    if (isConfigured && changed) {
      try {
        await _client.logIn(cleanRcId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RevenueCatStorePaymentClientAdapter] logIn error: $e');
        }
      }
    }
    return true;
  }

  /// Identifies the authenticated Saman user in RevenueCat using a server-issued
  /// `rc_cus_<32-hex>` ID. Rejects raw emails or legacy `saman_usr_*` hashes.
  Future<bool> logIn(String backendAppUserId, {String? accountId}) async {
    final cleanRcId = backendAppUserId.trim();
    if (!isValidRevenueCatAppUserId(cleanRcId)) {
      return false;
    }
    _currentAppUserId = cleanRcId;
    if (accountId != null && accountId.trim().isNotEmpty) {
      _boundAccountId = accountId.trim();
    }
    if (isConfigured) {
      try {
        await _client.logIn(cleanRcId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RevenueCatStorePaymentClientAdapter] logIn error: $e');
        }
      }
    }
    return true;
  }

  /// Clears user identity on logout or account switch.
  Future<void> logOut() async {
    _currentAppUserId = null;
    _boundAccountId = null;
    if (isConfigured) {
      try {
        await _client.logOut();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RevenueCatStorePaymentClientAdapter] logOut error: $e');
        }
      }
    }
  }

  /// Resolves store product SKU from plan tier and billing period.
  String resolveProductId(PurchaseIntent intent) {
    final period =
        intent.billingPeriod == BillingPeriod.yearly ? 'yearly' : 'monthly';
    switch (intent.plan.tier) {
      case MembershipTier.plus:
        return 'saman_plus_$period';
      case MembershipTier.pro:
        return 'saman_pro_$period';
      case MembershipTier.ultra:
        return 'saman_ultra_$period';
      case MembershipTier.free:
        return 'saman_free';
    }
  }

  @override
  Future<StoreClientOutcome> initiateStorePurchase(PurchaseIntent intent) async {
    if (!isConfigured) {
      return StoreClientOutcome.unavailable(
        'RevenueCat SDK is not configured. Membership plans remain in preview mode.',
      );
    }

    final accountId = intent.accountId.trim();
    if (accountId.isEmpty) {
      return StoreClientOutcome.failed(
        errorCode: 'UNAUTHENTICATED_USER',
        message: 'Must be logged in to initiate purchase.',
      );
    }

    if (_currentAppUserId == null ||
        !isValidRevenueCatAppUserId(_currentAppUserId) ||
        (_boundAccountId != null && _boundAccountId != accountId)) {
      return StoreClientOutcome.failed(
        errorCode: 'MISSING_BACKEND_CUSTOMER_IDENTITY',
        message:
            'Authoritative backend customer identity (rc_cus_*) is required before initiating purchase.',
      );
    }

    final activeRcId = _currentAppUserId!;
    final productId = resolveProductId(intent);

    try {
      final customerInfo = await _client.purchaseProduct(productId);

      final candidateOrig = customerInfo.originalAppUserId.trim();
      final token = isValidRevenueCatAppUserId(candidateOrig)
          ? candidateOrig
          : activeRcId;

      if (candidateOrig.isNotEmpty &&
          isValidRevenueCatAppUserId(candidateOrig) &&
          candidateOrig != activeRcId) {
        return StoreClientOutcome.failed(
          errorCode: 'CUSTOMER_IDENTITY_MISMATCH',
          message:
              'Store customer identity did not match the authenticated account mapping.',
        );
      }

      String? txnId;
      if (customerInfo.nonSubscriptionTransactions.isNotEmpty) {
        txnId = customerInfo
            .nonSubscriptionTransactions.last.transactionIdentifier;
      }

      return StoreClientOutcome.tokenReady(
        StorePurchasePayload(
          provider: 'revenuecat',
          environment: _environment,
          appId: _defaultAppId,
          productId: productId,
          verificationToken: token,
          transactionId: txnId,
          originalTransactionId: txnId,
          clientRequestId: 'req_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return StoreClientOutcome.canceled('Purchase was canceled by user.');
      } else if (errorCode == PurchasesErrorCode.paymentPendingError) {
        return StoreClientOutcome.pending('Payment is pending approval.');
      } else {
        return StoreClientOutcome.failed(
          errorCode: errorCode.name,
          message: e.message ?? 'Store purchase failed.',
        );
      }
    } catch (e) {
      return StoreClientOutcome.failed(
        errorCode: 'PURCHASE_FAILED',
        message: e.toString(),
      );
    }
  }

  @override
  Future<StoreClientOutcome> queryPastPurchases() async {
    if (!isConfigured) {
      return StoreClientOutcome.unavailable(
        'RevenueCat SDK is not configured. Live restore is unavailable.',
      );
    }

    if (!isRestorePolicyVerified) {
      return StoreClientOutcome.unavailable(restoreUnavailableReason);
    }

    if (_currentAppUserId == null ||
        !isValidRevenueCatAppUserId(_currentAppUserId)) {
      return StoreClientOutcome.failed(
        errorCode: 'MISSING_BACKEND_CUSTOMER_IDENTITY',
        message:
            'Authoritative backend customer identity (rc_cus_*) is required before restoring purchases.',
      );
    }

    final activeRcId = _currentAppUserId!;

    try {
      final customerInfo = await _client.restorePurchases();
      if (customerInfo.activeSubscriptions.isEmpty &&
          customerInfo.entitlements.active.isEmpty) {
        return StoreClientOutcome.failed(
          errorCode: 'NO_PURCHASES_TO_RESTORE',
          message: 'No active purchases or subscriptions found in RevenueCat.',
        );
      }

      final restoredSku = customerInfo.activeSubscriptions.isNotEmpty
          ? customerInfo.activeSubscriptions.first
          : (customerInfo.entitlements.active.values.isNotEmpty
              ? customerInfo.entitlements.active.values.first.productIdentifier
              : 'restore_query');

      final candidateOrig = customerInfo.originalAppUserId.trim();
      if (candidateOrig.isNotEmpty &&
          isValidRevenueCatAppUserId(candidateOrig) &&
          candidateOrig != activeRcId) {
        return StoreClientOutcome.failed(
          errorCode: 'CUSTOMER_IDENTITY_MISMATCH',
          message:
              'Restored customer identity does not match the active account mapping.',
        );
      }

      return StoreClientOutcome.tokenReady(
        StorePurchasePayload(
          provider: 'revenuecat',
          environment: _environment,
          appId: _defaultAppId,
          productId: restoredSku,
          verificationToken: activeRcId,
        ),
      );
    } on PlatformException catch (e) {
      return StoreClientOutcome.failed(
        errorCode: PurchasesErrorHelper.getErrorCode(e).name,
        message: e.message ?? 'Restore failed.',
      );
    } catch (e) {
      return StoreClientOutcome.failed(
        errorCode: 'RESTORE_FAILED',
        message: e.toString(),
      );
    }
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/membership/data/datasources/membership_remote_data_source.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/data/models/revenue_catalog_dto.dart';
import 'package:health_ai_app/features/membership/data/repositories/membership_repository_impl.dart';
import 'package:health_ai_app/features/membership/data/repositories/payment_repository_impl.dart';
import 'package:health_ai_app/features/membership/data/repositories/revenuecat_payment_adapter.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/domain/models/purchase_state.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const String kValidRcIdA = 'rc_cus_a1b2c3d4e5f60718293a4b5c6d7e8f90';
const String kValidRcIdB = 'rc_cus_f0e1d2c3b4a5968778695a4b3c2d1e0f';
const String kValidAcctIdA = 'acct_11112222333344445555666677778888';

CustomerInfo buildTestCustomerInfo({
  required String originalAppUserId,
  List<String> activeSubscriptions = const [],
  List<String> allPurchasedProductIdentifiers = const [],
  Map<String, dynamic> activeEntitlements = const {},
}) {
  return CustomerInfo.fromJson({
    'entitlements': {
      'all': activeEntitlements,
      'active': activeEntitlements,
      'verification': 'NOT_REQUESTED',
    },
    'allPurchaseDates': const <String, dynamic>{},
    'activeSubscriptions': activeSubscriptions,
    'allPurchasedProductIdentifiers': allPurchasedProductIdentifiers,
    'nonSubscriptionTransactions': const <dynamic>[],
    'firstSeen': '2026-10-31T00:00:00Z',
    'originalAppUserId': originalAppUserId,
    'allExpirationDates': const <String, dynamic>{},
    'requestDate': '2026-10-31T00:00:00Z',
  });
}

class FakeRevenueCatPurchasesClient implements IRevenueCatPurchasesClient {
  bool configured = false;
  String? configuredApiKey;
  String? currentUserId;
  CustomerInfo? nextCustomerInfo;
  Object? nextError;
  int logInCalls = 0;
  int logOutCalls = 0;

  @override
  Future<bool> get isConfigured async => configured;

  @override
  Future<void> configure(String apiKey, {String? appUserID}) async {
    configured = true;
    configuredApiKey = apiKey;
    currentUserId = appUserID;
  }

  @override
  Future<String> getAppUserID() async => currentUserId ?? '';

  @override
  Future<void> logIn(String appUserID) async {
    logInCalls++;
    currentUserId = appUserID;
  }

  @override
  Future<void> logOut() async {
    logOutCalls++;
    currentUserId = null;
  }

  @override
  Future<CustomerInfo> purchaseProduct(String productIdentifier) async {
    if (nextError != null) {
      final err = nextError!;
      throw err;
    }
    return nextCustomerInfo ??
        buildTestCustomerInfo(
          originalAppUserId: currentUserId ?? kValidRcIdA,
          activeSubscriptions: [productIdentifier],
        );
  }

  @override
  Future<CustomerInfo> restorePurchases() async {
    if (nextError != null) {
      final err = nextError!;
      throw err;
    }
    return nextCustomerInfo ??
        buildTestCustomerInfo(
          originalAppUserId: currentUserId ?? kValidRcIdA,
        );
  }
}

class FakeBackendRemoteDataSource implements IMembershipRemoteDataSource {
  BackendPurchaseVerificationResult? verificationResult;
  RestorePurchasesResult? restoreResult;
  AccountMembershipDto? membershipResult;
  Exception? networkException;
  int verifyCallCount = 0;
  int refreshCallCount = 0;
  StorePurchasePayload? lastVerifiedPayload;

  FakeBackendRemoteDataSource({
    this.verificationResult,
    this.restoreResult,
    this.membershipResult,
    this.networkException,
  });

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    throw UnimplementedError();
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    refreshCallCount++;
    if (networkException != null) throw networkException!;
    return membershipResult ?? AccountMembershipDto.defaultFree();
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    verifyCallCount++;
    lastVerifiedPayload = payload;
    if (networkException != null) throw networkException!;
    return verificationResult ??
        BackendPurchaseVerificationResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.ai',
          provider: payload.provider,
          environment: payload.environment,
          tier: MembershipTier.plus,
          isActiveSubscription: true,
          transactionId: payload.transactionId,
        );
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    if (networkException != null) throw networkException!;
    return restoreResult ??
        RestorePurchasesResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.ai',
          provider: payload.provider,
          environment: payload.environment,
          tier: MembershipTier.plus,
          isActiveSubscription: true,
          ownershipStatus: 'same_account_restore',
          transactionId: payload.transactionId,
        );
  }
}

MembershipPlan buildTestPlusPlan({bool purchasable = true}) {
  final base = MembershipCatalog.getPlan(MembershipTier.plus);
  return base.copyWith(purchasable: purchasable);
}

void main() {
  group('REVENUE-R02A RevenueCat Identity, Policy & Verification Tests', () {
    test(
        '1. isValidRevenueCatAppUserId accepts only server-owned rc_cus_<32-hex> and rejects emails, anonymous IDs, and legacy saman_usr_* hashes',
        () {
      expect(isValidRevenueCatAppUserId(kValidRcIdA), isTrue);
      expect(isValidRevenueCatAppUserId('  $kValidRcIdB  '), isTrue);

      // Reject raw emails, anonymous IDs, and retired R02 email hashes
      expect(isValidRevenueCatAppUserId('user_a@saman.ai'), isFalse);
      expect(isValidRevenueCatAppUserId(r'$RCAnonymousID:8796093022208'), isFalse);
      expect(isValidRevenueCatAppUserId('saman_usr_a1b2c3d4e5f60718'), isFalse);
      expect(isValidRevenueCatAppUserId('rc_cus_short'), isFalse);
      expect(isValidRevenueCatAppUserId(''), isFalse);
      expect(isValidRevenueCatAppUserId(null), isFalse);
    });

    test(
        '2. Unconfigured adapter reports isConfigured = false and returns unavailable outcome',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final adapter = RevenueCatStorePaymentClientAdapter(client: fakeClient);

      expect(adapter.isConfigured, isFalse);

      final intent = PurchaseIntent(
        accountId: 'user_a@saman.ai',
        plan: buildTestPlusPlan(),
        billingPeriod: BillingPeriod.monthly,
      );

      final outcome = await adapter.initiateStorePurchase(intent);
      expect(outcome.status, equals(StoreClientOutcomeStatus.unavailable));
      expect(outcome.errorCode, equals('PAYMENT_CONFIG_NOT_READY'));

      final restoreOutcome = await adapter.queryPastPurchases();
      expect(restoreOutcome.status, equals(StoreClientOutcomeStatus.unavailable));
    });

    test(
        '3. Configured adapter without backend-bound rc_cus_* identity fails closed and never hashes email locally',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final adapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_public_key',
        environment: 'sandbox',
      );

      // Attempting to bind email or legacy saman_usr_* fails closed
      expect(
        await adapter.bindBackendCustomerIdentity(
          accountId: 'user_a@saman.ai',
          opaqueAppUserId: 'user_a@saman.ai',
        ),
        isFalse,
      );
      expect(
        await adapter.bindBackendCustomerIdentity(
          accountId: 'user_a@saman.ai',
          opaqueAppUserId: 'saman_usr_1234567890abcdef',
        ),
        isFalse,
      );
      expect(fakeClient.logInCalls, equals(0));

      final intent = PurchaseIntent(
        accountId: 'user_a@saman.ai',
        plan: buildTestPlusPlan(),
        billingPeriod: BillingPeriod.monthly,
      );

      final outcome = await adapter.initiateStorePurchase(intent);
      expect(outcome.status, equals(StoreClientOutcomeStatus.failed));
      expect(outcome.errorCode, equals('MISSING_BACKEND_CUSTOMER_IDENTITY'));
    });

    test(
        '4. Configured adapter bound to backend rc_cus_* resolves SKUs and produces tokenReady payload',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final adapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_public_key',
        environment: 'sandbox',
      );

      final bound = await adapter.bindBackendCustomerIdentity(
        accountId: 'user_a@saman.ai',
        opaqueAppUserId: kValidRcIdA,
      );
      expect(bound, isTrue);
      expect(fakeClient.currentUserId, equals(kValidRcIdA));

      final plusMonthlyIntent = PurchaseIntent(
        accountId: 'user_a@saman.ai',
        plan: buildTestPlusPlan(),
        billingPeriod: BillingPeriod.monthly,
      );
      expect(adapter.resolveProductId(plusMonthlyIntent), equals('saman_plus_monthly'));

      final outcome = await adapter.initiateStorePurchase(plusMonthlyIntent);
      expect(outcome.status, equals(StoreClientOutcomeStatus.tokenReadyForVerification));
      expect(outcome.payload, isNotNull);
      final payload = outcome.payload!;
      expect(payload.provider, equals('revenuecat'));
      expect(payload.environment, equals('sandbox'));
      expect(payload.productId, equals('saman_plus_monthly'));
      expect(payload.verificationToken, equals(kValidRcIdA));
      expect(payload.verificationToken.contains('@'), isFalse);
    });

    test(
        '5. User cancellation maps cleanly to StoreClientOutcomeStatus.canceled',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final adapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_public_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
      );

      fakeClient.nextError = PlatformException(
        code: '${PurchasesErrorCode.purchaseCancelledError.index}',
        message: 'User cancelled',
      );

      final intent = PurchaseIntent(
        accountId: 'user_a@saman.ai',
        plan: buildTestPlusPlan(),
        billingPeriod: BillingPeriod.monthly,
      );

      final outcome = await adapter.initiateStorePurchase(intent);
      expect(outcome.status, equals(StoreClientOutcomeStatus.canceled));
      expect(outcome.message, contains('canceled by user'));
    });

    test(
        '6. Restore policy gate: queryPastPurchases returns unavailable when isRestorePolicyVerified == false, and works when verified',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final unverifiedAdapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_public_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
        isRestorePolicyVerified: false,
      );

      final blockedOutcome = await unverifiedAdapter.queryPastPurchases();
      expect(blockedOutcome.status, equals(StoreClientOutcomeStatus.unavailable));
      expect(blockedOutcome.errorCode, equals('PAYMENT_CONFIG_NOT_READY'));
      expect(blockedOutcome.message, contains('restore policy'));

      final verifiedAdapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_public_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
        isRestorePolicyVerified: true,
      );

      fakeClient.nextCustomerInfo = buildTestCustomerInfo(
        originalAppUserId: kValidRcIdA,
        activeSubscriptions: [],
      );
      final emptyRestore = await verifiedAdapter.queryPastPurchases();
      expect(emptyRestore.status, equals(StoreClientOutcomeStatus.failed));
      expect(emptyRestore.errorCode, equals('NO_PURCHASES_TO_RESTORE'));

      fakeClient.nextCustomerInfo = buildTestCustomerInfo(
        originalAppUserId: kValidRcIdA,
        activeSubscriptions: ['saman_plus_monthly'],
      );
      final activeRestore = await verifiedAdapter.queryPastPurchases();
      expect(activeRestore.status, equals(StoreClientOutcomeStatus.tokenReadyForVerification));
      expect(activeRestore.payload!.productId, equals('saman_plus_monthly'));
      expect(activeRestore.payload!.verificationToken, equals(kValidRcIdA));
    });

    test(
        '7. End-to-end purchase flow: MembershipPurchaseNotifier loads backend rc_cus_* -> RevenueCat tokenReady -> backend verify -> membership refresh -> confirmed',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final adapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_key',
      );

      final remoteDs = FakeBackendRemoteDataSource(
        verificationResult: const BackendPurchaseVerificationResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.ai',
          provider: 'revenuecat',
          environment: 'sandbox',
          tier: MembershipTier.plus,
          isActiveSubscription: true,
          transactionId: 'rc_txn_123',
        ),
        membershipResult: AccountMembershipDto(
          userId: 'user_a@saman.ai',
          accountId: kValidAcctIdA,
          opaqueAppUserId: kValidRcIdA,
          tier: MembershipTier.plus,
          status: 'active',
          isActiveSubscription: true,
          currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
          entitlements: const [
            {'benefit_id': 'ai.nutrition_gemini', 'status': 'granted'}
          ],
          usage: const {},
          asOf: DateTime.now(),
        ),
      );

      final membershipRepo = MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);

      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: adapter,
        remoteDataSource: remoteDs,
      );

      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
        storeAdapter: adapter,
      );

      final state = await purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildTestPlusPlan(purchasable: true),
          billingPeriod: BillingPeriod.monthly,
        ),
      );

      expect(state.status, equals(PurchaseFlowStatus.confirmed));
      expect(state.isGranted, isTrue);
      expect(state.targetTier, equals(MembershipTier.plus));
      expect(adapter.currentAppUserId, equals(kValidRcIdA));
      expect(remoteDs.lastVerifiedPayload?.verificationToken, equals(kValidRcIdA));
      expect(remoteDs.verifyCallCount, equals(1));
      expect(membershipNotifier.state.tier, equals(MembershipTier.plus));
      expect(membershipNotifier.state.data?.accountId, equals(kValidAcctIdA));
    });

    test(
        '8. Account switch mid-purchase logs out RevenueCat identity and aborts without granting switched account',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();
      final adapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
      );

      final remoteDs = FakeBackendRemoteDataSource(
        verificationResult: const BackendPurchaseVerificationResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.ai',
          provider: 'revenuecat',
          environment: 'sandbox',
          tier: MembershipTier.plus,
          isActiveSubscription: true,
        ),
        membershipResult: AccountMembershipDto(
          userId: 'user_a@saman.ai',
          accountId: kValidAcctIdA,
          opaqueAppUserId: kValidRcIdA,
          tier: MembershipTier.free,
          status: 'none',
          isActiveSubscription: false,
          entitlements: const [],
          usage: const {},
          asOf: DateTime.now(),
        ),
      );

      final membershipRepo = MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);
      await membershipNotifier.loadMembership(accountId: 'user_a@saman.ai');

      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: adapter,
        remoteDataSource: remoteDs,
      );

      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
        storeAdapter: adapter,
      );

      final futurePurchase = purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildTestPlusPlan(purchasable: true),
          billingPeriod: BillingPeriod.monthly,
        ),
      );

      // Switch account before purchase finishes
      purchaseNotifier.onAccountChanged('user_b@saman.ai');

      final finalState = await futurePurchase;
      expect(finalState.status, equals(PurchaseFlowStatus.failed));
      expect(finalState.errorCode, equals('ACCOUNT_SWITCHED_DURING_PURCHASE'));
      expect(adapter.currentAppUserId, isNull);
      expect(fakeClient.logOutCalls, greaterThanOrEqualTo(1));
    });

    test(
        '9. REVENUE-R03 Restore policy separation: distinguishes unapproved policy, unverified dashboard, and unsafe transfer_to_new_app_user_id from verified keep_with_original_app_user_id',
        () async {
      final fakeClient = FakeRevenueCatPurchasesClient();

      // (a) Policy not business-approved
      final unapprovedAdapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
        isRestorePolicyApproved: false,
        isRestoreBehaviorVerified: true,
        configuredRestoreBehavior: 'keep_with_original_app_user_id',
      );
      expect(unapprovedAdapter.isRestorePolicyVerified, isFalse);
      final outcomeA = await unapprovedAdapter.queryPastPurchases();
      expect(outcomeA.status, equals(StoreClientOutcomeStatus.unavailable));
      expect(outcomeA.message, contains('RESTORE_POLICY_NOT_APPROVED'));

      // (b) Policy approved, but dashboard restore behavior not yet verified
      final unverifiedDashboardAdapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
        isRestorePolicyApproved: true,
        isRestoreBehaviorVerified: false,
        configuredRestoreBehavior: 'keep_with_original_app_user_id',
      );
      expect(unverifiedDashboardAdapter.isRestorePolicyVerified, isFalse);
      final outcomeB = await unverifiedDashboardAdapter.queryPastPurchases();
      expect(outcomeB.status, equals(StoreClientOutcomeStatus.unavailable));
      expect(outcomeB.message, contains('RESTORE_DASHBOARD_NOT_VERIFIED'));

      // (c) Dashboard configured with transfer_to_new_app_user_id (must fail closed)
      final unsafeTransferAdapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
        isRestorePolicyApproved: true,
        isRestoreBehaviorVerified: true,
        configuredRestoreBehavior: 'transfer_to_new_app_user_id',
      );
      expect(unsafeTransferAdapter.isRestorePolicyVerified, isFalse);
      final outcomeC = await unsafeTransferAdapter.queryPastPurchases();
      expect(outcomeC.status, equals(StoreClientOutcomeStatus.unavailable));
      expect(outcomeC.message, contains('RESTORE_BEHAVIOR_MUST_KEEP_ORIGINAL'));

      // (d) All three satisfied -> allowed to proceed
      final safeAdapter = RevenueCatStorePaymentClientAdapter(
        client: fakeClient,
        apiKey: 'test_rc_key',
        appUserId: kValidRcIdA,
        boundAccountId: 'user_a@saman.ai',
        isRestorePolicyApproved: true,
        isRestoreBehaviorVerified: true,
        configuredRestoreBehavior: 'keep_with_original_app_user_id',
      );
      expect(safeAdapter.isRestorePolicyVerified, isTrue);
      fakeClient.nextCustomerInfo = buildTestCustomerInfo(
        originalAppUserId: kValidRcIdA,
        activeSubscriptions: ['saman_plus_monthly'],
      );
      final outcomeD = await safeAdapter.queryPastPurchases();
      expect(outcomeD.status, equals(StoreClientOutcomeStatus.tokenReadyForVerification));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/membership/data/datasources/membership_remote_data_source.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/data/models/revenue_catalog_dto.dart';
import 'package:health_ai_app/features/membership/data/repositories/membership_repository_impl.dart';
import 'package:health_ai_app/features/membership/data/repositories/payment_repository_impl.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/domain/models/purchase_state.dart';
import 'package:health_ai_app/features/membership/domain/repositories/payment_repository.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';

class FakeStorePaymentClientAdapter implements StorePaymentClientAdapter {
  bool configured;
  StoreClientOutcome nextOutcome;
  Duration delay;

  FakeStorePaymentClientAdapter({
    this.configured = true,
    required this.nextOutcome,
    this.delay = Duration.zero,
  });

  @override
  bool get isConfigured => configured;

  @override
  Future<StoreClientOutcome> initiateStorePurchase(
      PurchaseIntent intent) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return nextOutcome;
  }

  @override
  Future<StoreClientOutcome> queryPastPurchases() async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return nextOutcome;
  }
}

class FakePaymentMembershipDataSource implements IMembershipRemoteDataSource {
  BackendPurchaseVerificationResult? verificationResult;
  AccountMembershipDto? membershipResult;
  Duration verificationDelay;
  Duration membershipDelay;
  Exception? verificationException;

  FakePaymentMembershipDataSource({
    this.verificationResult,
    this.membershipResult,
    this.verificationDelay = Duration.zero,
    this.membershipDelay = Duration.zero,
    this.verificationException,
  });

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    throw UnimplementedError();
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    if (membershipDelay > Duration.zero) {
      await Future.delayed(membershipDelay);
    }
    if (membershipResult != null) {
      return membershipResult!;
    }
    return AccountMembershipDto.defaultFree();
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    if (verificationDelay > Duration.zero) {
      await Future.delayed(verificationDelay);
    }
    if (verificationException != null) {
      throw verificationException!;
    }
    if (verificationResult != null) {
      return verificationResult!;
    }
    throw StateError('No verificationResult configured');
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    throw UnimplementedError();
  }
}

MembershipPlan buildPurchasablePlusPlan({
  bool purchasable = true,
}) {
  final base = MembershipCatalog.getPlan(MembershipTier.plus);
  return base.copyWith(purchasable: purchasable);
}

void main() {
  group('CP-07 Flutter Payment Boundary & Purchase State Machine', () {
    test(
        'Scenario 1: Missing config or preview plan keeps PurchaseFlowStatus.unavailable (previewMode: true)',
        () async {
      final remoteDs = FakePaymentMembershipDataSource();
      final membershipRepo =
          MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);

      // Default unconfigured store adapter
      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: const UnconfiguredStorePaymentClientAdapter(),
        remoteDataSource: remoteDs,
      );
      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
      );

      // Preview plan from static catalog (previewMode: true, purchasable: false)
      final previewPlan = MembershipCatalog.getPlan(MembershipTier.plus);
      final state1 = await purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: previewPlan,
          billingPeriod: BillingPeriod.monthly,
        ),
      );
      expect(state1.status, PurchaseFlowStatus.unavailable);
      expect(state1.previewMode, isTrue);
      expect(state1.isGranted, isFalse);

      // Even if plan is marked purchasable, unconfigured adapter keeps state unavailable
      final purchasablePlan = buildPurchasablePlusPlan(purchasable: true);
      final state2 = await purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: purchasablePlan,
          billingPeriod: BillingPeriod.monthly,
        ),
      );
      expect(state2.status, PurchaseFlowStatus.unavailable);
      expect(state2.previewMode, isTrue);
      expect(state2.isGranted, isFalse);
    });

    test(
        'Scenario 2: Store SDK tokenReadyForVerification does NOT self-activate membership when backend rejects',
        () async {
      final storeAdapter = FakeStorePaymentClientAdapter(
        configured: true,
        nextOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_plus_monthly_sandbox',
            verificationToken: 'sdk_fake_success_token',
            transactionId: 'tx_fake_1',
          ),
        ),
      );
      final remoteDs = FakePaymentMembershipDataSource(
        verificationResult: const BackendPurchaseVerificationResult(
          outcome: 'failed',
          userId: 'user_a@saman.ai',
          provider: 'apple_app_store',
          environment: 'sandbox',
          tier: MembershipTier.free,
          isActiveSubscription: false,
          errorCode: 'PROVIDER_VERIFICATION_INVALID',
          message: 'Provider rejected purchase proof.',
        ),
      );

      final membershipRepo =
          MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);
      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: storeAdapter,
        remoteDataSource: remoteDs,
      );
      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
      );

      final result = await purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildPurchasablePlusPlan(),
          billingPeriod: BillingPeriod.monthly,
        ),
      );

      expect(result.status, PurchaseFlowStatus.failed);
      expect(result.isGranted, isFalse);
      // Account membership must NOT become Plus
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });

    test(
        'Scenario 3: Pending and canceled store/backend outcomes do NOT grant entitlement',
        () async {
      final remoteDs = FakePaymentMembershipDataSource();
      final membershipRepo =
          MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);

      // 3a. Store pending
      final pendingAdapter = FakeStorePaymentClientAdapter(
        configured: true,
        nextOutcome: StoreClientOutcome.pending('Ask to Buy pending approval'),
      );
      final pendingNotifier = MembershipPurchaseNotifier(
        paymentRepository: PaymentRepositoryImpl(
          storeAdapter: pendingAdapter,
          remoteDataSource: remoteDs,
        ),
        membershipNotifier: membershipNotifier,
      );
      final resPending = await pendingNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildPurchasablePlusPlan(),
          billingPeriod: BillingPeriod.monthly,
        ),
      );
      expect(resPending.status, PurchaseFlowStatus.pending);
      expect(resPending.isGranted, isFalse);

      // 3b. Store canceled
      final canceledAdapter = FakeStorePaymentClientAdapter(
        configured: true,
        nextOutcome: StoreClientOutcome.canceled('User dismissed payment sheet'),
      );
      final canceledNotifier = MembershipPurchaseNotifier(
        paymentRepository: PaymentRepositoryImpl(
          storeAdapter: canceledAdapter,
          remoteDataSource: remoteDs,
        ),
        membershipNotifier: membershipNotifier,
      );
      final resCanceled = await canceledNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildPurchasablePlusPlan(),
          billingPeriod: BillingPeriod.monthly,
        ),
      );
      expect(resCanceled.status, PurchaseFlowStatus.canceled);
      expect(resCanceled.isGranted, isFalse);
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });

    test(
        'Scenario 4: Confirmed requires BOTH backend verification AND authoritative membership refresh',
        () async {
      final storeAdapter = FakeStorePaymentClientAdapter(
        configured: true,
        nextOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_plus_monthly_sandbox',
            verificationToken: 'valid_sandbox_receipt',
            transactionId: 'tx_valid_1',
            originalTransactionId: 'orig_valid_1',
          ),
        ),
      );
      final remoteDs = FakePaymentMembershipDataSource(
        verificationResult: BackendPurchaseVerificationResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.ai',
          provider: 'apple_app_store',
          environment: 'sandbox',
          transactionId: 'tx_valid_1',
          originalTransactionId: 'orig_valid_1',
          subscriptionId: 'sub_apple_sandbox_orig_valid_1',
          tier: MembershipTier.plus,
          isActiveSubscription: true,
          currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
          message: 'Purchase verified and entitlements projected.',
        ),
        membershipResult: AccountMembershipDto(
          userId: 'user_a@saman.ai',
          tier: MembershipTier.plus,
          status: 'active',
          isActiveSubscription: true,
          entitlements: const [],
          usage: const {},
          asOf: DateTime.now(),
        ),
      );

      final membershipRepo =
          MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);
      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: storeAdapter,
        remoteDataSource: remoteDs,
      );
      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
      );

      final recordedStatuses = <PurchaseFlowStatus>[];
      purchaseNotifier.addListener((state) {
        recordedStatuses.add(state.status);
      });

      final finalState = await purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildPurchasablePlusPlan(),
          billingPeriod: BillingPeriod.monthly,
        ),
      );

      expect(finalState.status, PurchaseFlowStatus.confirmed);
      expect(finalState.isGranted, isTrue);
      expect(finalState.targetTier, MembershipTier.plus);
      expect(
        recordedStatuses,
        containsAllInOrder([
          PurchaseFlowStatus.unavailable,
          PurchaseFlowStatus.loading,
          PurchaseFlowStatus.verifying,
          PurchaseFlowStatus.confirmed,
        ]),
      );
      expect(membershipNotifier.state.isKnown, isTrue);
      expect(membershipNotifier.state.tier, MembershipTier.plus);
    });

    test(
        'Scenario 5: Slow backend verification + account switch mid-purchase NEVER grants or refreshes new account',
        () async {
      final storeAdapter = FakeStorePaymentClientAdapter(
        configured: true,
        nextOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_plus_monthly_sandbox',
            verificationToken: 'tok_slow_verify',
            transactionId: 'tx_slow_1',
          ),
        ),
      );
      final remoteDs = FakePaymentMembershipDataSource(
        verificationDelay: const Duration(milliseconds: 80),
        verificationResult: BackendPurchaseVerificationResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.ai',
          provider: 'apple_app_store',
          environment: 'sandbox',
          transactionId: 'tx_slow_1',
          subscriptionId: 'sub_slow_1',
          tier: MembershipTier.plus,
          isActiveSubscription: true,
          currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
        ),
        membershipResult: AccountMembershipDto(
          userId: 'user_a@saman.ai',
          tier: MembershipTier.plus,
          status: 'active',
          isActiveSubscription: true,
          entitlements: const [],
          usage: const {},
          asOf: DateTime.now(),
        ),
      );

      final membershipRepo =
          MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);
      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: storeAdapter,
        remoteDataSource: remoteDs,
      );
      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
      );

      // Start purchase for User A
      final purchaseFuture = purchaseNotifier.startPurchase(
        PurchaseIntent(
          accountId: 'user_a@saman.ai',
          plan: buildPurchasablePlusPlan(),
          billingPeriod: BillingPeriod.monthly,
        ),
      );

      // Wait 20ms so purchase is in `verifying` state, then switch account to User B
      await Future.delayed(const Duration(milliseconds: 20));
      expect(purchaseNotifier.state.status, PurchaseFlowStatus.verifying);

      membershipNotifier.reset();
      membershipNotifier.setDemoBaseline('user_b@saman.ai');
      purchaseNotifier.onAccountChanged('user_b@saman.ai');

      final abortedState = await purchaseFuture;
      expect(abortedState.status, PurchaseFlowStatus.failed);
      expect(abortedState.errorCode, 'ACCOUNT_SWITCHED_DURING_VERIFICATION');

      // User B must remain on Free demo baseline and NEVER receive User A's Plus state
      expect(membershipNotifier.state.accountId, 'user_b@saman.ai');
      expect(membershipNotifier.state.tier, MembershipTier.free);
      expect(purchaseNotifier.state.accountId, 'user_b@saman.ai');
      expect(purchaseNotifier.state.isGranted, isFalse);
    });
  });
}

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

class FakeLifecycleStoreClientAdapter implements StorePaymentClientAdapter {
  bool configured;
  StoreClientOutcome nextPurchaseOutcome;
  StoreClientOutcome nextRestoreOutcome;
  Duration delay;

  FakeLifecycleStoreClientAdapter({
    this.configured = true,
    StoreClientOutcome? nextPurchaseOutcome,
    StoreClientOutcome? nextRestoreOutcome,
    this.delay = Duration.zero,
  })  : nextPurchaseOutcome = nextPurchaseOutcome ??
            StoreClientOutcome.unavailable('Payment not configured'),
        nextRestoreOutcome = nextRestoreOutcome ??
            StoreClientOutcome.unavailable('Restore not configured');

  @override
  bool get isConfigured => configured;

  @override
  Future<StoreClientOutcome> initiateStorePurchase(
      PurchaseIntent intent) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return nextPurchaseOutcome;
  }

  @override
  Future<StoreClientOutcome> queryPastPurchases() async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return nextRestoreOutcome;
  }
}

class FakeLifecycleRemoteDataSource implements IMembershipRemoteDataSource {
  AccountMembershipDto? membershipResult;
  BackendPurchaseVerificationResult? verificationResult;
  RestorePurchasesResult? restoreResult;
  Duration restoreDelay;
  Exception? restoreException;

  FakeLifecycleRemoteDataSource({
    this.membershipResult,
    this.verificationResult,
    this.restoreResult,
    this.restoreDelay = Duration.zero,
    this.restoreException,
  });

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    throw UnimplementedError();
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    if (membershipResult != null) {
      return membershipResult!;
    }
    return AccountMembershipDto.defaultFree();
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    if (verificationResult != null) {
      return verificationResult!;
    }
    throw StateError('No verificationResult configured');
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    if (restoreDelay > Duration.zero) {
      await Future.delayed(restoreDelay);
    }
    if (restoreException != null) {
      throw restoreException!;
    }
    if (restoreResult != null) {
      return restoreResult!;
    }
    throw StateError('No restoreResult configured');
  }
}

void main() {
  group('CP-08 Flutter Subscription Lifecycle & Restore State Machine', () {
    test(
        'Scenario 1: Restore when provider is unconfigured remains unavailable (no fake success)',
        () async {
      final remoteDs = FakeLifecycleRemoteDataSource();
      final membershipRepo =
          MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final membershipNotifier = AccountMembershipNotifier(membershipRepo);

      final unconfiguredAdapter = FakeLifecycleStoreClientAdapter(
        configured: false,
      );
      final paymentRepo = PaymentRepositoryImpl(
        storeAdapter: unconfiguredAdapter,
        remoteDataSource: remoteDs,
      );
      final purchaseNotifier = MembershipPurchaseNotifier(
        paymentRepository: paymentRepo,
        membershipNotifier: membershipNotifier,
      );

      final result = await purchaseNotifier.restorePurchases(
        accountId: 'user_test@saman.ai',
      );

      expect(result.status, PurchaseFlowStatus.unavailable);
      expect(result.previewMode, isTrue);
      expect(result.errorCode, 'PAYMENT_CONFIG_NOT_READY');
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });

    test(
        'Scenario 2: Same-account restore refreshes membership to Pro and returns confirmed state',
        () async {
      final now = DateTime.now();
      final expiry = now.add(const Duration(days: 30));

      final storeAdapter = FakeLifecycleStoreClientAdapter(
        configured: true,
        nextRestoreOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_pro_monthly_sandbox',
            verificationToken: 'valid_restore_receipt_data',
            transactionId: 'tx_restore_100',
            originalTransactionId: 'orig_100',
          ),
        ),
      );

      final remoteDs = FakeLifecycleRemoteDataSource(
        restoreResult: RestorePurchasesResult(
          outcome: 'confirmed',
          userId: 'user_same@saman.ai',
          provider: 'apple_app_store',
          environment: 'sandbox',
          ownershipStatus: 'verified_owner',
          transactionId: 'tx_restore_100',
          originalTransactionId: 'orig_100',
          subscriptionId: 'sub_apple_sandbox_orig_100',
          tier: MembershipTier.pro,
          isActiveSubscription: true,
          currentPeriodEnd: expiry,
          autoRenewStatus: true,
          inGracePeriod: false,
          restoredGrantsCount: 1,
          message: 'Purchases restored successfully.',
        ),
        membershipResult: AccountMembershipDto(
          userId: 'user_same@saman.ai',
          tier: MembershipTier.pro,
          status: 'active',
          isActiveSubscription: true,
          autoRenewStatus: true,
          inGracePeriod: false,
          ownershipStatus: 'verified_owner',
          entitlements: const [],
          usage: const {},
          currentPeriodEnd: expiry,
          asOf: now,
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

      final result = await purchaseNotifier.restorePurchases(
        accountId: 'user_same@saman.ai',
      );

      expect(result.status, PurchaseFlowStatus.confirmed);
      expect(result.isGranted, isTrue);
      expect(result.targetTier, MembershipTier.pro);
      expect(result.transactionId, 'tx_restore_100');
      expect(membershipNotifier.state.tier, MembershipTier.pro);
      expect(membershipNotifier.state.status, 'active');
      expect(membershipNotifier.state.isKnown, isTrue);
    });

    test(
        'Scenario 3: Cross-account restore reports RECEIPT_OWNERSHIP_CONFLICT without transferring entitlement',
        () async {
      final storeAdapter = FakeLifecycleStoreClientAdapter(
        configured: true,
        nextRestoreOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_pro_monthly_sandbox',
            verificationToken: 'receipt_owned_by_another_user',
            transactionId: 'tx_conflict_1',
            originalTransactionId: 'orig_bound_to_user_a',
          ),
        ),
      );

      final remoteDs = FakeLifecycleRemoteDataSource(
        restoreResult: const RestorePurchasesResult(
          outcome: 'conflict',
          userId: 'user_b@saman.ai',
          provider: 'apple_app_store',
          environment: 'sandbox',
          ownershipStatus: 'unresolved_conflict',
          tier: MembershipTier.free,
          isActiveSubscription: false,
          firstOwnerPolicy: 'PROPOSED',
          errorCode: 'RECEIPT_OWNERSHIP_CONFLICT',
          message:
              'Receipt orig_bound_to_user_a is registered to user_a@saman.ai. Ownership transfer is not supported.',
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

      final result = await purchaseNotifier.restorePurchases(
        accountId: 'user_b@saman.ai',
      );

      expect(result.status, PurchaseFlowStatus.failed);
      expect(result.errorCode, 'RECEIPT_OWNERSHIP_CONFLICT');
      expect(result.isGranted, isFalse);
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });

    test(
        'Scenario 4: Account switch during in-flight restore aborts and discards stale response',
        () async {
      final storeAdapter = FakeLifecycleStoreClientAdapter(
        configured: true,
        delay: const Duration(milliseconds: 40),
        nextRestoreOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_pro_monthly_sandbox',
            verificationToken: 'slow_receipt_token',
          ),
        ),
      );

      final remoteDs = FakeLifecycleRemoteDataSource(
        restoreDelay: const Duration(milliseconds: 40),
        restoreResult: const RestorePurchasesResult(
          outcome: 'confirmed',
          userId: 'user_initial@saman.ai',
          provider: 'apple_app_store',
          environment: 'sandbox',
          ownershipStatus: 'verified_owner',
          tier: MembershipTier.pro,
          isActiveSubscription: true,
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

      final restoreFuture = purchaseNotifier.restorePurchases(
        accountId: 'user_initial@saman.ai',
      );

      // User switches account while restore is in flight
      await Future.delayed(const Duration(milliseconds: 10));
      purchaseNotifier.onAccountChanged('user_switched@saman.ai');

      final result = await restoreFuture;

      expect(result.status, PurchaseFlowStatus.failed);
      expect(result.errorCode, 'ACCOUNT_SWITCHED_DURING_RESTORE');
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });

    test(
        'Scenario 5: AccountMembershipDto parses auto_renew_status: false and reports cancelsAtPeriodEnd',
        () {
      final futureDate = DateTime.parse('2026-11-29T12:00:00Z');
      final dto = AccountMembershipDto.fromJson({
        'user_id': 'user_cancel_renew@saman.ai',
        'tier': 'pro',
        'status': 'active',
        'is_active_subscription': true,
        'current_period_end': futureDate.toIso8601String(),
        'auto_renew_status': false,
        'cancel_at_period_end': true,
        'in_grace_period': false,
        'ownership_status': 'verified_owner',
        'entitlements': [],
        'usage': {},
        'as_of': '2026-10-30T08:00:00Z',
      });

      expect(dto.tier, MembershipTier.pro);
      expect(dto.isActiveSubscription, isTrue);
      expect(dto.autoRenewStatus, isFalse);
      expect(dto.cancelAtPeriodEnd, isTrue);
      expect(dto.inGracePeriod, isFalse);
      expect(dto.ownershipStatus, 'verified_owner');
    });

    test(
        'Scenario 6: AccountMembershipDto parses in_grace_period: true with gracePeriodExpiresAt',
        () {
      final graceExpiry = DateTime.parse('2026-11-05T00:00:00Z');
      final dto = AccountMembershipDto.fromJson({
        'user_id': 'user_grace@saman.ai',
        'tier': 'plus',
        'status': 'past_due',
        'is_active_subscription': true,
        'current_period_end': '2026-10-29T00:00:00Z',
        'auto_renew_status': true,
        'in_grace_period': true,
        'grace_period_expires_at': graceExpiry.toIso8601String(),
        'ownership_status': 'verified_owner',
        'entitlements': [],
        'usage': {},
        'as_of': '2026-10-30T08:00:00Z',
      });

      expect(dto.tier, MembershipTier.plus);
      expect(dto.status, 'past_due');
      expect(dto.isActiveSubscription, isTrue);
      expect(dto.inGracePeriod, isTrue);
      expect(dto.gracePeriodExpiresAt, graceExpiry);
    });

    test(
        'Scenario 7: Restore with no active subscription returns RESTORE_NOT_CONFIRMED without updating membership',
        () async {
      final storeAdapter = FakeLifecycleStoreClientAdapter(
        configured: true,
        nextRestoreOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'google_play',
            environment: 'sandbox',
            appId: 'com.saman.health',
            productId: 'saman_plus_monthly_sandbox',
            verificationToken: 'token_expired_subscription',
          ),
        ),
      );

      final remoteDs = FakeLifecycleRemoteDataSource(
        restoreResult: const RestorePurchasesResult(
          outcome: 'no_active_subscription',
          userId: 'user_expired@saman.ai',
          provider: 'google_play',
          environment: 'sandbox',
          ownershipStatus: 'verified_owner',
          tier: MembershipTier.free,
          isActiveSubscription: false,
          errorCode: 'NO_ACTIVE_SUBSCRIPTION',
          message: 'No active subscription found to restore.',
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

      final result = await purchaseNotifier.restorePurchases(
        accountId: 'user_expired@saman.ai',
      );

      expect(result.status, PurchaseFlowStatus.failed);
      expect(result.errorCode, 'NO_ACTIVE_SUBSCRIPTION');
      expect(result.isGranted, isFalse);
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });

    test(
        'Scenario 8: Network or backend error during restore returns RESTORE_VERIFICATION_ERROR and keeps current tier',
        () async {
      final storeAdapter = FakeLifecycleStoreClientAdapter(
        configured: true,
        nextRestoreOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_pro_monthly_sandbox',
            verificationToken: 'valid_token_but_network_down',
          ),
        ),
      );

      final remoteDs = FakeLifecycleRemoteDataSource(
        restoreException: Exception('Backend network unreachable 503'),
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

      final result = await purchaseNotifier.restorePurchases(
        accountId: 'user_net_err@saman.ai',
      );

      expect(result.status, PurchaseFlowStatus.failed);
      expect(result.errorCode, 'RESTORE_VERIFICATION_ERROR');
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });
  });
}

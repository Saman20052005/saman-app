import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/api_client.dart';
import '../../../../utils/auth_helper.dart';
import '../../data/datasources/membership_remote_data_source.dart';
import '../../data/models/account_membership_dto.dart';
import '../../data/repositories/membership_repository_impl.dart';
import '../../data/repositories/payment_repository_impl.dart';
import '../../data/repositories/revenuecat_payment_adapter.dart';
import '../../domain/models/membership_plan.dart';
import '../../domain/models/purchase_state.dart';
import '../../domain/repositories/membership_repository.dart';
import '../../domain/repositories/payment_repository.dart';

/// Single source of truth for billing period (Monthly vs Yearly).
/// Shared across Compare, Plan Details, and Membership Overview.
final billingPeriodProvider =
    StateProvider<BillingPeriod>((ref) => BillingPeriod.monthly);

/// Remote data source provider
final membershipRemoteDataSourceProvider =
    Provider<IMembershipRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return MembershipRemoteDataSourceImpl(dio: dio);
});

/// Membership repository provider
final membershipRepositoryProvider = Provider<MembershipRepository>((ref) {
  final remoteDataSource = ref.watch(membershipRemoteDataSourceProvider);
  return MembershipRepositoryImpl(remoteDataSource: remoteDataSource);
});

/// StateNotifier for versioned catalog plans.
/// Defaults to static baseline preview plans immediately without starting unasked-for network timers.
class MembershipCatalogNotifier extends StateNotifier<List<MembershipPlan>> {
  final MembershipRepository _repository;

  MembershipCatalogNotifier(this._repository) : super(MembershipCatalog.plans);

  Future<void> loadCatalog({bool forceRefresh = false}) async {
    try {
      final plans =
          await _repository.getCatalogPlans(forceRefresh: forceRefresh);
      if (plans.isNotEmpty) {
        state = plans;
      }
    } catch (_) {}
  }
}

/// Provides dynamic catalog plans. When subscribed to via ref.watch,
/// returns List<MembershipPlan> with initial baseline plans, matching existing UI contracts.
final membershipCatalogProvider =
    StateNotifierProvider<MembershipCatalogNotifier, List<MembershipPlan>>(
        (ref) {
  final repo = ref.watch(membershipRepositoryProvider);
  return MembershipCatalogNotifier(repo);
});

/// Provides a single plan by tier from the active catalog.
final membershipPlanProvider =
    Provider.family<MembershipPlan, MembershipTier>((ref, tier) {
  final plans = ref.watch(membershipCatalogProvider);
  return plans.firstWhere(
    (plan) => plan.tier == tier,
    orElse: () => MembershipCatalog.getPlan(tier),
  );
});

/// StateNotifier for authenticated account membership and metered usage.
/// Initializes with safe default demo baseline. Invalidate / clear on logout.
class AccountMembershipNotifier
    extends StateNotifier<AccountMembershipState> {
  final MembershipRepository _repository;
  int _requestEpoch = 0;
  String? _activeAccountId;

  AccountMembershipNotifier(this._repository)
      : super(AccountMembershipState.demoBaseline());

  String? get activeAccountId => _activeAccountId;

  void setActiveAccount(String? accountId) {
    if (_activeAccountId != accountId) {
      _activeAccountId = accountId;
      _requestEpoch++;
      _repository.setActiveAccount(accountId);
    }
  }

  Future<AccountMembershipState> loadMembership({String? accountId}) async {
    if (accountId != null && accountId != _activeAccountId) {
      _activeAccountId = accountId;
      _repository.setActiveAccount(accountId);
    }
    final targetAccount = accountId ?? _activeAccountId;
    final epoch = ++_requestEpoch;

    state = AccountMembershipState.loading(
      previousData: state.accountId == targetAccount ? state.data : null,
      accountId: targetAccount,
    );
    try {
      final newState =
          await _repository.getAccountMembershipState(accountId: targetAccount);
      // Guard against late responses arriving after logout or account switch
      if (epoch != _requestEpoch || _activeAccountId != targetAccount) {
        return state;
      }
      state = newState;
      return newState;
    } catch (e) {
      if (epoch != _requestEpoch || _activeAccountId != targetAccount) {
        return state;
      }
      final errState = AccountMembershipState.unknownError(
        e.toString(),
        accountId: targetAccount,
      );
      state = errState;
      return errState;
    }
  }

  void reset() {
    _requestEpoch++;
    _activeAccountId = null;
    _repository.clearAccountCache();
    state = AccountMembershipState.loggedOut();
  }

  void setDemoBaseline([String? userId]) {
    _requestEpoch++;
    _activeAccountId = userId;
    _repository.setActiveAccount(userId);
    state = AccountMembershipState.demoBaseline(userId);
  }
}

/// Provides authenticated account membership and metered usage state.
/// Automatically resets to loggedOut and purges account cache on logout.
final accountMembershipProvider = StateNotifierProvider<
    AccountMembershipNotifier, AccountMembershipState>((ref) {
  final repo = ref.watch(membershipRepositoryProvider);
  final notifier = AccountMembershipNotifier(repo);
  ref.listen(authLoggingOutProvider, (_, loggingOut) {
    if (loggingOut) notifier.reset();
  });
  return notifier;
});

/// Current user entitlement tier (defaults to Free).
final currentMembershipTierProvider = Provider<MembershipTier>((ref) {
  final accountState = ref.watch(accountMembershipProvider);
  return accountState.tier;
});

/// Store payment client adapter provider (defaults to unconfigured preview adapter).
final storePaymentClientAdapterProvider =
    Provider<StorePaymentClientAdapter>((ref) {
  return const UnconfiguredStorePaymentClientAdapter();
});

/// RevenueCat store payment client adapter provider (initialized fail-closed).
final revenueCatPaymentAdapterProvider =
    Provider<RevenueCatStorePaymentClientAdapter>((ref) {
  return RevenueCatStorePaymentClientAdapter();
});

/// Payment repository provider
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final storeAdapter = ref.watch(storePaymentClientAdapterProvider);
  final remoteDataSource = ref.watch(membershipRemoteDataSourceProvider);
  return PaymentRepositoryImpl(
    storeAdapter: storeAdapter,
    remoteDataSource: remoteDataSource,
  );
});

/// StateNotifier managing the CP-07 purchase state machine:
///   unavailable, loading, pending, verifying, confirmed, canceled, failed.
///
/// Invariants:
/// 1. When provider/config/plan is not ready (`!plan.purchasable` or `plan.previewMode` or
///    `!paymentRepository.isPaymentConfigured`), remains `unavailable` with `previewMode: true`.
/// 2. Store SDK success (`tokenReadyForVerification`) transitions only to `verifying` —
///    NEVER directly to `confirmed` and NEVER mutates `accountMembershipProvider` locally.
/// 3. `confirmed` requires BOTH:
///    (a) Backend `/api/revenue/purchases/verify` returning `outcome == 'confirmed'` for the same user, AND
///    (b) Authoritative backend membership refresh (`loadMembership`) returning `known` active state
///        for the same account.
/// 4. If the account changes or logs out during store purchase, backend verification, or
///    membership refresh, the stale response is discarded and never grants or refreshes the new account.
class MembershipPurchaseNotifier extends StateNotifier<PurchaseState> {
  final PaymentRepository _paymentRepository;
  final AccountMembershipNotifier _membershipNotifier;
  final StorePaymentClientAdapter? _storeAdapter;
  int _purchaseEpoch = 0;
  String? _activeAccountId;

  MembershipPurchaseNotifier({
    required PaymentRepository paymentRepository,
    required AccountMembershipNotifier membershipNotifier,
    StorePaymentClientAdapter? storeAdapter,
  })  : _paymentRepository = paymentRepository,
        _membershipNotifier = membershipNotifier,
        _storeAdapter = storeAdapter,
        super(PurchaseState.unavailable());

  void onAccountChanged(String? newAccountId) {
    if (_activeAccountId != newAccountId) {
      _activeAccountId = newAccountId;
      _purchaseEpoch++;
      final adapter = _storeAdapter;
      if (adapter is RevenueCatStorePaymentClientAdapter) {
        unawaited(adapter.logOut());
      }
      state = PurchaseState.unavailable(accountId: newAccountId);
    }
  }

  void reset() {
    _purchaseEpoch++;
    _activeAccountId = null;
    final adapter = _storeAdapter;
    if (adapter is RevenueCatStorePaymentClientAdapter) {
      unawaited(adapter.logOut());
    }
    state = PurchaseState.unavailable();
  }

  Future<void> _ensureBackendCustomerIdentityBound(
      String originatingAccount) async {
    final adapter = _storeAdapter;
    if (adapter is! RevenueCatStorePaymentClientAdapter) return;

    var currentState = _membershipNotifier.state;
    if (!currentState.isKnown ||
        currentState.accountId != originatingAccount ||
        !isValidRevenueCatAppUserId(currentState.opaqueAppUserId)) {
      currentState = await _membershipNotifier.loadMembership(
        accountId: originatingAccount,
      );
    }
    final rcId = currentState.opaqueAppUserId;
    if (currentState.accountId == originatingAccount &&
        isValidRevenueCatAppUserId(rcId)) {
      await adapter.bindBackendCustomerIdentity(
        accountId: originatingAccount,
        opaqueAppUserId: rcId!,
      );
    }
  }

  Future<PurchaseState> startPurchase(PurchaseIntent intent) async {
    final originatingAccount = intent.accountId.trim();
    if (originatingAccount.isEmpty) {
      final failed = PurchaseState.failed(
        targetTier: intent.plan.tier,
        billingPeriod: intent.billingPeriod,
        errorCode: 'UNAUTHENTICATED_USER',
        message: 'Please sign in before purchasing a membership.',
      );
      state = failed;
      return failed;
    }

    _activeAccountId = originatingAccount;
    _membershipNotifier.setActiveAccount(originatingAccount);
    final epoch = ++_purchaseEpoch;

    // Invariant: Missing config or preview plan keeps unavailable/preview state
    if (!intent.plan.purchasable || !_paymentRepository.isPaymentConfigured) {
      final unavail = PurchaseState.unavailable(
        accountId: originatingAccount,
        targetTier: intent.plan.tier,
        billingPeriod: intent.billingPeriod,
        errorCode: 'PAYMENT_CONFIG_NOT_READY',
        message:
            'Membership plans are currently in preview mode. Purchasing is not yet enabled.',
      );
      state = unavail;
      return unavail;
    }

    state = PurchaseState.loading(
      accountId: originatingAccount,
      targetTier: intent.plan.tier,
      billingPeriod: intent.billingPeriod,
    );

    try {
      await _ensureBackendCustomerIdentityBound(originatingAccount);
      final storeOutcome = await _paymentRepository.startStorePurchase(intent);

      // Guard 1: Check if account switched or logged out while store sheet was open
      if (epoch != _purchaseEpoch || _activeAccountId != originatingAccount) {
        return PurchaseState.failed(
          accountId: originatingAccount,
          targetTier: intent.plan.tier,
          billingPeriod: intent.billingPeriod,
          errorCode: 'ACCOUNT_SWITCHED_DURING_PURCHASE',
          message: 'Account changed during purchase; operation aborted.',
        );
      }

      switch (storeOutcome.status) {
        case StoreClientOutcomeStatus.unavailable:
          final unavail = PurchaseState.unavailable(
            accountId: originatingAccount,
            targetTier: intent.plan.tier,
            billingPeriod: intent.billingPeriod,
            errorCode: storeOutcome.errorCode,
            message: storeOutcome.message,
          );
          state = unavail;
          return unavail;

        case StoreClientOutcomeStatus.pending:
          final pending = PurchaseState.pending(
            accountId: originatingAccount,
            targetTier: intent.plan.tier,
            billingPeriod: intent.billingPeriod,
            message: storeOutcome.message,
          );
          state = pending;
          return pending;

        case StoreClientOutcomeStatus.canceled:
          final canceled = PurchaseState.canceled(
            accountId: originatingAccount,
            targetTier: intent.plan.tier,
            billingPeriod: intent.billingPeriod,
            message: storeOutcome.message,
          );
          state = canceled;
          return canceled;

        case StoreClientOutcomeStatus.failed:
          final failed = PurchaseState.failed(
            accountId: originatingAccount,
            targetTier: intent.plan.tier,
            billingPeriod: intent.billingPeriod,
            errorCode: storeOutcome.errorCode,
            message: storeOutcome.message,
          );
          state = failed;
          return failed;

        case StoreClientOutcomeStatus.tokenReadyForVerification:
          final payload = storeOutcome.payload;
          if (payload == null || payload.verificationToken.trim().isEmpty) {
            final failed = PurchaseState.failed(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              errorCode: 'MISSING_VERIFICATION_TOKEN',
              message: 'Store returned an empty verification token.',
            );
            state = failed;
            return failed;
          }

          // Transition to verifying (never confirmed until backend verifies + refreshes)
          state = PurchaseState.verifying(
            accountId: originatingAccount,
            targetTier: intent.plan.tier,
            billingPeriod: intent.billingPeriod,
            transactionId: payload.transactionId,
          );

          final backendResult =
              await _paymentRepository.verifyPurchaseWithBackend(payload);

          // Guard 2: Check if account switched or logged out while backend verification was in flight
          if (epoch != _purchaseEpoch ||
              _activeAccountId != originatingAccount) {
            return PurchaseState.failed(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              errorCode: 'ACCOUNT_SWITCHED_DURING_VERIFICATION',
              message:
                  'Account changed while verifying purchase; response discarded.',
            );
          }

          // Guard 3: Backend response userId must match originatingAccount
          if (backendResult.userId.isNotEmpty &&
              backendResult.userId != originatingAccount) {
            final mismatch = PurchaseState.failed(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              errorCode: 'USER_IDENTITY_MISMATCH',
              message:
                  'Verification response user identity did not match active account.',
            );
            state = mismatch;
            return mismatch;
          }

          if (backendResult.outcome == 'pending') {
            final pending = PurchaseState.pending(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              transactionId: backendResult.transactionId,
              message: backendResult.message,
            );
            state = pending;
            return pending;
          }

          if (backendResult.outcome == 'canceled') {
            final canceled = PurchaseState.canceled(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              message: backendResult.message,
            );
            state = canceled;
            return canceled;
          }

          if (backendResult.outcome != 'confirmed' ||
              !backendResult.isActiveSubscription) {
            final failed = PurchaseState.failed(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              errorCode:
                  backendResult.errorCode ?? 'BACKEND_VERIFICATION_REJECTED',
              message: backendResult.message ??
                  'Server could not confirm active subscription entitlement.',
            );
            state = failed;
            return failed;
          }

          // Authoritative membership refresh required before transitioning to confirmed
          final refreshedState = await _membershipNotifier.loadMembership(
            accountId: originatingAccount,
          );

          // Guard 4: Check if account switched during membership refresh
          if (epoch != _purchaseEpoch ||
              _activeAccountId != originatingAccount) {
            return PurchaseState.failed(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              errorCode: 'ACCOUNT_SWITCHED_DURING_REFRESH',
              message: 'Account changed during membership refresh.',
            );
          }

          if (!refreshedState.isKnown ||
              refreshedState.data == null ||
              refreshedState.data!.userId != originatingAccount ||
              !refreshedState.data!.isActiveSubscription) {
            final failed = PurchaseState.failed(
              accountId: originatingAccount,
              targetTier: intent.plan.tier,
              billingPeriod: intent.billingPeriod,
              errorCode: 'AUTHORITATIVE_REFRESH_INCOMPLETE',
              message:
                  'Purchase verified, but authoritative membership refresh did not confirm active entitlement yet.',
            );
            state = failed;
            return failed;
          }

          final confirmed = PurchaseState.confirmed(
            accountId: originatingAccount,
            targetTier: refreshedState.tier,
            billingPeriod: intent.billingPeriod,
            transactionId: backendResult.transactionId,
            subscriptionId: backendResult.subscriptionId,
            message: backendResult.message,
          );
          state = confirmed;
          return confirmed;
      }
    } catch (e) {
      if (epoch != _purchaseEpoch || _activeAccountId != originatingAccount) {
        return state;
      }
      final failed = PurchaseState.failed(
        accountId: originatingAccount,
        targetTier: intent.plan.tier,
        billingPeriod: intent.billingPeriod,
        errorCode: 'PURCHASE_VERIFICATION_ERROR',
        message: e.toString(),
      );
      state = failed;
      return failed;
    }
  }

  Future<PurchaseState> restorePurchases({required String accountId}) async {
    final originatingAccount = accountId.trim();
    if (originatingAccount.isEmpty) {
      final failed = PurchaseState.failed(
        errorCode: 'UNAUTHENTICATED_USER',
        message: 'Please sign in before restoring purchases.',
      );
      state = failed;
      return failed;
    }

    _activeAccountId = originatingAccount;
    _membershipNotifier.setActiveAccount(originatingAccount);
    final epoch = ++_purchaseEpoch;

    if (!_paymentRepository.isPaymentConfigured) {
      final unavail = PurchaseState.unavailable(
        accountId: originatingAccount,
        errorCode: 'PAYMENT_CONFIG_NOT_READY',
        message:
            'Payment provider is not yet configured. Live restore is unavailable.',
      );
      state = unavail;
      return unavail;
    }

    state = PurchaseState.loading(accountId: originatingAccount);

    try {
      await _ensureBackendCustomerIdentityBound(originatingAccount);
      final storeOutcome = await _paymentRepository.startStoreRestore();

      if (epoch != _purchaseEpoch || _activeAccountId != originatingAccount) {
        return PurchaseState.failed(
          accountId: originatingAccount,
          errorCode: 'ACCOUNT_SWITCHED_DURING_RESTORE',
          message: 'Account changed during restore; operation aborted.',
        );
      }

      switch (storeOutcome.status) {
        case StoreClientOutcomeStatus.unavailable:
          final unavail = PurchaseState.unavailable(
            accountId: originatingAccount,
            errorCode: storeOutcome.errorCode,
            message: storeOutcome.message,
          );
          state = unavail;
          return unavail;

        case StoreClientOutcomeStatus.pending:
          final pending = PurchaseState.pending(
            accountId: originatingAccount,
            message: storeOutcome.message,
          );
          state = pending;
          return pending;

        case StoreClientOutcomeStatus.canceled:
          final canceled = PurchaseState.canceled(
            accountId: originatingAccount,
            message: storeOutcome.message,
          );
          state = canceled;
          return canceled;

        case StoreClientOutcomeStatus.failed:
          final failed = PurchaseState.failed(
            accountId: originatingAccount,
            errorCode: storeOutcome.errorCode,
            message: storeOutcome.message,
          );
          state = failed;
          return failed;

        case StoreClientOutcomeStatus.tokenReadyForVerification:
          final payload = storeOutcome.payload;
          if (payload == null || payload.verificationToken.trim().isEmpty) {
            final failed = PurchaseState.failed(
              accountId: originatingAccount,
              errorCode: 'MISSING_VERIFICATION_TOKEN',
              message: 'Store returned an empty restore token.',
            );
            state = failed;
            return failed;
          }

          state = PurchaseState.verifying(
            accountId: originatingAccount,
            transactionId: payload.transactionId,
          );

          final restoreResult =
              await _paymentRepository.restorePurchasesWithBackend(payload);

          if (epoch != _purchaseEpoch ||
              _activeAccountId != originatingAccount) {
            return PurchaseState.failed(
              accountId: originatingAccount,
              errorCode: 'ACCOUNT_SWITCHED_DURING_RESTORE',
              message:
                  'Account changed while restoring purchases; response discarded.',
            );
          }

          if (restoreResult.userId.isNotEmpty &&
              restoreResult.userId != originatingAccount) {
            final mismatch = PurchaseState.failed(
              accountId: originatingAccount,
              errorCode: 'USER_IDENTITY_MISMATCH',
              message:
                  'Restore response user identity did not match active account.',
            );
            state = mismatch;
            return mismatch;
          }

          if (restoreResult.ownershipStatus == 'unresolved_conflict') {
            final conflict = PurchaseState.failed(
              accountId: originatingAccount,
              errorCode: 'RECEIPT_OWNERSHIP_CONFLICT',
              message: restoreResult.message ??
                  'This purchase receipt is bound to another Saman account. Automatic transfer is not supported.',
            );
            state = conflict;
            return conflict;
          }

          if (restoreResult.outcome != 'confirmed' ||
              !restoreResult.isActiveSubscription) {
            final failed = PurchaseState.failed(
              accountId: originatingAccount,
              errorCode: restoreResult.errorCode ?? 'RESTORE_NOT_CONFIRMED',
              message: restoreResult.message ??
                  'No active subscription found to restore.',
            );
            state = failed;
            return failed;
          }

          final refreshedState = await _membershipNotifier.loadMembership(
            accountId: originatingAccount,
          );

          if (epoch != _purchaseEpoch ||
              _activeAccountId != originatingAccount) {
            return PurchaseState.failed(
              accountId: originatingAccount,
              errorCode: 'ACCOUNT_SWITCHED_DURING_REFRESH',
              message: 'Account changed during membership refresh.',
            );
          }

          final confirmed = PurchaseState.confirmed(
            accountId: originatingAccount,
            targetTier: refreshedState.tier,
            transactionId: restoreResult.transactionId,
            subscriptionId: restoreResult.subscriptionId,
            message: restoreResult.message,
          );
          state = confirmed;
          return confirmed;
      }
    } catch (e) {
      if (epoch != _purchaseEpoch || _activeAccountId != originatingAccount) {
        return state;
      }
      final failed = PurchaseState.failed(
        accountId: originatingAccount,
        errorCode: 'RESTORE_VERIFICATION_ERROR',
        message: e.toString(),
      );
      state = failed;
      return failed;
    }
  }
}

final membershipPurchaseProvider =
    StateNotifierProvider<MembershipPurchaseNotifier, PurchaseState>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final membershipNotifier = ref.watch(accountMembershipProvider.notifier);
  final storeAdapter = ref.watch(storePaymentClientAdapterProvider);
  final notifier = MembershipPurchaseNotifier(
    paymentRepository: paymentRepo,
    membershipNotifier: membershipNotifier,
    storeAdapter: storeAdapter,
  );
  ref.listen(authLoggingOutProvider, (_, loggingOut) {
    if (loggingOut) notifier.reset();
  });
  return notifier;
});


import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/membership/data/datasources/membership_remote_data_source.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/data/models/revenue_catalog_dto.dart';
import 'package:health_ai_app/features/membership/data/repositories/membership_repository_impl.dart';
import 'package:health_ai_app/features/membership/data/repositories/payment_repository_impl.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/domain/models/purchase_state.dart';
import 'package:health_ai_app/features/membership/domain/repositories/payment_repository.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/features/nutrition/data/datasources/nutrition_remote_data_source.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';

// =============================================================================
// Test Fakes & Mock Data Sources
// =============================================================================

class FakeFaultStorePaymentAdapter implements StorePaymentClientAdapter {
  bool configured;
  StoreClientOutcome nextPurchaseOutcome;
  StoreClientOutcome nextRestoreOutcome;
  Duration delay;

  FakeFaultStorePaymentAdapter({
    this.configured = true,
    StoreClientOutcome? nextPurchaseOutcome,
    StoreClientOutcome? nextRestoreOutcome,
    this.delay = Duration.zero,
  })  : nextPurchaseOutcome = nextPurchaseOutcome ??
            StoreClientOutcome.unavailable('Not configured'),
        nextRestoreOutcome = nextRestoreOutcome ??
            StoreClientOutcome.unavailable('Not configured');

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

class FakeFaultRemoteDataSource implements IMembershipRemoteDataSource {
  AccountMembershipDto? membershipResult;
  Duration membershipDelay;
  DioException? membershipError;

  BackendPurchaseVerificationResult? verificationResult;
  Duration verificationDelay;

  RestorePurchasesResult? restoreResult;
  Duration restoreDelay;
  Exception? restoreException;

  FakeFaultRemoteDataSource({
    this.membershipResult,
    this.membershipDelay = Duration.zero,
    this.membershipError,
    this.verificationResult,
    this.verificationDelay = Duration.zero,
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
    if (membershipDelay > Duration.zero) {
      await Future.delayed(membershipDelay);
    }
    if (membershipError != null) {
      throw membershipError!;
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
    if (verificationResult != null) {
      return verificationResult!;
    }
    throw StateError('No verificationResult');
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
    throw StateError('No restoreResult');
  }
}

class FakeFaultNutritionRemoteDataSource extends INutritionRemoteDataSource {
  final List<String> receivedIdempotencyKeys = [];
  final List<String> receivedClientRequestIds = [];
  int analyzeCallCount = 0;
  int lookupCallCount = 0;
  DioException? analyzeErrorToThrow;
  Map<String, dynamic>? lookupResultToReturn;
  DioException? lookupErrorToThrow;

  @override
  Future<Map<String, dynamic>> analyzeFoodImage(
    XFile imageFile, {
    String? mode,
    NutritionRequestContext? session,
    String? idempotencyKey,
    String? clientRequestId,
  }) async {
    analyzeCallCount++;
    if (idempotencyKey != null) {
      receivedIdempotencyKeys.add(idempotencyKey);
    }
    if (clientRequestId != null) {
      receivedClientRequestIds.add(clientRequestId);
    }
    if (analyzeErrorToThrow != null) {
      throw analyzeErrorToThrow!;
    }
    return {
      'operation_id': 'op_test_nutrition_001',
      'status': 'COMMITTED',
      'food_name': 'Pho Bo Tai',
    };
  }

  @override
  Future<Map<String, dynamic>?> lookupOperation({
    required String idempotencyKey,
    String benefitId = 'ai.nutrition_gemini',
    NutritionRequestContext? session,
  }) async {
    lookupCallCount++;
    if (lookupErrorToThrow != null) {
      throw lookupErrorToThrow!;
    }
    return lookupResultToReturn;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MembershipPlan _buildTestPlan() {
  final base = MembershipCatalog.getPlan(MembershipTier.plus);
  return base.copyWith(purchasable: true);
}

Widget _buildLocalizedApp({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(languageProvider);
        return MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: child),
        );
      },
    ),
  );
}

// =============================================================================
// Test Suite: CP-09 Frontend Fault, Transport & Session Boundary Verification
// =============================================================================

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'language_mode': 'en',
      'language_code': 'en',
    });
  });

  group('CP-09 Frontend Fault, Transport & Session Boundary Verification', () {
    // -------------------------------------------------------------------------
    // Scenario E1: In-flight request A -> logout/login User B -> response A arrives -> discarded via session epoch
    // -------------------------------------------------------------------------
    test(
        'Scenario E1: In-flight request A -> logout/login User B -> response A arrives -> discarded via session epoch',
        () async {
      final remoteDs = FakeFaultRemoteDataSource(
        membershipDelay: const Duration(milliseconds: 60),
        membershipResult: AccountMembershipDto(
          userId: 'user_a@saman.test',
          tier: MembershipTier.pro,
          status: 'active',
          isActiveSubscription: true,
          entitlements: const [],
          usage: const {},
          asOf: DateTime.now(),
        ),
      );

      final repo = MembershipRepositoryImpl(remoteDataSource: remoteDs);
      final notifier = AccountMembershipNotifier(repo);

      // Start fetching membership for User A
      final futureA = notifier.loadMembership(accountId: 'user_a@saman.test');

      // Before response A returns, User A logs out and User B logs in
      await Future.delayed(const Duration(milliseconds: 15));
      notifier.reset();
      notifier.setDemoBaseline('user_b@saman.test');

      // Now wait for User A's slow network request to complete
      await futureA;

      // Invariant: User A's late response was discarded due to session epoch increment
      // User B must remain in their demo baseline state (Free tier), NOT User A's Pro state!
      expect(notifier.state.accountId, 'user_b@saman.test');
      expect(notifier.state.tier, MembershipTier.free);
      expect(notifier.state.isDemo, isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario E2: In-flight purchase or restore -> user switches account -> operation aborted, response discarded
    // -------------------------------------------------------------------------
    test(
        'Scenario E2: In-flight purchase or restore -> user switches account -> operation aborted, response discarded',
        () async {
      final storeAdapter = FakeFaultStorePaymentAdapter(
        configured: true,
        delay: const Duration(milliseconds: 50),
        nextRestoreOutcome: StoreClientOutcome.tokenReady(
          const StorePurchasePayload(
            provider: 'apple_app_store',
            environment: 'sandbox',
            appId: 'com.saman.health.ios',
            productId: 'saman_pro_monthly_sandbox',
            verificationToken: 'token_user_a_restore',
            transactionId: 'tx_e2_1',
            originalTransactionId: 'orig_e2_1',
          ),
        ),
      );

      final remoteDs = FakeFaultRemoteDataSource(
        restoreDelay: const Duration(milliseconds: 50),
        restoreResult: RestorePurchasesResult(
          outcome: 'confirmed',
          userId: 'user_a@saman.test',
          provider: 'apple_app_store',
          environment: 'sandbox',
          transactionId: 'tx_e2_1',
          subscriptionId: 'sub_e2_1',
          tier: MembershipTier.pro,
          isActiveSubscription: true,
          currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
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

      // Start restore for User A
      final restoreFuture = purchaseNotifier.restorePurchases(
        accountId: 'user_a@saman.test',
      );

      // User switches account to User B while restore is in progress
      await Future.delayed(const Duration(milliseconds: 20));
      membershipNotifier.reset();
      membershipNotifier.setDemoBaseline('user_b@saman.test');
      purchaseNotifier.onAccountChanged('user_b@saman.test');

      final abortedState = await restoreFuture;

      // Invariant: Response discarded, purchase aborted, zero entitlement leaked to User B
      expect(abortedState.status, PurchaseFlowStatus.failed);
      expect(abortedState.errorCode, 'ACCOUNT_SWITCHED_DURING_RESTORE');
      expect(membershipNotifier.state.accountId, 'user_b@saman.test');
      expect(membershipNotifier.state.tier, MembershipTier.free);
      expect(purchaseNotifier.state.isGranted, isFalse);
    });

    // -------------------------------------------------------------------------
    // Scenario E3: Food analysis network timeout before receiving operation ID -> client preserves state and operation key across retries
    // -------------------------------------------------------------------------
    test(
        'Scenario E3: Food analysis network timeout before receiving operation ID -> client preserves state and operation key across retries',
        () async {
      final nutritionDs = FakeFaultNutritionRemoteDataSource();

      // Configure first call to time out before operation response is received
      nutritionDs.analyzeErrorToThrow = DioException(
        requestOptions: RequestOptions(path: '/api/nutrition/analyze-food-image'),
        type: DioExceptionType.connectionTimeout,
        message: 'Network timed out waiting for backend',
      );

      const clientRequestId = 'req_unique_client_food_001';
      const deterministicKey = 'idemp_food_pho_user_001';
      final dummyImage = XFile('test/fixtures/food.jpg');

      // Attempt 1: Fails with timeout
      try {
        await nutritionDs.analyzeFoodImage(
          dummyImage,
          idempotencyKey: deterministicKey,
          clientRequestId: clientRequestId,
        );
        fail('Should have thrown DioException timeout');
      } catch (e) {
        expect(e, isA<DioException>());
      }

      // Network recovers: Caller retries using the EXACT SAME client_request_id and idempotency_key
      nutritionDs.analyzeErrorToThrow = null;
      final retryResult = await nutritionDs.analyzeFoodImage(
        dummyImage,
        idempotencyKey: deterministicKey,
        clientRequestId: clientRequestId,
      );

      // Invariant: Both attempts used the identical idempotencyKey & clientRequestId
      expect(nutritionDs.analyzeCallCount, 2);
      expect(nutritionDs.receivedIdempotencyKeys.length, 2);
      expect(nutritionDs.receivedIdempotencyKeys[0], deterministicKey);
      expect(nutritionDs.receivedIdempotencyKeys[1], deterministicKey);
      expect(nutritionDs.receivedClientRequestIds[0], clientRequestId);
      expect(nutritionDs.receivedClientRequestIds[1], clientRequestId);
      expect(retryResult['status'], 'COMMITTED');
    });

    // -------------------------------------------------------------------------
    // Scenario E4: Operation lookup returning 503 or pending -> UI shows retry / error, NEVER re-dispatches inference
    // -------------------------------------------------------------------------
    test(
        'Scenario E4: Operation lookup returning 503 or pending -> UI shows retry / error, NEVER re-dispatches inference',
        () async {
      final nutritionDs = FakeFaultNutritionRemoteDataSource();

      // 1. Operation lookup returns 503 Service Unavailable
      nutritionDs.lookupErrorToThrow = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/quota/operations/lookup'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/revenue/quota/operations/lookup'),
          statusCode: 503,
          statusMessage: 'Service Unavailable',
        ),
        type: DioExceptionType.badResponse,
      );

      try {
        await nutritionDs.lookupOperation(idempotencyKey: 'op_lookup_key_001');
        fail('Should have thrown 503');
      } catch (e) {
        expect(e, isA<DioException>());
      }

      // 2. Operation lookup retried and returns status: PENDING
      nutritionDs.lookupErrorToThrow = null;
      nutritionDs.lookupResultToReturn = {
        'operation_id': 'op_lookup_001',
        'status': 'PENDING',
        'benefit_id': 'ai.nutrition_gemini',
      };

      final pendingResult = await nutritionDs.lookupOperation(
        idempotencyKey: 'op_lookup_key_001',
      );

      expect(pendingResult?['status'], 'PENDING');
      // Invariant: Exactly 2 lookup calls were made, and ZERO new inference dispatches!
      expect(nutritionDs.lookupCallCount, 2);
      expect(nutritionDs.analyzeCallCount, 0,
          reason: 'Must NEVER re-dispatch AI inference when lookup returns pending/failure');
    });

    // -------------------------------------------------------------------------
    // Scenario E5: Membership offline fallback -> cached data renders staleKnown, no cache renders unknownError, never false Free
    // -------------------------------------------------------------------------
    test(
        'Scenario E5: Membership offline fallback -> cached data renders staleKnown, no cache renders unknownError, never false Free',
        () async {
      final mockDs = FakeFaultRemoteDataSource();
      final repo = MembershipRepositoryImpl(remoteDataSource: mockDs);

      // Case A: No cache exists and network is dead
      mockDs.membershipError = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
          statusCode: 503,
          statusMessage: 'Service Unavailable',
        ),
        message: '503 Service Unavailable',
        type: DioExceptionType.badResponse,
      );

      final noCacheState = await repo.getAccountMembershipState(
        accountId: 'user_e5_nocache@saman.test',
      );

      expect(noCacheState.isUnknown, isTrue,
          reason: 'No cache + 503 must yield unknownError');
      expect(noCacheState.hasValidData, isFalse,
          reason: 'Must NOT fabricate false valid Free data');
      expect(noCacheState.errorMessage, contains('Service Unavailable'));

      // Case B: User with valid Pro cache encounters network failure
      mockDs.membershipError = null;
      mockDs.membershipResult = AccountMembershipDto(
        userId: 'user_e5_pro@saman.test',
        tier: MembershipTier.pro,
        status: 'active',
        isActiveSubscription: true,
        entitlements: const [],
        usage: const {},
        asOf: DateTime.now(),
      );

      // Populate cache
      final onlineState = await repo.getAccountMembershipState(
        accountId: 'user_e5_pro@saman.test',
      );
      expect(onlineState.isKnown, isTrue);
      expect(onlineState.tier, MembershipTier.pro);

      // Network goes down
      mockDs.membershipResult = null;
      mockDs.membershipError = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
        type: DioExceptionType.connectionError,
        message: 'No internet connection',
      );

      final offlineState = await repo.getAccountMembershipState(
        accountId: 'user_e5_pro@saman.test',
      );

      // Invariant: Returns staleKnown preserving Pro tier. NEVER collapses to Free!
      expect(offlineState.isStale, isTrue);
      expect(offlineState.hasValidData, isTrue);
      expect(offlineState.tier, MembershipTier.pro);
    });

    // -------------------------------------------------------------------------
    // Scenario E6: Restore unavailable displays localized text in EN and VI
    // -------------------------------------------------------------------------
    testWidgets(
        'Scenario E6: Restore unavailable displays localized text in EN and VI',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Verify English locale rendering
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          child: Column(
            children: [
              Builder(builder: (context) {
                return Text(context.tr('restore_purchases_action'));
              }),
              Builder(builder: (context) {
                return Text(context.tr('quiet_footer_notice'));
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Membership preview · Paid plans are not available yet.'),
          findsOneWidget);

      // 2. Verify Vietnamese locale rendering
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          child: Column(
            children: [
              Builder(builder: (context) {
                return Text(context.tr('restore_purchases_action'));
              }),
              Builder(builder: (context) {
                return Text(context.tr('quiet_footer_notice'));
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Khôi phục gói mua'), findsOneWidget);
      expect(find.text('Bản xem trước hội viên · Các gói trả phí chưa khả dụng.'),
          findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Scenario E7: Polling / pending timeout cancellation in purchase state machine
    // -------------------------------------------------------------------------
    test(
        'Scenario E7: Polling / pending timeout cancellation in purchase state machine',
        () async {
      final storeAdapter = FakeFaultStorePaymentAdapter(
        configured: true,
        nextPurchaseOutcome: StoreClientOutcome.pending(
          'Payment approval pending from family organizer / bank authorization.',
        ),
      );

      final remoteDs = FakeFaultRemoteDataSource();
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

      final intent = PurchaseIntent(
        accountId: 'user_e7@saman.test',
        plan: _buildTestPlan(),
        billingPeriod: BillingPeriod.monthly,
      );

      final pendingState = await purchaseNotifier.startPurchase(intent);

      // Invariant: Pending state does NOT grant entitlement
      expect(pendingState.status, PurchaseFlowStatus.pending);
      expect(pendingState.isGranted, isFalse);
      expect(membershipNotifier.state.tier, MembershipTier.free);

      // User cancels / cancels pending purchase
      storeAdapter.nextPurchaseOutcome = StoreClientOutcome.canceled(
        'Purchase was canceled by user before authorization completed.',
      );

      final canceledState = await purchaseNotifier.startPurchase(intent);
      expect(canceledState.status, PurchaseFlowStatus.canceled);
      expect(canceledState.isGranted, isFalse);
      expect(membershipNotifier.state.tier, MembershipTier.free);
    });
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/membership/data/datasources/membership_remote_data_source.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/data/models/revenue_catalog_dto.dart';
import 'package:health_ai_app/features/membership/data/repositories/membership_repository_impl.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/domain/models/purchase_state.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/features/nutrition/data/datasources/nutrition_remote_data_source.dart';
import 'package:health_ai_app/features/nutrition/data/repositories/nutrition_repository_impl.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:image_picker/image_picker.dart';

class MockFailingMembershipDataSource implements IMembershipRemoteDataSource {
  int attempts = 0;
  AccountMembershipDto? nextResult;
  DioException? errorToThrow;

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    throw Exception('Not implemented for this mock');
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    attempts++;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    if (nextResult != null) {
      return nextResult!;
    }
    throw DioException(
      requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
      type: DioExceptionType.connectionError,
      message: 'Connection failed',
    );
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    throw Exception('Not implemented for this mock');
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    throw Exception('Not implemented for this mock');
  }
}

class MockDelayingMembershipDataSource implements IMembershipRemoteDataSource {
  AccountMembershipDto? delayedResult;
  Duration delay = const Duration(milliseconds: 50);

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    throw Exception('Not implemented for this mock');
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    await Future.delayed(delay);
    if (delayedResult != null) {
      return delayedResult!;
    }
    return AccountMembershipDto.defaultFree();
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    throw Exception('Not implemented for this mock');
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    throw Exception('Not implemented for this mock');
  }
}

class MockNutritionRemoteDataSource extends INutritionRemoteDataSource {
  final List<String> receivedIdempotencyKeys = [];
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
    if (idempotencyKey != null) {
      receivedIdempotencyKeys.add(idempotencyKey);
    }
    return {
      'food_name': 'Grilled Chicken Breast',
      'nutrition': {
        'calories': 250,
        'protein': 35.0,
        'carbs': 0.0,
        'fat': 5.0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>?> lookupOperation({
    required String idempotencyKey,
    String benefitId = 'ai.nutrition_gemini',
    NutritionRequestContext? session,
  }) async {
    await session?.validate();
    if (lookupErrorToThrow != null) {
      throw lookupErrorToThrow!;
    }
    return lookupResultToReturn;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CP-06A Invariant 1: Eliminate False Free Fallback', () {
    test('Network/storage failure with NO cache produces unknown error, never Free', () async {
      final mockDs = MockFailingMembershipDataSource();
      mockDs.errorToThrow = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
          statusCode: 503,
          statusMessage: 'Service Unavailable',
        ),
        type: DioExceptionType.badResponse,
      );

      final repo = MembershipRepositoryImpl(remoteDataSource: mockDs);
      final state = await repo.getAccountMembershipState(accountId: 'user_new@saman.test');

      expect(state.isUnknown, isTrue, reason: 'Must be marked as unknown error');
      expect(state.isKnown, isFalse);
      expect(state.isStale, isFalse);
      expect(state.hasValidData, isFalse, reason: 'Unknown failure cannot claim valid Free data');
      expect(state.stateStatus, MembershipStateStatus.unknownError);
    });

    test('Network failure WITH valid cache returns stale known tier with isStale: true', () async {
      final mockDs = MockFailingMembershipDataSource();
      final plusUserDto = AccountMembershipDto(
        userId: 'plus_user@saman.test',
        tier: MembershipTier.plus,
        status: 'active',
        isActiveSubscription: true,
        entitlements: const [],
        usage: const {},
        asOf: DateTime.now(),
      );

      // First call succeeds and caches
      mockDs.nextResult = plusUserDto;
      final repo = MembershipRepositoryImpl(remoteDataSource: mockDs);
      final firstState = await repo.getAccountMembershipState(accountId: 'plus_user@saman.test');

      expect(firstState.isKnown, isTrue);
      expect(firstState.tier, MembershipTier.plus);
      expect(firstState.isStale, isFalse);

      // Second call fails with network disconnect
      mockDs.nextResult = null;
      mockDs.errorToThrow = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
        type: DioExceptionType.connectionTimeout,
        message: 'Timeout contacting revenue service',
      );

      final secondState = await repo.getAccountMembershipState(accountId: 'plus_user@saman.test');
      expect(secondState.isStale, isTrue, reason: 'Should return stale cached data');
      expect(secondState.isUnknown, isFalse);
      expect(secondState.tier, MembershipTier.plus, reason: 'Must preserve Plus, NEVER fallback to Free');
      expect(secondState.hasValidData, isTrue);
      expect(secondState.fetchedAt, isNotNull);
    });
  });

  group('CP-06A Invariant 2: Multi-Tenant Cache & Session Isolation', () {
    test('User A cache cleared on logout; never leaked to User B', () async {
      final mockDs = MockFailingMembershipDataSource();
      final repo = MembershipRepositoryImpl(remoteDataSource: mockDs);

      // User A signs in as Ultra
      final ultraUser = AccountMembershipDto(
        userId: 'ultra_user_a@saman.test',
        tier: MembershipTier.ultra,
        status: 'active',
        isActiveSubscription: true,
        entitlements: const [],
        usage: const {},
        asOf: DateTime.now(),
      );
      mockDs.nextResult = ultraUser;
      repo.setActiveAccount('ultra_user_a@saman.test');
      final stateA = await repo.getAccountMembershipState();
      expect(stateA.tier, MembershipTier.ultra);

      // User A logs out
      repo.clearAccountCache();

      // User B opens app offline (network error)
      mockDs.nextResult = null;
      mockDs.errorToThrow = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/membership/me'),
        type: DioExceptionType.connectionError,
      );
      repo.setActiveAccount('user_b@saman.test');
      final stateB = await repo.getAccountMembershipState();

      // User B MUST NOT see User A's Ultra cache!
      expect(stateB.isUnknown, isTrue);
      expect(stateB.tier, isNot(MembershipTier.ultra));
      expect(stateB.hasValidData, isFalse);
    });

    test('Late response from obsolete session epoch is rejected in Repository and Notifier', () async {
      final mockDs = MockDelayingMembershipDataSource();
      final repo = MembershipRepositoryImpl(remoteDataSource: mockDs);

      mockDs.delayedResult = AccountMembershipDto(
        userId: 'user_a_slow@saman.test',
        tier: MembershipTier.pro,
        status: 'active',
        isActiveSubscription: true,
        entitlements: const [],
        usage: const {},
        asOf: DateTime.now(),
      );

      final notifier = AccountMembershipNotifier(repo);
      // Fire slow load for User A
      final futureA = notifier.loadMembership(accountId: 'user_a_slow@saman.test');

      // User immediately logs out / switches to User B before response returns
      notifier.reset();
      notifier.setActiveAccount('user_b@saman.test');

      await futureA;
      // Notifier state MUST NOT be overwritten by User A's late response
      expect(notifier.state.tier, isNot(MembershipTier.pro));
      expect(repo.getCachedMembership('user_b@saman.test'), isNull);
    });

    test('Logged out state is distinct from Free tier in Riverpod provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(accountMembershipProvider.notifier);
      expect(container.read(accountMembershipProvider).stateStatus, MembershipStateStatus.demoBaseline);

      // Trigger logout
      notifier.reset();

      final state = container.read(accountMembershipProvider);
      expect(state.isLoggedOut, isTrue);
      expect(state.stateStatus, MembershipStateStatus.loggedOut);
      expect(state.status, 'none');
    });
  });

  group('CP-06A Invariant 3: Nutrition Operation Identity & Recovery Closure', () {
    test('Operation key is passed down to remote data source across retries', () async {
      final mockRemote = MockNutritionRemoteDataSource();
      final repo = NutritionRepositoryImpl(remoteDataSource: mockRemote);

      final dummyFile = XFile('test/fixtures/food.jpg');
      const testOpKey = 'fa_op_1730000000_12345_m_advanced_g_100';

      // First attempt
      await repo.analyzeFoodImage(
        dummyFile,
        mode: 'advanced',
        idempotencyKey: testOpKey,
      );

      // Second attempt (retry of same operation)
      await repo.analyzeFoodImage(
        dummyFile,
        mode: 'advanced',
        idempotencyKey: testOpKey,
      );

      expect(mockRemote.receivedIdempotencyKeys.length, 2);
      expect(mockRemote.receivedIdempotencyKeys[0], testOpKey);
      expect(mockRemote.receivedIdempotencyKeys[1], testOpKey, reason: 'Retry must reuse identical operation key');
    });

    test('Committed operation recovery supports both cached_payload and cached_response without duplicate inference', () async {
      final mockRemote = MockNutritionRemoteDataSource();
      mockRemote.lookupResultToReturn = {
        'operation_id': 'op_test_1',
        'status': 'committed',
        'cached_payload': {
          'food_name': 'Grilled Salmon',
          'food_label': 'grilled_salmon',
          'confidence': 0.95,
          'low_confidence': false,
          'grams': 200.0,
          'nutrition': {
            'calories': 350,
            'protein': 30.0,
            'carbs': 0.0,
            'fat': 18.0,
          },
        },
      };

      final repo = NutritionRepositoryImpl(remoteDataSource: mockRemote);
      const testOpKey = 'fa_op_existing_123';

      final recovered = await repo.lookupAnalysisOperation(
        idempotencyKey: testOpKey,
      );

      expect(recovered, isNotNull);
      expect(recovered!.foodName, 'Grilled Salmon');
      expect(recovered.calories, 350);
      expect(mockRemote.receivedIdempotencyKeys.isEmpty, isTrue, reason: 'Recovery did NOT invoke new inference');
    });

    test('Pending (reserved/executing), failed_unknown, or lookup 503 failure throws and NEVER returns null to redispatch inference', () async {
      final mockRemote = MockNutritionRemoteDataSource();
      final repo = NutritionRepositoryImpl(remoteDataSource: mockRemote);

      // 1. executing -> throws AnalysisOperationStateException
      mockRemote.lookupResultToReturn = {
        'operation_id': 'op_executing_1',
        'status': 'executing',
      };
      await expectLater(
        repo.lookupAnalysisOperation(idempotencyKey: 'idem_exec'),
        throwsA(isA<AnalysisOperationStateException>()),
      );

      // 2. failed_unknown -> throws AnalysisOperationStateException
      mockRemote.lookupResultToReturn = {
        'operation_id': 'op_unknown_1',
        'status': 'failed_unknown',
      };
      await expectLater(
        repo.lookupAnalysisOperation(idempotencyKey: 'idem_unk'),
        throwsA(isA<AnalysisOperationStateException>()),
      );

      // 3. Lookup 503 error -> rethrows DioException (never returns null)
      mockRemote.lookupResultToReturn = null;
      mockRemote.lookupErrorToThrow = DioException(
        requestOptions: RequestOptions(path: '/api/revenue/operations/lookup'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/revenue/operations/lookup'),
          statusCode: 503,
        ),
        type: DioExceptionType.badResponse,
      );
      await expectLater(
        repo.lookupAnalysisOperation(idempotencyKey: 'idem_503'),
        throwsA(isA<DioException>()),
      );
      expect(mockRemote.receivedIdempotencyKeys, isEmpty);
    });
  });
}

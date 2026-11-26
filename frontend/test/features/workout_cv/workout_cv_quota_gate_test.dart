import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import 'package:health_ai_app/features/workout_cv/data/services/workout_cv_quota_client.dart';

class _StubWorkoutCvQuotaClient extends WorkoutCvQuotaClient {
  final WorkoutCvAuthorizeResult result;
  int callCount = 0;

  _StubWorkoutCvQuotaClient(this.result)
      : super(
          client: MockClient((_) async => http.Response('{}', 200)),
          tokenGetter: () async => 'stub-token',
          bypassCheck: false,
        );

  @override
  Future<WorkoutCvAuthorizeResult> authorize({
    String? exerciseSlug,
    String sourceMode = 'realtime',
    String? idempotencyKey,
  }) async {
    callCount += 1;
    return result;
  }
}

class _GateHarness extends ConsumerWidget {
  final VoidCallback onCvOpened;

  const _GateHarness({required this.onCvOpened});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final authResult =
                await ref.read(workoutCvQuotaClientProvider).authorize(
                      exerciseSlug: 'squat',
                      sourceMode: 'realtime',
                    );
            if (!context.mounted) return;
            if (!authResult.allowed) {
              if (authResult.isQuotaExhausted || authResult.isUpgradeRequired) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      authResult.message ??
                          'Bạn đã dùng hết lượt Form Check AI trong tuần.',
                    ),
                  ),
                );
                await showUpgradeBottomSheet(
                  context,
                  tier: MembershipTier.pro,
                );
              }
              return;
            }
            onCvOpened();
          },
          child: const Text('Start Form Check'),
        ),
      ),
    );
  }
}

void main() {
  group('WorkoutCvQuotaClient unit tests', () {
    test('200 OK Free tier remaining units returns allowed=true and metadata',
        () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'allowed': true,
            'paywall_enforced': true,
            'tier': 'free',
            'limit_units': 3,
            'remaining_units': 2,
            'operation_id': 'op_free_001',
          }),
          200,
        );
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_test_token',
        bypassCheck: false,
      );

      final result = await client.authorize(
        exerciseSlug: 'squat',
        sourceMode: 'realtime',
        idempotencyKey: 'idem_123',
      );

      expect(
        capturedRequest.url.toString(),
        ApiConfig.workoutCvAuthorizeEndpoint,
      );
      expect(capturedRequest.headers['Authorization'], 'Bearer jwt_test_token');
      final sentBody =
          jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(sentBody['exercise_slug'], 'squat');
      expect(sentBody['source_mode'], 'realtime');
      expect(sentBody['idempotency_key'], 'idem_123');

      expect(result.allowed, isTrue);
      expect(result.paywallEnforced, isTrue);
      expect(result.tier, 'free');
      expect(result.limitUnits, 3);
      expect(result.remainingUnits, 2);
      expect(result.operationId, 'op_free_001');
      expect(result.isQuotaExhausted, isFalse);
      expect(result.isUpgradeRequired, isFalse);
      expect(result.isServiceUnavailable, isFalse);
    });

    test('200 OK Pro unlimited (-1) returns allowed=true', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'allowed': true,
            'paywall_enforced': true,
            'tier': 'pro',
            'limit_units': -1,
            'remaining_units': -1,
            'operation_id': 'op_pro_999',
          }),
          200,
        );
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_pro_token',
        bypassCheck: false,
      );

      final result = await client.authorize(
        exerciseSlug: 'deadlift',
        sourceMode: 'video_upload',
      );

      expect(result.allowed, isTrue);
      expect(result.tier, 'pro');
      expect(result.limitUnits, -1);
      expect(result.remainingUnits, -1);
      expect(result.operationId, 'op_pro_999');
    });

    test('200 OK with paywall_enforced=false returns allowed=true', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'allowed': true,
            'paywall_enforced': false,
            'tier': 'free',
            'limit_units': 3,
            'remaining_units': 3,
            'operation_id': 'op_bypass_001',
          }),
          200,
        );
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_token',
        bypassCheck: false,
      );

      final result = await client.authorize(exerciseSlug: 'push_up');

      expect(result.allowed, isTrue);
      expect(result.paywallEnforced, isFalse);
      expect(result.remainingUnits, 3);
      expect(result.operationId, 'op_bypass_001');
    });

    test('429 Too Many Requests with quota_exceeded returns isQuotaExhausted',
        () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'quota_exceeded',
              'message': 'Weekly Form Check limit reached',
              'tier': 'free',
              'limit_units': 3,
              'remaining_units': 0,
            },
          }),
          429,
        );
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_token',
        bypassCheck: false,
      );

      final result = await client.authorize(exerciseSlug: 'squat');

      expect(result.allowed, isFalse);
      expect(result.isQuotaExhausted, isTrue);
      expect(result.isUpgradeRequired, isFalse);
      expect(result.isServiceUnavailable, isFalse);
      expect(result.limitUnits, 3);
      expect(result.remainingUnits, 0);
      expect(result.message, 'Weekly Form Check limit reached');
    });

    test('403 Forbidden with entitlement_required returns isUpgradeRequired',
        () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'entitlement_required',
              'message': 'Pro membership required for Form Check',
              'tier': 'free',
            },
          }),
          403,
        );
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_token',
        bypassCheck: false,
      );

      final result = await client.authorize(exerciseSlug: 'squat');

      expect(result.allowed, isFalse);
      expect(result.isUpgradeRequired, isTrue);
      expect(result.isQuotaExhausted, isFalse);
      expect(result.isServiceUnavailable, isFalse);
      expect(result.message, 'Pro membership required for Form Check');
    });

    test('503 Service Unavailable returns isServiceUnavailable=true', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'detail': {'message': 'Quota service temporarily unavailable'},
          }),
          503,
        );
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_token',
        bypassCheck: false,
      );

      final result = await client.authorize(exerciseSlug: 'squat');

      expect(result.allowed, isFalse);
      expect(result.isServiceUnavailable, isTrue);
      expect(result.message, 'Quota service temporarily unavailable');
    });

    test('Network exception returns isServiceUnavailable=true', () async {
      final mockClient = MockClient((_) async {
        throw TimeoutException('Request timed out');
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => 'jwt_token',
        bypassCheck: false,
      );

      final result = await client.authorize(exerciseSlug: 'squat');

      expect(result.allowed, isFalse);
      expect(result.isServiceUnavailable, isTrue);
    });

    test('bypassCheck=true short-circuits without HTTP call', () async {
      var httpCalled = false;
      final mockClient = MockClient((_) async {
        httpCalled = true;
        return http.Response('{}', 500);
      });

      final client = WorkoutCvQuotaClient(
        client: mockClient,
        tokenGetter: () async => null,
        bypassCheck: true,
      );

      final result = await client.authorize(exerciseSlug: 'squat');

      expect(httpCalled, isFalse);
      expect(result.allowed, isTrue);
      expect(result.paywallEnforced, isFalse);
    });
  });

  group('WorkoutCv quota gate widget tests', () {
    testWidgets('allows navigation to CV flow when authorize returns allowed=true',
        (tester) async {
      var cvOpened = false;
      final stubClient = _StubWorkoutCvQuotaClient(
        const WorkoutCvAuthorizeResult(
          allowed: true,
          paywallEnforced: true,
          remainingUnits: 2,
          operationId: 'op_1',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvQuotaClientProvider.overrideWithValue(stubClient),
          ],
          child: MaterialApp(
            home: _GateHarness(onCvOpened: () => cvOpened = true),
          ),
        ),
      );

      await tester.tap(find.text('Start Form Check'));
      await tester.pumpAndSettle();

      expect(stubClient.callCount, 1);
      expect(cvOpened, isTrue);
      expect(find.byType(UpgradeBottomSheet), findsNothing);
    });

    testWidgets(
        'blocks CV flow and opens Pro upgrade paywall when authorize returns 429',
        (tester) async {
      var cvOpened = false;
      final stubClient = _StubWorkoutCvQuotaClient(
        const WorkoutCvAuthorizeResult(
          allowed: false,
          paywallEnforced: true,
          isQuotaExhausted: true,
          limitUnits: 3,
          remainingUnits: 0,
          message: 'Hết lượt Form Check miễn phí tuần này.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvQuotaClientProvider.overrideWithValue(stubClient),
          ],
          child: MaterialApp(
            home: _GateHarness(onCvOpened: () => cvOpened = true),
          ),
        ),
      );

      await tester.tap(find.text('Start Form Check'));
      await tester.pumpAndSettle();

      expect(stubClient.callCount, 1);
      expect(cvOpened, isFalse);
      expect(
        find.text('Hết lượt Form Check miễn phí tuần này.'),
        findsOneWidget,
      );
      expect(find.byType(UpgradeBottomSheet), findsOneWidget);
    });

    testWidgets(
        'blocks CV flow and opens Pro upgrade paywall when authorize returns 403',
        (tester) async {
      var cvOpened = false;
      final stubClient = _StubWorkoutCvQuotaClient(
        const WorkoutCvAuthorizeResult(
          allowed: false,
          paywallEnforced: true,
          isUpgradeRequired: true,
          message: 'Tính năng yêu cầu gói Pro.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutCvQuotaClientProvider.overrideWithValue(stubClient),
          ],
          child: MaterialApp(
            home: _GateHarness(onCvOpened: () => cvOpened = true),
          ),
        ),
      );

      await tester.tap(find.text('Start Form Check'));
      await tester.pumpAndSettle();

      expect(stubClient.callCount, 1);
      expect(cvOpened, isFalse);
      expect(find.text('Tính năng yêu cầu gói Pro.'), findsOneWidget);
      expect(find.byType(UpgradeBottomSheet), findsOneWidget);
    });
  });
}

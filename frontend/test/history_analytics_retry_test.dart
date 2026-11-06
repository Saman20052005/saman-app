import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/services/analytics_service.dart';

class _FakeAnalyticsService extends AnalyticsService {
  final operationIds = <String>[];
  int calls = 0;
  int preflightCalls = 0;

  @override
  Future<AnalyticsQuote> getPreflightQuote(int rangeDays) async {
    preflightCalls++;
    return AnalyticsQuote(
      quoteId: 'quote-$rangeDays-$calls',
      rangeDays: rangeDays,
      rawNutritionCount: 2,
      activeDays: 1,
      workoutSessions: 1,
      includedWorkouts: 1,
      workoutTruncated: false,
      estimatedTokens: 100,
      quotaCost: 1,
    );
  }

  @override
  Future<Map<String, dynamic>> executeAnalytics({
    required String quoteId,
    required int rangeDays,
    required bool confirm,
    required String operationId,
  }) async {
    calls++;
    operationIds.add(operationId);
    if (calls == 1) throw const QuoteExpiredException();
    return {'report': 'done'};
  }
}

void main() {
  testWidgets(
      'multi-tap is debounced and expired quote requires confirmation again',
      (tester) async {
    final service = _FakeAnalyticsService();
    var executeCalls = 0;
    final executeCompleter = Completer<String>();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => HistoryAnalyticsSheet(
                        service: service,
                        onExecute: (_) async {
                          executeCalls++;
                          if (executeCalls == 1) {
                            await executeCompleter.future;
                            throw const QuoteExpiredException();
                          }
                          return 'ok';
                        },
                      ),
                    ),
                    child: const Text('Open'),
                  )),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Xác nhận phân tích'));
    }
    expect(executeCalls, 1);
    executeCompleter.complete('expired');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Báo giá đã hết hạn. Đang lấy báo giá mới, vui lòng xác nhận lại.'),
        findsOneWidget);
    expect(service.preflightCalls, 2);
    expect(find.text('Xác nhận phân tích'), findsOneWidget);
    await tester.tap(find.text('Xác nhận phân tích'));
    await tester.pumpAndSettle();
    expect(executeCalls, 2);
  });

  test('retry keeps the generated operation id', () async {
    final service = _FakeAnalyticsService();
    final container = ProviderContainer(overrides: [
      chatControllerProvider.overrideWith(
          (ref) => ChatController(ref, analyticsService: service)),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider.notifier);
    const quote = AnalyticsQuote(
      quoteId: 'stable-quote',
      rangeDays: 7,
      rawNutritionCount: 0,
      activeDays: 0,
      workoutSessions: 0,
      includedWorkouts: 0,
      workoutTruncated: false,
      estimatedTokens: 10,
      quotaCost: 1,
    );
    await expectLater(controller.executeHistoryAnalytics(quote),
        throwsA(isA<QuoteExpiredException>()));
    await controller.executeHistoryAnalytics(quote);
    expect(service.operationIds, hasLength(2));
    expect(service.operationIds.first, service.operationIds.last);
    expect(service.operationIds.first, hasLength(32));
  });
}

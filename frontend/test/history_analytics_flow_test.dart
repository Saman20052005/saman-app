import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_action_row.dart';
import 'package:health_ai_app/services/analytics_service.dart';

class _FakeAnalyticsService extends AnalyticsService {
  int quoteCalls = 0;

  @override
  Future<AnalyticsQuote> getPreflightQuote(int rangeDays) async {
    quoteCalls++;
    return AnalyticsQuote(
      quoteId: 'quote-$rangeDays-$quoteCalls',
      rangeDays: rangeDays,
      rawNutritionCount: 12,
      activeDays: 5,
      workoutSessions: 8,
      includedWorkouts: 8,
      workoutTruncated: false,
      estimatedTokens: 1200,
      quotaCost: 1,
    );
  }
}

void main() {
  for (final size in const [Size(390, 844), Size(1440, 960)]) {
    testWidgets('analytics sheet flow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _FakeAnalyticsService();
      var executeCount = 0;
      final executeCompleter = Completer<String>();

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SamanChatActionRow(
              item: SamanChatActionItem.approvedActions.last,
              onTap: (_) {},
              analyticsSheetBuilder: (_) => HistoryAnalyticsSheet(
                service: service,
                onExecute: (_) async {
                  executeCount++;
                  return executeCompleter.future;
                },
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Phân tích xu hướng'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Từ khi đăng ký'), findsOneWidget);
      final locked = tester.widget<ChoiceChip>(find.ancestor(
        of: find.textContaining('Từ khi đăng ký'),
        matching: find.byType(ChoiceChip),
      ));
      expect(locked.onSelected, isNull);

      await tester.tap(find.widgetWithText(ChoiceChip, '14 ngày'));
      await tester.pumpAndSettle();
      expect(service.quoteCalls, 2);
      expect(find.text('Ước lượng: ~1200 tokens'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '30 ngày'));
      await tester.pumpAndSettle();
      expect(service.quoteCalls, 3);
      expect(find.text('Phạm vi: 30 ngày'), findsOneWidget);

      await tester.tap(find.text('Xác nhận phân tích'));
      await tester.pump();
      expect(executeCount, 1);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      executeCompleter.complete('report');
      await tester.pumpAndSettle();
    });
  }
}

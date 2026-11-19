import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/services/analytics_service.dart';

class _ControlledAnalyticsService extends AnalyticsService {
  _ControlledAnalyticsService({required this.handlers});

  final Map<int, Future<AnalyticsQuote> Function()> handlers;

  @override
  Future<AnalyticsQuote> getPreflightQuote(int rangeDays) {
    final handler = handlers[rangeDays];
    if (handler != null) return handler();
    throw UnimplementedError('No handler for rangeDays: $rangeDays');
  }
}

void main() {
  group('HistoryAnalyticsSheet Stitch Design Tests', () {
    testWidgets('Frame 1: Displays data, active days coverage, tokens and guidance',
        (tester) async {
      final quote = AnalyticsQuote(
        quoteId: 'quote-frame1-14',
        rangeDays: 14,
        rawNutritionCount: 38,
        activeDays: 12,
        workoutSessions: 14,
        includedWorkouts: 14,
        workoutTruncated: false,
        estimatedTokens: 3840,
        quotaCost: 1,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HistoryAnalyticsSheet(
                initialQuote: quote,
                isDemo: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Phân tích xu hướng'), findsOneWidget);
      expect(find.text('Xem xu hướng từ nhật ký ăn uống và tập luyện của bạn.'),
          findsOneWidget);

      // Time range pills
      expect(find.text('7 ngày'), findsOneWidget);
      expect(find.text('14 ngày'), findsOneWidget);
      expect(find.text('30 ngày'), findsOneWidget);

      // Locked row
      expect(find.text('Từ khi đăng ký'), findsOneWidget);
      expect(
          find.text('Chưa hỗ trợ trong bản thử nghiệm'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

      // Stats card
      expect(find.text('Dữ liệu trong 14 ngày qua'), findsOneWidget);
      expect(find.text('Dữ liệu minh họa'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
      expect(find.text('bữa ăn'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('buổi tập'), findsOneWidget);

      // Coverage and Token estimation
      expect(find.textContaining('12/14 ngày'), findsOneWidget);
      expect(find.text('Token ước tính'), findsOneWidget);
      expect(find.text('~3840 token'), findsOneWidget);

      // Guidance block
      expect(find.text('SAMAN SẼ PHÂN TÍCH'), findsOneWidget);
      expect(
          find.text(
              'Bạn đã tập thường xuyên thế nào và ghi bữa ăn đều đến đâu.'),
          findsOneWidget);
      expect(
          find.text('Kết quả sẽ xuất hiện trong cuộc trò chuyện này.'),
          findsOneWidget);

      // Action buttons
      expect(find.text('Xác nhận phân tích'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      // Confirm button is enabled for Frame 1
      final confirmBtn =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('Frame 2: Empty state displays 0 meals, 0 workouts, empty message and disables confirm in demo',
        (tester) async {
      final emptyQuote7 = AnalyticsQuote(
        quoteId: 'quote-frame2-7',
        rangeDays: 7,
        rawNutritionCount: 0,
        activeDays: 0,
        workoutSessions: 0,
        includedWorkouts: 0,
        workoutTruncated: false,
        estimatedTokens: 0,
        quotaCost: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HistoryAnalyticsSheet(
                initialQuote: emptyQuote7,
                isDemo: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stats card shows 0
      expect(find.text('Dữ liệu trong 7 ngày qua'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('bữa ăn'), findsOneWidget);
      expect(find.text('buổi tập'), findsOneWidget);

      // Empty state notice for 7 days
      expect(
          find.text(
              'Chưa có nhật ký trong khoảng này. Thử chọn 14 hoặc 30 ngày.'),
          findsOneWidget);

      // Token estimation & Guidance block MUST NOT be visible in empty state
      expect(find.text('Token ước tính'), findsNothing);
      expect(find.text('SAMAN SẼ PHÂN TÍCH'), findsNothing);

      // In demo mode with no data, confirm button is disabled
      final confirmBtn =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('Responsive resilience: No layout overflow at narrow 320px width',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final quote = AnalyticsQuote(
        quoteId: 'quote-narrow',
        rangeDays: 14,
        rawNutritionCount: 20,
        activeDays: 7,
        workoutSessions: 5,
        includedWorkouts: 5,
        workoutTruncated: false,
        estimatedTokens: 1500,
        quotaCost: 1,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HistoryAnalyticsSheet(
                initialQuote: quote,
                isDemo: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Xác nhận phân tích'), findsOneWidget);
    });

    testWidgets(
        'Rapid switching 7 -> 14 -> 30 days: Late responses do not overwrite, confirm matches selected range',
        (tester) async {
      final completer7 = Completer<AnalyticsQuote>();
      final completer14 = Completer<AnalyticsQuote>();
      final completer30 = Completer<AnalyticsQuote>();

      final service = _ControlledAnalyticsService(
        handlers: {
          7: () => completer7.future,
          14: () => completer14.future,
          30: () => completer30.future,
        },
      );

      AnalyticsQuote? executedQuote;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HistoryAnalyticsSheet(
                service: service,
                onExecute: (quote) async {
                  executedQuote = quote;
                  return 'done';
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Starts at 7 days, loading
      var confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Switch to 14 days
      await tester.tap(find.text('14 ngày'));
      await tester.pump();
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Switch to 30 days
      await tester.tap(find.text('30 ngày'));
      await tester.pump();
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Now complete 7 days late
      completer7.complete(AnalyticsQuote(
        quoteId: 'quote-7',
        rangeDays: 7,
        rawNutritionCount: 5,
        activeDays: 3,
        workoutSessions: 2,
        includedWorkouts: 2,
        workoutTruncated: false,
        estimatedTokens: 700,
        quotaCost: 1,
      ));
      await tester.pump();
      // Confirm button must STILL be disabled because 30 days is selected!
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Now complete 14 days late
      completer14.complete(AnalyticsQuote(
        quoteId: 'quote-14',
        rangeDays: 14,
        rawNutritionCount: 15,
        activeDays: 8,
        workoutSessions: 6,
        includedWorkouts: 6,
        workoutTruncated: false,
        estimatedTokens: 1400,
        quotaCost: 1,
      ));
      await tester.pump();
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Finally complete 30 days
      completer30.complete(AnalyticsQuote(
        quoteId: 'quote-30',
        rangeDays: 30,
        rawNutritionCount: 30,
        activeDays: 20,
        workoutSessions: 12,
        includedWorkouts: 12,
        workoutTruncated: false,
        estimatedTokens: 3000,
        quotaCost: 1,
      ));
      await tester.pumpAndSettle();

      // Now confirm button is enabled for 30 days
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNotNull);
      expect(find.text('Dữ liệu trong 30 ngày qua'), findsOneWidget);
      expect(find.text('~3000 token'), findsOneWidget);

      // Execute must use the 30-day quote
      await tester.tap(find.text('Xác nhận phân tích'));
      await tester.pumpAndSettle();
      expect(executedQuote, isNotNull);
      expect(executedQuote!.rangeDays, 30);
      expect(executedQuote!.quoteId, 'quote-30');
    });

    testWidgets(
        'Live flow empty data (0 meals, 0 workouts): Confirm is enabled AND estimated tokens are visible before confirming',
        (tester) async {
      final service = _ControlledAnalyticsService(
        handlers: {
          7: () async => AnalyticsQuote(
                quoteId: 'quote-empty-live',
                rangeDays: 7,
                rawNutritionCount: 0,
                activeDays: 0,
                workoutSessions: 0,
                includedWorkouts: 0,
                workoutTruncated: false,
                estimatedTokens: 150,
                quotaCost: 1,
              ),
        },
      );

      AnalyticsQuote? executedQuote;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HistoryAnalyticsSheet(
                service: service,
                isDemo: false, // Live flow
                onExecute: (quote) async {
                  executedQuote = quote;
                  return 'executed';
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 0 meals, 0 workouts
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('bữa ăn'), findsOneWidget);
      expect(find.text('buổi tập'), findsOneWidget);

      // Empty notice
      expect(
          find.text(
              'Chưa có nhật ký trong khoảng này. Thử chọn 14 hoặc 30 ngày.'),
          findsOneWidget);

      // Token estimation is clearly visible BEFORE clicking
      expect(find.text('Token ước tính'), findsOneWidget);
      expect(find.text('~150 token'), findsOneWidget);

      // Confirm button is ENABLED according to backend policy
      final confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNotNull);

      // Tapping confirm proceeds with empty data quote
      await tester.tap(find.text('Xác nhận phân tích'));
      await tester.pumpAndSettle();
      expect(executedQuote, isNotNull);
      expect(executedQuote!.quoteId, 'quote-empty-live');
    });
  });
}

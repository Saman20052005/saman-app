import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/ai_mode_selector.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/widgets.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/nutrition/widgets/meal_review_dialog.dart';

import 'features/nutrition/daily_story_controller_test.dart'
    show FoodHarness, foodReply;

// Exercise the production screen, controller, services and repositories. Only
// the HTTP boundary and platform storage use the existing isolated harness.
Future<void> _flush(WidgetTester tester) async {
  // Dio/storage continuations and modal route transitions run on separate
  // turns. Bound both explicitly so assertions see the completed transition.
  for (var turn = 0; turn < 3; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  for (final size in const [Size(390, 844), Size(1440, 960)]) {
    testWidgets('unified Core 3, analytics and food confirmation at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var chatAttempts = 0;
      late FoodHarness h;
      h = FoodHarness(onRequest: (request) async {
        if (request.path.endsWith('/api/chat')) {
          chatAttempts++;
          if (chatAttempts == 1) {
            return foodReply({'detail': 'Unavailable'}, 503);
          }
          return foodReply({
            'reply': 'Core 3 coaching reply',
            'conversation_id': 'cp06-conversation',
          });
        }
        if (request.path.endsWith('/analytics/preflight')) {
          final days = (request.data as Map)['range_days'];
          return foodReply({
            'quote_id': 'cp06-quote-$days',
            'range_days': days,
            'raw_nutrition_count': 3,
            'active_days': 2,
            'matched_workout_sessions': 2,
            'included_workout_sessions': 2,
            'workout_truncated': false,
            'estimated_tokens': 1200,
            'quota_cost': 1,
          });
        }
        if (request.path.endsWith('/analytics/execute')) {
          return foodReply({'report': 'CP-06 history report'});
        }
        return h.defaults(request);
      });
      await tester.runAsync(h.start);
      addTearDown(h.close);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: const ChatScreen(isTabActive: false),
          ),
        ),
      ));
      await _flush(tester);

      final controller = h.container.read(chatControllerProvider.notifier);
      ChatState state() => h.container.read(chatControllerProvider);
      expect(state().selectedAIMode, AIMode.core3);
      expect(find.byType(AIModeSelector), findsOneWidget);

      // Send through the composer, then retry with an independent draft.
      const question = 'How should I balance meals and training today?';
      await tester.enterText(find.byType(TextField), question);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _flush(tester);
      expect(state().failedUserMessage, question);
      expect(chatAttempts, 1);
      const draft = 'Keep this draft while I use the tools';
      await tester.enterText(find.byType(TextField), draft);
      final textController =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      textController.selection =
          const TextSelection(baseOffset: 2, extentOffset: 8);
      await tester.pump();
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await _flush(tester);
      final chatRequests = h.requests
          .where((request) => request.path.endsWith('/api/chat'))
          .toList();
      expect(chatRequests, hasLength(2));
      final payload = chatRequests.first.data as Map;
      expect(payload['message'], question);
      expect(payload['contract_version'], 'core3-local-v1');
      expect(payload['operation_id'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(chatRequests.last.data, equals(payload));
      expect(state().messages.where((message) => message.role == 'user'),
          hasLength(1));
      expect(state().messages.last.content, 'Core 3 coaching reply');
      expect(state().activeConversationId, 'cp06-conversation');
      expect(state().errorMessage, isNull);
      expect(textController.text, draft);
      expect(textController.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8));

      // The action remains reachable after the first chat turn. A quote and
      // changing its range must not execute or mutate the chat history.
      final messagesBeforeTools = List<ChatMessage>.of(state().messages);
      await tester.tap(find.text('Phân tích xu hướng'));
      await _flush(tester);
      expect(find.byType(HistoryAnalyticsSheet), findsOneWidget);
      expect(find.text('Ước lượng: ~1200 tokens'), findsOneWidget);
      for (final days in [14, 30]) {
        await tester.tap(find.widgetWithText(ChoiceChip, '$days ngày'));
        await _flush(tester);
        expect(find.text('Phạm vi: $days ngày'), findsOneWidget);
      }
      expect(h.writes('/analytics/execute'), 0);
      expect(state().messages, orderedEquals(messagesBeforeTools));
      await tester.tap(find.text('Xác nhận phân tích'));
      await _flush(tester);
      expect(find.byType(HistoryAnalyticsSheet), findsNothing);
      final analyticsRequest = h.requests.singleWhere(
          (request) => request.path.endsWith('/analytics/execute'));
      expect(analyticsRequest.data, {
        'quote_id': 'cp06-quote-30',
        'range_days': 30,
        'confirm': true,
        'operation_id': (analyticsRequest.data as Map)['operation_id'],
      });
      expect((analyticsRequest.data as Map)['operation_id'],
          matches(RegExp(r'^[0-9a-f]{32}$')));
      expect((analyticsRequest.data as Map)['operation_id'],
          isNot(payload['operation_id']));
      expect(state().messages.take(2), orderedEquals(messagesBeforeTools));
      expect(state().messages.last.content, 'CP-06 history report');

      // Composer attachment UI coexists with the current conversation.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _flush(tester);
      expect(find.byType(SamanAttachmentSheet), findsOneWidget);
      expect(find.text('Take food photo'), findsOneWidget);
      expect(find.text('Upload image'), findsOneWidget);
      expect(find.text('Tiêu chuẩn'), findsOneWidget);
      await tester.tap(find.text('✨ AI nâng cao'));
      await tester.pump();
      expect(find.text('Hỗ trợ món ăn phức hợp & món Việt Nam (Gemini)'),
          findsOneWidget);
      Navigator.of(tester.element(find.byType(SamanAttachmentSheet))).pop();
      await _flush(tester);

      // Simulate the picked-image event, keeping production food analysis and
      // the user-confirmed persistence path intact in both analysis modes.
      final messagesBeforeFood = List<ChatMessage>.of(state().messages);
      final mode = size.width < 600 ? 'standard' : 'advanced';
      await tester
          .runAsync(() => controller.analyzeFoodPhoto(h.photo(), mode: mode));
      await _flush(tester);
      expect(state().foodAnalysisState?.status, FoodAnalysisStatus.success);
      expect(state().foodAnalysisState?.mode, mode);
      expect(state().foodAnalysisState?.result?.foodName, 'Rice');
      expect(h.writes('/log-story'), 0);
      expect(h.writes('/logs'), 0);
      expect(state().messages, orderedEquals(messagesBeforeFood));
      final list =
          tester.widget<SamanMessageList>(find.byType(SamanMessageList));
      list.scrollController.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Log meal'),
        200,
        scrollable: find.descendant(
          of: find.byType(SamanMessageList),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Log meal'));
      await tester.pump();
      expect(find.text('Log meal').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Log meal').hitTestable());
      await _flush(tester);
      expect(find.byType(MealReviewDialog), findsOneWidget);
      expect(
          tester
              .widget<MealReviewDialog>(find.byType(MealReviewDialog))
              .onConfirm,
          isNotNull);
      expect(find.text('Lưu bữa này'), findsOneWidget);
      expect(h.writes('/logs'), 0);
      await tester.ensureVisible(find.text('Lưu bữa này'));
      await tester.tap(find.text('Lưu bữa này'));
      await _flush(tester);
      expect(find.byType(MealReviewDialog), findsNothing);
      expect(h.writes('/log-story'), 1);
      expect(h.writes('/logs'), 1);
      expect(state().foodAnalysisState?.isMealLogged, isTrue);
      expect(state().messages, orderedEquals(messagesBeforeFood));
      expect(state().activeConversationId, 'cp06-conversation');
      expect(state().selectedAIMode, AIMode.core3);
      expect(state().isLoading, isFalse);
      expect(textController.text, draft);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
    });
  }
}

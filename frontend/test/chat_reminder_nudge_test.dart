import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/models/saman_nudge.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_empty_state.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_header.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_monogram.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_reminder_nudge.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeNudgeChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];

  _FakeNudgeChatNotifier({ChatState? initialState})
      : super(initialState ?? ChatState(messages: []));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {
    sentMessages.add(text);
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(role: 'user', content: text),
        ChatMessage(
          role: 'assistant',
          content:
              'A grilled chicken rice bowl with greens would fit cleanly.',
        ),
      ],
      isLoading: false,
    );
  }

  @override
  void clearChat() {
    state = ChatState(messages: []);
  }

  @override
  Future<void> retry() async {}

  @override
  void clearError() {}

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}
}

Widget _buildWrapper({
  required _FakeNudgeChatNotifier notifier,
  SamanNudge? initialNudge,
  double width = 390,
  double height = 844,
}) {
  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: SizedBox(
        width: width,
        height: height,
        child: ChatScreen(initialNudge: initialNudge),
      ),
    ),
  );
}

SamanNudge _createSampleNudge({
  String? promptToSend = 'Plan a high-protein dinner based on my remaining nutrition targets.',
}) {
  return SamanNudge(
    id: 'test_dinner_nudge',
    message:
        'You still have 620 kcal and 35g protein left today. A high-protein dinner would close most of the gap before tomorrow’s upper-body session.',
    supportingLine: '• 1,780 / 2,400 kcal · 35g protein remaining',
    timestamp: DateTime(2026, 9, 22, 18, 15),
    primaryLabel: 'Plan dinner',
    secondaryLabel: 'Later',
    promptToSend: promptToSend,
  );
}

void main() {
  group('Saman Chat Phase 7 — State 04 Reminder / Proactive Nudge', () {
    testWidgets('1. Normal Chat with no nudge renders no reminder card',
        (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      await tester.pumpWidget(_buildWrapper(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.byType(SamanReminderNudge), findsNothing);
      expect(find.text('Plan dinner'), findsNothing);
      expect(find.text('Later'), findsNothing);
    });

    testWidgets('2-7. Explicit nudge renders Saman identity, timestamp, copy, supporting line & CTAs',
        (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      // 2. Saman identity & monogram
      expect(find.byType(SamanReminderNudge), findsOneWidget);
      expect(find.descendant(
        of: find.byType(SamanReminderNudge),
        matching: find.text('Saman'),
      ), findsOneWidget);
      expect(find.descendant(
        of: find.byType(SamanReminderNudge),
        matching: find.byType(SamanMonogram),
      ), findsOneWidget);

      // 3. Formatted timestamp
      expect(find.text('6:15 PM'), findsOneWidget);

      // 4. Main message
      expect(
        find.textContaining('You still have 620 kcal and 35g protein left today.'),
        findsOneWidget,
      );

      // 5. Supporting telemetry line
      expect(
        find.text('• 1,780 / 2,400 kcal · 35g protein remaining'),
        findsOneWidget,
      );

      // 6. Primary CTA
      expect(find.text('Plan dinner'), findsOneWidget);

      // 7. Secondary Later
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('8. Primary CTA dispatches normal Chat prompt', (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      // Tap primary CTA
      await tester.tap(find.text('Plan dinner'));
      await tester.pumpAndSettle();

      // Nudge is dismissed and prompt is dispatched
      expect(find.byType(SamanReminderNudge), findsNothing);
      expect(notifier.sentMessages, hasLength(1));
      expect(
        notifier.sentMessages.first,
        'Plan a high-protein dinner based on my remaining nutrition targets.',
      );

      // Both user prompt and assistant response appear in conversation
      expect(
        find.text('Plan a high-protein dinner based on my remaining nutrition targets.'),
        findsOneWidget,
      );
      expect(
        find.text('A grilled chicken rice bowl with greens would fit cleanly.'),
        findsOneWidget,
      );
    });

    testWidgets('9. Later button dismisses visible nudge presentation',
        (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SamanReminderNudge), findsOneWidget);

      // Tap Later
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      // Nudge is dismissed
      expect(find.byType(SamanReminderNudge), findsNothing);
      expect(notifier.sentMessages, isEmpty);
    });

    testWidgets('10-11. Nudge is NOT inserted into ChatMessage history or API messages',
        (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      // State messages must remain empty
      expect(notifier.state.messages, isEmpty);
    });

    testWidgets('12. Bell has NO green dot without active nudge', (tester) async {
      final notifier = _FakeNudgeChatNotifier();

      await tester.pumpWidget(_buildWrapper(notifier: notifier));
      await tester.pumpAndSettle();

      final headerFinder = find.byType(SamanChatHeader);
      expect(headerFinder, findsOneWidget);

      // Green dot must not be present
      final dotFinder = find.descendant(
        of: headerFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == SamanChatTokens.greenAccent &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(dotFinder, findsNothing);
    });

    testWidgets('13. Bell has green dot with active nudge', (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      final headerFinder = find.byType(SamanChatHeader);
      final dotFinder = find.descendant(
        of: headerFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == SamanChatTokens.greenAccent &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(dotFinder, findsOneWidget);
    });

    testWidgets('14. Drawer has strictly NO fake "2 active" count', (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      // Open drawer
      final menuBtn = find.byIcon(Icons.notes_rounded);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SamanChatDrawer), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);

      // Strictly NO fake unread count
      expect(find.text('2 active'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('15. 360px viewport renders nudge with NO overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(
          notifier: notifier,
          initialNudge: nudge,
          width: 360,
          height: 780,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SamanReminderNudge), findsOneWidget);
    });

    testWidgets('16. When nudge timestamp is null, timestamp is omitted entirely',
        (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      const nudge = SamanNudge(
        id: 'no_timestamp_nudge',
        message: 'Quick nutrition check.',
        supportingLine: '• 500 kcal remaining',
        timestamp: null,
        primaryLabel: 'Plan dinner',
        secondaryLabel: 'Later',
        promptToSend: 'Plan dinner',
      );

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SamanReminderNudge), findsOneWidget);
      // Fallback '6:15 PM' must NOT be rendered when timestamp is null
      expect(find.text('6:15 PM'), findsNothing);
      // No timestamp Text widget rendered inside the header row
      final nudgeFinder = find.byType(SamanReminderNudge);
      expect(
        find.descendant(
          of: nudgeFinder,
          matching: find.text('Saman'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        '17. New conversation clears active nudge, removes notification dots, and resets to empty state',
        (tester) async {
      final notifier = _FakeNudgeChatNotifier();
      final nudge = _createSampleNudge();

      await tester.pumpWidget(
        _buildWrapper(notifier: notifier, initialNudge: nudge),
      );
      await tester.pumpAndSettle();

      // Nudge and green dot are present
      expect(find.byType(SamanReminderNudge), findsOneWidget);
      final headerFinder = find.byType(SamanChatHeader);
      final dotPredicate = find.descendant(
        of: headerFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  SamanChatTokens.greenAccent &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(dotPredicate, findsOneWidget);

      // Trigger New conversation from Header
      final editBtn = find.byIcon(Icons.edit_square);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // Active nudge is dismissed
      expect(find.byType(SamanReminderNudge), findsNothing);
      // Green dot is gone
      expect(dotPredicate, findsNothing);
      // Chat state reset to empty state
      expect(find.byType(SamanChatEmptyState), findsOneWidget);
    });
  });
}

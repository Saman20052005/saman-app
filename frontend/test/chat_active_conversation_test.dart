import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/widgets.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeActiveChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];
  bool clearChatCalled = false;

  _FakeActiveChatNotifier({ChatState? initialState})
      : super(
          initialState ??
              ChatState(
                messages: [
                  ChatMessage(
                    role: 'user',
                    content: 'Should I train heavy today?',
                  ),
                  ChatMessage(
                    role: 'assistant',
                    content:
                        "Your recovery is slightly below baseline today. I’d keep the session, but reduce the top-set intensity to around **RPE 7–7.5**.",
                  ),
                ],
                isLoading: false,
              ),
        );

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {
    sentMessages.add(text);
    state = state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: text)],
      isLoading: false,
    );
  }

  @override
  void clearChat() {
    clearChatCalled = true;
    state = ChatState(messages: []);
  }
}

Widget _buildActiveTestWrapper({
  required _FakeActiveChatNotifier notifier,
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
      home: const ChatScreen(),
    ),
  );
}

void main() {
  group('Saman Chat Phase 2 - Active Conversation State', () {
    testWidgets(
        '1. Non-empty ChatState does NOT render Empty State headline or action rows',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Empty state items must NOT be present
      expect(find.text('Your coach is ready'), findsNothing);
      expect(
        find.text('Ask about training, meals, recovery, or what to do next.'),
        findsNothing,
      );
      expect(find.text('Review today\'s workout'), findsNothing);
      expect(find.text('Plan next meal'), findsNothing);
      expect(find.text('Check recovery'), findsNothing);
    });

    testWidgets(
        '2. User message renders with right-alignment and dark charcoal styling',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // SamanUserMessage widget is present
      expect(find.byType(SamanUserMessage), findsOneWidget);
      expect(find.text('Should I train heavy today?'), findsOneWidget);

      // Verify container styling
      final userContainerFinder = find.descendant(
        of: find.byType(SamanUserMessage),
        matching: find.byType(Container),
      );
      expect(userContainerFinder, findsOneWidget);

      final container = tester.widget<Container>(userContainerFinder);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, SamanChatTokens.userBubble);
      expect(
        decoration.border,
        Border.all(color: SamanChatTokens.userBubbleBorder, width: 1.0),
      );
      // No green accent fill
      expect(decoration.color, isNot(SamanChatTokens.greenAccent));
    });

    testWidgets(
        '3. Saman response renders "Saman" (Title case) with S monogram identity row',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.byType(SamanAssistantResponse), findsOneWidget);

      // Assistant identity row renders 'Saman' in Title case
      final assistantNameFinder = find.descendant(
        of: find.byType(SamanAssistantResponse),
        matching: find.text('Saman'),
      );
      expect(assistantNameFinder, findsOneWidget);

      // Monogram is present in assistant row
      final monogramFinder = find.descendant(
        of: find.byType(SamanAssistantResponse),
        matching: find.byType(SamanMonogram),
      );
      expect(monogramFinder, findsOneWidget);
    });

    testWidgets(
        '4. Legacy branding is completely absent (no "AI Coach", no "SAMAN" uppercase, no robot icon)',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Ensure legacy "AI Coach" is absent
      expect(find.text('AI Coach'), findsNothing);

      // Ensure no uppercase "SAMAN" in message feed
      final uppercaseSamanFinder = find.descendant(
        of: find.byType(SamanMessageList),
        matching: find.text('SAMAN'),
      );
      expect(uppercaseSamanFinder, findsNothing);

      // Ensure no robot icon
      expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
      expect(find.byIcon(Icons.smart_toy), findsNothing);
    });

    testWidgets(
        '5. Assistant response is NOT enclosed in old full bubble-card container',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Assistant response does not wrap the message body in a bubble-card container
      final assistantWidget = tester.widget<SamanAssistantResponse>(
        find.byType(SamanAssistantResponse),
      );
      expect(assistantWidget, isNotNull);

      // Directly uses MarkdownBody
      final markdownFinder = find.descendant(
        of: find.byType(SamanAssistantResponse),
        matching: find.byType(MarkdownBody),
      );
      expect(markdownFinder, findsOneWidget);
    });

    testWidgets('6. Markdown text correctly renders formatting',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      final markdownBody = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(
        markdownBody.data,
        contains('reduce the top-set intensity to around **RPE 7–7.5**'),
      );
    });

    testWidgets('7. Empty-State rapid chips are hidden once conversation starts',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Rapid chips must not be displayed in active conversation
      expect(find.byType(SamanChatRapidChips), findsNothing);
      expect(find.text('Post-workout meal'), findsNothing);
      expect(find.text('Protein check'), findsNothing);
    });

    testWidgets('8. Global Composer remains visible and functional',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.byType(SamanChatComposer), findsOneWidget);
      expect(
        find.text('Ask Saman about training, meals, recovery...'),
        findsOneWidget,
      );
    });

    testWidgets('9. Sending new message still dispatches through ChatController',
        (tester) async {
      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'What should I eat after?',
      );
      await tester.pump();

      // Tap send button
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(fakeNotifier.sentMessages, contains('What should I eat after?'));
    });

    testWidgets('10. No layout overflow at narrow mobile viewport (360x780)',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeActiveChatNotifier();
      await tester.pumpWidget(_buildActiveTestWrapper(
        notifier: fakeNotifier,
        width: 360,
        height: 780,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

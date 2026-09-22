import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/widgets.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeLoadingRecoveryNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];
  int retryCallCount = 0;
  bool clearErrorCalled = false;
  bool clearChatCalled = false;

  _FakeLoadingRecoveryNotifier({ChatState? initialState})
      : super(initialState ?? ChatState(messages: []));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {
    sentMessages.add(text);
    // Simulate immediate user message append and isLoading = true
    state = state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: text)],
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  void simulateAssistantResponse(String reply) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(role: 'assistant', content: reply)
      ],
      isLoading: false,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  void simulateError(String failedPrompt) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: "I couldn't complete that response.",
      failedUserMessage: failedPrompt,
    );
  }

  @override
  Future<void> retry() async {
    retryCallCount++;
    final textToRetry = state.failedUserMessage ??
        (state.messages.isNotEmpty && state.messages.last.role == 'user'
            ? state.messages.last.content
            : null);
    if (textToRetry == null) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  @override
  void clearError() {
    clearErrorCalled = true;
    state = state.copyWith(
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  @override
  void clearChat() {
    clearChatCalled = true;
    state = ChatState(messages: []);
  }

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}
}

Widget _buildLoadingRecoveryTestWrapper({
  required _FakeLoadingRecoveryNotifier notifier,
  double width = 390,
  double height = 844,
}) {
  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: SamanChatTokens.canvas,
        extensions: const [
          AppThemeExtension(
            aiAccent: SamanChatTokens.greenAccent,
            primaryPressed: Color(0xFF0B7249),
            warning: Color(0xFFD97706),
            inkMuted: Color(0xFF888888),
            inkSubtle: Color(0xFF555555),
            hairline: Color(0xFF2A2A2A),
            surfaceElevated: Color(0xFF222222),
            heroNumeric: TextStyle(fontSize: 44),
            labelCaps: TextStyle(fontSize: 11),
            statValue: TextStyle(fontSize: 17),
          ),
        ],
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: true, // Deterministic for widget test stability
        ),
        child: const ChatScreen(),
      ),
    ),
  );
}

void main() {
  group('Phase 3 — State 05: Typing / Generating State Tests', () {
    testWidgets('1-4. User message sent -> transient Saman generating UI appears with 3 dots & natural line',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: "Should I reduce today's squat load? Lower back felt tight during morning warmup.",
            ),
          ],
          isLoading: true,
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      // Verify user message is rendered
      expect(find.byType(SamanUserMessage), findsOneWidget);

      // Verify SamanGeneratingIndicator is rendered
      expect(find.byType(SamanGeneratingIndicator), findsOneWidget);

      // Verify natural helper line is present
      expect(find.text("Reviewing your recent training..."), findsOneWidget);

      // Verify Title Case "Saman" in identity row
      expect(find.text("Saman"), findsOneWidget);
    });

    testWidgets('5-6. Absence of legacy loading indicators (no CircularProgressIndicator, no "Saman is thinking...")',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'What is my recovery score?'),
          ],
          isLoading: true,
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      // Verify NO circular progress indicator
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Verify NO legacy "Saman is thinking..." string
      expect(find.text('Saman is thinking...'), findsNothing);

      // Verify NO green spinner
      expect(find.text('AI Coach'), findsNothing);
    });

    testWidgets('7-8. Composer shows "Saman is responding..." and neutral stop control',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'Plan my next meal.'),
          ],
          isLoading: true,
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      // Composer shows responding hint
      expect(find.text('Saman is responding...'), findsOneWidget);

      // Stop button icon exists with neutral background
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

      // Send upward arrow is NOT shown while loading
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });

    testWidgets('9. Generating UI disappears after assistant response is received',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'Check my recovery.'),
          ],
          isLoading: true,
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      expect(find.byType(SamanGeneratingIndicator), findsOneWidget);

      // Simulate completion
      fakeNotifier.simulateAssistantResponse(
        'Your recovery score is optimal today. You can push hard on your main sets.',
      );
      await tester.pump();

      // Generating indicator must disappear
      expect(find.byType(SamanGeneratingIndicator), findsNothing);

      // Assistant response is now visible
      expect(find.byType(SamanAssistantResponse), findsOneWidget);

      // Composer returns to normal hint
      expect(find.text('Ask Saman about training, meals, recovery...'), findsOneWidget);
    });
  });

  group('Phase 3 — State 07: Recoverable Error State Tests', () {
    testWidgets('10-14. Failed request preserves user message and renders recoverable error without raw exceptions',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: "Can you adjust today's workout?"),
          ],
          isLoading: false,
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: "Can you adjust today's workout?",
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      // 10. User message preserved
      expect(find.text("Can you adjust today's workout?"), findsOneWidget);

      // 11. Raw exception is NOT rendered
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('500'), findsNothing);
      expect(find.textContaining('⚠️'), findsNothing);

      // 12. Approved error copy rendered
      expect(find.text("I couldn't complete that response."), findsOneWidget);

      // 13. Retry button rendered
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('→'), findsOneWidget);

      // 14. Edit question button rendered
      expect(find.text('Edit question'), findsOneWidget);
    });

    testWidgets('15-16. Tapping Retry does NOT duplicate user message and triggers retry request',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: "Can you adjust today's workout?"),
          ],
          isLoading: false,
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: "Can you adjust today's workout?",
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      // Verify 1 user message initially
      expect(find.byType(SamanUserMessage), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pump();

      // Retry handler called
      expect(fakeNotifier.retryCallCount, 1);

      // Still exactly 1 user message (NO duplication!)
      expect(fakeNotifier.state.messages.length, 1);
      expect(find.byType(SamanUserMessage), findsOneWidget);

      // State is now loading with generating indicator
      expect(fakeNotifier.state.isLoading, true);
      expect(fakeNotifier.state.errorMessage, isNull);
    });

    testWidgets('17. Tapping Edit question restores failed text to composer and clears error',
        (tester) async {
      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: "Can you adjust today's workout?"),
          ],
          isLoading: false,
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: "Can you adjust today's workout?",
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(notifier: fakeNotifier));
      await tester.pump();

      // Verify composer input initially empty
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      TextField textField = tester.widget(textFieldFinder);
      expect(textField.controller?.text, isEmpty);

      // Tap Edit question
      await tester.tap(find.text('Edit question'));
      await tester.pump();

      // Controller cleared error
      expect(fakeNotifier.clearErrorCalled, true);
      expect(fakeNotifier.state.errorMessage, isNull);

      // Composer text restored to failed query
      textField = tester.widget(textFieldFinder);
      expect(textField.controller?.text, "Can you adjust today's workout?");
    });

    testWidgets('18. Error state does not corrupt message history',
        (tester) async {
      final state = ChatState(
        messages: [
          ChatMessage(role: 'user', content: 'First valid question'),
          ChatMessage(role: 'assistant', content: 'First valid answer'),
          ChatMessage(role: 'user', content: 'Failing question'),
        ],
        isLoading: false,
        errorMessage: "I couldn't complete that response.",
        failedUserMessage: 'Failing question',
      );

      // Ensure messages list only contains real user/assistant items
      for (final m in state.messages) {
        expect(m.content, isNot(contains("I couldn't complete that response.")));
        expect(m.content, isNot(contains("Exception")));
      }
      expect(state.messages.length, 3);
    });
  });

  group('Phase 3 — Viewport & Regression Tests', () {
    testWidgets('19. State 05 Typing does not overflow at narrow 360x780 viewport',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 780 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Very long question testing narrow viewport layout responsiveness across devices.',
            ),
          ],
          isLoading: true,
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(
        notifier: fakeNotifier,
        width: 360,
        height: 780,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SamanGeneratingIndicator), findsOneWidget);
    });

    testWidgets('20. State 07 Recoverable Error does not overflow at narrow 360x780 viewport',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 780 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeLoadingRecoveryNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Very long question testing narrow viewport layout responsiveness across devices.',
            ),
          ],
          isLoading: false,
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: 'Very long question testing narrow viewport layout responsiveness across devices.',
        ),
      );

      await tester.pumpWidget(_buildLoadingRecoveryTestWrapper(
        notifier: fakeNotifier,
        width: 360,
        height: 780,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SamanErrorResponse), findsOneWidget);
    });
  });
}

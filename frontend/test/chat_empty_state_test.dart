import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];
  bool clearChatCalled = false;

  _FakeChatNotifier({ChatState? initialState})
      : super(initialState ?? ChatState(messages: []));

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

  @override
  Future<void> retry() async {}

  @override
  void clearError() {
    state = state.copyWith(clearError: true, clearFailedUserMessage: true);
  }
}

Widget _buildTestWrapper({
  required _FakeChatNotifier notifier,
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
  group('Saman Chat Phase 1 - Foundation & Empty State', () {
    testWidgets(
        '1 & 3. Header renders "Saman Coach" and monogram, empty state renders "Your coach is ready"',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Header title
      expect(find.text('Saman Coach'), findsWidgets);

      // Hero title and subtitle
      expect(find.text('Your coach is ready'), findsOneWidget);
      expect(
        find.text('Ask about training, meals, recovery, or what to do next.'),
        findsOneWidget,
      );

      // Context card
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Legs & Chain · 45 min'), findsOneWidget);
      expect(find.text('RPE 8.5 · 35g protein left'), findsOneWidget);
      expect(find.text('Review workout'), findsOneWidget);
    });

    testWidgets(
        '2. Legacy visible branding is gone (no "AI Coach", no robot icon)',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Ensure legacy "AI Coach" text is absent
      expect(find.text('AI Coach'), findsNothing);

      // Ensure robot icon is absent
      expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
      expect(find.byIcon(Icons.smart_toy), findsNothing);
    });

    testWidgets('4 & 5. Composer placeholder and monochrome send button',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Composer placeholder
      expect(
        find.text('Ask Saman about training, meals, recovery...'),
        findsOneWidget,
      );

      // Send button icon
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      // Find the AnimatedContainer for send button
      final sendIconFinder = find.byIcon(Icons.arrow_upward_rounded);
      final animatedContainerFinder = find.ancestor(
        of: sendIconFinder,
        matching: find.byType(AnimatedContainer),
      );
      expect(animatedContainerFinder, findsOneWidget);

      final animatedContainer =
          tester.widget<AnimatedContainer>(animatedContainerFinder);
      final boxDecoration = animatedContainer.decoration as BoxDecoration;

      // Color MUST NOT be Saman green (#10B981)
      expect(boxDecoration.color, isNot(SamanChatTokens.greenAccent));
      expect(boxDecoration.color, isNot(const Color(0xFF10B981)));
      // Default disabled color is monochrome/neutral
      expect(boxDecoration.color, SamanChatTokens.composerSendDisabledBg);
    });

    testWidgets('6. Three approved Empty State actions render', (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.text("Review today's workout"), findsOneWidget);
      expect(find.text('Plan next meal'), findsOneWidget);
      expect(find.text('Check recovery'), findsOneWidget);

      // Icons for each action
      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('7. Tapping suggested actions dispatches approved prompts',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Review today's workout"));
      await tester.pumpAndSettle();

      expect(fakeNotifier.sentMessages.length, 1);
      expect(
        fakeNotifier.sentMessages.first,
        "Review today's workout briefing: cues and volume.",
      );

      // Reset to empty state for Plan next meal
      fakeNotifier.clearChat();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text("Plan next meal"));
      await tester.tap(find.text("Plan next meal"));
      await tester.pumpAndSettle();
      expect(
        fakeNotifier.sentMessages.last,
        "Plan my next meal based on today's remaining nutrition targets.",
      );

      // Reset to empty state for Check recovery
      fakeNotifier.clearChat();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text("Check recovery"));
      await tester.tap(find.text("Check recovery"));
      await tester.pumpAndSettle();
      expect(
        fakeNotifier.sentMessages.last,
        "Check my recovery today and suggest how hard I should train.",
      );
    });

    testWidgets('7b. Tapping rapid query chip dispatches message to controller',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.text('Post-workout meal'), findsOneWidget);
      await tester.tap(find.text('Post-workout meal'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.sentMessages.length, 1);
      expect(
        fakeNotifier.sentMessages.first,
        'Post-workout meal recommendation',
      );
    });

    testWidgets('8. No layout overflow at narrow mobile viewport (360x780)',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(
        notifier: fakeNotifier,
        width: 360,
        height: 780,
      ));
      await tester.pumpAndSettle();

      // No Flutter overflow errors
      expect(tester.takeException(), isNull);
    });
  });
}

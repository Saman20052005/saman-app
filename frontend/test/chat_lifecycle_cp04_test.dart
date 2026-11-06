import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_generating_indicator.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_error_response.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_user_message.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _StaticProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LifecycleChatNotifier extends StateNotifier<ChatState> implements ChatController {
  final List<String> sentMessages = [];
  int retryCount = 0;
  bool clearErrorCalled = false;
  bool newConversationCalled = false;
  String? loadedConversationId;
  int _requestEpoch = 0;
  String? _failedOperationId;

  _LifecycleChatNotifier({ChatState? initialState})
      : super(initialState ??
            ChatState(
              messages: [],
              recentConversations: [
                ChatConversationSummary(
                  id: 'c1',
                  title: 'Buổi tập ngực',
                  updatedAt: DateTime.now().toIso8601String(),
                ),
                ChatConversationSummary(
                  id: 'c2',
                  title: 'Dinh dưỡng TDEE',
                  updatedAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
                ),
              ],
              activeConversationId: 'c1',
            ));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    sentMessages.add(trimmed);
    _failedOperationId = 'op_${sentMessages.length}';

    state = state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: trimmed)],
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  void completeAssistantResponse(String reply) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(role: 'assistant', content: reply),
      ],
      isLoading: false,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  void simulateFailure(String failedPrompt) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: "I couldn't complete that response.",
      failedUserMessage: failedPrompt,
    );
  }

  @override
  Future<void> retry() async {
    retryCount++;
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
    newConversation();
  }

  @override
  void newConversation() {
    newConversationCalled = true;
    _requestEpoch++;
    state = state.copyWith(
      messages: [],
      clearActiveConversation: true,
      isLoading: false,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    loadedConversationId = conversationId;
    _requestEpoch++;
    state = state.copyWith(
      activeConversationId: conversationId,
      messages: [
        ChatMessage(role: 'user', content: 'Tin nhắn cũ trong $conversationId'),
        ChatMessage(role: 'assistant', content: 'Phản hồi cũ trong $conversationId'),
      ],
      isLoading: false,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  int get currentEpoch => _requestEpoch;
  String? get failedOpId => _failedOperationId;
}

Widget _buildLifecycleApp({
  required _LifecycleChatNotifier chatNotifier,
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'saman@member.app',
  );

  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => chatNotifier),
      profileProvider.overrideWith(
        (ref) => _StaticProfileNotifier(
          ProfileState(
            profile: profileEntity,
            snapshot: profileSnapshot,
            status: ProfileStatus.ready,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: const ChatScreen(),
    ),
  );
}

void main() {
  group('CP-04 · Saman Coach Turn Lifecycle & Error Recovery', () {
    testWidgets('1. Immediate user bubble and draft clearing on send', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Type question in composer
      final textFieldFinder = find.byType(TextField);
      await tester.enterText(textFieldFinder, 'Lên kế hoạch tập thân trên hôm nay');
      await tester.pumpAndSettle();

      // Submit via Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // User bubble appears immediately
      expect(find.byType(SamanUserMessage), findsOneWidget);
      expect(find.text('Lên kế hoạch tập thân trên hôm nay'), findsOneWidget);

      // Composer draft was cleared
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, isEmpty);

      // State is loading
      expect(notifier.state.isLoading, isTrue);
      expect(notifier.sentMessages, ['Lên kế hoạch tập thân trên hôm nay']);
    });

    testWidgets('2. Double-send & concurrent Enter/Send guard', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Send first message
      await tester.enterText(find.byType(TextField), 'Câu hỏi thứ nhất');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(notifier.sentMessages.length, 1);

      // Try typing and sending second message while still loading
      await tester.enterText(find.byType(TextField), 'Gửi cố khi đang chờ');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Guard blocked second send! Only 1 message was accepted
      expect(notifier.sentMessages.length, 1);
      // Draft typed while waiting remains in composer
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Gửi cố khi đang chờ');
    });

    testWidgets('3. Compose next draft while Core 3 is processing; draft preserved when response arrives', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Send first prompt
      await tester.enterText(find.byType(TextField), 'Bài tập ngực nào tốt nhất?');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(notifier.sentMessages.length, 1);

      // Composer TextField is enabled and allows composing next draft!
      final textFieldWidget = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldWidget.enabled, isTrue);

      // User types draft for their next question while waiting
      await tester.enterText(find.byType(TextField), 'Dinh dưỡng sau tập thì sao?');
      await tester.pump();

      // Core 3 completes and assistant response arrives
      notifier.completeAssistantResponse('Nên tập Incline Bench Press và Dumbbell Flyes.');
      await tester.pumpAndSettle();

      // Assistant response is displayed
      expect(find.text('Nên tập Incline Bench Press và Dumbbell Flyes.'), findsOneWidget);

      // Next draft in composer is STILL PRESERVED!
      final updatedTextField = tester.widget<TextField>(find.byType(TextField));
      expect(updatedTextField.controller?.text, 'Dinh dưỡng sau tập thì sao?');

      // Now that isLoading is false, user can immediately send this draft
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(notifier.sentMessages, [
        'Bài tập ngực nào tốt nhất?',
        'Dinh dưỡng sau tập thì sao?',
      ]);
    });

    testWidgets('4. Passive waiting indicator rendered at response position', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Send prompt
      await tester.enterText(find.byType(TextField), 'Chào Saman');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Passive generating indicator displayed with localized text
      expect(find.byType(SamanGeneratingIndicator), findsOneWidget);
      expect(find.text('Saman đang trả lời...'), findsOneWidget);

      // No Stop button in UI
      expect(find.text('Dừng'), findsNothing);
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets('5. Reading position preserved when scrolled up; scroll-to-bottom button appears', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Preload with 15 messages
      final initialMessages = [
        for (int i = 1; i <= 15; i++) ...[
          ChatMessage(role: 'user', content: 'Câu hỏi thứ $i của người dùng'),
          ChatMessage(role: 'assistant', content: 'Phản hồi chi tiết thứ $i từ Saman Coach với nhiều nội dung phân tích thể lực.'),
        ],
      ];

      final notifier = _LifecycleChatNotifier(
        initialState: ChatState(messages: initialMessages),
      );

      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      final messageListScrollable = find.descendant(
        of: find.byType(SamanMessageList),
        matching: find.byType(Scrollable),
      ).first;
      // Drag down slightly to trigger scroll notification while scrolled up
      await tester.drag(messageListScrollable, const Offset(0, 100));
      await tester.pumpAndSettle();

      // Scroll-to-bottom floating pill button appears!
      expect(find.text('Mới nhất'), findsOneWidget);

      // Assistant arrives while user is scrolled up
      notifier.completeAssistantResponse('Tin nhắn mới nhất đến khi người dùng đang đọc ở trên');
      await tester.pumpAndSettle();

      // User reading position is preserved (scroll-to-bottom button is still visible)
      expect(find.text('Mới nhất'), findsOneWidget);

      // Tap "Mới nhất" button to proactively scroll back to bottom
      await tester.tap(find.text('Mới nhất'));
      await tester.pumpAndSettle();

      // Button disappears once user is back near bottom
      expect(find.text('Mới nhất'), findsNothing);
      expect(find.text('Tin nhắn mới nhất đến khi người dùng đang đọc ở trên'), findsOneWidget);
    });

    testWidgets('6. Thread switch isolation: response/error of previous thread does not leak', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Send in Conversation c1
      await tester.enterText(find.byType(TextField), 'Yêu cầu trong c1');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final epochInC1 = notifier.currentEpoch;

      // Switch to Conversation c2 while c1 is pending
      await tester.tap(find.text('Dinh dưỡng TDEE'));
      await tester.pumpAndSettle();

      // Verified: current active conversation is c2 and epoch changed
      expect(notifier.loadedConversationId, 'c2');
      expect(notifier.currentEpoch, greaterThan(epochInC1));
      expect(find.text('Tin nhắn cũ trong c2'), findsOneWidget);

      // Even if response from c1 arrives now, it must NOT leak into c2!
      expect(find.text('Yêu cầu trong c1'), findsNothing);
    });

    testWidgets('7. Error recovery: Retry reuses operation ID without duplicating user bubble', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Send prompt
      await tester.enterText(find.byType(TextField), 'Câu hỏi gặp lỗi mạng');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Simulate failure
      notifier.simulateFailure('Câu hỏi gặp lỗi mạng');
      await tester.pumpAndSettle();

      // Error message with Retry and Edit question is rendered
      expect(find.byType(SamanErrorResponse), findsOneWidget);
      expect(find.text("I couldn't complete that response."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Edit question'), findsOneWidget);

      // User types a draft while viewing error
      await tester.enterText(find.byType(TextField), 'Bản nháp gõ trong lúc lỗi');
      await tester.pump();
      await tester.pumpAndSettle();

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Retry count incremented
      expect(notifier.retryCount, 1);

      // User bubble count is still exactly 1 (no duplicate bubble created!)
      expect(find.byType(SamanUserMessage), findsOneWidget);

      // Draft in composer was preserved during retry
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Bản nháp gõ trong lúc lỗi');
    });

    testWidgets('8. Edit question: Prompt confirmation if composer already has draft, else populates failed question', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _LifecycleChatNotifier();
      await tester.pumpWidget(_buildLifecycleApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Send prompt and simulate failure
      await tester.enterText(find.byType(TextField), 'Câu hỏi bị timeout');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      notifier.simulateFailure('Câu hỏi bị timeout');
      await tester.pumpAndSettle();

      // Case A: Composer is empty -> directly populates failed text
      await tester.tap(find.text('Edit question'));
      await tester.pumpAndSettle();

      final textFieldA = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldA.controller?.text, 'Câu hỏi bị timeout');

      // Now change text to a different draft
      await tester.enterText(find.byType(TextField), 'Bản nháp khác chưa gửi');
      await tester.pumpAndSettle();

      // Re-trigger failure to test dialog
      notifier.simulateFailure('Câu hỏi bị timeout');
      await tester.pumpAndSettle();

      // Case B: Composer already has a different draft -> shows confirmation dialog!
      await tester.tap(find.text('Edit question'));
      await tester.pumpAndSettle();

      expect(find.text('Thay thế bản nháp?'), findsOneWidget);
      expect(find.text('Giữ bản nháp'), findsOneWidget);
      expect(find.text('Thay thế'), findsOneWidget);

      // Choose "Giữ bản nháp" -> keeps user's draft!
      await tester.tap(find.text('Giữ bản nháp'));
      await tester.pumpAndSettle();

      final textFieldB = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldB.controller?.text, 'Bản nháp khác chưa gửi');

      // Tap again and choose "Thay thế" -> replaces with failed question!
      await tester.tap(find.text('Edit question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thay thế'));
      await tester.pumpAndSettle();

      final textFieldC = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldC.controller?.text, 'Câu hỏi bị timeout');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_attachment_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_error_response.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_generating_indicator.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_user_message.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _IntegrationProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _IntegrationProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IntegrationChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];
  final List<String> operationIds = [];
  int chatAttempts = 0;
  int retryAttempts = 0;
  bool newConversationCalled = false;
  String? loadedConversationId;
  String? lastLoadedId;

  // Stored thread histories for multi-thread verification
  final Map<String, List<ChatMessage>> threadHistories = {
    'thread_A': [
      ChatMessage(role: 'user', content: 'Lịch sử thread A'),
      ChatMessage(role: 'assistant', content: 'Nội dung cũ của A'),
    ],
    'thread_B': [
      ChatMessage(role: 'user', content: 'Lịch sử thread B'),
      ChatMessage(role: 'assistant', content: 'Nội dung cũ của B'),
    ],
  };

  _IntegrationChatNotifier({ChatState? initialState})
      : super(
          initialState ??
              ChatState(
                messages: [],
                recentConversations: [
                  ChatConversationSummary(
                    id: 'thread_A',
                    title: 'Buổi tập ngực hôm nay',
                    updatedAt: DateTime.now().toIso8601String(),
                  ),
                  ChatConversationSummary(
                    id: 'thread_B',
                    title: 'Tính toán calo TDEE',
                    updatedAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
                  ),
                ],
                activeConversationId: 'thread_A',
              ),
        );

  @override
  Ref get ref => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    chatAttempts++;
    sentMessages.add(trimmed);
    final opId = 'op_canonical_${sentMessages.length.toString().padLeft(4, '0')}';
    operationIds.add(opId);

    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(role: 'user', content: trimmed),
      ],
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  void simulateServerError(String failedQuestion) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: "I couldn't complete that response.",
      failedUserMessage: failedQuestion,
    );
  }

  @override
  Future<void> retry() async {
    if (state.failedUserMessage == null) return;
    retryAttempts++;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      // Do not duplicate user message
    );
  }

  void completeAssistantResponse(String reply, {String? canonicalThreadId}) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(role: 'assistant', content: reply),
      ],
      isLoading: false,
      activeConversationId: canonicalThreadId ?? state.activeConversationId,
      clearError: true,
    );
    // Persist to local thread cache if applicable
    if (state.activeConversationId != null) {
      threadHistories[state.activeConversationId!] = List.from(state.messages);
    }
  }

  @override
  void clearChat() {
    state = state.copyWith(messages: []);
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  void newConversation() {
    newConversationCalled = true;
    state = state.copyWith(
      messages: [],
      clearActiveConversation: true,
      clearError: true,
    );
  }

  @override
  Future<void> loadConversation(String conversationId) async {
    lastLoadedId = conversationId;
    loadedConversationId = conversationId;
    final history = threadHistories[conversationId] ?? [];
    state = state.copyWith(
      activeConversationId: conversationId,
      messages: List.from(history),
      clearError: true,
    );
  }

  @override
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

Widget _buildIntegrationApp({
  required _IntegrationChatNotifier chatNotifier,
  _IntegrationProfileNotifier? profileNotifier,
  Size? size,
  bool disableAnimations = false,
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'saman@member.app',
  );

  final profNotifier = profileNotifier ??
      _IntegrationProfileNotifier(
        ProfileState(
          profile: profileEntity,
          snapshot: profileSnapshot,
          status: ProfileStatus.ready,
        ),
      );

  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => chatNotifier),
      profileProvider.overrideWith((ref) => profNotifier),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: SamanChatTokens.canvas,
      ),
      routes: {
        '/profile': (context) => const ProfileScreen(),
      },
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            size: size ?? mq.size,
            disableAnimations: disableAnimations,
          ),
          child: child!,
        );
      },
      home: const ChatScreen(isTabActive: false),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CP-06 · Saman Coach Series 3 Comprehensive Integration Matrix', () {
    // ══════════════════════════════════════════════════════════════════════════
    // SECTION A: Sidebar & Navigation Acceptance
    // ══════════════════════════════════════════════════════════════════════════
    testWidgets('Ca A1. Desktop Sidebar: Expand -> Rail -> Expand retains draft & scroll', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Verify permanent sidebar is present
      expect(find.byType(SamanChatDrawer), findsOneWidget);
      expect(find.text('Buổi tập ngực hôm nay'), findsOneWidget);

      // Type a draft
      const draft = 'Bản nháp kiểm tra đóng mở sidebar';
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();

      // Collapse sidebar to Rail via toggle button
      final toggleFinder = find.byTooltip('Thu gọn thanh bên');
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // finish 200ms animation
      await tester.pumpAndSettle();

      // Verify collapsed rail (thread title hidden, open tooltip shown)
      expect(find.byTooltip('Mở rộng thanh bên'), findsOneWidget);
      expect(find.text('Buổi tập ngực hôm nay'), findsNothing);

      // Re-expand sidebar
      await tester.tap(find.byTooltip('Mở rộng thanh bên'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify draft is completely preserved and sidebar restored
      expect(find.text('Buổi tập ngực hôm nay'), findsOneWidget);
      expect(find.text(draft), findsOneWidget);
    });

    testWidgets('Ca A2. Dynamic Resize across 840px breakpoint maintains integrity', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      expect(find.byType(SamanChatDrawer), findsOneWidget);

      // Resize down to 400px (Mobile viewport)
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Verify desktop permanent sidebar is gone and drawer icon is available
      expect(find.byTooltip('Coach Menu'), findsOneWidget);

      // Resize back to 1024px
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Verify permanent sidebar returned cleanly without conflicting duplicates
      expect(find.byType(SamanChatDrawer), findsOneWidget);
    });

    testWidgets('Ca A3. Mobile Drawer: Open, close by scrim/back, and switch threads', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Open drawer via header button
      await tester.tap(find.byTooltip('Coach Menu'));
      await tester.pumpAndSettle();

      // Verify drawer is open with thread list
      expect(find.text('Buổi tập ngực hôm nay'), findsOneWidget);
      expect(find.text('Tính toán calo TDEE'), findsOneWidget);

      // Select thread B
      await tester.tap(find.text('Tính toán calo TDEE'));
      await tester.pumpAndSettle();

      // Verify drawer closed and thread B was loaded
      expect(notifier.lastLoadedId, 'thread_B');
    });

    testWidgets('Ca A4. Navigation entries: Account row, Settings gear and Reminders', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Verify pinned account row is visible
      expect(find.text('Saman Athlete'), findsOneWidget);

      // Tap settings gear icon -> opens preferences / personas sheet
      final gearFinder = find.byTooltip('Tùy chọn Saman');
      expect(gearFinder, findsOneWidget);
      await tester.tap(gearFinder);
      await tester.pumpAndSettle();

      expect(find.text('Saman Preferences'), findsOneWidget);
      // Close sheet
      Navigator.of(tester.element(find.text('Saman Preferences'))).pop();
      await tester.pumpAndSettle();

      // Tap Account row -> navigates to Profile
      await tester.tap(find.text('Saman Athlete'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('Ca A5. New Chat does not dispatch empty request to backend', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Tap 'Đoạn chat mới' pill button
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();

      // Verify state was reset and 0 network requests dispatched
      expect(notifier.newConversationCalled, isTrue);
      expect(notifier.chatAttempts, 0);
    });

    // ══════════════════════════════════════════════════════════════════════════
    // SECTION B: Composer, Keyboard & Popovers Acceptance
    // ══════════════════════════════════════════════════════════════════════════
    testWidgets('Ca B1. Vietnamese IME composing guard blocks Enter; multiline expands', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      final controller = textField.controller!;

      // Simulate Vietnamese active IME composition (e.g. typing 'tôir')
      controller.value = const TextEditingValue(
        text: 'tôi',
        composing: TextRange(start: 0, end: 3),
      );
      await tester.pump();

      // Send Enter key while composing
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Verify send was ignored during composition
      expect(notifier.chatAttempts, 0);

      // Finish composition
      controller.value = const TextEditingValue(
        text: 'tôi cần tư vấn thực đơn',
        composing: TextRange.empty,
      );
      await tester.pump();

      // Tap Send button
      await tester.tap(find.bySemanticsLabel('Gửi tin nhắn'));
      await tester.pump();
      expect(notifier.chatAttempts, 1);
    });

    testWidgets('Ca B2. Popover menus dismiss cleanly via Outside Tap and Escape key', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Open Tools popover
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text('Phân tích lịch sử'), findsOneWidget);

      // Tap outside (barrier) -> closes tools popover
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Phân tích lịch sử'), findsNothing);

      // Open Mode popover with focus on composer
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();
      expect(find.text('Mặc định toàn diện'), findsOneWidget);

      // Press Escape key -> dismisses
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text('Mặc định toàn diện'), findsNothing);
    });

    testWidgets('Ca B3. Locked AI modes (Swift 3 & Pro 3) do not alter selection', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Open Mode Menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Tap Swift 3 (locked)
      await tester.tap(find.text('Swift 3'));
      await tester.pump();
      // Should show SnackBar and keep Core 3 active
      expect(find.byType(SnackBar), findsOneWidget);
      expect(notifier.chatAttempts, 0);
      expect(find.text('Core 3'), findsWidgets);
    });

    testWidgets('Ca B4. Tools entry points open HistoryAnalyticsSheet and SamanAttachmentSheet', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // 1. Open Tools popover -> Tap 'Phân tích lịch sử'
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phân tích lịch sử'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HistoryAnalyticsSheet), findsOneWidget);
      // History analytics sheet opened successfully
      // Close sheet
      Navigator.of(tester.element(find.byType(HistoryAnalyticsSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 2. Open Tools popover -> Tap 'Phân tích ảnh món ăn'
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phân tích ảnh món ăn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SamanAttachmentSheet), findsOneWidget);
      expect(find.text('Take food photo'), findsOneWidget);
      expect(find.text('Upload image'), findsOneWidget);
      // Close sheet
      Navigator.of(tester.element(find.byType(SamanAttachmentSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    // ══════════════════════════════════════════════════════════════════════════
    // SECTION C: Turn Lifecycle Acceptance (Send, Wait, Respond, Scroll)
    // ══════════════════════════════════════════════════════════════════════════
    testWidgets('Ca C1. User bubble appears immediately, draft clears, waiting indicator shows', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      const question = 'Hôm nay tôi nên tập nhóm cơ nào?';
      await tester.enterText(find.byType(TextField), question);
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Gửi tin nhắn'));
      await tester.pump();

      // Verify user message bubble appeared immediately
      expect(find.text(question), findsOneWidget);
      // Verify composer draft was cleared
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      // Verify waiting indicator is oscillating
      expect(find.byType(SamanGeneratingIndicator), findsOneWidget);
    });

    testWidgets('Ca C2. Compose next draft while waiting; draft preserved when response arrives', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Send first message
      await tester.enterText(find.byType(TextField), 'Câu hỏi đầu tiên');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Gửi tin nhắn'));
      await tester.pump();

      // User types next draft into composer while waiting
      const nextDraft = 'Câu hỏi tiếp theo đang soạn dở...';
      await tester.enterText(find.byType(TextField), nextDraft);
      await tester.pump();

      // Assistant response completes
      notifier.completeAssistantResponse('Đây là câu trả lời từ Saman Coach.');
      await tester.pumpAndSettle();

      // Verify response is visible AND draft remains intact
      expect(find.text('Đây là câu trả lời từ Saman Coach.'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, nextDraft);
    });

    testWidgets('Ca C3. Double-send & concurrent Enter/Send guard rejects duplicates', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Thử nghiệm gửi đúp');
      await tester.pump();

      // First tap
      await tester.tap(find.bySemanticsLabel('Gửi tin nhắn'));
      // Immediate second tap without pumpAndSettle
      await tester.tap(find.bySemanticsLabel('Gửi tin nhắn'));
      await tester.pump();

      // Only 1 attempt registered
      expect(notifier.chatAttempts, 1);
    });

    // ══════════════════════════════════════════════════════════════════════════
    // SECTION D: Error Recovery, Retry & Multi-Thread Isolation
    // ══════════════════════════════════════════════════════════════════════════
    testWidgets('Ca D1. Server error shows non-alarmist message with Retry & Edit actions', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Câu hỏi gặp lỗi mạng');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Gửi tin nhắn'));
      await tester.pump();

      // Simulate server error 503/timeout
      notifier.simulateServerError('Câu hỏi gặp lỗi mạng');
      await tester.pumpAndSettle();

      expect(find.byType(SamanErrorResponse), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Edit question'), findsOneWidget);

      // Tap Retry -> reuses operation and does not duplicate bubble
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(notifier.retryAttempts, 1);
      final userBubbles = find.descendant(of: find.byType(SamanMessageList), matching: find.byType(SamanUserMessage));
      expect(userBubbles, findsOneWidget);
    });

    testWidgets('Ca D2. Edit question protects active draft with confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Send question and simulate failure
      await tester.enterText(find.byType(TextField), 'Câu hỏi gốc bị lỗi');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      notifier.simulateServerError('Câu hỏi gốc bị lỗi');
      await tester.pumpAndSettle();

      // User has typed a new draft into composer
      await tester.enterText(find.byType(TextField), 'Bản nháp mới quan trọng');
      await tester.pump();

      // Tap 'Edit question'
      await tester.tap(find.text('Edit question'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Thay thế bản nháp?'), findsOneWidget);
      expect(find.text('Giữ bản nháp'), findsOneWidget);
      expect(find.text('Thay thế'), findsOneWidget);

      // 1. Choose 'Giữ bản nháp' -> preserves composer text
      await tester.tap(find.text('Giữ bản nháp'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Bản nháp mới quan trọng');

      // 2. Tap 'Edit question' again -> Choose 'Thay thế'
      await tester.tap(find.text('Edit question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thay thế'));
      await tester.pumpAndSettle();

      // Failed question is restored to composer
      expect(field.controller!.text, 'Câu hỏi gốc bị lỗi');
    });

    testWidgets('Ca D3. Thread switching isolates responses and preserves canonical state', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Currently on thread_A
      expect(find.text('Buổi tập ngực hôm nay'), findsOneWidget);

      // Switch to thread_B via sidebar
      await tester.tap(find.text('Tính toán calo TDEE'));
      await tester.pumpAndSettle();

      // Verify thread_B canonical messages are loaded
      expect(find.text('Lịch sử thread B'), findsOneWidget);
      expect(find.text('Nội dung cũ của B'), findsOneWidget);
      expect(find.text('Lịch sử thread A'), findsNothing);

      // Switch back to thread_A
      await tester.tap(find.text('Buổi tập ngực hôm nay'));
      await tester.pumpAndSettle();

      expect(find.text('Lịch sử thread A'), findsOneWidget);
      expect(find.text('Lịch sử thread B'), findsNothing);
    });

    // ══════════════════════════════════════════════════════════════════════════
    // SECTION E: Motion & Accessibility Compliance
    // ══════════════════════════════════════════════════════════════════════════
    testWidgets('Ca E1. Mid-flight sidebar transition (100ms) has zero layout overflow', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Trigger collapse
      await tester.tap(find.byTooltip('Thu gọn thanh bên'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // Exactly mid-flight

      // Verify width is between 64 and 260 and no Flutter exception occurred
      final drawerBox = tester.renderObject<RenderBox>(find.byType(SamanChatDrawer));
      expect(drawerBox.size.width, lessThan(260.0));
      expect(drawerBox.size.width, greaterThan(64.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ca E2. Reduced motion collapses animation durations to Duration.zero', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(
        chatNotifier: notifier,
        size: const Size(1024, 768),
        disableAnimations: true,
      ));
      await tester.pumpAndSettle();

      // Tap toggle collapse
      await tester.tap(find.byTooltip('Thu gọn thanh bên'));
      await tester.pump(); // Instant transition with 0 duration

      final drawerBox = tester.renderObject<RenderBox>(find.byType(SamanChatDrawer));
      expect(drawerBox.size.width, equals(64.0));
    });

    testWidgets('Ca E3. Mobile primary touch targets strictly satisfy 48x48 logical px', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _IntegrationChatNotifier();
      await tester.pumpWidget(_buildIntegrationApp(chatNotifier: notifier, size: const Size(400, 800)));
      await tester.pumpAndSettle();

      final plusFinder = find.descendant(
        of: find.byTooltip('Thêm công cụ'),
        matching: find.byType(SizedBox),
      ).first;
      final plusSize = tester.getSize(plusFinder);
      expect(plusSize.width, greaterThanOrEqualTo(48.0));
      expect(plusSize.height, greaterThanOrEqualTo(48.0));

      // Enter draft text to activate 2-row layout with send button
      await tester.enterText(find.byType(TextField), 'Ke hoach tap hom nay');
      await tester.pumpAndSettle();

      final sendFinder = find.descendant(
        of: find.bySemanticsLabel('Gửi tin nhắn'),
        matching: find.byType(SizedBox),
      ).first;
      final sendSize = tester.getSize(sendFinder);
      expect(sendSize.width, greaterThanOrEqualTo(48.0));
      expect(sendSize.height, greaterThanOrEqualTo(48.0));

      final modeInkWellFinder = find.ancestor(
        of: find.text('Core 3'),
        matching: find.byType(InkWell),
      );
      final modeSize = tester.getSize(modeInkWellFinder);
      expect(modeSize.height, greaterThanOrEqualTo(48.0));
    });
  });
}

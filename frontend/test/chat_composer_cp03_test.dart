import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_empty_state.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _StaticProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockChatNotifier extends StateNotifier<ChatState> implements ChatController {
  final List<String> sentMessages = [];
  bool newConversationCalled = false;
  String? loadedConversationId;

  _MockChatNotifier({ChatState? initialState})
      : super(initialState ??
            ChatState(
              messages: [],
              recentConversations: [
                ChatConversationSummary(
                  id: 'c1',
                  title: 'Buổi tập thân trên hôm nay',
                  updatedAt: DateTime.now().toIso8601String(),
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
    sentMessages.add(text);
    state = state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: text)],
      isLoading: false,
    );
  }

  @override
  void clearChat() {
    newConversation();
  }

  @override
  void newConversation() {
    newConversationCalled = true;
    state = state.copyWith(messages: [], clearActiveConversation: true);
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    loadedConversationId = conversationId;
    state = state.copyWith(activeConversationId: conversationId);
  }
}

Widget _buildComposerTestHarness({
  required TextEditingController controller,
  FocusNode? focusNode,
  VoidCallback? onSend,
  bool isLoading = false,
  VoidCallback? onAttachFoodPhoto,
  VoidCallback? onOpenAnalytics,
  AIMode activeMode = AIMode.core3,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SamanTheme.dark(),
    home: Scaffold(
      backgroundColor: SamanChatTokens.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480.0),
            child: SamanChatComposer(
              controller: controller,
              focusNode: focusNode,
              onSend: onSend ?? () {},
              isLoading: isLoading,
              onAttachFoodPhoto: onAttachFoodPhoto,
              onOpenAnalytics: onOpenAnalytics,
              activeMode: activeMode,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CP-03 · Saman Coach Composer & Popovers Matrix', () {
    testWidgets('1. Unified composer states: empty 1-row pill and active composing 2-row container', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      // --- Empty State (1-row pill) ---
      // Check + button
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      // Check TextField with localized placeholder
      expect(find.text('Hỏi Saman về dinh dưỡng, bài tập, phục hồi...'), findsOneWidget);

      // Check Mode selector button showing Core 3
      expect(find.text('Core 3'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      // Send button is NOT present when empty
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      // Mic button is explicitly hidden
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);

      // Focus without typing still maintains 1-row layout (no send button)
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      // Whitespace only does not activate 2-row container or send button
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      // --- Composing State (2-row container) ---
      // Entering single-line text transforms into 2-row container with send button
      await tester.enterText(find.byType(TextField), 'Hôm nay tập gì?');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.text('Core 3'), findsOneWidget);

      // Clearing text returns to 1-row pill
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });

    testWidgets('2. Multiline text expansion preserves draft and pins bottom controls', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      final initialRect = tester.getRect(find.byType(SamanChatComposer));

      // Enter 4 lines of text
      await tester.enterText(find.byType(TextField), 'Dòng 1: Kế hoạch tập\nDòng 2: Bài Squat 4x8\nDòng 3: Bài Bench Press 4x8\nDòng 4: Dinh dưỡng sau tập');
      await tester.pumpAndSettle();

      final expandedRect = tester.getRect(find.byType(SamanChatComposer));

      // Composer height expanded
      expect(expandedRect.height, greaterThan(initialRect.height));

      // Verify controls stay visible and anchored
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.text('Core 3'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(controller.text, contains('Dòng 4: Dinh dưỡng sau tập'));
    });

    testWidgets('3. Vietnamese IME composing guard prevents premature submit on Enter', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      bool sendTriggered = false;

      await tester.pumpWidget(_buildComposerTestHarness(
        controller: controller,
        onSend: () => sendTriggered = true,
      ));
      await tester.pumpAndSettle();

      // Tap TextField to focus and attach text input client
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Simulate Vietnamese IME active composing state: e.g. typing 'đang' with composing range [0, 4]
      controller.value = const TextEditingValue(
        text: 'đang',
        composing: TextRange(start: 0, end: 4),
      );
      await tester.pumpAndSettle();

      // Submit via Enter key while composing
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // IME composing guard prevented submission!
      expect(sendTriggered, isFalse);

      // Now clear composing range (finished composing word)
      controller.value = const TextEditingValue(
        text: 'đang ăn trưa',
        composing: TextRange.empty,
      );
      await tester.pumpAndSettle();

      // Submit via Enter key after composing finished
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Submitted successfully!
      expect(sendTriggered, isTrue);
    });

    testWidgets('4. Tool menu (+): Opens popover, + changes to ×, contains food and analytics', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      bool foodPhotoCalled = false;
      bool analyticsCalled = false;

      await tester.pumpWidget(_buildComposerTestHarness(
        controller: controller,
        onAttachFoodPhoto: () => foodPhotoCalled = true,
        onOpenAnalytics: () => analyticsCalled = true,
      ));
      await tester.pumpAndSettle();

      // Tap + button
      final addBtn = find.byTooltip('Thêm công cụ');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // + changed to ×
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byTooltip('Đóng công cụ'), findsOneWidget);

      // Tool items are visible in popover
      expect(find.text('Phân tích ảnh món ăn'), findsOneWidget);
      expect(find.text('Standard & Advanced AI'), findsOneWidget);
      expect(find.text('Phân tích lịch sử'), findsOneWidget);
      expect(find.text('7, 14, 30 ngày'), findsOneWidget);

      // Tap "Phân tích ảnh món ăn"
      await tester.tap(find.text('Phân tích ảnh món ăn'));
      await tester.pumpAndSettle();

      // Popover closed, callback fired
      expect(foodPhotoCalled, isTrue);
      expect(analyticsCalled, isFalse);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.text('Phân tích ảnh món ăn'), findsNothing);
    });

    testWidgets('5. Mode menu: Opens rollout popover, Core 3 active, Swift 3 & Pro 3 locked', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      // Tap Core 3 button
      final modeBtn = find.text('Core 3');
      await tester.tap(modeBtn);
      await tester.pumpAndSettle();

      // Chevron flipped upward
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

      // Mode items in popover
      expect(find.text('Mặc định toàn diện'), findsOneWidget);
      expect(find.text('Đang dùng'), findsOneWidget);

      expect(find.text('Swift 3'), findsOneWidget);
      expect(find.text('Phản hồi nhanh, câu hỏi ngắn'), findsOneWidget);
      expect(find.text('Pro 3'), findsOneWidget);
      expect(find.text('Suy luận chuyên sâu & kế hoạch dài hạn'), findsOneWidget);
      expect(find.text('Sắp ra mắt'), findsNWidgets(2));

      // Tap locked Swift 3
      await tester.tap(find.text('Swift 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Explanatory snackbar shown, does NOT change active mode
      expect(find.text('Chế độ Swift 3 đang được hiệu chuẩn, vui lòng trải nghiệm Core 3.'), findsOneWidget);
    });

    testWidgets('6. Popover mutual exclusion and outside tap dismissal', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      // Open + menu
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pumpAndSettle();
      expect(find.text('Phân tích ảnh món ăn'), findsOneWidget);

      // Tap outside (barrier) -> closes + menu
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Phân tích ảnh món ăn'), findsNothing);

      // Now tap Mode button -> opens Mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();
      expect(find.text('Mặc định toàn diện'), findsOneWidget);

      // Tap outside (barrier) -> closes Mode menu
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Mặc định toàn diện'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('7. Empty chat suggestions fill draft instead of auto-sending', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockChat = _MockChatNotifier();
      const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
      const profileSnapshot = ProfileSnapshot(
        profile: profileEntity,
        fullName: 'Saman Athlete',
        email: 'saman@member.app',
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith((ref) => mockChat),
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
      ));
      await tester.pumpAndSettle();

      // Verify empty state is visible
      expect(find.byType(SamanChatEmptyState), findsOneWidget);

      // Tap a suggestion chip: "Plan next meal"
      final actionItem = find.text('Plan next meal');
      expect(actionItem, findsOneWidget);
      await tester.tap(actionItem);
      await tester.pumpAndSettle();

      // Verified: Message was NOT auto-sent!
      expect(mockChat.sentMessages, isEmpty);

      // Verified: Text was filled into composer draft!
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isNotEmpty);
      expect(find.text("Plan my next meal based on today's remaining nutrition targets."), findsOneWidget);
    });

    testWidgets('8. Existing draft is preserved when suggestion is tapped', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockChat = _MockChatNotifier();
      const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
      const profileSnapshot = ProfileSnapshot(
        profile: profileEntity,
        fullName: 'Saman Athlete',
        email: 'saman@member.app',
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          chatControllerProvider.overrideWith((ref) => mockChat),
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
      ));
      await tester.pumpAndSettle();

      // Enter existing draft
      await tester.enterText(find.byType(TextField), 'Nội dung người dùng đang tự soạn...');
      await tester.pumpAndSettle();

      // Tap a suggestion chip
      await tester.tap(find.text("Review today's workout"));
      await tester.pumpAndSettle();

      // Verified: Existing draft is preserved, not overwritten!
      expect(find.text('Nội dung người dùng đang tự soạn...'), findsOneWidget);
      expect(mockChat.sentMessages, isEmpty);
    });

    testWidgets('9. Passive loading waiting state when isLoading is true', (tester) async {
      final controller = TextEditingController(text: 'Câu hỏi đã gửi');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(
        controller: controller,
        isLoading: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // CircularProgressIndicator is displayed instead of active send button
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });
  });
}

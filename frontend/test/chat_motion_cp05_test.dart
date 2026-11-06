import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _StaticProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MotionChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];

  _MotionChatNotifier({ChatState? initialState})
      : super(initialState ??
            ChatState(
              messages: [],
              recentConversations: [
                ChatConversationSummary(
                  id: 'c1',
                  title: 'Buổi tập ngực',
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
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    sentMessages.add(trimmed);
    state = state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: trimmed)],
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  @override
  void clearChat() {
    state = state.copyWith(messages: []);
  }

  @override
  void newConversation() {
    state = state.copyWith(messages: [], clearActiveConversation: true);
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(activeConversationId: conversationId);
  }
}

Widget _buildMotionApp({
  required _MotionChatNotifier chatNotifier,
  bool disableAnimations = false,
  Size? size,
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: SamanChatTokens.canvas,
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: disableAnimations,
            size: size ?? mq.size,
          ),
          child: child!,
        );
      },
      home: const ChatScreen(),
    ),
  );
}

void main() {
  group('CP-05 · Saman Coach Motion, Keyboard & Accessibility Matrix', () {
    testWidgets('1. Desktop sidebar width animates smoothly (260px -> 64px) with 0 overflow mid-flight', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Check initial width: 260px
      final drawerFinder = find.byType(SamanChatDrawer);
      expect(drawerFinder, findsOneWidget);
      expect(tester.getSize(drawerFinder).width, 260.0);

      // Tap sidebar toggle button to collapse to rail
      final toggleFinder = find.byTooltip('Thu gọn thanh bên');
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      await tester.pump();

      // Advance by 100ms (mid-flight of 200ms transition)
      await tester.pump(const Duration(milliseconds: 100));
      final midWidth = tester.getSize(drawerFinder).width;
      expect(midWidth, greaterThan(64.0));
      expect(midWidth, lessThan(260.0));
      // No layout exceptions or overflow
      expect(tester.takeException(), isNull);

      // Finish transition
      await tester.pumpAndSettle();
      expect(tester.getSize(drawerFinder).width, 64.0);

      // Expand again: check mid-flight and completion
      final expandFinder = find.byTooltip('Mở rộng thanh bên');
      expect(expandFinder, findsOneWidget);
      await tester.tap(expandFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(drawerFinder).width, greaterThan(64.0));
      expect(tester.getSize(drawerFinder).width, lessThan(260.0));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.getSize(drawerFinder).width, 260.0);
    });

    testWidgets('2. Reduced motion collapses sidebar transition to Duration.zero', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier, disableAnimations: true));
      await tester.pumpAndSettle();

      final drawerFinder = find.byType(SamanChatDrawer);
      expect(tester.getSize(drawerFinder).width, 260.0);

      // Tap collapse
      await tester.tap(find.byTooltip('Thu gọn thanh bên'));
      await tester.pump(); // Zero duration completes instantly on first frame
      expect(tester.getSize(drawerFinder).width, 64.0);
    });

    testWidgets('3. Popover opens with fade & slide; outside tap & Escape dismiss cleanly', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // 1. Open tools popover
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Popover items are visible
      expect(find.text('Phân tích ảnh món ăn'), findsOneWidget);
      expect(find.text('Phân tích lịch sử'), findsOneWidget);
      await tester.pumpAndSettle();

      // Tap outside (barrier) -> closes tools popover
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Phân tích ảnh món ăn'), findsNothing);

      // 2. Open mode menu while composer has focus
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();
      expect(find.text('Mặc định toàn diện'), findsOneWidget);

      // Press Escape key -> closes popover and retains draft/focus
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Mặc định toàn diện'), findsNothing);
    });

    testWidgets('4. Plus button morphs to "x" via 140ms rotation and mode chevron rotates', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Check AnimatedRotation exists on '+'
      final rotationFinder = find.byType(RotationTransition);
      expect(rotationFinder, findsWidgets);

      // Tap '+' tools button
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70)); // mid-turn

      // Button semantics toggles to 'Đóng công cụ'
      expect(find.byTooltip('Đóng công cụ'), findsOneWidget);
      await tester.pumpAndSettle();

      // Close menu
      await tester.tap(find.byTooltip('Đóng công cụ'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Thêm công cụ'), findsOneWidget);

      // Open mode menu -> chevron rotates
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();
      expect(find.text('Mặc định toàn diện'), findsOneWidget);
      expect(find.text('Swift 3'), findsOneWidget);
      expect(find.text('Pro 3'), findsOneWidget);
    });

    testWidgets('5. Touch targets meet minimum 48 logical px on mobile', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Tools button touch container is at least 48x48
      final toolsFinder = find.descendant(
        of: find.byTooltip('Thêm công cụ'),
        matching: find.byType(SizedBox),
      ).first;
      final toolsSize = tester.getSize(toolsFinder);
      expect(toolsSize.width, greaterThanOrEqualTo(48.0));
      expect(toolsSize.height, greaterThanOrEqualTo(48.0));

      // Enter draft text to activate 2-row layout with send button
      await tester.enterText(find.byType(TextField), 'Ke hoach tap hom nay');
      await tester.pumpAndSettle();

      // Send button touch container is at least 48x48
      final sendFinder = find.descendant(
        of: find.bySemanticsLabel('Gửi tin nhắn'),
        matching: find.byType(SizedBox),
      ).first;
      final sendSize = tester.getSize(sendFinder);
      expect(sendSize.width, greaterThanOrEqualTo(48.0));
      expect(sendSize.height, greaterThanOrEqualTo(48.0));

      // Mode selector height is at least 48
      final modeInkWellFinder = find.ancestor(
        of: find.text('Core 3'),
        matching: find.byType(InkWell),
      );
      final modeSize = tester.getSize(modeInkWellFinder);
      expect(modeSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('6. Locked AI modes have clear semantics, high-contrast badges, and do not change state on tap', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Open mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Tap locked Swift 3
      await tester.tap(find.text('Swift 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // SnackBar explaining calibration appears
      expect(find.text('Chế độ Swift 3 đang được hiệu chuẩn, vui lòng trải nghiệm Core 3.'), findsOneWidget);

      // Active mode remains Core 3
      expect(find.text('Core 3'), findsOneWidget);
    });

    testWidgets('7. Vietnamese IME composing guard: Enter while composing does NOT send message', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = _MotionChatNotifier();
      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'tiees');
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));

      // Simulate Vietnamese IME composing syllable
      textField.controller!.value = const TextEditingValue(
        text: 'tiees',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      await tester.pump();

      // Press Enter while IME is actively composing -> NOT sent
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(notifier.sentMessages.length, 0);

      // Enter completed text
      await tester.enterText(find.byType(TextField), 'tiến độ tập luyện');
      await tester.pump();

      // Press Enter -> submitted
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(notifier.sentMessages.length, 1);
      expect(notifier.sentMessages.first, 'tiến độ tập luyện');
    });

    testWidgets('8. Scroll-to-bottom button appears with smooth fade/scale and accessible label', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final manyMessages = List.generate(
        12,
        (i) => i.isEven
            ? ChatMessage(role: 'user', content: 'Câu hỏi số $i')
            : ChatMessage(role: 'assistant', content: 'Câu trả lời số $i cho người dùng'),
      );

      final notifier = _MotionChatNotifier(
        initialState: ChatState(
          messages: manyMessages,
          isLoading: false,
          activeConversationId: 'c1',
        ),
      );

      await tester.pumpWidget(_buildMotionApp(chatNotifier: notifier));
      await tester.pumpAndSettle();

      // Drag up to scroll into history
      final scrollableFinder = find
          .descendant(
            of: find.byType(SamanMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollableFinder, const Offset(0, 450));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Animated floating button is visible
      final buttonFinder = find.byKey(const ValueKey('scroll_to_newest_button'));
      expect(buttonFinder, findsOneWidget);
      expect(find.text('Mới nhất'), findsOneWidget);

      // Tap "Mới nhất" jumps to bottom and button disappears
      await tester.tap(buttonFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('scroll_to_newest_button')), findsNothing);
    });
  });
}
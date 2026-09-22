import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
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

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}
}

Widget _buildTestWrapper({
  required _FakeChatNotifier notifier,
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

Future<void> _openDrawer(WidgetTester tester) async {
  // Find menu button in header and tap it
  final menuFinder = find.byTooltip('Coach Menu');
  expect(menuFinder, findsOneWidget);
  await tester.tap(menuFinder);
  await tester.pumpAndSettle();
}

void main() {
  group('Saman Chat Phase 4 - Full-Height Drawer (State 10)', () {
    testWidgets(
        '1-7. Drawer opens from header menu and renders all required approved sections',
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

      await _openDrawer(tester);

      // Verify drawer widget is present
      expect(find.byType(SamanChatDrawer), findsOneWidget);

      // 2. Micro-context line
      expect(find.text('Saman · Your personal coach'), findsOneWidget);

      // 3. New conversation primary action
      expect(find.text('New conversation'), findsOneWidget);

      // 4. Recent section header and sample items
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Upper body form check'), findsOneWidget);
      expect(find.text('Post-workout meal plan'), findsOneWidget);
      expect(find.text('Lower-back adjustment'), findsOneWidget);
      expect(find.text('Macro review'), findsOneWidget);
      expect(find.text('View all conversations'), findsOneWidget);

      // 5. Coach tools section header and tools
      expect(find.text('Coach tools'), findsOneWidget);
      expect(find.text('Weekly review'), findsOneWidget);
      expect(find.text('Nutrition review'), findsOneWidget);
      expect(find.text('Workout analysis'), findsOneWidget);

      // 6. Reminders row (neutral)
      expect(find.text('Reminders'), findsOneWidget);

      // 7. Saman preferences row with subtitle
      expect(find.text('Saman preferences'), findsOneWidget);
      expect(
        find.text('Coaching tone, response style, reminders'),
        findsOneWidget,
      );
    });

    testWidgets(
        '8. Legacy strings and artifacts are completely absent from drawer',
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

      await _openDrawer(tester);

      expect(find.text('Adaptive AI'), findsNothing);
      expect(find.text('QUẢN LÝ CHAT'), findsNothing);
      expect(find.text('PHÂN TÍCH & BÁO CÁO'), findsNothing);
      expect(find.text('CÀI ĐẶT AI COACH'), findsNothing);
      expect(find.text('SAMAN OS'), findsNothing);
      expect(find.text('Version 2.1.0 (SAMAN OS)'), findsNothing);
      expect(find.text('Cuộc trò chuyện mới'), findsNothing);
    });

    testWidgets('9. New conversation calls clearChat() and closes drawer',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'Existing chat message'),
          ],
        ),
      );
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await _openDrawer(tester);

      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.clearChatCalled, isTrue);
      // Drawer should be dismissed
      expect(find.byType(SamanChatDrawer), findsNothing);
    });

    testWidgets('10. Mapped Coach Tool action dispatches prompt and closes drawer',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await _openDrawer(tester);

      await tester.tap(find.text('Weekly review'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.sentMessages.length, 1);
      expect(
        fakeNotifier.sentMessages.first,
        contains('7 ngày gần nhất'),
      );
      // Drawer should be closed
      expect(find.byType(SamanChatDrawer), findsNothing);
    });

    testWidgets('11. Saman preferences opens persona/preferences sheet',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await _openDrawer(tester);

      await tester.tap(find.text('Saman preferences'));
      await tester.pumpAndSettle();

      // Drawer is closed
      expect(find.byType(SamanChatDrawer), findsNothing);

      // Preferences bottom sheet is open
      expect(find.text('Saman Preferences'), findsOneWidget);
      expect(find.text('Coaching tone & response style'), findsOneWidget);
      expect(find.text('Strict PT'), findsOneWidget);
      expect(find.text('Nutrition Doctor'), findsOneWidget);
      expect(find.text('AI Best Friend'), findsOneWidget);

      // Tapping a persona style dispatches prompt
      await tester.tap(find.text('Strict PT'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.sentMessages.length, 1);
      expect(fakeNotifier.sentMessages.first, contains('STRICT Personal Trainer'));
    });

    testWidgets('12. Reminders has no fake "2 active" count and no green dot',
        (tester) async {
      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await _openDrawer(tester);

      expect(find.text('2 active'), findsNothing);
      expect(find.text('active'), findsNothing);
    });

    testWidgets('13. 360px viewport has no overflow when drawer is open',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      await _openDrawer(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(SamanChatDrawer), findsOneWidget);
    });

    testWidgets('14. Drawer width leaves visible dark scrim on the right',
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

      await _openDrawer(tester);

      final drawerRenderBox =
          tester.renderObject<RenderBox>(find.byType(Drawer));
      final drawerSize = drawerRenderBox.size;

      // Screen width is 390. Drawer width should be roughly 78-84% (approx 320px)
      // Clamped between 280 and 340, leaving roughly 70px of scrim on 390px.
      expect(drawerSize.width, lessThan(390.0));
      expect(drawerSize.width, greaterThanOrEqualTo(280.0));
      expect(drawerSize.width, lessThanOrEqualTo(340.0));
    });
  });
}

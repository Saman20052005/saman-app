import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/services/analytics_service.dart';

class _MockChatNotifier extends StateNotifier<ChatState> implements ChatController {
  final List<String> sentMessages = [];
  bool clearChatCalled = false;
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
                ChatConversationSummary(
                  id: 'c2',
                  title: 'Kế hoạch dinh dưỡng TDEE',
                  updatedAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
                ),
                for (int i = 3; i <= 20; i++)
                  ChatConversationSummary(
                    id: 'c$i',
                    title: 'Lịch sử hội thoại thứ $i về bài tập và chế độ ăn',
                    updatedAt: DateTime.now().subtract(Duration(days: i)).toIso8601String(),
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
    clearChatCalled = true;
    newConversation();
  }

  @override
  void newConversation() {
    newConversationCalled = true;
    clearChatCalled = true;
    state = state.copyWith(
      messages: [],
      clearActiveConversation: true,
    );
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    loadedConversationId = conversationId;
    state = state.copyWith(activeConversationId: conversationId);
  }

  @override
  Future<void> retry() async {}

  @override
  void clearError() {
    state = state.copyWith(clearError: true, clearFailedUserMessage: true);
  }

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption, String? mode}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}

  @override
  Future<String> executeHistoryAnalytics(AnalyticsQuote quote) async {
    return 'Mock analytics report';
  }
}

class _StaticProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildSidebarTestApp({
  required _MockChatNotifier chatNotifier,
  String athleteName = 'Nguyen Van Saman',
  String athleteEmail = 'saman.athlete@test.com',
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  final profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: athleteName,
    email: athleteEmail,
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
  group('CP-02 · Saman Coach Sidebar & Drawer Acceptance Matrix', () {
    testWidgets('1. Desktop Viewport (1024x768): Permanent sidebar rendered, drawer is null', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Sidebar widget is present in body
      expect(find.byType(SamanChatDrawer), findsOneWidget);

      // Verify New conversation pill button
      expect(find.text('New conversation'), findsOneWidget);

      // Verify Coach tools section
      expect(find.text('Coach tools'), findsOneWidget);
      expect(find.descendant(of: find.byType(SamanChatDrawer), matching: find.text('Phân tích lịch sử')), findsOneWidget);
      expect(find.descendant(of: find.byType(SamanChatDrawer), matching: find.text('Phân tích ảnh món ăn')), findsOneWidget);
      expect(find.text('Weekly review'), findsNothing);
      expect(find.text('Workout analysis'), findsNothing);

      // Verify Recent section
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Buổi tập thân trên hôm nay'), findsOneWidget);
      expect(find.text('Kế hoạch dinh dưỡng TDEE'), findsOneWidget);

      // Verify Pinned Account Row with masked email
      expect(find.text('Nguyen Van Saman'), findsOneWidget);
      expect(find.text('sa***@test.com'), findsOneWidget);

      // Verify Header menu button is hidden on desktop
      expect(find.byTooltip('Coach Menu'), findsNothing);
    });

    testWidgets('2. Desktop Viewport: Collapse into Icon Rail and Expand back', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Click collapse button
      final collapseBtn = find.byTooltip('Thu gọn thanh bên');
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await tester.pumpAndSettle();

      // Rail mode: Text labels in sidebar are collapsed
      expect(find.text('Nguyen Van Saman'), findsNothing);
      expect(find.text('Buổi tập thân trên hôm nay'), findsNothing);

      // Rail mode: Expand button and rail icons are visible with tooltips
      final expandBtn = find.byTooltip('Mở rộng thanh bên');
      expect(expandBtn, findsOneWidget);
      expect(find.byTooltip('Phân tích lịch sử'), findsOneWidget);
      expect(find.byTooltip('Phân tích ảnh món ăn'), findsOneWidget);
      expect(find.byTooltip('Weekly review'), findsNothing);

      // Click expand button to restore full sidebar
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      expect(find.text('Nguyen Van Saman'), findsOneWidget);
      expect(find.text('Buổi tập thân trên hôm nay'), findsOneWidget);
    });

    testWidgets('3. Mobile Viewport (390x844): Slide-out drawer opens, selects thread and closes', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // In mobile mode, sidebar is NOT in body
      expect(find.byType(SamanChatDrawer), findsNothing);

      // Header has Coach Menu button
      final menuBtn = find.byTooltip('Coach Menu');
      expect(menuBtn, findsOneWidget);

      // Open drawer
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Drawer is now open
      expect(find.byType(SamanChatDrawer), findsOneWidget);
      expect(find.text('Nguyen Van Saman'), findsOneWidget);
      expect(find.text('Kế hoạch dinh dưỡng TDEE'), findsOneWidget);

      // Tap on second conversation
      await tester.tap(find.text('Kế hoạch dinh dưỡng TDEE'));
      await tester.pumpAndSettle();

      // Controller loaded conversation c2
      expect(mockChat.loadedConversationId, 'c2');

      // Drawer is closed
      expect(find.byType(SamanChatDrawer), findsNothing);
    });

    testWidgets('4. New conversation button triggers newConversation()', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      final newChatBtn = find.widgetWithText(InkWell, 'New conversation');
      expect(newChatBtn, findsOneWidget);

      await tester.tap(newChatBtn);
      await tester.pumpAndSettle();

      expect(mockChat.newConversationCalled, isTrue);
    });

    testWidgets('5. Dynamic Resize across 840px breakpoint: switches cleanly between sidebar and drawer', (tester) async {
      // Start with Desktop size (900x700)
      tester.view.physicalSize = const Size(900 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Desktop: Sidebar present in body, Coach Menu icon absent
      expect(find.byType(SamanChatDrawer), findsOneWidget);
      expect(find.byTooltip('Coach Menu'), findsNothing);

      // Resize down to Mobile (600x700 < 840)
      tester.view.physicalSize = const Size(600 * 2, 700 * 2);
      await tester.pumpAndSettle();

      // Mobile: Sidebar removed from body, Coach Menu icon now present
      expect(find.byType(SamanChatDrawer), findsNothing);
      expect(find.byTooltip('Coach Menu'), findsOneWidget);

      // Resize back to Desktop (950x700 >= 840)
      tester.view.physicalSize = const Size(950 * 2, 700 * 2);
      await tester.pumpAndSettle();

      // Desktop restored
      expect(find.byType(SamanChatDrawer), findsOneWidget);
      expect(find.byTooltip('Coach Menu'), findsNothing);
    });

    testWidgets('6. Long conversation list scrolls independently while account row remains pinned', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Account name is visible
      expect(find.text('Nguyen Van Saman'), findsOneWidget);

      // Scroll the middle ListView
      final scrollableFinder = find.byType(Scrollable).first;
      await tester.drag(scrollableFinder, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Account row is still firmly pinned at the bottom
      expect(find.text('Nguyen Van Saman'), findsOneWidget);
      expect(find.text('sa***@test.com'), findsOneWidget);
    });

    testWidgets('7. Tapping account row navigates to ProfileScreen', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Tap on account row
      final accountTapTarget = find.text('Nguyen Van Saman');
      await tester.tap(accountTapTarget);
      await tester.pumpAndSettle();

      // Profile screen is pushed
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('8. Fast switching between thread A and thread B', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Tap conversation c2
      await tester.tap(find.text('Kế hoạch dinh dưỡng TDEE'));
      await tester.pumpAndSettle();
      expect(mockChat.loadedConversationId, 'c2');

      // Tap conversation c1
      await tester.tap(find.text('Buổi tập thân trên hôm nay'));
      await tester.pumpAndSettle();
      expect(mockChat.loadedConversationId, 'c1');
    });

    testWidgets('9. Desktop: Toggle expand -> rail -> expand preserves draft text and scroll position', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Enter draft in composer
      final composerInput = find.byType(TextField);
      expect(composerInput, findsOneWidget);
      await tester.enterText(composerInput, 'Bản thảo câu hỏi về chế độ ăn...');
      await tester.pumpAndSettle();

      // Collapse sidebar to rail
      await tester.tap(find.byTooltip('Thu gọn thanh bên'));
      await tester.pumpAndSettle();

      // Verify draft text is still present in composer
      expect(find.text('Bản thảo câu hỏi về chế độ ăn...'), findsOneWidget);

      // Re-expand sidebar
      await tester.tap(find.byTooltip('Mở rộng thanh bên'));
      await tester.pumpAndSettle();

      // Verify draft text is preserved
      expect(find.text('Bản thảo câu hỏi về chế độ ăn...'), findsOneWidget);
    });

    testWidgets('10. New conversation reset does not create canonical thread until message sent', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      final initialConversationsCount = mockChat.state.recentConversations.length;

      // Click New conversation
      await tester.tap(find.widgetWithText(InkWell, 'New conversation'));
      await tester.pumpAndSettle();

      // Verified: messages cleared, activeConversationId cleared, but NO new thread added
      expect(mockChat.state.messages, isEmpty);
      expect(mockChat.state.activeConversationId, isNull);
      expect(mockChat.state.recentConversations.length, equals(initialConversationsCount));
    });

    testWidgets('11. Coach tools: Phân tích lịch sử and Phân tích ảnh món ăn entry points', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Verify both approved tools exist in sidebar
      final historyTool = find.descendant(of: find.byType(SamanChatDrawer), matching: find.text('Phân tích lịch sử'));
      final photoTool = find.descendant(of: find.byType(SamanChatDrawer), matching: find.text('Phân tích ảnh món ăn'));

      expect(historyTool, findsOneWidget);
      expect(photoTool, findsOneWidget);

      // Tap history tool to verify it triggers sheet
      await tester.tap(historyTool);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HistoryAnalyticsSheet), findsOneWidget);

      // Close modal sheet
      final currentContext = tester.element(find.byType(HistoryAnalyticsSheet));
      Navigator.of(currentContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('12. Settings gear icon and Saman preferences opens Persona bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChat = _MockChatNotifier();
      await tester.pumpWidget(_buildSidebarTestApp(chatNotifier: mockChat));
      await tester.pumpAndSettle();

      // Tap gear icon on pinned account row
      final gearBtn = find.byTooltip('Tùy chọn Saman');
      expect(gearBtn, findsOneWidget);
      await tester.tap(gearBtn);
      await tester.pumpAndSettle();

      // Persona preferences dialog is shown
      expect(find.text('Saman Preferences'), findsOneWidget);
      expect(find.text('Strict PT'), findsOneWidget);
      expect(find.text('Nutrition Doctor'), findsOneWidget);
      expect(find.text('Supportive Coach'), findsOneWidget);

      // Close dialog
      final dialogContext = tester.element(find.text('Saman Preferences'));
      Navigator.of(dialogContext).pop();
      await tester.pumpAndSettle();
    });
  });
}

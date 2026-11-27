import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/community/presentation/screens/notifications/community_notifications_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_account_popup_menu.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_header.dart';
import 'package:health_ai_app/screens/settings/app_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _FakeProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeChatNotifier(super.state);

  String? loadedConversationId;

  @override
  Future<void> loadConversation(String conversationId) async {
    loadedConversationId = conversationId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapTestApp({
  required Widget child,
  PreferredSizeWidget? appBar,
  List<Override> extraOverrides = const [],
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'athlete@saman.app',
  );

  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(
        (ref) => _FakeProfileNotifier(
          ProfileState(
            profile: profileEntity,
            snapshot: profileSnapshot,
            status: ProfileStatus.ready,
          ),
        ),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: Scaffold(
        appBar: appBar,
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SamanChatHeader wiring', () {
    testWidgets(
      'tapping bell icon navigates to CommunityNotificationsScreen without placeholder SnackBar',
      (tester) async {
        await tester.pumpWidget(
          _wrapTestApp(
            appBar: SamanChatHeader(
              onMenuTap: () {},
              onNewChat: () {},
            ),
            child: const SizedBox.shrink(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Reminders'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CommunityNotificationsScreen), findsOneWidget);
        expect(
          find.text('No active coach reminders right now.'),
          findsNothing,
        );
      },
    );
  });

  group('SamanChatDrawer wiring', () {
    testWidgets(
      'tapping View all conversations opens bottom sheet with all recentConversations and selects item',
      (tester) async {
        String? selectedId;
        final conversations = [
          ChatConversationSummary(id: 'conv_1', title: 'Lịch tập Push Pull Legs'),
          ChatConversationSummary(id: 'conv_2', title: 'Phân tích Squat rep 5'),
          ChatConversationSummary(id: 'conv_3', title: 'Thực đơn cắt mỡ 2200 kcal'),
        ];

        await tester.pumpWidget(
          _wrapTestApp(
            child: SamanChatDrawer(
              isDesktop: true,
              onNewChat: () {},
              onPromptSelected: (_) {},
              onOpenPreferences: () {},
              recentConversations: conversations,
              activeConversationId: 'conv_1',
              onSelectConversation: (id) => selectedId = id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('View all conversations'));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('Phân tích Squat rep 5'), findsAtLeastNWidgets(1));
        expect(find.text('Thực đơn cắt mỡ 2200 kcal'), findsAtLeastNWidgets(1));

        // Tap item inside the bottom sheet
        await tester.tap(find.text('Thực đơn cắt mỡ 2200 kcal').last);
        await tester.pumpAndSettle();

        expect(selectedId, 'conv_3');
        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets(
      'tapping Reminders in drawer navigates to AppSettingsScreen without placeholder SnackBar',
      (tester) async {
        await tester.pumpWidget(
          _wrapTestApp(
            child: SamanChatDrawer(
              isDesktop: true,
              onNewChat: () {},
              onPromptSelected: (_) {},
              onOpenPreferences: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Reminders'));
        await tester.pumpAndSettle();

        expect(find.byType(AppSettingsScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  });

  group('SamanAccountPopupMenu wiring and cleanup', () {
    testWidgets(
      'hides unimplemented items (Dữ liệu dùng để cá nhân hóa, Gửi phản hồi)',
      (tester) async {
        await tester.pumpWidget(
          _wrapTestApp(
            child: SamanAccountPopupMenu(
              onClose: () {},
              onOpenPreferences: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dữ liệu dùng để cá nhân hóa'), findsNothing);
        expect(find.text('Gửi phản hồi'), findsNothing);
        expect(find.text('Giới hạn sử dụng'), findsOneWidget);
        expect(find.text('Cài đặt nhắc nhở'), findsOneWidget);
        expect(find.text('Lịch sử trò chuyện'), findsOneWidget);
        expect(find.text('Trợ giúp'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping Giới hạn sử dụng navigates to ManageMembershipScreen',
      (tester) async {
        await tester.pumpWidget(
          _wrapTestApp(
            child: SamanAccountPopupMenu(
              onClose: () {},
              onOpenPreferences: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Giới hạn sử dụng'));
        await tester.pumpAndSettle();

        expect(find.byType(ManageMembershipScreen), findsOneWidget);
        expect(find.textContaining('Tính năng chưa khả dụng'), findsNothing);
      },
    );

    testWidgets(
      'tapping Cài đặt nhắc nhở navigates to AppSettingsScreen',
      (tester) async {
        await tester.pumpWidget(
          _wrapTestApp(
            child: SamanAccountPopupMenu(
              onClose: () {},
              onOpenPreferences: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cài đặt nhắc nhở'));
        await tester.pumpAndSettle();

        expect(find.byType(AppSettingsScreen), findsOneWidget);
        expect(find.textContaining('Tính năng chưa khả dụng'), findsNothing);
      },
    );

    testWidgets(
      'tapping Lịch sử trò chuyện opens conversation history sheet from ChatController',
      (tester) async {
        final fakeChat = _FakeChatNotifier(
          ChatState(
            messages: const [],
            recentConversations: [
              ChatConversationSummary(id: 'c_1', title: 'Lịch tập thân trên'),
              ChatConversationSummary(id: 'c_2', title: 'Chế độ ăn tăng cơ'),
            ],
          ),
        );

        await tester.pumpWidget(
          _wrapTestApp(
            extraOverrides: [
              chatControllerProvider.overrideWith((ref) => fakeChat),
            ],
            child: SamanAccountPopupMenu(
              onClose: () {},
              onOpenPreferences: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Lịch sử trò chuyện'));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('Chế độ ăn tăng cơ'), findsOneWidget);

        await tester.tap(find.text('Chế độ ăn tăng cơ'));
        await tester.pumpAndSettle();

        expect(fakeChat.loadedConversationId, 'c_2');
      },
    );

    testWidgets(
      'tapping Trợ giúp opens Hướng dẫn nhanh Saman V1.0 dialog and invokes onResetCoachTour',
      (tester) async {
        var resetCalled = false;

        await tester.pumpWidget(
          _wrapTestApp(
            child: SamanAccountPopupMenu(
              onClose: () {},
              onOpenPreferences: () {},
              onResetCoachTour: () => resetCalled = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Trợ giúp'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trợ giúp'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Hướng dẫn nhanh Saman V1.0'), findsOneWidget);
        expect(find.text('AI Coach & Dẫn chứng Video'), findsOneWidget);
        expect(find.text('Workout Form Check AI'), findsOneWidget);
        expect(find.text('Quét & Theo dõi Dinh dưỡng'), findsOneWidget);
        expect(find.textContaining('Tính năng chưa khả dụng'), findsNothing);

        await tester.tap(find.text('Xem lại hướng dẫn tương tác'));
        await tester.pumpAndSettle();

        expect(resetCalled, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_account_popup_menu.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_persona_menu.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_plans_comparison_screen.dart';

class _FakeProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _FakeProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required Widget child,
  Size size = const Size(1024, 768),
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'sa***@gmail.com',
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
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('Saman AI Chat — Floating Account Menu (Gemini-Style)', () {
    testWidgets(
        '1. Avatar, ten tai khoan hoac banh rang deu mo cung mot menu noi tren footer',
        (tester) async {
      final drawer = SamanChatDrawer(
        isDesktop: true,
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
      );

      await tester.pumpWidget(_buildTestApp(child: drawer));
      await tester.pumpAndSettle();

      // Initially menu is closed
      expect(find.byType(SamanAccountPopupMenu), findsNothing);

      // 1a. Tap gear button -> opens floating menu
      final gearBtn = find.byTooltip('Tùy chọn Saman');
      expect(gearBtn, findsOneWidget);
      await tester.tap(gearBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

      // 1b. Tap barrier outside menu -> closes menu
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();

      expect(find.byType(SamanAccountPopupMenu), findsNothing);

      // 1c. Tap account name / row -> opens same menu
      final accountRow = find.text('Saman Athlete');
      await tester.tap(accountRow);
      await tester.pumpAndSettle();

      expect(find.byType(SamanAccountPopupMenu), findsOneWidget);
    });

    testWidgets(
        '2. Menu noi hien thi dung thu tu 3 nhom, 10 muc va he icon bieu tuong',
        (tester) async {
      final drawer = SamanChatDrawer(
        isDesktop: true,
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
      );

      await tester.pumpWidget(_buildTestApp(child: drawer));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();

      // Nhom 1: Tai khoan
      expect(find.text('Tài khoản'), findsOneWidget);
      expect(find.text('Giới hạn sử dụng'), findsOneWidget);
      expect(find.text('Quản lý gói'), findsOneWidget);
      expect(find.text('Nâng cấp gói'), findsOneWidget);

      // Nhom 2: Tuy chon
      expect(find.text('Tùy chọn'), findsOneWidget);
      expect(find.text('Cá nhân hóa Coach'), findsOneWidget);
      expect(find.text('Giao diện'), findsOneWidget);
      expect(find.text('Cài đặt nhắc nhở'), findsOneWidget);

      // Nhom 3: Du lieu va quyen rieng tu
      expect(find.text('Dữ liệu và quyền riêng tư'), findsOneWidget);
      expect(find.text('Dữ liệu dùng để cá nhân hóa'), findsOneWidget);
      expect(find.text('Lịch sử trò chuyện'), findsOneWidget);
      expect(find.text('Gửi phản hồi'), findsOneWidget);
      expect(find.text('Trợ giúp'), findsOneWidget);

      // Verify sparkle icon is used for "Nâng cấp gói"
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);

      // Verify no "Pro" badge on "Nâng cấp gói" row
      expect(find.text('Pro'), findsNothing);
    });

    testWidgets('3. Bam ra ngoai barrier hoac an Escape dong menu va tra focus',
        (tester) async {
      final drawer = SamanChatDrawer(
        isDesktop: true,
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
      );

      await tester.pumpWidget(_buildTestApp(child: drawer));
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();
      expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

      // Tap outside (on the header area)
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();
      expect(find.byType(SamanAccountPopupMenu), findsNothing);

      // Open menu again
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();
      expect(find.byType(SamanAccountPopupMenu), findsOneWidget);

      // Press Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SamanAccountPopupMenu), findsNothing);
    });

    testWidgets(
        '4. Ca nhan hoa Coach mo man Saman Preferences, Quan ly goi mo ManageMembershipScreen',
        (tester) async {
      bool preferencesCalled = false;

      final drawer = SamanChatDrawer(
        isDesktop: true,
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {
          preferencesCalled = true;
        },
      );

      await tester.pumpWidget(_buildTestApp(child: drawer));
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();

      // Tap Ca nhan hoa Coach
      await tester.tap(find.text('Cá nhân hóa Coach'));
      await tester.pumpAndSettle();

      expect(preferencesCalled, isTrue);
      expect(find.byType(SamanAccountPopupMenu), findsNothing);

      // Dismiss persona menu if open before next step
      if (find.byType(SamanPersonaMenu).evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(50, 50));
        await tester.pumpAndSettle();
      }

      // Open menu again and test Quan ly goi
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quản lý gói'));
      await tester.pumpAndSettle();

      expect(find.byType(ManageMembershipScreen), findsOneWidget);
    });

    testWidgets(
        '5. Nang cap goi mo man Bang so sanh cac goi Saman (Frame 2) va quay lai duoc',
        (tester) async {
      final drawer = SamanChatDrawer(
        isDesktop: true,
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
      );

      await tester.pumpWidget(_buildTestApp(child: drawer));
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();

      // Tap Nang cap goi
      await tester.tap(find.text('Nâng cấp gói'));
      await tester.pumpAndSettle();

      // Frame 2 opens
      expect(find.byType(SamanPlansComparisonScreen), findsOneWidget);
      expect(find.text('Các gói Saman'), findsOneWidget);
      expect(find.text('Bản xem trước'), findsOneWidget);
      expect(find.textContaining('Bản xem trước tính năng'), findsOneWidget);

      // 4 plan cards rendered
      expect(find.text('Saman Free'), findsOneWidget);
      expect(find.text('Saman Plus'), findsOneWidget);
      expect(find.text('Saman Pro'), findsOneWidget);

      // Scroll down to see Saman Ultra
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Saman Ultra'), findsOneWidget);

      // Verify "Gói hiện tại" badge on Free
      expect(find.text('Gói hiện tại'), findsOneWidget);

      // Tap Quay lai button
      final backBtn = find.byTooltip('Quay lại');
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // Screen pops back cleanly to drawer
      expect(find.byType(SamanPlansComparisonScreen), findsNothing);
      expect(find.byType(SamanChatDrawer), findsOneWidget);
    });

    testWidgets(
        '6. Muc chua co chuc nang (Gioi han su dung) hien thi SnackBar chua kha dung',
        (tester) async {
      final drawer = SamanChatDrawer(
        isDesktop: true,
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
      );

      await tester.pumpWidget(_buildTestApp(child: drawer));
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();

      // Tap Gioi han su dung
      await tester.tap(find.text('Giới hạn sử dụng'));
      await tester.pumpAndSettle();

      // Verify non-empty and non-fake SnackBar is shown
      expect(
        find.text(
            'Giới hạn sử dụng: Tính năng chưa khả dụng trong phiên bản thử nghiệm.'),
        findsOneWidget,
      );
    });
  });
}

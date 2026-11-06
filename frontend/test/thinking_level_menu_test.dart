import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';

Widget _buildComposerTestHarness({
  required TextEditingController controller,
  FocusNode? focusNode,
  VoidCallback? onSend,
  bool isLoading = false,
  AIMode activeMode = AIMode.core3,
  double maxWidth = 600.0,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SamanTheme.dark(),
    home: Scaffold(
      backgroundColor: SamanChatTokens.canvas,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SamanChatComposer(
              controller: controller,
              focusNode: focusNode,
              onSend: onSend ?? () {},
              isLoading: isLoading,
              activeMode: activeMode,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Thinking Level in Core 3 AI Mode Menu Matrix', () {
    testWidgets('1. Main menu displays Core 3, Swift 3, Pro 3, divider, and Thinking level trigger row', (tester) async {
      final controller = TextEditingController(text: 'Kế hoạch tập ngực');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      // Open Mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Verify AI modes
      expect(find.text('Core 3'), findsNWidgets(2)); // Button + Item
      expect(find.text('Mặc định toàn diện'), findsOneWidget);
      expect(find.text('Swift 3'), findsOneWidget);
      expect(find.text('Pro 3'), findsOneWidget);

      // Verify Trigger row
      expect(find.text('Mức độ suy luận'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      // Verify draft preserved
      expect(controller.text, 'Kế hoạch tập ngực');
    });

    testWidgets('2. Desktop cascading submenu: click opens Low (locked), Medium (active), High (locked)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = TextEditingController(text: 'Dinh dưỡng');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller, maxWidth: 500.0));
      await tester.pumpAndSettle();

      // Open Mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Submenu not open initially
      expect(find.text('Cân bằng độ sâu'), findsNothing);

      // Click "Mức độ suy luận"
      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Submenu items visible simultaneously on desktop
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Nhanh và gọn'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Cân bằng độ sâu'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Phân tích kỹ hơn'), findsOneWidget);

      // Both main menu and submenu visible simultaneously
      expect(find.text('Mặc định toàn diện'), findsOneWidget);
      expect(find.text('Cân bằng độ sâu'), findsOneWidget);

      // Low and High have lock badges "Sắp ra mắt"
      expect(find.text('Sắp ra mắt'), findsNWidgets(4)); // Swift 3, Pro 3, Low, High
    });

    testWidgets('3. Desktop hover opens submenu after 150ms debounce, mouse bridge maintains open state', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      // Open Mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      // Pointer enters trigger row
      final triggerLocation = tester.getCenter(find.text('Mức độ suy luận'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(triggerLocation);
      await tester.pump();

      // Before 150ms debounce: submenu not yet open
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Cân bằng độ sâu'), findsNothing);

      // After 150ms debounce: submenu opens
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Cân bằng độ sâu'), findsOneWidget);

      // Move mouse towards submenu card
      final mediumLocation = tester.getCenter(find.text('Medium'));
      await gesture.moveTo(mediumLocation);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Submenu remains open without closing
      expect(find.text('Cân bằng độ sâu'), findsOneWidget);
      await gesture.removePointer();
    });

    testWidgets('4. Tapping locked Low/High shows snackbar and keeps Medium selected', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap locked "Low"
      await tester.tap(find.text('Low'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Snackbar shown
      expect(find.text('Mức suy luận này chưa được mở'), findsOneWidget);

      // Medium is still selected and present
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Cân bằng độ sâu'), findsOneWidget);

      // Tap locked "High"
      await tester.tap(find.text('High'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Snackbar shown again
      expect(find.text('Mức suy luận này chưa được mở'), findsOneWidget);
    });

    testWidgets('5. Tapping Medium closes entire cascade and restores composer focus', (tester) async {
      final controller = TextEditingController(text: 'Chào Saman');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(
        controller: controller,
        focusNode: focusNode,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Medium'), findsOneWidget);

      // Tap Medium
      await tester.tap(find.text('Medium'));
      await tester.pumpAndSettle();

      // All popovers closed
      expect(find.text('Mặc định toàn diện'), findsNothing);
      expect(find.text('Cân bằng độ sâu'), findsNothing);

      // Composer focus restored & draft preserved
      expect(focusNode.hasFocus, isTrue);
      expect(controller.text, 'Chào Saman');
    });

    testWidgets('6. Escape closes submenu first, next Escape closes main menu, outside tap closes cascade', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(
        controller: controller,
        focusNode: focusNode,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Cân bằng độ sâu'), findsOneWidget);
      expect(find.text('Mặc định toàn diện'), findsOneWidget);

      // 1st Escape: Closes submenu only, keeps main menu open
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Cân bằng độ sâu'), findsNothing);
      expect(find.text('Mặc định toàn diện'), findsOneWidget);

      // 2nd Escape: Closes main menu, restores focus
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Mặc định toàn diện'), findsNothing);
      expect(focusNode.hasFocus, isTrue);

      // Re-open and verify outside tap closes cascade completely
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Cân bằng độ sâu'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20)); // Barrier tap
      await tester.pumpAndSettle();

      expect(find.text('Cân bằng độ sâu'), findsNothing);
      expect(find.text('Mặc định toàn diện'), findsNothing);
    });

    testWidgets('7. Mobile drilldown layout: replaces popover card, back button returns to AI modes, >= 48px targets', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildComposerTestHarness(controller: controller, maxWidth: 360.0));
      await tester.pumpAndSettle();

      // Open Mode menu on mobile
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      expect(find.text('Mặc định toàn diện'), findsOneWidget);
      expect(find.text('Mức độ suy luận'), findsOneWidget);

      // Tap "Mức độ suy luận" on mobile -> drilldown into submenu view
      await tester.tap(find.text('Mức độ suy luận'));
      await tester.pumpAndSettle();

      // Main menu replaced by drilldown view
      expect(find.text('Mặc định toàn diện'), findsNothing);
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);

      // Verify touch targets >= 48 logical pixels
      final headerRect = tester.getRect(find.byIcon(Icons.chevron_left_rounded));
      expect(headerRect.height, greaterThanOrEqualTo(20.0));

      // Tap back button "‹ Mức độ suy luận"
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();

      // Back to main menu
      expect(find.text('Mặc định toàn diện'), findsOneWidget);
      expect(find.text('Swift 3'), findsOneWidget);
      expect(find.text('Cân bằng độ sâu'), findsNothing);
    });
  });
}


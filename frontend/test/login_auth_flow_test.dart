import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/screens/login/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pumpLoginScreen(
    WidgetTester tester, {
    required ThemeData theme,
    Size viewport = const Size(390, 844),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  group('LoginScreen Dual-Theme & Platform Guard', () {
    testWidgets('renders cleanly without overflow in SamanTheme.light()',
        (tester) async {
      await pumpLoginScreen(tester, theme: SamanTheme.light());

      expect(tester.takeException(), isNull);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, SamanPalette.light.canvas);

      final formCard = find.ancestor(
        of: find.byType(Form),
        matching: find.byType(Container),
      );
      final cardWidget = tester.widget<Container>(formCard.first);
      final decoration = cardWidget.decoration! as BoxDecoration;
      expect(decoration.color, SamanPalette.light.surface);

      final switchButton =
          find.textContaining("Don't have an account?", findRichText: true);
      await tester.ensureVisible(switchButton);
      await tester.tap(switchButton);
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly without overflow in SamanTheme.dark()',
        (tester) async {
      await pumpLoginScreen(tester, theme: SamanTheme.dark());

      expect(tester.takeException(), isNull);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, SamanPalette.dark.canvas);

      final formCard = find.ancestor(
        of: find.byType(Form),
        matching: find.byType(Container),
      );
      final cardWidget = tester.widget<Container>(formCard.first);
      final decoration = cardWidget.decoration! as BoxDecoration;
      expect(decoration.color, SamanPalette.dark.surface);

      final switchButton =
          find.textContaining("Don't have an account?", findRichText: true);
      await tester.ensureVisible(switchButton);
      await tester.tap(switchButton);
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'hides Apple Sign-In and shows Google & Facebook on TargetPlatform.android',
        (tester) async {
      await pumpLoginScreen(tester, theme: SamanTheme.light());

      expect(find.byKey(const ValueKey('apple_login_button')), findsNothing);
      expect(find.byKey(const ValueKey('google_login_button')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('facebook_login_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('shows Google, Apple & Facebook buttons on TargetPlatform.iOS',
        (tester) async {
      await pumpLoginScreen(tester, theme: SamanTheme.dark());

      expect(find.byKey(const ValueKey('google_login_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('apple_login_button')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('facebook_login_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('renders streamlined Guest Mode TextButton with expected label',
        (tester) async {
      await pumpLoginScreen(tester, theme: SamanTheme.light());

      final guestFinder = find.byKey(const Key('guest_login_button'));
      expect(guestFinder, findsOneWidget);
      expect(tester.widget(guestFinder), isA<TextButton>());
      expect(
        find.descendant(
          of: guestFinder,
          matching: find.text('Dùng thử không cần tài khoản'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'ForgotPasswordSheet opens cleanly in both light and dark themes',
        (tester) async {
      for (final theme in [SamanTheme.light(), SamanTheme.dark()]) {
        await pumpLoginScreen(tester, theme: theme);
        await tester.tap(find.text('Forgot Password?'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(LoginScreen))).pop();
        await tester.pumpAndSettle();
      }
    });
  });
}

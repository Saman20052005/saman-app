import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/screens/login/login_screen.dart';
import 'package:health_ai_app/screens/plan_screen.dart' as legacy_plan;
import 'package:health_ai_app/screens/splash_screen.dart';
import 'package:health_ai_app/widgets/app_logo.dart';

import 'fixtures/chat_render/render_resources.dart';

Future<ByteData> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final pixels = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final directory = Platform.environment['SAMAN_RENDER_EVIDENCE'];
      if (directory != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$directory/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
      }
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  });
  return pixels!;
}

int _solidPixels(ByteData pixels, Color color) {
  var count = 0;
  for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
    if (pixels.getUint8(offset) == color.red &&
        pixels.getUint8(offset + 1) == color.green &&
        pixels.getUint8(offset + 2) == color.blue &&
        pixels.getUint8(offset + 3) == color.alpha) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadChatRenderFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  final cases = [
    (
      name: 'light',
      brightness: Brightness.light,
      isLightMode: true,
      tint: null,
      ink: const Color(0xFF1E1E1E),
      background: Colors.white,
    ),
    (
      name: 'dark',
      brightness: Brightness.dark,
      isLightMode: true,
      tint: null,
      ink: Colors.white,
      background: Colors.black,
    ),
    (
      name: 'explicit_dark',
      brightness: Brightness.light,
      isLightMode: false,
      tint: null,
      ink: Colors.white,
      background: Colors.black,
    ),
    (
      name: 'tinted',
      brightness: Brightness.dark,
      isLightMode: true,
      tint: const Color(0xFF126B45),
      ink: const Color(0xFF126B45),
      background: Colors.white,
    ),
  ];

  for (final scenario in cases) {
    testWidgets('AppLogo paints bundled artwork: ${scenario.name}',
        (tester) async {
      for (final size in [24.0, 30.0, 90.0, 130.0]) {
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: scenario.brightness),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: scenario.background,
                child: AppLogo(
                  size: size,
                  isLightMode: scenario.isLightMode,
                  color: scenario.tint,
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(AppLogo)), Size.square(size));
        final pixels = await _capture(
            tester, key, 'logo_${scenario.name}_${size.toInt()}');
        expect(_solidPixels(pixels, scenario.ink), greaterThan(size * size / 4),
            reason: 'The registered SVG must load and paint visible artwork.');
        expect(
            _solidPixels(pixels, scenario.background), greaterThan(size * size),
            reason: 'The mark must retain its transparent surrounding area.');
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Splash renders the bundled logo within its existing bounds',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: const SplashScreen(enableAnimations: false),
      ),
    ));
    // The splash spinner stays active until the existing 2200 ms auth redirect.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('SAMAN'), findsOneWidget);
    expect(tester.getSize(find.byType(AppLogo)), const Size.square(130));
    await _capture(tester, key, 'splash_light');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Login and register keep their logo bounds and mode switch usable',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: RepaintBoundary(key: key, child: const LoginScreen()),
        ),
      ));
      await tester.pumpAndSettle();
      final originalLogoRect = tester.getRect(find.byType(AppLogo));
      expect(originalLogoRect.size, const Size.square(90));
      expect(find.text('Welcome Back!'), findsOneWidget);
      await _capture(tester, key, 'login_${brightness.name}');

      final switchMode =
          find.textContaining("Don't have an account?", findRichText: true);
      await tester.ensureVisible(switchMode);
      await tester.tap(switchMode);
      await tester.pumpAndSettle();
      expect(find.text('Create Account'), findsOneWidget);
      expect(tester.getSize(find.byType(AppLogo)), originalLogoRect.size);
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'register_${brightness.name}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Existing Plan logo callers fit the app bar and editable field',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: RepaintBoundary(
          key: key,
          child: const legacy_plan.CreatePlanScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      final logos = find.byType(AppLogo);
      expect(logos, findsNWidgets(2));
      final leadingRect = tester.getRect(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(AppLogo),
      ));
      final prefixRect = tester.getRect(find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(AppLogo),
      ));
      expect(leadingRect.size, const Size.square(32));
      expect(prefixRect.size, const Size.square(24));
      expect(tester.getRect(find.byType(AppBar)).intersect(leadingRect),
          leadingRect);
      expect(
          tester
              .getRect(find.byType(TextFormField).first)
              .intersect(prefixRect),
          prefixRect);
      await _capture(tester, key, 'plan_${brightness.name}');
      await tester.tap(find.byType(TextFormField).first);
      await tester.enterText(
          find.byType(TextFormField).first, 'Existing plan title');
      expect(find.text('Existing plan title'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

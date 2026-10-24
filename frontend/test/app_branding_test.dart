import 'dart:convert';
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

Future<Map<String, Object>> _measureLogoContrast(
  WidgetTester tester,
  GlobalKey key,
  Finder logo,
  ByteData pixels,
  String state,
) async {
  const pixelRatio = 2;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = tester.getRect(logo);
  final local = boundary.globalToLocal(rect.topLeft);
  final width = (boundary.size.width * pixelRatio).round();
  final height = (boundary.size.height * pixelRatio).round();
  final left = (local.dx * pixelRatio).floor().clamp(0, width).toInt();
  final top = (local.dy * pixelRatio).floor().clamp(0, height).toInt();
  final right =
      ((local.dx + rect.width) * pixelRatio).ceil().clamp(0, width).toInt();
  final bottom =
      ((local.dy + rect.height) * pixelRatio).ceil().clamp(0, height).toInt();
  final histogram = <int, int>{};
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * width + x) * 4;
      final color = Color.fromARGB(
        pixels.getUint8(offset + 3),
        pixels.getUint8(offset),
        pixels.getUint8(offset + 1),
        pixels.getUint8(offset + 2),
      );
      histogram.update(color.value, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  // The artwork has transparent corners, exposing the real caller surface.
  final corner = (top * width + left) * 4;
  final background = Color.fromARGB(
    pixels.getUint8(corner + 3),
    pixels.getUint8(corner),
    pixels.getUint8(corner + 1),
    pixels.getUint8(corner + 2),
  );
  final backgroundLuminance = background.computeLuminance();
  var foregroundPixels = 0;
  var strongestContrast = 1.0;
  for (final entry in histogram.entries) {
    final luminance = Color(entry.key).computeLuminance();
    final contrast = luminance > backgroundLuminance
        ? (luminance + 0.05) / (backgroundLuminance + 0.05)
        : (backgroundLuminance + 0.05) / (luminance + 0.05);
    if (contrast > strongestContrast) strongestContrast = contrast;
    if (contrast >= 7) foregroundPixels += entry.value;
  }
  final area = (right - left) * (bottom - top);
  final backgroundPixels = histogram[background.value] ?? 0;
  final measurement = <String, Object>{
    'state': state,
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'pixelRect': [left, top, right, bottom],
    'background': background.value,
    'backgroundPixels': backgroundPixels,
    'foregroundPixelsAtLeast7To1': foregroundPixels,
    'strongestContrast': strongestContrast,
    'area': area,
    'passes': area > 0 &&
        foregroundPixels >= area * 0.10 &&
        backgroundPixels >= area * 0.20,
  };
  final directory = Platform.environment['SAMAN_RENDER_EVIDENCE'];
  if (directory != null) {
    File('$directory/$state.contrast.json')
        .writeAsStringSync(jsonEncode(measurement));
  }
  return measurement;
}

void _expectReadableLogos(List<Map<String, Object>> measurements) {
  expect(measurements.every((entry) => entry['passes'] == true), isTrue,
      reason: 'Each real caller must paint substantial foreground at >=7:1 '
          'contrast against its actual surface: ${jsonEncode(measurements)}');
}

ThemeData _callerTheme(Brightness brightness) {
  // Match SamanTheme input surfaces using cached harness fonts only.
  final surface =
      brightness == Brightness.dark ? const Color(0xFF1C1C1C) : Colors.white;
  return ThemeData(
    brightness: brightness,
    inputDecorationTheme:
        InputDecorationTheme(filled: true, fillColor: surface),
  );
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
    final measurements = <Map<String, Object>>[];
    for (final brightness in Brightness.values) {
      for (final animated in [false, true]) {
        final key = GlobalKey();
        final state = 'splash_${animated ? 'animated_' : ''}${brightness.name}';
        await tester.pumpWidget(MaterialApp(
          theme: _callerTheme(brightness),
          home: RepaintBoundary(
            key: key,
            child: SplashScreen(enableAnimations: animated),
          ),
        ));
        // Sample after fade/scale, before the existing 2200 ms auth redirect.
        await tester.pump();
        for (var frame = 0; frame < (animated ? 6 : 1); frame++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.text('SAMAN'), findsOneWidget);
        expect(tester.getSize(find.byType(AppLogo)), const Size.square(130));
        final pixels = await _capture(tester, key, state);
        measurements.add(await _measureLogoContrast(
            tester, key, find.byType(AppLogo), pixels, state));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    _expectReadableLogos(measurements);
  });

  testWidgets(
      'Login and register keep their logo bounds and mode switch usable',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final measurements = <Map<String, Object>>[];
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: _callerTheme(brightness),
          home: RepaintBoundary(key: key, child: const LoginScreen()),
        ),
      ));
      await tester.pumpAndSettle();
      final originalLogoRect = tester.getRect(find.byType(AppLogo));
      expect(originalLogoRect.size, const Size.square(90));
      expect(find.text('Welcome Back!'), findsOneWidget);
      final loginState = 'login_${brightness.name}';
      final loginPixels = await _capture(tester, key, loginState);
      measurements.add(await _measureLogoContrast(
          tester, key, find.byType(AppLogo), loginPixels, loginState));

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
      final registerState = 'register_${brightness.name}';
      final registerPixels = await _capture(tester, key, registerState);
      measurements.add(await _measureLogoContrast(
          tester, key, find.byType(AppLogo), registerPixels, registerState));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    _expectReadableLogos(measurements);
  });

  testWidgets('Existing Plan logo callers fit the app bar and editable field',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final measurements = <Map<String, Object>>[];
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: _callerTheme(brightness),
        home: RepaintBoundary(
          key: key,
          child: const legacy_plan.CreatePlanScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      final logos = find.byType(AppLogo);
      expect(logos, findsNWidgets(2));
      final leadingLogo = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(AppLogo),
      );
      final prefixLogo = find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(AppLogo),
      );
      final leadingRect = tester.getRect(leadingLogo);
      final prefixRect = tester.getRect(prefixLogo);
      expect(leadingRect.size, const Size.square(32));
      expect(prefixRect.size, const Size.square(24));
      expect(tester.getRect(find.byType(AppBar)).intersect(leadingRect),
          leadingRect);
      expect(
          tester
              .getRect(find.byType(TextFormField).first)
              .intersect(prefixRect),
          prefixRect);
      final state = 'plan_${brightness.name}';
      final pixels = await _capture(tester, key, state);
      measurements.add(await _measureLogoContrast(
          tester, key, leadingLogo, pixels, '${state}_leading'));
      measurements.add(await _measureLogoContrast(
          tester, key, prefixLogo, pixels, '${state}_prefix'));
      await tester.tap(find.byType(TextFormField).first);
      await tester.enterText(
          find.byType(TextFormField).first, 'Existing plan title');
      expect(find.text('Existing plan title'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    _expectReadableLogos(measurements);
  });
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/step_age_gender_view.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/step_body_view.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/onboarding_tokens.dart';

const String _outputDir = 'D:/SamanDev/runtime/onboarding_input_ui_fix';

Future<void> _capture(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('render_capture_boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      final file = File('$_outputDir/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
    }
    image.dispose();
  });
}

Widget _wrapScreen({
  required Widget child,
  ThemeData? theme,
  EdgeInsets? viewInsets,
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ??
        ThemeData.dark().copyWith(
          scaffoldBackgroundColor: OnboardingTokens.canvas,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.white, // Emulate inherited white fill to verify fix
          ),
        ),
    home: RepaintBoundary(
      key: const ValueKey('render_capture_boundary'),
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          devicePixelRatio: 1.0,
          textScaler: TextScaler.linear(textScaleFactor),
          viewInsets: viewInsets ?? EdgeInsets.zero,
        ),
        child: SizedBox(
          width: 390,
          height: 844,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = Directory(_outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  });

    testWidgets('Step 2 - Empty state (placeholder, dark surface)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          child: StepAgeGenderView(
            initialAge: null,
            initialGender: null,
            onAgeChanged: (_) {},
            onGenderSelected: (_) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step2_after_empty.png');
      expect(find.byKey(const Key('age_input_field')), findsOneWidget);
      expect(find.text('Enter your age'), findsOneWidget);
      expect(find.text('YEARS'), findsOneWidget);
    });

    testWidgets('Step 2 - Filled state (age entered, gender selected)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          child: StepAgeGenderView(
            initialAge: 28,
            initialGender: Gender.male,
            onAgeChanged: (_) {},
            onGenderSelected: (_) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step2_after_filled.png');
      expect(find.text('28'), findsOneWidget);
      expect(find.text('YEARS'), findsOneWidget);
    });

    testWidgets('Step 2 - Keyboard open state', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          viewInsets: const EdgeInsets.only(bottom: 280),
          child: StepAgeGenderView(
            initialAge: 28,
            initialGender: Gender.male,
            onAgeChanged: (_) {},
            onGenderSelected: (_) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step2_after_keyboard.png');
      expect(find.text('28'), findsOneWidget);
    });

    testWidgets('Step 3 - Empty state (placeholder, dark surface)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          child: StepBodyView(
            initialHeight: null,
            initialWeight: null,
            onHeightChanged: (_, __) {},
            onWeightChanged: (_, __) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step3_after_empty.png');
      expect(find.byKey(const Key('height_input_field')), findsOneWidget);
      expect(find.byKey(const Key('weight_input_field')), findsOneWidget);
      expect(find.text('Enter height'), findsOneWidget);
      expect(find.text('Enter weight'), findsOneWidget);
      expect(find.text('cm'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
    });

    testWidgets('Step 3 - Filled state (height and weight with decimal)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          child: StepBodyView(
            initialHeight: 178.5,
            initialWeight: 72.4,
            onHeightChanged: (_, __) {},
            onWeightChanged: (_, __) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step3_after_filled.png');
      expect(find.text('178.5'), findsOneWidget);
      expect(find.text('72.4'), findsOneWidget);
      expect(find.text('cm'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
    });

    testWidgets('Step 3 - Keyboard open state', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          viewInsets: const EdgeInsets.only(bottom: 280),
          child: StepBodyView(
            initialHeight: 178.5,
            initialWeight: 72.4,
            onHeightChanged: (_, __) {},
            onWeightChanged: (_, __) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step3_after_keyboard.png');
      expect(find.text('178.5'), findsOneWidget);
      expect(find.text('72.4'), findsOneWidget);
    });

    testWidgets('Light Theme test (ensuring dark surface remains dark)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapScreen(
          theme: ThemeData.light().copyWith(
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          child: StepAgeGenderView(
            initialAge: 25,
            initialGender: Gender.female,
            onAgeChanged: (_) {},
            onGenderSelected: (_) {},
            onContinue: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _capture(tester, 'step2_light_theme_mode.png');
      expect(find.text('25'), findsOneWidget);
    });
}

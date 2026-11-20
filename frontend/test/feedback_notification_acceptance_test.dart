import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/widgets/saman_feedback_snackbar.dart';

Future<void> _captureScreenPng(WidgetTester tester, String outputPath) async {
  await tester.runAsync(() async {
    final boundary = tester.allRenderObjects
        .whereType<RenderRepaintBoundary>()
        .firstOrNull;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(buffer);

        // Also duplicate to current conversation brain artifact dir for immediate report embedding
        const artifactDir =
            'C:/Users/GL/.gemini/antigravity/brain/b55ba6aa-10b8-4bc5-a4d8-f0aa6aba211b';
        final fileName = outputPath.split(RegExp(r'[/\\]')).last;
        final artifactFile = File('$artifactDir/$fileName');
        await artifactFile.parent.create(recursive: true);
        await artifactFile.writeAsBytes(buffer);
      }
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final msg = details.exceptionAsString();
      if (msg.contains('google_fonts') || msg.contains('Manrope')) {
        return;
      }
      originalOnError?.call(details);
    };
  });

  Widget buildTestHost({
    required ThemeMode themeMode,
    required Widget Function(BuildContext context) triggerBuilder,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Manrope',
        snackBarTheme: SamanTheme.light().snackBarTheme,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Manrope',
        snackBarTheme: SamanTheme.dark().snackBarTheme,
      ),
      themeMode: themeMode,
      home: Scaffold(
        backgroundColor: themeMode == ThemeMode.dark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F5),
        body: Builder(
          builder: (context) => Center(
            child: triggerBuilder(context),
          ),
        ),
      ),
    );
  }

  group('Saman Feedback Notifications Acceptance Tests', () {
    testWidgets('1. Ca mẫu Strict PT in Dark Mode: #26282D background, #383A40 border, green check icon', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestHost(
          themeMode: ThemeMode.dark,
          triggerBuilder: (context) => ElevatedButton(
            onPressed: () {
              SamanFeedbackSnackBar.show(
                context,
                message: 'Đã chuyển sang phong cách: Strict PT',
                type: FeedbackType.success,
                duration: const Duration(seconds: 2),
              );
            },
            child: const Text('Trigger Strict PT'),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Strict PT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Đã chuyển sang phong cách: Strict PT'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);
      final snackBar = tester.widget<SnackBar>(snackBarFinder);

      expect(snackBar.backgroundColor, equals(const Color(0xFF26282D)));
      expect(snackBar.behavior, equals(SnackBarBehavior.floating));

      final shape = snackBar.shape as RoundedRectangleBorder;
      expect(shape.side.color, equals(const Color(0xFF383A40)));
      expect(shape.side.width, equals(1.0));
      expect(shape.borderRadius, equals(BorderRadius.circular(12.0)));

      await _captureScreenPng(
        tester,
        'runtime_evidence/feedback_notifications/strict_pt_neutral_feedback.png',
      );
    });

    testWidgets('2. Ca mẫu Strict PT in Light Mode: #FFFFFF background, #E2E8F0 border, green check icon', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestHost(
          themeMode: ThemeMode.light,
          triggerBuilder: (context) => ElevatedButton(
            onPressed: () {
              SamanFeedbackSnackBar.show(
                context,
                message: 'Đã chuyển sang phong cách: Strict PT',
                type: FeedbackType.success,
                duration: const Duration(seconds: 2),
              );
            },
            child: const Text('Trigger Strict PT Light'),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Strict PT Light'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Đã chuyển sang phong cách: Strict PT'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, equals(const Color(0xFFFFFFFF)));

      final shape = snackBar.shape as RoundedRectangleBorder;
      expect(shape.side.color, equals(const Color(0xFFE2E8F0)));

      await _captureScreenPng(
        tester,
        'runtime_evidence/feedback_notifications/strict_pt_light_neutral_feedback.png',
      );
    });

    testWidgets('3. Error notification with "Thử lại" action works and remains accessible on neutral gray', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool retryTapped = false;

      await tester.pumpWidget(
        buildTestHost(
          themeMode: ThemeMode.dark,
          triggerBuilder: (context) => ElevatedButton(
            onPressed: () {
              SamanFeedbackSnackBar.show(
                context,
                message: 'Đăng xuất thất bại: Network connection lost',
                type: FeedbackType.error,
                action: SnackBarAction(
                  label: 'Thử lại',
                  textColor: const Color(0xFF10B981),
                  onPressed: () {
                    retryTapped = true;
                  },
                ),
              );
            },
            child: const Text('Trigger Error'),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Đăng xuất thất bại: Network connection lost'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, equals(const Color(0xFF26282D)));

      await _captureScreenPng(
        tester,
        'runtime_evidence/feedback_notifications/error_retry_neutral_feedback.png',
      );

      // Tap "Thử lại"
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(retryTapped, isTrue);
    });

    testWidgets('4. Long Vietnamese message wraps smoothly without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestHost(
          themeMode: ThemeMode.dark,
          triggerBuilder: (context) => ElevatedButton(
            onPressed: () {
              SamanFeedbackSnackBar.show(
                context,
                message: 'Không thể kết nối đến máy chủ AI để phân tích thực đơn bữa sáng hôm nay. Vui lòng kiểm tra lại kết nối mạng.',
                type: FeedbackType.warning,
              );
            },
            child: const Text('Trigger Long Text'),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Long Text'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}

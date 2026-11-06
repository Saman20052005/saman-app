import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/journal/data/datasources/journal_fake_datasource.dart';
import 'package:health_ai_app/features/journal/data/repositories/journal_repository_impl.dart';
import 'package:health_ai_app/features/journal/presentation/providers/journal_providers.dart';
import 'package:health_ai_app/features/journal/presentation/screens/journal_discover_screen.dart';
import 'package:health_ai_app/features/journal/presentation/screens/journal_search_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_picks_carousel.dart';

const screenshotDir = r'D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840\docs\jcom01_journal_discover\screenshots';
const screenshotDirA = r'D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840\docs\jcom01a_runtime_acceptance\screenshots';
const captureBoundaryKey = ValueKey('journal-screen-capture-boundary');

Future<void> captureScreenshot(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureBoundaryKey),
  );
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    Directory(screenshotDir).createSync(recursive: true);
    File('$screenshotDir/$filename.png').writeAsBytesSync(bytes);
    Directory(screenshotDirA).createSync(recursive: true);
    File('$screenshotDirA/$filename.png').writeAsBytesSync(bytes);
    img.dispose();
  });
}

Widget buildCaptureHarness({
  required Widget child,
  JournalFakeDatasource? datasource,
  Locale locale = const Locale('vi'),
  double textScaleFactor = 1.0,
}) {
  return ProviderScope(
    overrides: [
      if (datasource != null)
        journalRepositoryProvider.overrideWithValue(
          JournalRepositoryImpl(datasource: datasource),
        ),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: RepaintBoundary(
        key: captureBoundaryKey,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(textScaleFactor),
            padding: const EdgeInsets.only(top: 44, bottom: 34),
          ),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SamanPicksCarousel.resetLastNavTime();
  });

  group('JCOM-01 — UI Render & Evidence Screenshot Generation', () {
    testWidgets('Capture 01: Home Saman Picks with Journal entrypoint', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCaptureHarness(
          child: Scaffold(
            backgroundColor: const Color(0xFF0C0D0E),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Chào buổi sáng, Vận động viên',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SamanPicksCarousel(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureScreenshot(tester, '01_home_journal_entry');
    });

    testWidgets('Capture 02 & 03: R01 Journal Discover populated top and bottom',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalDiscoverScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Top fold
      await captureScreenshot(tester, '02_r01_journal_discover_top');

      // Scroll down to capture libraries, guided series, and doorway card
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, '03_r01_journal_discover_bottom');
    });

    testWidgets('Capture 04: R02 Journal Search with empty query', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalSearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Clear search query
      await tester.tap(find.byKey(const ValueKey('clear_search_button')));
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '04_r02_journal_search_empty_query');
    });

    testWidgets('Capture 05, 06, 07: R02 Search populated results and category filter',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalSearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Populated with default query "protein"
      await captureScreenshot(tester, '05_r02_journal_search_populated_protein');

      // Filter by "Bài tập"
      await tester.tap(find.byKey(const ValueKey('filter_chip_exercises')));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, '06_r02_journal_search_filter_exercises');

      // Drag chips left and filter by "Thực phẩm"
      await tester.drag(find.byType(ListView).first, const Offset(-150, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter_chip_foods')));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, '07_r02_journal_search_filter_foods');
    });

    testWidgets('Capture 08: R02 Search empty results state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalSearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('journal_search_input_field')),
        'không_tồn_tại_123',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '08_r02_journal_search_no_results');
    });

    testWidgets('Capture 09: R02 Search error state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(
        simulatedDelay: Duration.zero,
        shouldSimulateError: true,
      );
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalSearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '09_r02_journal_search_error_state');
    });

    testWidgets('Capture 10: R01 narrow 360px viewport without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            journalRepositoryProvider.overrideWithValue(
              JournalRepositoryImpl(datasource: datasource),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('vi'),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: RepaintBoundary(
              key: captureBoundaryKey,
              child: const MediaQuery(
                data: MediaQueryData(
                  size: Size(360, 780),
                  padding: EdgeInsets.only(top: 40, bottom: 24),
                ),
                child: JournalDiscoverScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureScreenshot(tester, '10_r01_narrow_360px_viewport');
    });

    testWidgets('Capture 11: R01 large text scaling 200% without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          textScaleFactor: 2.0,
          child: const JournalDiscoverScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await captureScreenshot(tester, '11_r01_large_text_scaling_200');
    });

    testWidgets('Capture 12: Community doorway preview sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalDiscoverScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -520));
      await tester.pumpAndSettle();

      expect(find.text('Khám phá cộng đồng'), findsOneWidget);
      await captureScreenshot(tester, '12_r01_community_doorway_sheet');
    });

    testWidgets('Capture 13: Backlog tab Thư viện honest notice', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalDiscoverScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thư viện').first);
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '13_r01_backlog_library_tab');
    });

    testWidgets('Capture 14: R01 English locale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          locale: const Locale('en'),
          child: const JournalDiscoverScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '14_r01_english_locale');
    });

    testWidgets('Capture 15: Food preview portion sheet without DB write',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalSearchScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find "+" icon on chicken breast item and tap
      final addIcon = find.byIcon(Icons.add_rounded).first;
      await tester.tap(addIcon);
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '15_r02_food_preview_sheet');
    });

    testWidgets('Capture 16: Reading progress sample preview sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(
        buildCaptureHarness(
          datasource: datasource,
          child: const JournalDiscoverScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hiểu calories và các chất dinh dưỡng').first);
      await tester.pumpAndSettle();

      await captureScreenshot(tester, '16_r01_reading_progress_preview_sheet');
    });

    testWidgets('Capture 17-21: Multi-step Back Navigation Sequence', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            journalRepositoryProvider.overrideWithValue(
              JournalRepositoryImpl(datasource: datasource),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('vi'),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            onGenerateRoute: AppRoutes.onGenerateRoute,
            builder: (context, child) => RepaintBoundary(
              key: captureBoundaryKey,
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFF0C0D0E),
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Saman Home',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SamanPicksCarousel(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: On Home Carousel
      await captureScreenshot(tester, 'step1_home_carousel');

      // Step 2: Tap Journal card -> navigates to R01
      await tester.tap(find.text('SAMAN JOURNAL').first);
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'step2_r01_discover_entered');

      // Step 3: Tap search trigger bar -> navigates to R02
      await tester.tap(find.text('Tìm kiến thức, bài tập, món ăn…'));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'step3_r02_search_opened');

      // Step 4: Tap Back on R02 -> returns to R01
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'step4_r02_back_to_r01');

      // Step 5: Tap Back on R01 -> returns to Home
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'step5_r01_back_to_home');
    });
  });
}

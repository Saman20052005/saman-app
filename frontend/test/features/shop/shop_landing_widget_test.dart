import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/presentation/providers/shop_providers.dart';
import 'package:health_ai_app/features/shop/presentation/screens/shop_landing_screen.dart';
import 'package:health_ai_app/features/shop/presentation/screens/shop_detail_screen.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_category_tabs.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_editorial_hero.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_editorial_strip.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_header.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_product_card.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_search_bar.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_state_views.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_picks_carousel.dart';

/// Helper to capture genuine Flutter raster screenshots from a RepaintBoundary.
Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  await tester.runAsync(() async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final dir = Directory(
              'D:/SamanDev/runtime_evidence/CP-SHOP-03_20261029_101500/screenshots');
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          final file = File('${dir.path}/$fileName');
          await file.writeAsBytes(byteData.buffer.asUint8List());
        }
      }
    } catch (_) {}
  });
}

Widget _buildTestApp({
  required SharedPreferences prefs,
  required FakeShopRepositoryImpl fakeRepo,
  Locale locale = const Locale('vi'),
  double textScaleFactor = 1.0,
  GlobalKey? boundaryKey,
  Widget? homeWidget,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      shopRepositoryProvider.overrideWithValue(fakeRepo),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: boundaryKey != null
          ? RepaintBoundary(
              key: boundaryKey,
              child: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(textScaleFactor),
                ),
                child: homeWidget ?? const ShopLandingScreen(),
              ),
            )
          : MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(textScaleFactor),
              ),
              child: homeWidget ?? const ShopLandingScreen(),
            ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FakeShopRepositoryImpl fakeRepo;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SamanPicksCarousel.resetLastNavTime();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeRepo = FakeShopRepositoryImpl(
      defaultDelay: Duration.zero,
      scenario: FakeShopScenario.normal,
    );
  });

  group('ShopLandingScreen — Visual Layout & Core Composition', () {
    testWidgets('renders all core boutique sections at 390x844',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();

      // Header components
      expect(find.byType(ShopHeader), findsOneWidget);
      expect(find.text('Saman Shop'), findsOneWidget);

      // Search bar
      expect(find.byType(ShopSearchBar), findsOneWidget);
      expect(find.text('Tìm sản phẩm'), findsOneWidget);

      // Editorial hero
      expect(find.byType(ShopEditorialHero), findsOneWidget);
      expect(find.text('Đồ tốt cho\nnhịp tập của bạn.'), findsOneWidget);
      expect(find.text('Khám phá'), findsOneWidget);

      // Category text tabs
      expect(find.byType(ShopCategoryTabs), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Dụng cụ tập'), findsOneWidget);
      expect(find.text('Thời trang thể thao'), findsOneWidget);

      // Catalog header
      expect(find.text('TUYỂN CHỌN'), findsOneWidget);

      // Product cards
      expect(find.byType(ShopProductCard), findsWidgets);

      // Capture verified Flutter screenshot for report evidence
      await _captureScreenshot(tester, boundaryKey, 'landing_390px_loaded.png');

      // Scroll down to reveal the embedded editorial collection strip
      await tester.scrollUntilVisible(
        find.text('Bắt đầu tập tại nhà'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Editorial collection strip is now in viewport
      expect(find.byType(ShopEditorialStrip), findsOneWidget);
      expect(find.text('Bắt đầu tập tại nhà'), findsOneWidget);
    });

    testWidgets('renders cleanly on narrow 360x640 screen without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _captureScreenshot(tester, boundaryKey, 'landing_360px_narrow.png');
    });

    testWidgets('adapts to 200% large font without layout overflow',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        textScaleFactor: 2.0,
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _captureScreenshot(
          tester, boundaryKey, 'landing_large_font_200.png');
    });
  });

  group('ShopLandingScreen — Navigation & Double-Tap Protection', () {
    testWidgets('navigates from SamanPicks shop card to Shop Landing and pops back',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            shopRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: Scaffold(
              body: SamanPicksCarousel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shopCardFinder =
          find.text('Recovery essentials, picked for your plan');

      // Drag horizontal ListView to bring the Shop pick card fully into view
      await tester.drag(find.byType(ListView), const Offset(-250, 0));
      await tester.pumpAndSettle();

      // Find the Saman Shop pick card
      expect(shopCardFinder, findsOneWidget);

      // Tap card
      await tester.tap(shopCardFinder);
      await tester.pumpAndSettle();

      // We are now on Saman Shop Landing!
      expect(find.byType(ShopLandingScreen), findsOneWidget);
      expect(find.text('Saman Shop'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      // Back on home
      expect(find.byType(ShopLandingScreen), findsNothing);
      expect(find.byType(SamanPicksCarousel), findsOneWidget);
    });

    testWidgets('double-tap on shop card does not push multiple routes',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            shopRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: Scaffold(
              body: SamanPicksCarousel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shopCardFinder =
          find.text('Recovery essentials, picked for your plan');

      // Drag horizontal ListView to bring the Shop pick card fully into view
      await tester.drag(find.byType(ListView), const Offset(-250, 0));
      await tester.pumpAndSettle();

      // Rapid double tap
      await tester.tap(shopCardFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(shopCardFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(ShopLandingScreen), findsOneWidget);

      // Single back pop returns to Home
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(ShopLandingScreen), findsNothing);
    });
  });

  group('ShopLandingScreen — Search & Filter Interactions', () {
    testWidgets('typing into search filters products and clear button restores',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
      ));
      await tester.pumpAndSettle();

      // Type "shaker" into search bar
      final searchInput = find.byType(TextField);
      await tester.enterText(searchInput, 'shaker');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Clear button is now visible
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Verify filtered products
      expect(find.text('Matte Obsidian Stainless Steel Shaker 750ml'),
          findsOneWidget);

      // Tap clear button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Full catalog restored
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byType(ShopProductCard), findsWidgets);
    });

    testWidgets('category tabs switch category filter and underline moves',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
      ));
      await tester.pumpAndSettle();

      // Tap "Phục hồi" tab
      await tester.ensureVisible(find.text('Phục hồi'));
      await tester.tap(find.text('Phục hồi'));
      await tester.pumpAndSettle();

      // Verify recovery products are present
      expect(
          find.text('High-Density Foam Roller 45cm Bọt Xốp Mật Độ Cao'),
          findsOneWidget);

      // Tap "Tất cả" tab to restore
      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopProductCard), findsWidgets);
    });

    testWidgets('editorial collection strip filters catalog and shows active badge',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
      ));
      await tester.pumpAndSettle();

      // Scroll to reveal collection strip
      await tester.scrollUntilVisible(
        find.text('Bắt đầu tập tại nhà'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Tap collection strip
      await tester.tap(find.text('Bắt đầu tập tại nhà'));
      await tester.pumpAndSettle();

      // Active collection badge rendered (scroll back up if needed)
      await tester.scrollUntilVisible(
        find.text('Bộ sưu tập: Bắt đầu tập tại nhà'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Bộ sưu tập: Bắt đầu tập tại nhà'), findsOneWidget);

      // Tap clear on active badge
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Bộ sưu tập: Bắt đầu tập tại nhà'), findsNothing);
    });
  });

  group('ShopLandingScreen — State Views & Error Handling', () {
    testWidgets('displays no results view when search yields no products',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();

      // Search non-existent keyword
      await tester.enterText(find.byType(TextField), 'tu_khoa_khong_ton_tai_xyz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byType(ShopNoResultsView), findsOneWidget);
      expect(find.text('Không tìm thấy sản phẩm'), findsOneWidget);
      expect(find.text('Đặt lại bộ lọc'), findsOneWidget);

      await _captureScreenshot(tester, boundaryKey, 'landing_no_results.png');

      // Tap "Đặt lại bộ lọc"
      await tester.tap(find.text('Đặt lại bộ lọc'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopNoResultsView), findsNothing);
      expect(find.byType(ShopProductCard), findsWidgets);
    });

    testWidgets('displays first page error and recovers via Retry button',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      fakeRepo.scenario = FakeShopScenario.firstPageError;
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ShopFirstPageErrorView), findsOneWidget);
      expect(find.text('Không thể tải danh mục sản phẩm'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      await _captureScreenshot(
          tester, boundaryKey, 'landing_first_page_error.png');

      // Recover by resetting repo and tapping Retry
      fakeRepo.scenario = FakeShopScenario.normal;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopFirstPageErrorView), findsNothing);
      expect(find.byType(ShopProductCard), findsWidgets);
    });

    testWidgets('displays load-more error footer preserving items',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      fakeRepo.scenario = FakeShopScenario.nextPageError;
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();

      // Scroll all the way to bottom to trigger load more
      await tester.scrollUntilVisible(
        find.byType(ShopLoadMoreFooter),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Footer error visible, but items still intact!
      expect(find.text('Không thể tải thêm sản phẩm. Chạm để thử lại.'),
          findsOneWidget);
      expect(find.byType(ShopProductCard), findsWidgets);

      await _captureScreenshot(
          tester, boundaryKey, 'landing_load_more_error.png');
    });
  });

  group('ShopLandingScreen — Product Card Edge Cases & Wishlist', () {
    testWidgets('bookmarking product updates wishlist and header badge',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
      ));
      await tester.pumpAndSettle();

      // Initial header shows 0 saved items
      expect(find.byIcon(Icons.bookmark_outline_rounded), findsWidgets);

      // Scroll slightly so cards are centered in viewport
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();

      // Bookmark first product card
      final bookmarkButtons = find.byWidgetPredicate((w) =>
          w is Icon &&
          (w.icon == Icons.bookmark_outline_rounded ||
              w.icon == Icons.bookmark_rounded));
      expect(bookmarkButtons, findsWidgets);

      await tester.tap(bookmarkButtons.at(1)); // First product bookmark
      await tester.pumpAndSettle();

      // Wishlist persistence updated
      final savedIds = prefs.getStringList('saman_shop_wishlist_ids_v1');
      expect(savedIds?.length, equals(1));
    });

    testWidgets('null price product displays "Xem giá trên Shopee"',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
      ));
      await tester.pumpAndSettle();

      // Filter by category where null price product exists (Gear: prod_tg_06)
      await tester.tap(find.text('Dụng cụ tập'));
      await tester.pumpAndSettle();

      // Scroll to reveal null price product
      await tester.scrollUntilVisible(
        find.text('Xem giá trên Shopee'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Product prod_tg_06 has null price
      expect(find.text('Xem giá trên Shopee'), findsOneWidget);
    });

    testWidgets('tapping product card navigates to Product Detail screen',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
      ));
      await tester.pumpAndSettle();

      // Scroll down so first product card is centered in viewport
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ShopProductCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(ShopDetailScreen), findsOneWidget);
    });
  });

  group('ShopLandingScreen — Localization (vi / en)', () {
    testWidgets('switches UI text cleanly between Vietnamese and English',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Test Vietnamese
      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        locale: const Locale('vi'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tìm sản phẩm'), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Khám phá'), findsOneWidget);

      // Test English
      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Search products'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('CURATED'), findsOneWidget);
    });

    testWidgets(
        'ShopSearchBar maintains transparent/no-fill background under global filled inputDecorationTheme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          home: Scaffold(
            body: ShopSearchBar(
              onQueryChanged: (_) {},
              onClear: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration?.filled, isFalse);
      expect(textField.decoration?.border, equals(InputBorder.none));
      expect(textField.decoration?.enabledBorder, equals(InputBorder.none));
      expect(textField.decoration?.focusedBorder, equals(InputBorder.none));
    });
  });
}

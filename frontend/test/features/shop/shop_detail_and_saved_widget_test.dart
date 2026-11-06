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
import 'package:health_ai_app/features/shop/presentation/screens/shop_detail_screen.dart';
import 'package:health_ai_app/features/shop/presentation/screens/shop_landing_screen.dart';
import 'package:health_ai_app/features/shop/presentation/screens/shop_saved_screen.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_demo_explanation_sheet.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_header.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_product_card.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_picks_carousel.dart';

const String _evidenceDir =
    'D:/SamanDev/runtime_evidence/CP-SHOP-05_20261029_131000/screenshots';

/// Helper capturing genuine Flutter raster images from a RepaintBoundary.
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
          final dir = Directory(_evidenceDir);
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
  required Widget child,
  Locale locale = const Locale('vi'),
  double textScaleFactor = 1.0,
  GlobalKey? boundaryKey,
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
                child: child,
              ),
            )
          : MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(textScaleFactor),
              ),
              child: child,
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
    fakeRepo = FakeShopRepositoryImpl(defaultDelay: Duration.zero);
  });

  group('ShopDetailScreen — Layout & Scenarios', () {
    testWidgets(
        'renders complete loaded boutique detail view with hero, specs, and sticky CTA at 390x844',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      // Top navigation bar
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);

      // Hero image & Title
      expect(find.text('Matte Obsidian Stainless Steel Shaker 750ml'),
          findsOneWidget);
      expect(find.textContaining('Cung cấp bởi Saman'), findsOneWidget);

      // Price & updated date
      expect(find.textContaining('~350.000'), findsOneWidget);
      expect(find.textContaining('Giá tham khảo cập nhật:'), findsOneWidget);

      // Why Saman Picked section
      expect(find.text('Vì sao Saman chọn'), findsOneWidget);

      // Sticky CTA
      expect(find.text('Xem trên Shopee (Minh họa)'), findsOneWidget);

      // Capture verified Flutter raster screenshot
      await _captureScreenshot(tester, boundaryKey, 'detail_loaded.png');
    });

    testWidgets(
        'renders null price product cleanly as "Xem giá trên Shopee" and handles broken image gracefully',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      // prod_tg_06 is the null price fixture
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
        child: const ShopDetailScreen(productId: 'prod_tg_06'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Xem giá trên Shopee'), findsOneWidget);
      expect(find.textContaining('0 đ'), findsNothing);

      await _captureScreenshot(
          tester, boundaryKey, 'detail_null_price_broken_img.png');
    });

    testWidgets(
        'tapping sticky CTA on demo product displays ShopDemoExplanationSheet with provenance information',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      // Tap sticky CTA
      await tester.tap(find.text('Xem trên Shopee (Minh họa)'));
      await tester.pumpAndSettle();

      // Explanation modal bottom sheet is displayed cleanly without technical provenance
      expect(find.byType(ShopDemoExplanationSheet), findsOneWidget);
      expect(find.text('Sản phẩm minh họa'), findsOneWidget);
      expect(find.text('Sản phẩm minh họa, chưa có liên kết mua thực tế.'),
          findsOneWidget);
      expect(find.text('Căn cứ quyền & Nguồn gốc'), findsNothing);
      expect(find.text('Đã hiểu'), findsOneWidget);

      await _captureScreenshot(
          tester, boundaryKey, 'detail_demo_bottom_sheet.png');

      // Tap "Đã hiểu" to close sheet
      await tester.tap(find.text('Đã hiểu'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopDemoExplanationSheet), findsNothing);
    });

    testWidgets(
        'CP-SHOP-08: demo product suppresses affiliate disclosure to prevent misrepresentation',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      // Demo item must NOT display affiliate disclosure
      expect(
        find.text(
            'Saman có thể nhận hoa hồng từ các giao dịch đủ điều kiện qua liên kết này.'),
        findsNothing,
      );
      expect(find.text('Tiếp tục mua hàng trên Shopee.'), findsNothing);
    });

    testWidgets(
        'invalid or unlisted productId displays notFound state with back button without crashing',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        child: const ShopDetailScreen(productId: 'invalid_id_999'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm không tồn tại'), findsOneWidget);
      expect(find.text('Quay lại danh mục'), findsOneWidget);
    });

    testWidgets(
        'tapping bookmark button in top bar toggles wishlist and updates storage',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      // Initially unsaved
      expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);

      // Tap bookmark button
      await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
      await tester.pumpAndSettle();

      // Now saved!
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

      // Verify persistence
      final savedIds = prefs.getStringList('saman_shop_wishlist_ids_v1');
      expect(savedIds, contains('prod_mp_01'));
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
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _captureScreenshot(tester, boundaryKey, 'detail_360px_narrow.png');
    });

    testWidgets('adapts to 200% font scaling without overflow',
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
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _captureScreenshot(
          tester, boundaryKey, 'detail_large_font_200.png');
    });
  });

  group('ShopSavedScreen — Layout & Synchronization', () {
    testWidgets(
        'renders saved items list with thumbnail, title, price, and count badge',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Pre-save 2 items
      await prefs.setStringList(
        'saman_shop_wishlist_ids_v1',
        ['prod_mp_01', 'prod_rc_01'],
      );

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
        child: const ShopSavedScreen(),
      ));
      await tester.pumpAndSettle();

      // Header shows title and count 2
      expect(find.text('Mục đã lưu'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Products rendered
      expect(find.text('Matte Obsidian Stainless Steel Shaker 750ml'),
          findsOneWidget);
      expect(find.text('High-Density Foam Roller 45cm Bọt Xốp Mật Độ Cao'),
          findsOneWidget);

      await _captureScreenshot(tester, boundaryKey, 'saved_with_items.png');
    });

    testWidgets(
        'renders empty state when no products are saved with explore button',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
        child: const ShopSavedScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chưa có sản phẩm nào được lưu'), findsOneWidget);
      expect(find.text('Khám phá danh mục'), findsOneWidget);

      await _captureScreenshot(tester, boundaryKey, 'saved_empty.png');
    });

    testWidgets(
        'renders missing unlisted item placeholder gracefully and permits unsaving',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Pre-save one real item and one deleted item
      await prefs.setStringList(
        'saman_shop_wishlist_ids_v1',
        ['prod_mp_01', 'deleted_item_xyz'],
      );

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        boundaryKey: boundaryKey,
        child: const ShopSavedScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm không còn trong danh mục'), findsOneWidget);
      expect(find.text('Mã ID: deleted_item_xyz'), findsOneWidget);

      await _captureScreenshot(
          tester, boundaryKey, 'saved_missing_product.png');

      // Unsaving the missing item works cleanly
      final unsaveButtons = find.byIcon(Icons.bookmark_remove_outlined);
      expect(unsaveButtons, findsNWidgets(2));

      await tester.tap(unsaveButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Sản phẩm không còn trong danh mục'), findsNothing);
      expect(prefs.getStringList('saman_shop_wishlist_ids_v1'),
          ['prod_mp_01']);
    });

    testWidgets('unsaving item from Saved screen updates header badge',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await prefs.setStringList(
        'saman_shop_wishlist_ids_v1',
        ['prod_mp_01'],
      );

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        child: const ShopSavedScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);

      // Tap unsave
      await tester.tap(find.byIcon(Icons.bookmark_remove_outlined));
      await tester.pumpAndSettle();

      // Switches to empty state
      expect(find.text('Chưa có sản phẩm nào được lưu'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('Full Navigation Flow & Lifecycle Integration', () {
    testWidgets(
        'complete flow: Landing -> Tap Card -> Detail -> Bookmark -> Pop -> Open Saved -> Detail -> Pop back',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        child: const ShopLandingScreen(),
      ));
      await tester.pumpAndSettle();

      // On Landing: Saved count is 0
      expect(find.byType(ShopLandingScreen), findsOneWidget);
      expect(find.text('Saman Shop'), findsOneWidget);

      // Scroll slightly and tap first product card
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();

      final firstProductCard = find.byType(ShopProductCard).first;
      await tester.tap(firstProductCard);
      await tester.pumpAndSettle();

      // Now on Detail Screen!
      expect(find.byType(ShopDetailScreen), findsOneWidget);

      // Bookmark this product from Detail
      await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

      // Pop back to Landing
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      // Back on Landing! Scroll position preserved, saved count is now 1
      expect(find.byType(ShopLandingScreen), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Scroll up to top
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();

      // Tap Bookmark icon in ShopHeader to navigate to Saved Screen
      final headerBookmarkButton = find.descendant(
        of: find.byType(ShopHeader),
        matching: find.byType(IconButton),
      ).last;
      await tester.tap(headerBookmarkButton);
      await tester.pumpAndSettle();

      // Now on Saved Screen!
      expect(find.byType(ShopSavedScreen), findsOneWidget);
      expect(find.text('Mục đã lưu'), findsOneWidget);

      // Tap item in Saved to open Detail again
      await tester.tap(find.text('Lifting Straps Cotton Heavy-Duty'));
      await tester.pumpAndSettle();

      // We are back in Detail!
      expect(find.byType(ShopDetailScreen), findsOneWidget);

      // Pop back to Saved
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ShopSavedScreen), findsOneWidget);

      // Pop back to Landing
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ShopLandingScreen), findsOneWidget);
    });
  });

  group('Shop Localization (vi / en)', () {
    testWidgets('Detail and Saved screens update all labels cleanly on locale switch',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Vietnamese Detail
      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        locale: const Locale('vi'),
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Vì sao Saman chọn'), findsOneWidget);
      expect(find.text('Xem trên Shopee (Minh họa)'), findsOneWidget);

      // English Detail
      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        fakeRepo: fakeRepo,
        locale: const Locale('en'),
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Why Saman picked this'), findsOneWidget);
      expect(find.text('View on Shopee (Demo)'), findsOneWidget);
    });
  });
}

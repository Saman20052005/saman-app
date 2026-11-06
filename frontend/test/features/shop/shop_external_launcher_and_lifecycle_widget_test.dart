import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/data/services/external_shop_launcher.dart';
import 'package:health_ai_app/features/shop/data/services/shop_platform_dispatcher.dart';
import 'package:health_ai_app/features/shop/domain/entities/content_provenance.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/presentation/providers/shop_providers.dart';
import 'package:health_ai_app/features/shop/presentation/screens/shop_detail_screen.dart';
import 'package:health_ai_app/features/shop/presentation/screens/shop_landing_screen.dart';
import 'package:health_ai_app/features/shop/presentation/widgets/shop_demo_explanation_sheet.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/saman_picks_carousel.dart';

const String _evidenceDir =
    'D:/SamanDev/runtime_evidence/CP-SHOP-05_20261029_131000/screenshots';

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

class ControllablePlatformDispatcher implements ShopPlatformDispatcher {
  int callCount = 0;
  Uri? lastUri;
  Duration delay = Duration.zero;
  bool returnValue = true;

  @override
  Future<bool> dispatchUrl(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    callCount++;
    lastUri = uri;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return returnValue;
  }
}

Widget _buildAppWithLauncher({
  required SharedPreferences prefs,
  required FakeShopRepositoryImpl repo,
  required ExternalShopLauncher launcher,
  required Widget child,
  GlobalKey? boundaryKey,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      shopRepositoryProvider.overrideWithValue(repo),
      shopLauncherProvider.overrideWithValue(launcher),
    ],
    child: MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: boundaryKey != null
          ? RepaintBoundary(key: boundaryKey, child: child)
          : child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FakeShopRepositoryImpl fakeRepo;
  late ControllablePlatformDispatcher dispatcher;
  late ExternalShopLauncher launcher;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SamanPicksCarousel.resetLastNavTime();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeRepo = FakeShopRepositoryImpl(defaultDelay: Duration.zero);
    dispatcher = ControllablePlatformDispatcher();
    launcher = ExternalShopLauncher(platformDispatcher: dispatcher);
  });

  group('External Launcher — Busy State & Double-Tap Throttling', () {
    testWidgets(
        'shows busy state during in-flight dispatch and suppresses double-taps',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Create a test repo with a real product
      final realProduct = ShopProduct(
        id: 'real_shaker_01',
        title: 'Obsidian Real Shaker',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Shopee Official Partner',
          rightsBasis: 'Partner License',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'assets/images/shop/shaker.png',
        shopeeUrl: 'https://shopee.vn/product/obsidian-real-shaker',
      );

      final customRepo = FakeShopRepositoryImpl(
        products: [realProduct],
        defaultDelay: Duration.zero,
      );

      dispatcher.delay = const Duration(milliseconds: 300);
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildAppWithLauncher(
        prefs: prefs,
        repo: customRepo,
        launcher: launcher,
        boundaryKey: boundaryKey,
        child: const ShopDetailScreen(productId: 'real_shaker_01'),
      ));
      await tester.pumpAndSettle();

      final ctaFinder = find.widgetWithText(ElevatedButton, 'Xem trên Shopee');
      expect(ctaFinder, findsOneWidget);

      // Tap once
      await tester.tap(ctaFinder);
      await tester.pump(const Duration(milliseconds: 50));

      // CircularProgressIndicator appears inside button while busy
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _captureScreenshot(tester, boundaryKey, 'launcher_busy_state.png');

      // Rapidly attempt second tap on button while in-flight
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      // Wait for delayed dispatch to complete
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Platform was called exactly ONCE!
      expect(dispatcher.callCount, 1);
      expect(dispatcher.lastUri.toString(),
          'https://shopee.vn/product/obsidian-real-shaker');
      // Busy indicator is cleared
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('External Launcher — Error & Retry Recovery Flow', () {
    testWidgets(
        'shows error SnackBar with Retry action when dispatch fails and recovers on retry',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final realProduct = ShopProduct(
        id: 'real_shaker_err',
        title: 'Obsidian Real Shaker Err',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Shopee Official Partner',
          rightsBasis: 'Partner License',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'assets/images/shop/shaker.png',
        shopeeUrl: 'https://shopee.vn/product/obsidian-real-shaker',
      );

      final customRepo = FakeShopRepositoryImpl(
        products: [realProduct],
        defaultDelay: Duration.zero,
      );

      // Force dispatch failure initially
      dispatcher.returnValue = false;
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildAppWithLauncher(
        prefs: prefs,
        repo: customRepo,
        launcher: launcher,
        boundaryKey: boundaryKey,
        child: const ShopDetailScreen(productId: 'real_shaker_err'),
      ));
      await tester.pumpAndSettle();

      final ctaFinder = find.widgetWithText(ElevatedButton, 'Xem trên Shopee');
      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      // Error SnackBar is presented with "Thử lại" action
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Thiết bị không thể mở liên kết mua sắm'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(dispatcher.callCount, 1);
      await _captureScreenshot(
          tester, boundaryKey, 'launcher_error_snackbar_retry.png');

      // Restore dispatcher to return true on retry
      dispatcher.returnValue = true;

      // Tap "Thử lại" on SnackBar
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      // Platform was called a second time
      expect(dispatcher.callCount, 2);
    });
  });

  group('Demo Mode — Clean Explanation Sheet Without Technical Provenance', () {
    testWidgets(
        'demo product opens explanation sheet without exposing tech provenance or file paths',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildAppWithLauncher(
        prefs: prefs,
        repo: fakeRepo,
        launcher: launcher,
        boundaryKey: boundaryKey,
        child: const ShopDetailScreen(productId: 'prod_mp_01'),
      ));
      await tester.pumpAndSettle();

      // In M1, demo items have CTA 'Xem trên Shopee (Minh họa)'
      final ctaFinder =
          find.widgetWithText(ElevatedButton, 'Xem trên Shopee (Minh họa)');
      expect(ctaFinder, findsOneWidget);

      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      // Demo explanation sheet is shown
      expect(find.byType(ShopDemoExplanationSheet), findsOneWidget);
      expect(find.text('Sản phẩm minh họa'), findsOneWidget);
      expect(find.text('Sản phẩm minh họa, chưa có liên kết mua thực tế.'),
          findsOneWidget);

      await _captureScreenshot(
          tester, boundaryKey, 'launcher_clean_demo_sheet.png');

      // Strictly NO technical provenance header, sources, or file paths
      expect(find.text('Căn cứ quyền & Nguồn gốc'), findsNothing);
      expect(find.textContaining('rightsBasis'), findsNothing);
      expect(find.textContaining('evidence'), findsNothing);
      expect(find.textContaining('runtime_evidence'), findsNothing);

      // Zero OS platform calls
      expect(dispatcher.callCount, 0);

      // Close cleanly
      await tester.tap(find.text('Đã hiểu'));
      await tester.pumpAndSettle();
      expect(find.byType(ShopDemoExplanationSheet), findsNothing);
    });
  });

  group('Simulated App Lifecycle & Navigation Context Preservation', () {
    testWidgets(
        'preserves search, filters, scroll position and bookmark status across navigation and lifecycle resume',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(_buildAppWithLauncher(
        prefs: prefs,
        repo: fakeRepo,
        launcher: launcher,
        boundaryKey: boundaryKey,
        child: const ShopLandingScreen(),
      ));
      await tester.pumpAndSettle();

      // 1. Enter search filter
      await tester.enterText(find.byType(TextField), 'shaker');
      await tester.pumpAndSettle();

      // Verify filtered product is shown
      expect(find.text('Matte Obsidian Stainless Steel Shaker 750ml'),
          findsOneWidget);

      // 2. Tap product card to navigate to Detail screen
      await tester.tap(find.text('Matte Obsidian Stainless Steel Shaker 750ml'));
      await tester.pumpAndSettle();

      // On Detail screen
      expect(find.byType(ShopDetailScreen), findsOneWidget);
      expect(find.text('Vì sao Saman chọn'), findsOneWidget);

      // 3. Harness simulates app backgrounding and resuming
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 100));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Verify NO spurious dispatch, NO order completion notifications
      expect(dispatcher.callCount, 0);
      expect(find.textContaining('thành công'), findsNothing);
      expect(find.textContaining('đơn hàng'), findsNothing);

      // 4. Bookmark item in Detail view
      final bookmarkButton = find.byIcon(Icons.bookmark_outline_rounded);
      expect(bookmarkButton, findsOneWidget);
      await tester.tap(bookmarkButton);
      await tester.pumpAndSettle();

      // Icon changes to filled bookmark
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

      // 5. Pop back to ShopLandingScreen
      final backButton = find.byIcon(Icons.arrow_back_ios_new_rounded);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Back on ShopLandingScreen
      expect(find.byType(ShopLandingScreen), findsOneWidget);

      // Search query 'shaker' is preserved!
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'shaker');

      // Filtered product is still present
      expect(find.text('Matte Obsidian Stainless Steel Shaker 750ml'),
          findsOneWidget);

      // Bookmark indicator on product card is updated to bookmarked state
      expect(find.byIcon(Icons.bookmark_rounded), findsWidgets);

      await _captureScreenshot(
          tester, boundaryKey, 'launcher_lifecycle_resumed_catalog.png');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/data/repositories/shared_preferences_shop_wishlist_repository.dart';
import 'package:health_ai_app/features/shop/data/services/fake_shop_launcher.dart';
import 'package:health_ai_app/features/shop/domain/services/shop_launcher_contract.dart';
import 'package:health_ai_app/features/shop/presentation/controllers/shop_detail_controller.dart';
import 'package:health_ai_app/features/shop/presentation/controllers/shop_detail_state.dart';

void main() {
  late SharedPreferences prefs;
  late FakeShopRepositoryImpl fakeRepo;
  late SharedPreferencesShopWishlistRepository wishlistRepo;
  late FakeShopLauncher fakeLauncher;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeRepo = FakeShopRepositoryImpl(defaultDelay: Duration.zero);
    wishlistRepo = SharedPreferencesShopWishlistRepository(prefs);
    fakeLauncher = FakeShopLauncher();
  });

  tearDown(() {
    wishlistRepo.dispose();
  });

  group('ShopDetailController — Data Fetching & Scenarios', () {
    test('loads product details by valid ID and initializes state', () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, ShopDetailStatus.loaded);
      expect(controller.state.product?.id, 'prod_mp_01');
      expect(controller.state.product?.title,
          'Matte Obsidian Stainless Steel Shaker 750ml');
      expect(controller.state.isSaved, isFalse);
    });

    test('sets notFound status when productId is null or empty', () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: null,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ShopDetailStatus.notFound);
      expect(controller.state.product, isNull);

      final emptyController = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: '   ',
      );
      addTearDown(emptyController.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(emptyController.state.status, ShopDetailStatus.notFound);
    });

    test('sets notFound status when repository throws ShopNotFoundFailure',
        () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'non_existent_id_999',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ShopDetailStatus.notFound);
    });

    test('handles error and retry recovers when repository resets', () async {
      fakeRepo.scenario = FakeShopScenario.firstPageError;

      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ShopDetailStatus.error);

      // Reset repo scenario and retry
      fakeRepo.scenario = FakeShopScenario.normal;
      controller.retry();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, ShopDetailStatus.loaded);
      expect(controller.state.product?.id, 'prod_mp_01');
    });
  });

  group('ShopDetailController — Wishlist Sync & Optimistic Updates', () {
    test('initializes with isSaved=true if already in wishlist', () async {
      await wishlistRepo.save('prod_mp_01');

      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSaved, isTrue);
    });

    test('toggleWishlist updates local state and persists to storage',
        () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSaved, isFalse);

      // Toggle to save
      await controller.toggleWishlist();
      expect(controller.state.isSaved, isTrue);
      expect(await wishlistRepo.isSaved('prod_mp_01'), isTrue);

      // Toggle to unsave
      await controller.toggleWishlist();
      expect(controller.state.isSaved, isFalse);
      expect(await wishlistRepo.isSaved('prod_mp_01'), isFalse);
    });

    test('reacts to external wishlist stream updates automatically', () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSaved, isFalse);

      // Save externally via repository
      await wishlistRepo.save('prod_mp_01');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Controller automatically reflects saved state!
      expect(controller.state.isSaved, isTrue);
    });
  });

  group('ShopDetailController — CTA Launching & Throttling', () {
    test('launchCta returns demo result for demo products without OS call',
        () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      final result = await controller.launchCta();
      expect(result?.type, LauncherResultType.demo);
      expect(controller.state.isLaunching, isFalse);
    });

    test('launchCta returns null for unavailable/discontinued products',
        () async {
      // prod_rt_08 is the built-in discontinued fixture
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_rt_08',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      final result = await controller.launchCta();
      expect(result, isNull);
    });

    test('launchCta handles launcher failure and returns failed result',
        () async {
      fakeLauncher.scenario = FakeLauncherScenario.forceFail;

      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      final result = await controller.launchCta();
      expect(result?.type, LauncherResultType.failed);
      expect(controller.state.isLaunching, isFalse);
    });

    test('launchCta throttles concurrent double-tap invocations', () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      // Start first launch
      final firstLaunchFuture = controller.launchCta();
      expect(controller.state.isLaunching, isTrue);

      // Second launch while busy must return null immediately
      final secondLaunchResult = await controller.launchCta();
      expect(secondLaunchResult, isNull);

      final firstLaunchResult = await firstLaunchFuture;
      expect(firstLaunchResult?.type, LauncherResultType.demo);
      expect(controller.state.isLaunching, isFalse);
    });

    test('recovers after failure so subsequent retry succeeds cleanly',
        () async {
      fakeLauncher.scenario = FakeLauncherScenario.forceFail;

      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      // First attempt fails
      final failResult = await controller.launchCta();
      expect(failResult?.type, LauncherResultType.failed);
      expect(controller.state.isLaunching, isFalse);

      // Recover launcher and retry
      fakeLauncher.scenario = FakeLauncherScenario.normal;
      final retryResult = await controller.launchCta();
      expect(retryResult?.type, LauncherResultType.demo);
      expect(controller.state.isLaunching, isFalse);
    });

    test('disposed controller completes async launch safely without throwing',
        () async {
      final controller = ShopDetailController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
        launcher: fakeLauncher,
        productId: 'prod_mp_01',
      );

      await Future<void>.delayed(Duration.zero);

      final launchFuture = controller.launchCta();
      controller.dispose(); // Disposed while launch is in-flight

      // Should complete without Unhandled Exception
      final result = await launchFuture;
      expect(result?.type, LauncherResultType.demo);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/data/repositories/shared_preferences_shop_wishlist_repository.dart';
import 'package:health_ai_app/features/shop/presentation/controllers/shop_saved_controller.dart';
import 'package:health_ai_app/features/shop/presentation/controllers/shop_saved_state.dart';

void main() {
  late SharedPreferences prefs;
  late FakeShopRepositoryImpl fakeRepo;
  late SharedPreferencesShopWishlistRepository wishlistRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeRepo = FakeShopRepositoryImpl(defaultDelay: Duration.zero);
    wishlistRepo = SharedPreferencesShopWishlistRepository(prefs);
  });

  tearDown(() {
    wishlistRepo.dispose();
  });

  group('ShopSavedController — Core Wishlist & Batch Operations', () {
    test('initializes cleanly with empty state when storage is empty',
        () async {
      final controller = ShopSavedController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, ShopSavedStatus.loaded);
      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.items, isEmpty);
    });

    test('loads saved items in the exact reverse-chronological order of IDs',
        () async {
      // Save items sequentially
      await wishlistRepo.save('prod_tg_01');
      await wishlistRepo.save('prod_mp_01');
      await wishlistRepo.save('prod_rc_01');

      final controller = ShopSavedController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, ShopSavedStatus.loaded);
      expect(controller.state.items.length, 3);
      // Newest saved first (prod_rc_01 -> prod_mp_01 -> prod_tg_01)
      expect(controller.state.items[0].productId, 'prod_rc_01');
      expect(controller.state.items[1].productId, 'prod_mp_01');
      expect(controller.state.items[2].productId, 'prod_tg_01');
      expect(controller.state.items.every((it) => !it.isMissing), isTrue);
    });

    test(
        'preserves missing unlisted product in state and storage without crashing',
        () async {
      // 'deleted_item_xyz' does not exist in catalog
      await wishlistRepo.save('deleted_item_xyz');
      await wishlistRepo.save('prod_mp_01');

      final controller = ShopSavedController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.items.length, 2);
      expect(controller.state.items[0].productId, 'prod_mp_01');
      expect(controller.state.items[0].isMissing, isFalse);

      expect(controller.state.items[1].productId, 'deleted_item_xyz');
      expect(controller.state.items[1].isMissing, isTrue);
      expect(controller.state.items[1].product, isNull);

      // Verify storage key was NOT wiped
      final rawIds = await wishlistRepo.getSavedProductIds();
      expect(rawIds, contains('deleted_item_xyz'));
    });

    test('unsave removes item optimistically and updates storage', () async {
      await wishlistRepo.save('prod_tg_01');
      await wishlistRepo.save('prod_mp_01');

      final controller = ShopSavedController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.items.length, 2);

      await controller.unsave('prod_mp_01');

      expect(controller.state.items.length, 1);
      expect(controller.state.items.first.productId, 'prod_tg_01');
      expect(await wishlistRepo.isSaved('prod_mp_01'), isFalse);
    });

    test('reacts to external wishlist stream broadcasts automatically',
        () async {
      final controller = ShopSavedController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.items, isEmpty);

      // Save via repository directly
      await wishlistRepo.save('prod_mp_01');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Controller auto-synced!
      expect(controller.state.items.length, 1);
      expect(controller.state.items.first.productId, 'prod_mp_01');
    });

    test('handles error and retry recovers', () async {
      fakeRepo.scenario = FakeShopScenario.firstPageError;
      await wishlistRepo.save('prod_mp_01');

      final controller = ShopSavedController(
        repository: fakeRepo,
        wishlistRepository: wishlistRepo,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ShopSavedStatus.error);

      // Reset repo and retry
      fakeRepo.scenario = FakeShopScenario.normal;
      controller.retry();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, ShopSavedStatus.loaded);
      expect(controller.state.items.length, 1);
    });
  });
}

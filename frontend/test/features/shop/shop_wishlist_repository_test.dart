import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/features/shop/data/repositories/shared_preferences_shop_wishlist_repository.dart';
import 'package:health_ai_app/features/shop/domain/failures/shop_failure.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SharedPreferencesShopWishlistRepository — Core Operations', () {
    test('reading uninitialized key returns empty list without error',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      final saved = await repository.getSavedProductIds();
      expect(saved, isEmpty);
    });

    test(
        'saves products with newest at the head (index 0) and maintains uniqueness',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      await repository.save('p1');
      await repository.save('p2');
      await repository.save('p3');

      expect(await repository.getSavedProductIds(), ['p3', 'p2', 'p1']);

      // Saving an already saved ID moves it back to head without duplicating
      await repository.save('p2');
      expect(await repository.getSavedProductIds(), ['p2', 'p3', 'p1']);
    });

    test('removes product and is idempotent when removing non-existent ID',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      await repository.save('p1');
      await repository.save('p2');

      await repository.remove('p1');
      expect(await repository.getSavedProductIds(), ['p2']);

      // Idempotent: removing non-existent ID completes cleanly
      await repository.remove('non_existent');
      expect(await repository.getSavedProductIds(), ['p2']);
    });

    test('toggle switches between saved and unsaved state', () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      final state1 = await repository.toggle('p1');
      expect(state1, isTrue);
      expect(await repository.isSaved('p1'), isTrue);

      final state2 = await repository.toggle('p1');
      expect(state2, isFalse);
      expect(await repository.isSaved('p1'), isFalse);
    });

    test('persists data across distinct repository instances', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo1 = SharedPreferencesShopWishlistRepository(prefs);
      await repo1.save('p_persisted_1');
      await repo1.save('p_persisted_2');

      // Create new instance pointing to same storage
      final repo2 = SharedPreferencesShopWishlistRepository(prefs);
      final savedFromRepo2 = await repo2.getSavedProductIds();

      expect(savedFromRepo2, ['p_persisted_2', 'p_persisted_1']);
    });
  });

  group('SharedPreferencesShopWishlistRepository — Serialization & Concurrency',
      () {
    test('serializes rapid concurrent writes without lost updates', () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      // Fire 10 writes concurrently without awaiting each sequentially
      final futures = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        futures.add(repository.save('concurrent_item_$i'));
      }

      await Future.wait(futures);

      final saved = await repository.getSavedProductIds();
      expect(saved.length, 10);
      // Item 9 fired last, should be at head
      expect(saved.first, 'concurrent_item_9');
    });
  });

  group('SharedPreferencesShopWishlistRepository — Error Handling & Recovery',
      () {
    test(
        'corrupted data in storage throws ShopStorageFailure and does NOT overwrite with empty list',
        () async {
      // Intentionally corrupt storage by writing an int instead of List<String>
      SharedPreferences.setMockInitialValues({
        SharedPreferencesShopWishlistRepository.storageKey:
            12345, // Corrupted data type
      });

      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      expect(
        () => repository.getSavedProductIds(),
        throwsA(isA<ShopStorageFailure>()),
      );

      // Ensure storage key was NOT silently wiped
      expect(
          prefs.get(SharedPreferencesShopWishlistRepository.storageKey), 12345);
    });

    test(
        'write failure in queue does not permanently break subsequent operations',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      await repository.save('valid_1');

      // Subsequent operation can still proceed normally
      await repository.save('valid_2');
      final list = await repository.getSavedProductIds();
      expect(list, ['valid_2', 'valid_1']);
    });

    test('reactive stream broadcasts updated list on write', () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesShopWishlistRepository(prefs);

      final receivedEvents = <List<String>>[];
      final subscription = repository.watchSavedProductIds().listen((event) {
        receivedEvents.add(event);
      });

      await repository.save('item_stream_1');
      await repository.save('item_stream_2');
      await repository.remove('item_stream_1');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();
      repository.dispose();

      expect(receivedEvents.length, 3);
      expect(receivedEvents[0], ['item_stream_1']);
      expect(receivedEvents[1], ['item_stream_2', 'item_stream_1']);
      expect(receivedEvents[2], ['item_stream_2']);
    });
  });
}
